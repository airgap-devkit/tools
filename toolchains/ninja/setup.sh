#!/usr/bin/env bash
set -euo pipefail

TOOL="ninja"
VERSION="1.13.2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../../.." && pwd)/prebuilt}"

if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OS" == "Windows_NT" ]]; then
    PLATFORM="windows"
    ARCHIVE="ninja-${VERSION}-windows.tar.xz"
    BINARY="ninja.exe"
    DEFAULT_PREFIX="${LOCALAPPDATA}/airgap-cpp-devkit/ninja"
else
    PLATFORM="linux"
    ARCHIVE="ninja-${VERSION}-linux.tar.xz"
    BINARY="ninja"
    if [[ "$(id -u)" == "0" ]]; then
        DEFAULT_PREFIX="/opt/airgap-cpp-devkit/ninja"
    else
        DEFAULT_PREFIX="${HOME}/.local/share/airgap-cpp-devkit/ninja"
    fi
fi

PREFIX="${INSTALL_PREFIX:-$DEFAULT_PREFIX}"
PARTS_DIR="$PREBUILT_DIR/toolchains/ninja/${VERSION}"
ARCHIVE_PATH="$PARTS_DIR/$ARCHIVE"

echo "==> Installing Ninja ${VERSION} (${PLATFORM}) to ${PREFIX}/bin"

if [[ ! -f "$ARCHIVE_PATH" ]]; then
    echo "ERROR: Archive not found: $ARCHIVE_PATH" >&2
    exit 1
fi

mkdir -p "$PREFIX/bin"
tar -xJf "$ARCHIVE_PATH" -C "$PREFIX/bin" "$BINARY"
chmod +x "$PREFIX/bin/$BINARY"

cat > "$PREFIX/INSTALL_RECEIPT.txt" << RECEIPT
tool=${TOOL}
version=${VERSION}
platform=${PLATFORM}
install_prefix=${PREFIX}
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RECEIPT

echo "==> Ninja ${VERSION} installed to ${PREFIX}/bin/${BINARY}"
