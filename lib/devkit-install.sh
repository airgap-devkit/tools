#!/usr/bin/env bash
# tools/lib/devkit-install.sh — shared installer utilities for airgap-devkit
# Source this file from any setup.sh:
#   source "$(dirname "${BASH_SOURCE[0]}")/../../lib/devkit-install.sh"

# ── Platform detection ──────────────────────────────────────────────────────
# AIRGAP_OS (set by the Go server) is authoritative. Variable refs are guarded
# so this file is safe to source under `set -u`.
if [[ "${AIRGAP_OS:-}" == "linux" ]]; then
    DEVKIT_PLATFORM="linux"
elif [[ "${AIRGAP_OS:-}" == "windows" || "${OSTYPE:-}" == "msys" || "${OSTYPE:-}" == "cygwin" || "${OS:-}" == "Windows_NT" ]]; then
    DEVKIT_PLATFORM="windows"
else
    DEVKIT_PLATFORM="linux"
fi

# ── glibc-aware Linux asset selection ───────────────────────────────────────
# RHEL 8 ships glibc 2.28; RHEL 9 ships 2.34. A binary linked against a newer
# glibc will not run on an older host, so tools that ship a dedicated older-libc
# build select it here instead of duplicating the ldd probe in every setup.sh.

# devkit_glibc_minor — echo the glibc minor version (e.g. 28 for 2.28), or 0 if
# ldd is unavailable (treated as "old" so the safer build is chosen).
devkit_glibc_minor() {
    local minor
    minor=$(ldd --version 2>/dev/null | awk 'NR==1{split($NF,v,"."); print int(v[2])}')
    echo "${minor:-0}"
}

# devkit_linux_asset MODERN_ASSET OLD_ASSET [THRESHOLD]
# Echo OLD_ASSET when the glibc minor version is below THRESHOLD (default 32,
# i.e. anything older than glibc 2.32 such as RHEL 8) or when ldd is missing;
# otherwise echo MODERN_ASSET.
devkit_linux_asset() {
    local modern="$1" old="$2" threshold="${3:-32}"
    local minor; minor=$(devkit_glibc_minor)
    if (( minor < threshold )); then echo "$old"; else echo "$modern"; fi
}

# ── Integrity verification ──────────────────────────────────────────────────
# devkit_verify_sha256 FILE EXPECTED_HEX
# Aborts (exit 1) on mismatch; returns 0 on match. If no sha256 tool exists on
# the host, warns and returns 0 rather than blocking an otherwise valid install.
devkit_verify_sha256() {
    local file="$1" expected="$2"
    [[ -f "$file" ]] || { echo "ERROR: verify: file not found: $file" >&2; exit 1; }
    local actual
    if command -v sha256sum &>/dev/null; then
        actual=$(sha256sum "$file" | awk '{print $1}')
    elif command -v shasum &>/dev/null; then
        actual=$(shasum -a 256 "$file" | awk '{print $1}')
    else
        echo "    [WARN] no sha256 tool available; skipping integrity check for $(basename "$file")" >&2
        return 0
    fi
    if [[ "${actual,,}" != "${expected,,}" ]]; then
        echo "ERROR: checksum mismatch for $(basename "$file")" >&2
        echo "       expected: ${expected}" >&2
        echo "       actual:   ${actual}" >&2
        exit 1
    fi
    echo "    [OK] sha256 verified: $(basename "$file")"
}

# devkit_manifest_sha256 MANIFEST_JSON ARCHIVE_NAME
# Extract the expected sha256 for ARCHIVE_NAME from a prebuilt manifest.json.
# Portable (grep only — no python/jq): the manifest lists each platform as
# {"archive": "<name>", "sha256": "<hex>"}, so the hash is the first real sha256
# that follows the line naming the archive. Matches only a genuine
# "sha256": "<64-hex>" entry — never the "part_sha256" map that split archives
# carry (those have no whole-file hash) — and prints empty when none is found.
devkit_manifest_sha256() {
    local manifest="$1" archive="$2"
    [[ -f "$manifest" ]] || return 0
    # Trailing `|| true`: a no-match must yield empty output with exit 0, so a
    # caller's `expected="$(devkit_manifest_sha256 …)"` never trips `set -e`.
    grep -A3 -F "\"${archive}\"" "$manifest" 2>/dev/null \
        | grep -oE '"sha256"[[:space:]]*:[[:space:]]*"[0-9a-fA-F]{64}"' \
        | head -1 \
        | grep -oE '[0-9a-fA-F]{64}' || true
}

# devkit_verify_archive MANIFEST_JSON ARCHIVE_PATH
# Look up ARCHIVE_PATH's expected sha256 in MANIFEST_JSON and verify it. Warns
# (does not fail) when the manifest or the hash entry is missing, so tools whose
# manifests predate checksum coverage still install; a present-but-mismatched
# hash is a hard failure.
devkit_verify_archive() {
    local manifest="$1" archive_path="$2"
    local base; base="$(basename "$archive_path")"
    if [[ ! -f "$manifest" ]]; then
        echo "    [WARN] no manifest at ${manifest}; skipping integrity check" >&2
        return 0
    fi
    local expected; expected="$(devkit_manifest_sha256 "$manifest" "$base")"
    if [[ -z "$expected" ]]; then
        echo "    [WARN] no sha256 for ${base} in manifest; skipping integrity check" >&2
        return 0
    fi
    devkit_verify_sha256 "$archive_path" "$expected"
}

# ── Split-archive assembly ──────────────────────────────────────────────────
# devkit_assemble_parts DIR [PLATFORM_FILTER]
# If DIR contains .part-aa/.part-ab/... files (optionally filtered by a
# platform keyword), assembles them into the base filename (stripping
# .part-aa).  Prints the assembled file path; prints nothing if no matching
# parts exist.
#
# IMPORTANT: only the parts belonging to a single base file are concatenated
# (pattern: "${target}.part-*"), so mixed-platform directories (e.g. both
# .exe.part-* and .rpm.part-* in the same dir) are handled correctly.
devkit_assemble_parts() {
    local dir="$1"
    local filter="${2:-}"

    local first_part
    if [[ -n "$filter" ]]; then
        first_part=$(ls "$dir"/*.part-aa 2>/dev/null | grep -i "$filter" | head -1)
    else
        first_part=$(ls "$dir"/*.part-aa 2>/dev/null | head -1)
    fi
    [[ -z "$first_part" ]] && return 0

    local stem="${first_part%.part-aa}"   # full path, extension kept
    local base; base="$(basename "$stem")"

    # Reuse an already-assembled whole file if one is present in the source dir.
    if [[ -f "$stem" ]]; then echo "$stem"; return 0; fi

    # Assemble in place only when the prebuilt dir is writable; otherwise write
    # to a temp dir. The prebuilt tree is read-only when the devkit is vendored
    # under a system prefix or run by a non-root user (e.g. the RHEL 8 CI
    # container, where /workspace is root-owned but installs run as `devkit`).
    local target
    if [[ -w "$dir" ]]; then target="$stem"; else target="$(mktemp -d)/$base"; fi

    echo "==> Assembling split archive: ${base}..." >&2
    # Only cat the parts that belong to this specific base file. A failed write
    # must abort — never return a path to a file that was not created.
    if ! cat "${stem}.part-"* > "$target" 2>/dev/null; then
        echo "ERROR: failed to reassemble ${base} — no writable location for the joined archive." >&2
        return 1
    fi
    echo "    $(du -sh "$target" 2>/dev/null | cut -f1) assembled" >&2
    echo "$target"
}

# devkit_resolve_archive DIR BASE_NO_EXT
# Locate the staged archive named BASE_NO_EXT + a supported extension, preferring
# the native, no-admin formats (.zip / .tar.gz) over legacy .tar.xz. Assembles
# split parts (BASE.ext.part-aa...) into the whole file when it is absent.
# Echoes the resolved archive path; returns 1 if nothing matches.
devkit_resolve_archive() {
    local dir="$1" base="$2" ext f out
    for ext in zip tar.gz tar.xz; do
        f="$dir/$base.$ext"
        if [[ -f "$f" ]]; then echo "$f"; return 0; fi
        if ls "$dir/$base.$ext".part-aa &>/dev/null; then
            # Assemble in place when the prebuilt dir is writable, else into a
            # temp dir (the prebuilt tree is read-only under a system prefix or
            # a non-root CI user). A failed write must return 1 — never echo a
            # path to a file that was not actually created.
            if [[ -w "$dir" ]]; then out="$f"; else out="$(mktemp -d)/$base.$ext"; fi
            if ! cat "$dir/$base.$ext".part-* > "$out" 2>/dev/null; then
                echo "ERROR: failed to reassemble $base.$ext — no writable location for the joined archive." >&2
                return 1
            fi
            echo "$out"; return 0
        fi
    done
    return 1
}

# ── File discovery ──────────────────────────────────────────────────────────
# devkit_find_file DIR [PLATFORM]
# Returns the best installer file for PLATFORM in DIR.
#
# Search order:
#   1. Platform-filtered split-part assembly (e.g. only linux .part-aa files)
#   2. Unfiltered split-part assembly (single-platform dirs that have no
#      platform keyword in the filename)
#   3. Pre-assembled platform-specific file (contains the platform keyword)
#   4. Any installer file (last-resort, no platform filter)
devkit_find_file() {
    local dir="$1"
    local plat="${2:-$DEVKIT_PLATFORM}"

    # 1. Assemble platform-specific split parts if present.
    local assembled
    assembled=$(devkit_assemble_parts "$dir" "$plat")
    if [[ -n "$assembled" ]]; then
        echo "$assembled"
        return 0
    fi

    # 2. No platform-specific parts — try unfiltered (single-platform dirs).
    assembled=$(devkit_assemble_parts "$dir")
    if [[ -n "$assembled" ]]; then
        echo "$assembled"
        return 0
    fi

    # 3. Platform-specific pre-assembled file (contains platform keyword).
    local file
    file=$(ls "$dir" 2>/dev/null \
        | grep -v "\.part-" | grep -v "manifest" \
        | grep -iE "\.(exe|msi|tar\.xz|tar\.gz|zip|deb|rpm)$" \
        | grep -i "$plat" | head -1)
    if [[ -n "$file" ]]; then echo "$dir/$file"; return 0; fi

    # 4. Any installer (last resort, no platform filter).
    file=$(ls "$dir" 2>/dev/null \
        | grep -v "\.part-" | grep -v "manifest" \
        | grep -iE "\.(exe|msi|tar\.xz|tar\.gz|zip|deb|rpm)$" \
        | head -1)
    if [[ -n "$file" ]]; then echo "$dir/$file"; return 0; fi

    return 1
}

# ── NSIS / EXE installer ────────────────────────────────────────────────────
# devkit_install_exe POSIX_PATH PREFIX [EXTRA_FLAGS...]
# Runs an NSIS-style .exe via cmd.exe (bypasses MSYS path conversion).
# Default flags: /VERYSILENT /NORESTART /NOCANCEL /SP- /DIR="PREFIX"
# Pass extra flags as additional arguments to override /DIR or add others.
devkit_install_exe() {
    local file="$1" prefix="$2"; shift 2
    local exe_w prefix_w
    exe_w="$(cygpath -w "$file")"
    prefix_w="$(cygpath -w "$prefix")"

    local flags="/VERYSILENT /NORESTART /NOCANCEL /SP- /DIR=\"${prefix_w}\""
    [[ $# -gt 0 ]] && flags="$*"

    echo "==> Running: \"${exe_w}\" ${flags}"
    set +e
    cmd.exe //c "\"${exe_w}\" ${flags}"
    local rc=$?
    set -e
    [[ $rc -ne 0 ]] && { echo "ERROR: Installer failed (exit $rc)" >&2; exit 1; }
}

# devkit_install_exe_silent POSIX_PATH
# For non-NSIS EXEs (e.g. Squirrel / Electron) that use --silent instead of /VERYSILENT.
devkit_install_exe_silent() {
    local file="$1"
    local exe_w
    exe_w="$(cygpath -w "$file")"
    echo "==> Running: \"${exe_w}\" --silent"
    set +e
    cmd.exe //c "\"${exe_w}\" --silent"
    local rc=$?
    set -e
    [[ $rc -ne 0 ]] && { echo "ERROR: Installer failed (exit $rc)" >&2; exit 1; }
}

# devkit_install_nsis_s POSIX_PATH PREFIX
# For NSIS installers that use the short /S flag (e.g. FileZilla) instead of /VERYSILENT.
devkit_install_nsis_s() {
    local file="$1" prefix="$2"
    local exe_w prefix_w
    exe_w="$(cygpath -w "$file")"
    prefix_w="$(cygpath -w "$prefix")"
    echo "==> Running: \"${exe_w}\" /S /D=\"${prefix_w}\""
    set +e
    cmd.exe //c "\"${exe_w}\" /S /D=\"${prefix_w}\""
    local rc=$?
    set -e
    [[ $rc -ne 0 ]] && { echo "ERROR: Installer failed (exit $rc)" >&2; exit 1; }
}

# ── MSI installer ───────────────────────────────────────────────────────────
# devkit_install_msi POSIX_PATH
# Runs msiexec via cmd.exe start /wait (blocks until all child processes exit).
devkit_install_msi() {
    local file="$1"
    local msi_w log_p log_w
    msi_w="$(cygpath -w "$file")"
    log_p="$(mktemp --suffix=.log)"
    log_w="$(cygpath -w "$log_p")"

    echo "==> Running: msiexec /i \"${msi_w}\" /quiet /qn /norestart"
    set +e
    cmd.exe //c "start /wait \"\" msiexec.exe /i \"${msi_w}\" /quiet /qn /norestart /L*V \"${log_w}\"" &
    local pid=$!

    # Stream MSI log while installer runs; abort after 10 minutes.
    local log_bytes=0
    local elapsed=0
    local timeout=600
    while kill -0 "$pid" 2>/dev/null; do
        if [[ $elapsed -ge $timeout ]]; then
            echo "ERROR: MSI install timed out after ${timeout}s — killing." >&2
            kill "$pid" 2>/dev/null || true
            break
        fi
        if [[ -f "$log_p" ]]; then
            local cur
            cur=$(wc -c < "$log_p" 2>/dev/null || echo 0)
            if [[ "$cur" -gt "$log_bytes" ]]; then
                tail -c +$((log_bytes + 1)) "$log_p" \
                    | tr -d '\r' \
                    | grep -E "^(Action start|MSI \(s\).*Note:|Return Value [^1]|Error [0-9])" \
                    | sed 's/^Action start [0-9:]*: /  step: /' \
                    | sed 's/^MSI (s)[^:]*Note: /  note: /' \
                    || true
                log_bytes=$cur
            fi
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    wait "$pid"
    local rc=$?
    set -e

    if [[ $rc -ne 0 && $rc -ne 3010 ]]; then
        if [[ -f "$log_p" ]]; then
            echo "==> Last MSI log errors:"
            tr -d '\r' < "$log_p" | grep -E "(Error|Return Value [^1]|Note:)" | tail -10
        fi
        rm -f "$log_p"
        echo "ERROR: msiexec failed (exit $rc)" >&2; exit 1
    fi
    rm -f "$log_p"
    [[ $rc -eq 3010 ]] && echo "==> Note: A system restart may be required."
}

# ── Archive extraction ──────────────────────────────────────────────────────
# devkit_extract POSIX_PATH DEST [STRIP_COMPONENTS]
# Extracts .tar.xz / .tar.gz / .zip to DEST.
devkit_extract() {
    local file="$1" dest="$2" strip="${3:-0}"
    local name
    name="$(basename "$file")"
    mkdir -p "$dest"

    case "${file,,}" in
        *.tar.xz)
            echo "==> Extracting ${name} → ${dest}"
            tar -xJf "$file" -C "$dest" --strip-components="$strip"
            ;;
        *.tar.gz)
            echo "==> Extracting ${name} → ${dest}"
            tar -xzf "$file" -C "$dest" --strip-components="$strip"
            ;;
        *.zip)
            echo "==> Extracting ${name} → ${dest}"
            if command -v unzip &>/dev/null; then
                unzip -qo "$file" -d "$dest"
            else
                # PowerShell fallback (always available on Windows)
                local fw dw
                fw="$(cygpath -w "$file")"
                dw="$(cygpath -w "$dest")"
                powershell.exe -NoProfile -NonInteractive -Command \
                    "Expand-Archive -Force -Path '$fw' -DestinationPath '$dw'"
            fi
            ;;
        *)
            echo "ERROR: devkit_extract: unsupported format: $name" >&2; exit 1
            ;;
    esac
}

# devkit_install_archive ARCHIVE DEST
# Extract ARCHIVE and place its payload into DEST, auto-stripping a SOLE
# top-level wrapper directory (e.g. cmake-4.3.3-linux-x86_64/, bin/, python/) —
# but never a single bare file (e.g. ninja). Extraction happens on the target
# host, so POSIX symlinks are recreated correctly (unlike repacking on Windows).
# This removes the need for per-tool/per-version --strip-components values.
devkit_install_archive() {
    local archive="$1" dest="$2"
    local tmp; tmp="$(mktemp -d)"
    devkit_extract "$archive" "$tmp" 0
    local root="$tmp"
    local entries=("$tmp"/*)
    if [[ ${#entries[@]} -eq 1 && -d "${entries[0]}" ]]; then
        root="${entries[0]}"
    fi
    mkdir -p "$dest"
    ( shopt -s dotglob; mv "$root"/* "$dest"/ )
    rm -rf "$tmp"
}

# ── Package manager installers ──────────────────────────────────────────────
# devkit_install_deb POSIX_PATH [DEST_PREFIX]
# Installs a .deb.  Uses dpkg if available; falls back to manual extraction.
devkit_install_deb() {
    local file="$1" prefix="${2:-/usr/local}"
    if command -v dpkg &>/dev/null; then
        echo "==> dpkg -i $(basename "$file")"
        dpkg -i "$file" 2>/dev/null || { apt-get install -f -y 2>/dev/null || true; }
    else
        # Manual extraction fallback (e.g. RHEL without alien)
        echo "==> Extracting .deb manually → ${prefix}"
        local tmp
        tmp="$(mktemp -d)"
        trap 'rm -rf "$tmp"' RETURN
        # .deb = ar archive: contains data.tar.* inside
        cd "$tmp" && ar x "$file"
        local data_tar
        data_tar=$(ls "$tmp"/data.tar.* 2>/dev/null | head -1)
        if [[ -n "$data_tar" ]]; then
            mkdir -p "$prefix"
            tar -xf "$data_tar" -C "$prefix" --strip-components=2 \
                --wildcards '*/bin/*' '*/usr/bin/*' 2>/dev/null || \
            tar -xf "$data_tar" -C "$prefix"
        else
            echo "ERROR: could not find data.tar inside .deb" >&2; exit 1
        fi
    fi
}

# devkit_install_rpm POSIX_PATH
devkit_install_rpm() {
    local file="$1"
    echo "==> rpm -Uvh $(basename "$file")"
    rpm -Uvh "$file"
}

# ── Receipt writing ─────────────────────────────────────────────────────────
# devkit_write_receipt TOOL VERSION PLATFORM PREFIX [EXTRA_LINE ...]
# Any additional arguments are appended verbatim as extra key=value receipt
# lines (e.g. "includes=clang,clang-format").
devkit_write_receipt() {
    local tool="$1" ver="$2" plat="$3" prefix="$4"; shift 4
    mkdir -p "$prefix"
    cat > "$prefix/INSTALL_RECEIPT.txt" << RECEIPT
tool=${tool}
version=${ver}
platform=${plat}
install_prefix=${prefix}
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RECEIPT
    local line
    for line in "$@"; do
        printf '%s\n' "$line" >> "$prefix/INSTALL_RECEIPT.txt"
    done
}

# ── Prefix / arg helpers ────────────────────────────────────────────────────
# devkit_default_prefix TOOL [PLATFORM]
# Returns the standard install prefix for TOOL on the current platform.
devkit_default_prefix() {
    local tool="$1" plat="${2:-$DEVKIT_PLATFORM}"
    if [[ "$plat" == "windows" ]]; then
        echo "${LOCALAPPDATA:-$HOME/AppData/Local}/airgap-cpp-devkit/${tool}"
    elif [[ "$(id -u 2>/dev/null)" == "0" ]]; then
        echo "/opt/airgap-cpp-devkit/${tool}"
    else
        echo "${HOME}/.local/share/airgap-cpp-devkit/${tool}"
    fi
}

# devkit_parse_args [--prefix PATH] [--rebuild] [--jobs N] ...
# Sets PREFIX, REBUILD, JOBS from CLI args.  Call after sourcing this file.
devkit_parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --prefix)  PREFIX="$2"; shift 2 ;;
            --rebuild) REBUILD=1; shift ;;
            --jobs)    JOBS="$2"; shift 2 ;;
            *)         shift ;;
        esac
    done
}
