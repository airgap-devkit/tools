#!/usr/bin/env bash
set -euo pipefail

TOOL="cmake"
VERSION="4.3.2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"
PARTS_DIR="$PREBUILT_DIR/build-tools/cmake/${VERSION}"

if [[ "${AIRGAP_OS:-}" == "windows" || "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "${OS:-}" == "Windows_NT" ]]; then
    PLATFORM="windows"
    ARCHIVE="cmake-${VERSION}-windows-x86_64.tar.xz"
    DEFAULT_PREFIX="${LOCALAPPDATA:-$HOME/AppData/Local}/airgap-cpp-devkit/cmake"
else
    PLATFORM="linux"
    ARCHIVE="cmake-${VERSION}-linux-x86_64.tar.xz"
    if [[ "$(id -u)" == "0" ]]; then
        DEFAULT_PREFIX="/opt/airgap-cpp-devkit/cmake"
    else
        DEFAULT_PREFIX="${HOME}/.local/share/airgap-cpp-devkit/cmake"
    fi
fi

PREFIX="${INSTALL_PREFIX:-$DEFAULT_PREFIX}"
while [[ $# -gt 0 ]]; do
    case "$1" in --prefix) PREFIX="$2"; shift 2 ;; *) shift ;; esac
done
ARCHIVE_PATH="$PARTS_DIR/$ARCHIVE"

echo "==> Installing CMake ${VERSION} (${PLATFORM}) to ${PREFIX}"

if [[ ! -f "$ARCHIVE_PATH" ]]; then
    echo "ERROR: Archive not found: $ARCHIVE_PATH" >&2; exit 1
fi

if [[ "$PLATFORM" == "windows" ]]; then
    MSYS_NO_PATHCONV=1 cmd.exe /c mkdir "$PREFIX" 2>/dev/null || true
    PREFIX="$(cygpath -u -- "$PREFIX")"
else
    mkdir -p "$PREFIX"
fi
tar -xJf "$ARCHIVE_PATH" -C "$PREFIX" --strip-components=0

cat > "$PREFIX/INSTALL_RECEIPT.txt" << RECEIPT
tool=${TOOL}
version=${VERSION}
platform=${PLATFORM}
install_prefix=${PREFIX}
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RECEIPT

echo "==> CMake ${VERSION} installed to ${PREFIX}"
echo "    Add ${PREFIX}/bin to your PATH."
