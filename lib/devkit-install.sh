#!/usr/bin/env bash
# tools/lib/devkit-install.sh — shared installer utilities for airgap-devkit
# Source this file from any setup.sh:
#   source "$(dirname "${BASH_SOURCE[0]}")/../../lib/devkit-install.sh"

# ── Platform detection ──────────────────────────────────────────────────────
if [[ "${AIRGAP_OS:-}" == "windows" || "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "${OS:-}" == "Windows_NT" ]]; then
    DEVKIT_PLATFORM="windows"
else
    DEVKIT_PLATFORM="linux"
fi

# ── Split-archive assembly ──────────────────────────────────────────────────
# devkit_assemble_parts DIR
# If DIR contains .part-aa/.part-ab/... files, assembles them into the base
# filename (stripping the .part-aa suffix).  Prints the assembled file path.
# Prints nothing if no parts are found (the directory already has the full file).
devkit_assemble_parts() {
    local dir="$1"
    local first_part
    first_part=$(ls "$dir"/*.part-aa 2>/dev/null | head -1)
    [[ -z "$first_part" ]] && return 0

    local target="${first_part%.part-aa}"
    if [[ ! -f "$target" ]]; then
        echo "==> Assembling split archive: $(basename "$target")..." >&2
        cat "$dir"/*.part-* > "$target"
        echo "    $(du -sh "$target" 2>/dev/null | cut -f1) assembled" >&2
    fi
    echo "$target"
}

# ── File discovery ──────────────────────────────────────────────────────────
# devkit_find_file DIR [PLATFORM]
# Assembles split parts first, then finds the best installer file for the
# current platform.  Prints the full path; exits non-zero if nothing found.
devkit_find_file() {
    local dir="$1"
    local plat="${2:-$DEVKIT_PLATFORM}"

    # Reassemble parts first (returns path if assembled, empty if none)
    local assembled
    assembled=$(devkit_assemble_parts "$dir")
    if [[ -n "$assembled" ]]; then
        echo "$assembled"
        return 0
    fi

    # Platform-specific file (contains "windows" or "linux" in name)
    local file
    file=$(ls "$dir" 2>/dev/null \
        | grep -v "\.part-" | grep -v "manifest" \
        | grep -iE "\.(exe|msi|tar\.xz|tar\.gz|zip|deb|rpm)$" \
        | grep -i "$plat" | head -1)
    if [[ -n "$file" ]]; then echo "$dir/$file"; return 0; fi

    # Any installer (no platform filter)
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
# For NSIS installers that use the short /S flag (7-Zip, FileZilla) instead of /VERYSILENT.
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

    # Stream MSI log while installer runs
    local log_bytes=0
    while kill -0 "$pid" 2>/dev/null; do
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
# devkit_write_receipt TOOL VERSION PLATFORM PREFIX
devkit_write_receipt() {
    local tool="$1" ver="$2" plat="$3" prefix="$4"
    mkdir -p "$prefix"
    cat > "$prefix/INSTALL_RECEIPT.txt" << RECEIPT
tool=${tool}
version=${ver}
platform=${plat}
install_prefix=${prefix}
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RECEIPT
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
