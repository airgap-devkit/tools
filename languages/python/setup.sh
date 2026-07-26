#!/usr/bin/env bash
set -euo pipefail

TOOL="python"
VERSION="3.14.6"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/devkit-install.sh"
PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"
PARTS_DIR="$PREBUILT_DIR/languages/python"

if [[ "$DEVKIT_PLATFORM" == "windows" ]]; then
    # Use full package (35MB) for devkit; embed (12MB) is also available
    ARCHIVE_BASE="python-${VERSION}-amd64"
elif [[ "$(devkit_libc)" == "musl" ]]; then
    # Alpine / musl hosts use the statically-linked musl standalone build.
    ARCHIVE_BASE="cpython-${VERSION}-linux-x64-musl"
else
    # glibc hosts (RHEL/Rocky/Debian/Ubuntu/SUSE/Arch/Fedora) use the glibc build.
    ARCHIVE_BASE="cpython-${VERSION}-linux-x64"
fi

PREFIX="${INSTALL_PREFIX:-$(devkit_default_prefix "$TOOL")}"
PIP_ONLY=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)   PREFIX="$2"; shift 2 ;;
        --pip-only) PIP_ONLY=true; shift ;;
        *)          shift ;;
    esac
done

# ---------------------------------------------------------------------------
# --pip-only: install vendored wheels without reinstalling Python itself.
# Called by the server with INSTALL_PREFIX=<base>/pip-packages.
# ---------------------------------------------------------------------------
if [[ "$PIP_ONLY" == "true" ]]; then
    WHEELS_DIR="$PREBUILT_DIR/languages/python/wheels"
    if [[ ! -d "$WHEELS_DIR" ]]; then
        echo "ERROR: Wheels directory not found: $WHEELS_DIR" >&2; exit 1
    fi

    # Locate the devkit-installed Python; fall back to PATH.
    if [[ "$DEVKIT_PLATFORM" == "linux" ]]; then
        _py="$(devkit_default_prefix "$TOOL")/bin/python3"
    else
        _py="$(devkit_default_prefix "$TOOL")/python3.exe"
    fi
    if [[ ! -x "$_py" ]]; then
        _py="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)"
    fi
    [[ -z "$_py" || ! -x "$_py" ]] && { echo "ERROR: Python not found. Install Python first." >&2; exit 1; }

    echo "==> Installing vendored pip packages"
    echo "    Python : $_py"
    echo "    Wheels : $WHEELS_DIR"

    # Collect wheel files; skip Windows-only wheels on Linux.
    WHEEL_FILES=()
    while IFS= read -r whl; do
        bname="$(basename "$whl")"
        if [[ "$DEVKIT_PLATFORM" == "linux" ]] && [[ "$bname" == *-win_amd64* || "$bname" == *-win32* ]]; then
            echo "    Skipping Windows-only wheel: $bname"
            continue
        fi
        WHEEL_FILES+=("$whl")
    done < <(find "$WHEELS_DIR" -maxdepth 1 -name "*.whl" | LC_ALL=C sort)

    if [[ ${#WHEEL_FILES[@]} -eq 0 ]]; then
        echo "ERROR: No compatible wheel files found in $WHEELS_DIR" >&2; exit 1
    fi
    echo "    Installing ${#WHEEL_FILES[@]} wheel(s)..."

    "$_py" -m pip install --no-deps --no-index "${WHEEL_FILES[@]}"

    devkit_write_receipt "pip-packages" "vendored" "$DEVKIT_PLATFORM" "$PREFIX"

    echo "==> Pip packages installed."
    exit 0
fi

echo "==> Installing Python ${VERSION} (${DEVKIT_PLATFORM}) to ${PREFIX}"

mkdir -p "$PREFIX"
if [[ "$DEVKIT_PLATFORM" == "windows" ]]; then
    PREFIX="$(cygpath -u -- "$PREFIX")"
fi

ARCHIVE_PATH="$(devkit_resolve_archive "$PARTS_DIR" "$ARCHIVE_BASE")" \
    || { echo "ERROR: Archive not found for ${ARCHIVE_BASE} in $PARTS_DIR" >&2; exit 1; }
devkit_verify_archive "$PARTS_DIR/manifest.json" "$ARCHIVE_PATH"

if [[ "$DEVKIT_PLATFORM" == "windows" ]]; then
    # Windows full/embeddable package has the interpreter at the archive root.
    devkit_install_archive "$ARCHIVE_PATH" "$PREFIX"
else
    # Linux .tar.gz is transcoded (symlinks preserved); the installer auto-strips
    # the upstream python/ wrapper.
    devkit_install_archive "$ARCHIVE_PATH" "$PREFIX"
    find "$PREFIX/bin" -maxdepth 1 -type f -exec chmod +x {} +

    # Create python3 -> python3.14 symlink if absent (the archive only ships
    # the versioned binary; most tooling expects the generic 'python3' name).
    if [[ -f "$PREFIX/bin/python3.14" && ! -e "$PREFIX/bin/python3" ]]; then
        ln -sf python3.14 "$PREFIX/bin/python3"
    fi
fi

devkit_write_receipt "$TOOL" "$VERSION" "$DEVKIT_PLATFORM" "$PREFIX"

echo "==> Python ${VERSION} installed to ${PREFIX}"
echo "    Add ${PREFIX} (Windows) or ${PREFIX}/bin (Linux) to your PATH."
