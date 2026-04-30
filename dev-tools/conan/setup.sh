#!/usr/bin/env bash
set -euo pipefail

TOOL="conan"
VERSION="2.28.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"
PARTS_DIR="$PREBUILT_DIR/dev-tools/conan/${VERSION}"

if [[ "${AIRGAP_OS:-}" == "windows" || "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "${OS:-}" == "Windows_NT" ]]; then
    PLATFORM="windows"
    ARCHIVE="conan-${VERSION}-windows-x86_64.tar.xz"
    DEFAULT_PREFIX="${LOCALAPPDATA:-$HOME/AppData/Local}/airgap-cpp-devkit/conan"
else
    PLATFORM="linux"
    ARCHIVE="conan-${VERSION}-linux-x86_64.tgz"
    if [[ "$(id -u)" == "0" ]]; then
        DEFAULT_PREFIX="/opt/airgap-cpp-devkit/conan"
    else
        DEFAULT_PREFIX="${HOME}/.local/share/airgap-cpp-devkit/conan"
    fi
fi

PREFIX="${INSTALL_PREFIX:-$DEFAULT_PREFIX}"
while [[ $# -gt 0 ]]; do
    case "$1" in --prefix) PREFIX="$2"; shift 2 ;; *) shift ;; esac
done

echo "==> Installing Conan ${VERSION} (${PLATFORM}) to ${PREFIX}"

ARCHIVE_PATH="$PARTS_DIR/$ARCHIVE"
if [[ ! -f "$ARCHIVE_PATH" ]]; then
    echo "ERROR: Archive not found: $ARCHIVE_PATH" >&2; exit 1
fi

if [[ "$PLATFORM" == "windows" ]]; then
    MSYS_NO_PATHCONV=1 cmd.exe /c mkdir "$PREFIX" 2>/dev/null || true
    PREFIX="$(cygpath -u -- "$PREFIX")"
    tar -xJf "$ARCHIVE_PATH" -C "$PREFIX" --strip-components=0
else
    mkdir -p "$PREFIX/bin"
    tar -xzf "$ARCHIVE_PATH" -C "$PREFIX/bin" --strip-components=1
    chmod +x "$PREFIX/bin/conan"
fi

cat > "$PREFIX/INSTALL_RECEIPT.txt" << RECEIPT
tool=${TOOL}
version=${VERSION}
platform=${PLATFORM}
install_prefix=${PREFIX}
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RECEIPT

echo "==> Conan ${VERSION} installed."
