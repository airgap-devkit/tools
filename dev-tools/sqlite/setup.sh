#!/usr/bin/env bash
set -euo pipefail

TOOL="sqlite"
VERSION="3.53.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"
PARTS_DIR="$PREBUILT_DIR/dev-tools/sqlite/${VERSION}"

if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OS" == "Windows_NT" ]]; then
    PLATFORM="windows"
    ARCHIVE="sqlite-tools-${VERSION}-windows-x64.tar.xz"
    DEFAULT_PREFIX="${LOCALAPPDATA}/airgap-cpp-devkit/sqlite"
else
    PLATFORM="linux"
    if [[ "$(id -u)" == "0" ]]; then
        DEFAULT_PREFIX="/opt/airgap-cpp-devkit/sqlite"
    else
        DEFAULT_PREFIX="${HOME}/.local/share/airgap-cpp-devkit/sqlite"
    fi
    # RHEL 8: prefer RPM if root
    RPM="$PARTS_DIR/sqlite-3.26.0-20.el8_10.x86_64.rpm"
    if command -v rpm &>/dev/null && [[ "$(id -u)" == "0" ]] && [[ -f "$RPM" ]]; then
        echo "==> Installing SQLite via RPM (RHEL 8)..."
        rpm -ivh "$RPM"
        mkdir -p "$DEFAULT_PREFIX"
        cat > "$DEFAULT_PREFIX/INSTALL_RECEIPT.txt" << RECEIPT
tool=${TOOL}
version=3.26.0
platform=linux-rhel8
install_prefix=system
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RECEIPT
        echo "==> SQLite (RHEL 8 RPM) installed."
        exit 0
    fi
    ARCHIVE="sqlite-tools-${VERSION}-linux-x64.tar.xz"
fi

PREFIX="${INSTALL_PREFIX:-$DEFAULT_PREFIX}"
ARCHIVE_PATH="$PARTS_DIR/$ARCHIVE"

echo "==> Installing SQLite CLI ${VERSION} (${PLATFORM}) to ${PREFIX}/bin"

if [[ ! -f "$ARCHIVE_PATH" ]]; then
    echo "ERROR: Archive not found: $ARCHIVE_PATH" >&2; exit 1
fi

mkdir -p "$PREFIX/bin"
tar -xJf "$ARCHIVE_PATH" -C "$PREFIX/bin" --strip-components=0

cat > "$PREFIX/INSTALL_RECEIPT.txt" << RECEIPT
tool=${TOOL}
version=${VERSION}
platform=${PLATFORM}
install_prefix=${PREFIX}
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RECEIPT

echo "==> SQLite CLI ${VERSION} installed to ${PREFIX}/bin"
