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

# ── glibc-aware Linux distro selection ──────────────────────────────────────
# The devkit targets RHEL / Rocky 8, 9 and 10 (baseline: 9). Each major ships a
# fixed glibc: 8 → 2.28, 9 → 2.34, 10 → 2.39. glibc is backward-compatible — a
# binary linked against an older glibc runs on newer hosts, but not the reverse.
# Tools that ship dedicated per-distro builds therefore select the closest
# variant at or below the host's glibc here, instead of duplicating the probe in
# every setup.sh.

# devkit_glibc_minor — echo the glibc minor version (e.g. 28 for 2.28), or 0 if
# ldd is unavailable (treated as "oldest" so the widest-compatible build wins).
devkit_glibc_minor() {
    local minor
    minor=$(ldd --version 2>/dev/null | awk 'NR==1{split($NF,v,"."); print int(v[2])}')
    echo "${minor:-0}"
}

# devkit_rhel_major — echo the RHEL/Rocky major (10, 9, or 8) the host matches,
# by glibc: >=2.39 → 10, >=2.34 → 9, else 8. Missing ldd → 8 (widest support).
devkit_rhel_major() {
    local minor; minor=$(devkit_glibc_minor)
    if   (( minor >= 39 )); then echo 10
    elif (( minor >= 34 )); then echo 9
    else                         echo 8
    fi
}

# devkit_rhel_tag — echo the EL variant tag matching the host: rhel10/rhel9/rhel8.
devkit_rhel_tag() { echo "rhel$(devkit_rhel_major)"; }

# devkit_rhel_tag_fallbacks — echo the ordered EL variant tags to try for this
# host, from the closest match down to the universal glibc-2.28 floor (rhel8).
# A per-distro build may not be staged yet; the floor always runs, so callers
# can try each tag in turn and still install on any supported host.
devkit_rhel_tag_fallbacks() {
    case "$(devkit_rhel_major)" in
        10) echo "rhel10 rhel9 rhel8" ;;
        9)  echo "rhel9 rhel8" ;;
        *)  echo "rhel8" ;;
    esac
}

# devkit_linux_asset MODERN_ASSET OLD_ASSET [THRESHOLD]
# Legacy two-way selector, retained for tools that ship only a "modern" and a
# single older-libc build. Echo OLD_ASSET when the glibc minor is below
# THRESHOLD (default 32, i.e. older than glibc 2.32 such as RHEL 8) or when ldd
# is missing; otherwise echo MODERN_ASSET. Prefer devkit_rhel_tag_fallbacks for
# new per-distro (8/9/10) tools.
devkit_linux_asset() {
    local modern="$1" old="$2" threshold="${3:-32}"
    local minor; minor=$(devkit_glibc_minor)
    if (( minor < threshold )); then echo "$old"; else echo "$modern"; fi
}

# ── C-library family selection (two-family distribution model) ───────────────
# The devkit ships at most two Linux artifact families that between them cover
# every mainstream distro:
#   glibc — one build against the oldest supported glibc (the "floor"). Because
#           glibc is backward-compatible, it runs on any glibc host at or above
#           that floor: RHEL/Rocky 8/9/10, Debian 10+, Ubuntu 20.04+, SUSE/SLES
#           15+, Arch, Fedora, ...
#   musl  — one fully-static musl build. It has no libc dependency at all, so it
#           runs on Alpine (musl) and, as a universal fallback, anywhere else.
# Detection is by libc, not by distro name, so new distros need no new code.

# devkit_libc — echo the host C library family: "musl" or "glibc".
# musl's ldd prints "musl libc ..."; the musl loader also lives at
# /lib/ld-musl-<arch>.so.1. Everything else is treated as glibc.
devkit_libc() {
    if ldd --version 2>&1 | grep -qi 'musl'; then
        echo "musl"
    elif compgen -G '/lib/ld-musl-*.so.1' >/dev/null 2>&1; then
        echo "musl"
    else
        echo "glibc"
    fi
}

# devkit_distro_id — echo the /etc/os-release ID (e.g. rhel, rocky, debian,
# ubuntu, sles, opensuse-leap, arch, alpine, fedora), or "linux" if unknown.
# Used for human-readable messaging; artifact selection keys off libc, not this.
devkit_distro_id() {
    local id="linux"
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        id="$( . /etc/os-release 2>/dev/null && echo "${ID:-linux}" )"
    fi
    echo "${id:-linux}"
}

# devkit_linux_family — echo the primary artifact family tag for this host:
# "musl" or "glibc".
devkit_linux_family() { devkit_libc; }

# devkit_linux_tag_fallbacks — echo the ordered artifact tags to try for the
# host, most-preferred first. musl hosts get "musl". glibc hosts prefer the
# dedicated "glibc" floor build, then fall back to the legacy per-RHEL-major
# builds (rhel8 is itself the glibc-2.28 floor, so it runs on any glibc >= 2.28).
# This keeps already-staged rhel8/9/10 artifacts working during the migration to
# the two-family model.
devkit_linux_tag_fallbacks() {
    if [[ "$(devkit_libc)" == "musl" ]]; then
        echo "musl"
    else
        echo "glibc rhel8 rhel9 rhel10"
    fi
}

# ── Integrity verification ──────────────────────────────────────────────────
# Every prebuilt-archive install is integrity-gated: the archive (or, for a split
# archive, each part) must match the sha256 recorded in the tool's manifest.json
# before it is unpacked. Verification is fail-closed — a missing manifest, a
# missing hash entry, or the absence of a sha256 tool aborts the install rather
# than proceeding unverified.

# devkit_verify_sha256 FILE EXPECTED_HEX
# Aborts (exit 1) on mismatch or when no sha256 tool is available; returns 0 on
# match. Verification is mandatory, so a host with no sha256 tool is a failure.
devkit_verify_sha256() {
    local file="$1" expected="$2"
    [[ -f "$file" ]] || { echo "ERROR: verify: file not found: $file" >&2; exit 1; }
    local actual
    if command -v sha256sum &>/dev/null; then
        actual=$(sha256sum "$file" | awk '{print $1}')
    elif command -v shasum &>/dev/null; then
        actual=$(shasum -a 256 "$file" | awk '{print $1}')
    else
        echo "ERROR: verify: no sha256 tool (sha256sum/shasum) available; cannot confirm integrity of $(basename "$file")" >&2
        exit 1
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

# devkit_manifest_part_sha256 MANIFEST_JSON PART_NAME
# Extract the expected sha256 for a single split-archive part from the manifest's
# "part_sha256" map. A part filename carries no 64-hex run of its own, so the only
# 64-hex token on its line is the hash. Prints empty when none is found.
devkit_manifest_part_sha256() {
    local manifest="$1" part="$2"
    [[ -f "$manifest" ]] || return 0
    # Trailing `|| true`: a no-match must yield empty output with exit 0 so a
    # caller's `hash="$(devkit_manifest_part_sha256 …)"` never trips `set -e`.
    grep -F "\"${part}\"" "$manifest" 2>/dev/null \
        | grep -oE '[0-9a-fA-F]{64}' \
        | head -1 || true
}

# devkit_verify_staged DIR ARCHIVE_BASENAME
# Fail-closed integrity gate for a staged prebuilt archive in DIR. When DIR holds
# split parts (ARCHIVE_BASENAME.part-*), every part is verified against the
# manifest's part_sha256 map; otherwise the whole archive is verified against its
# sha256 entry. A missing manifest, a missing hash, or a mismatch aborts. Callers
# whose stdout is captured (the resolvers below) must redirect this to stderr, as
# a successful verify prints an "[OK]" line.
devkit_verify_staged() {
    local dir="$1" base="$2"
    local manifest="$dir/manifest.json"
    if [[ ! -f "$manifest" ]]; then
        echo "ERROR: integrity: no manifest.json in ${dir}; refusing to install ${base} unverified" >&2
        exit 1
    fi

    # Split archive: verify each staged part before it is ever assembled.
    if ls "$dir/$base".part-* &>/dev/null; then
        local part pname hash verified=0
        for part in "$dir/$base".part-*; do
            [[ -f "$part" ]] || continue
            pname="$(basename "$part")"
            hash="$(devkit_manifest_part_sha256 "$manifest" "$pname")"
            if [[ -z "$hash" ]]; then
                echo "ERROR: integrity: no part_sha256 for ${pname} in ${manifest}; refusing to install unverified" >&2
                exit 1
            fi
            devkit_verify_sha256 "$part" "$hash"
            verified=$((verified + 1))
        done
        [[ "$verified" -gt 0 ]] || { echo "ERROR: integrity: no parts found for ${base} in ${dir}" >&2; exit 1; }
        return 0
    fi

    # Whole-file archive.
    local expected; expected="$(devkit_manifest_sha256 "$manifest" "$base")"
    if [[ -z "$expected" ]]; then
        echo "ERROR: integrity: no sha256 for ${base} in ${manifest}; refusing to install unverified" >&2
        exit 1
    fi
    devkit_verify_sha256 "$dir/$base" "$expected"
}

# devkit_verify_archive MANIFEST_JSON ARCHIVE_PATH
# Backward-compatible wrapper around devkit_verify_staged: verifies the archive
# named by ARCHIVE_PATH using the manifest and the parts/whole file staged
# alongside it (the manifest's own directory). Fail-closed.
devkit_verify_archive() {
    local manifest="$1" archive_path="$2"
    devkit_verify_staged "$(dirname "$manifest")" "$(basename "$archive_path")"
}

# devkit_platform_keys PLATFORM
# Echo the candidate manifest platform keys to try for a devkit platform, most
# specific first. Manifests name platforms variously (e.g. "linux-x64",
# "windows"); this maps our "linux"/"windows" onto those without each caller
# hard-coding the spelling.
devkit_platform_keys() {
    case "$1" in
        windows) echo "windows windows-x64 win64 win windows-amd64" ;;
        linux)   echo "linux-x64 linux linux-amd64 linux-x86_64" ;;
        *)       echo "$1" ;;
    esac
}

# devkit_manifest_archive MANIFEST PLATFORM_KEY...
# Echo the platforms.<key>.archive (or .installer) filename for the first key
# that has one. Manifests name the payload "archive" for tarballs/zips and
# "installer" for native installers (.exe/.msi) — both are the file to hand to
# the extractor/installer, so match either. Manifest-driven selection is
# authoritative and locale-independent, unlike guessing from filenames.
# grep-only (no jq/python), like the sha helpers.
devkit_manifest_archive() {
    local manifest="$1"; shift
    [[ -f "$manifest" ]] || return 0
    local key val
    for key in "$@"; do
        # The platform key line ("windows": {) is immediately followed by its
        # "archive"/"installer" field; -A3 covers any intervening whitespace/keys.
        val="$(grep -A3 -E "\"${key}\"[[:space:]]*:[[:space:]]*\{" "$manifest" 2>/dev/null \
            | grep -oE '"(archive|installer)"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 \
            | sed -E 's/.*:[[:space:]]*"([^"]+)"/\1/')"
        [[ -n "$val" ]] && { echo "$val"; return 0; }
    done
    return 0
}

# devkit_resolve_named DIR ARCHIVE_NAME
# Resolve a staged archive by its exact filename (extension included), as named
# by a manifest. Split parts take precedence and are ALWAYS assembled fresh from
# the verified parts into a temp file — a cached or planted whole file at
# "$dir/$name" is never handed to the extractor unverified. Fail-closed: a
# missing/failed hash aborts. Echoes the path to extract; returns 1 if absent.
devkit_resolve_named() {
    local dir="$1" name="$2" out
    if ls "$dir/$name".part-aa &>/dev/null; then
        devkit_verify_staged "$dir" "$name" >&2      # hashes every part, fail-closed
        out="$(mktemp -d)/$name"
        if ! cat "$dir/$name".part-* > "$out" 2>/dev/null; then
            echo "ERROR: failed to reassemble ${name}." >&2
            return 1
        fi
        echo "$out"; return 0
    fi
    if [[ -f "$dir/$name" ]]; then
        devkit_verify_staged "$dir" "$name" >&2      # whole-file sha256, fail-closed
        echo "$dir/$name"; return 0
    fi
    return 1
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

    # Always assemble fresh from the parts into a temp dir — never reuse or write
    # a whole file next to the parts. The caller verifies the parts against the
    # manifest, so the assembled bytes are exactly cat(verified parts). Reusing a
    # cached (or planted) whole file at "$stem" would hand the extractor a file
    # the integrity gate never checked, since the gate hashes the parts.
    local target; target="$(mktemp -d)/$base"

    echo "==> Assembling split archive: ${base}..." >&2
    # Only cat the parts that belong to this specific base file. A failed write
    # must abort — never return a path to a file that was not created.
    if ! cat "${stem}.part-"* > "$target" 2>/dev/null; then
        echo "ERROR: failed to reassemble ${base}." >&2
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
    local dir="$1" base="$2" ext
    for ext in zip tar.gz tar.xz; do
        local name="$base.$ext"
        # Split parts take PRECEDENCE over any co-located whole file: assemble
        # ONLY from the verified parts into a fresh temp file, so a cached or
        # planted "$dir/$name" can never be substituted for what the gate checked.
        if ls "$dir/$name".part-aa &>/dev/null; then
            devkit_resolve_named "$dir" "$name" && return 0
            return 1
        fi
        # Genuine whole-file archive (no parts): verify against the manifest's
        # whole-file sha256 before handing it back. Fail-closed.
        if [[ -f "$dir/$name" ]]; then
            devkit_verify_staged "$dir" "$name" >&2
            echo "$dir/$name"; return 0
        fi
    done
    return 1
}

# ── File discovery ──────────────────────────────────────────────────────────
# devkit_find_file DIR [PLATFORM]
# Returns the installer file for PLATFORM in DIR.
#
# Selection order:
#   0. Manifest-driven — platforms.<plat>.archive (authoritative, deterministic)
#   1. Legacy fallback for manifests without a platforms map: assemble split
#      parts / pick the pre-assembled file, keyed off the filename. This path is
#      only safe when the dir holds a single distinct base archive; a dir with
#      more than one (e.g. a per-platform bundle) is ambiguous and errors rather
#      than picking one by locale-dependent sort order.
devkit_find_file() {
    local dir="$1"
    local plat="${2:-$DEVKIT_PLATFORM}"

    # Every return path below is integrity-gated against the manifest in $dir.
    # stdout is captured by the caller, so verification output goes to stderr.

    # 0. Manifest-driven selection. When the manifest declares per-platform
    #    archives, pick this platform's archive by NAME — never guess from
    #    filenames (that guess is order/locale-dependent when no filename carries
    #    the platform keyword, and can hand a Windows .exe to a Linux host).
    local mname
    mname="$(devkit_manifest_archive "$dir/manifest.json" $(devkit_platform_keys "$plat"))"
    if [[ -n "$mname" ]]; then
        local resolved
        if resolved="$(devkit_resolve_named "$dir" "$mname")"; then
            echo "$resolved"; return 0
        fi
        echo "ERROR: manifest names '${mname}' for ${plat}, but it is missing or failed verification in ${dir}" >&2
        return 1
    fi

    # --- Legacy fallback (manifest has no platforms map) ---------------------
    # Guard against ambiguity: count distinct base archives (strip .part-* and
    # any known extension). If more than one, refuse rather than sort-and-guess.
    local bases
    bases=$(ls "$dir" 2>/dev/null \
        | grep -v "manifest" \
        | sed -E 's/\.part-[a-z]+$//' \
        | grep -iE "\.(exe|msi|tar\.xz|tar\.gz|zip|deb|rpm)$" \
        | sort -u)
    local n; n=$(printf '%s\n' "$bases" | grep -c . || true)
    if [[ "$n" -gt 1 ]]; then
        echo "ERROR: ${dir} holds ${n} distinct archives but its manifest declares no per-platform 'archive'." >&2
        echo "       Add a platforms.<platform>.archive map to manifest.json so selection is unambiguous." >&2
        printf '       candidate: %s\n' $bases >&2
        return 1
    fi

    # Single distinct base — assemble split parts (temp, verified) or return the
    # whole file, both integrity-gated.
    local assembled
    assembled=$(devkit_assemble_parts "$dir")
    if [[ -n "$assembled" ]]; then
        devkit_verify_staged "$dir" "$(basename "$assembled")" >&2
        echo "$assembled"
        return 0
    fi

    local file
    file=$(ls "$dir" 2>/dev/null \
        | grep -v "\.part-" | grep -v "manifest" \
        | grep -iE "\.(exe|msi|tar\.xz|tar\.gz|zip|deb|rpm)$" \
        | head -1)
    if [[ -n "$file" ]]; then
        devkit_verify_staged "$dir" "$file" >&2
        echo "$dir/$file"; return 0
    fi

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
            elif [[ "$DEVKIT_PLATFORM" == "windows" ]]; then
                # PowerShell fallback — Windows only (needs cygpath + Expand-Archive).
                local fw dw
                fw="$(cygpath -w "$file")"
                dw="$(cygpath -w "$dest")"
                powershell.exe -NoProfile -NonInteractive -Command \
                    "Expand-Archive -Force -Path '$fw' -DestinationPath '$dw'"
            elif command -v python3 &>/dev/null; then
                # Linux/musl without unzip (e.g. minimal Debian/Alpine): the devkit
                # Python is on PATH by this point and can extract zips.
                python3 -m zipfile -e "$file" "$dest"
            else
                echo "ERROR: cannot extract ${name}: need 'unzip' or python3." >&2
                exit 1
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
    # Overwrite in place: a plain `mv root/* dest/` fails on re-install because
    # mv refuses to merge a source dir onto an existing non-empty dest dir
    # (e.g. dest/bin already present). Replace each top-level entry instead, so a
    # second install over the same prefix succeeds and reflects the new payload.
    (
        shopt -s dotglob
        local _entry _name
        for _entry in "$root"/*; do
            _name="$(basename "$_entry")"
            rm -rf "$dest/$_name"
            mv "$_entry" "$dest/"
        done
    )
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
