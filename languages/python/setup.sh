#!/usr/bin/env bash
set -euo pipefail

TOOL="python"
VERSION="3.14.4"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"
PARTS_DIR="$PREBUILT_DIR/languages/python"

if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OS" == "Windows_NT" ]]; then
    PLATFORM="windows"
    # Use full package (35MB) for devkit; embed (12MB) is also available
    ARCHIVE="python-${VERSION}-amd64.zip"
    DEFAULT_PREFIX="${LOCALAPPDATA}/airgap-cpp-devkit/python"
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

echo "==> Installing Python ${VERSION} (${PLATFORM}) to ${PREFIX}"

mkdir -p "$PREFIX"

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
    cat "${PARTS[@]}" | tar -xJ --strip-components=1 -C "$PREFIX"
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
