#!/usr/bin/env bash
set -euo pipefail

TOOL="python"
VERSION="3.14.4"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"
PARTS_DIR="$PREBUILT_DIR/languages/python"

if [[ "${AIRGAP_OS:-}" == "windows" || "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "${OS:-}" == "Windows_NT" ]]; then
    PLATFORM="windows"
    # Use full package (35MB) for devkit; embed (12MB) is also available
    ARCHIVE="python-${VERSION}-amd64.zip"
    DEFAULT_PREFIX="${LOCALAPPDATA:-$HOME/AppData/Local}/airgap-cpp-devkit/python"
else
    PLATFORM="linux"
    ARCHIVE="cpython-${VERSION}-linux-x64.tar.xz"
    if [[ "$(id -u)" == "0" ]]; then
        DEFAULT_PREFIX="/opt/airgap-cpp-devkit/python"
    else
        DEFAULT_PREFIX="${HOME}/.local/share/airgap-cpp-devkit/python"
    fi
fi

PREFIX="${INSTALL_PREFIX:-$DEFAULT_PREFIX}"
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
    if [[ "$PLATFORM" == "linux" ]]; then
        if [[ "$(id -u)" == "0" ]]; then
            _py="/opt/airgap-cpp-devkit/python/bin/python3"
        else
            _py="${HOME}/.local/share/airgap-cpp-devkit/python/bin/python3"
        fi
    else
        _py="${LOCALAPPDATA:-$HOME/AppData/Local}/airgap-cpp-devkit/python/python3.exe"
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
        if [[ "$PLATFORM" == "linux" ]] && [[ "$bname" == *-win_amd64* || "$bname" == *-win32* ]]; then
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

    mkdir -p "$PREFIX"
    cat > "$PREFIX/INSTALL_RECEIPT.txt" << RECEIPT
tool=pip-packages
version=vendored
platform=${PLATFORM}
install_prefix=${PREFIX}
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RECEIPT

    echo "==> Pip packages installed."
    exit 0
fi

echo "==> Installing Python ${VERSION} (${PLATFORM}) to ${PREFIX}"

if [[ "$PLATFORM" == "windows" ]]; then
    mkdir -p "$PREFIX"
    PREFIX="$(cygpath -u -- "$PREFIX")"
else
    mkdir -p "$PREFIX"
fi

if [[ "$PLATFORM" == "windows" ]]; then
    ARCHIVE_PATH="$PARTS_DIR/$ARCHIVE"
    if [[ ! -f "$ARCHIVE_PATH" ]]; then
        echo "ERROR: Archive not found: $ARCHIVE_PATH" >&2; exit 1
    fi
    unzip -q "$ARCHIVE_PATH" -d "$PREFIX"
else
    PARTS=("$PARTS_DIR/${ARCHIVE}.part-"*)
    if [[ ${#PARTS[@]} -eq 0 || ! -f "${PARTS[0]}" ]]; then
        echo "ERROR: No parts found for ${ARCHIVE}" >&2; exit 1
    fi
    echo "    Found ${#PARTS[@]} parts."
    # Archive is structured as ./python/bin/..., so strip 2 components
    # (the leading './' and the 'python/' directory) to land in $PREFIX.
    cat "${PARTS[@]}" | tar -xJ --strip-components=2 -C "$PREFIX"
    find "$PREFIX/bin" -maxdepth 1 -type f -exec chmod +x {} +

    # Create python3 -> python3.14 symlink if absent (the archive only ships
    # the versioned binary; most tooling expects the generic 'python3' name).
    if [[ -f "$PREFIX/bin/python3.14" && ! -e "$PREFIX/bin/python3" ]]; then
        ln -sf python3.14 "$PREFIX/bin/python3"
    fi
fi

cat > "$PREFIX/INSTALL_RECEIPT.txt" << RECEIPT
tool=${TOOL}
version=${VERSION}
platform=${PLATFORM}
install_prefix=${PREFIX}
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RECEIPT

echo "==> Python ${VERSION} installed to ${PREFIX}"
echo "    Add ${PREFIX} (Windows) or ${PREFIX}/bin (Linux) to your PATH."
