#!/usr/bin/env bash
set -euo pipefail

TOOL="7zip"
VERSION="26.00"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"
PARTS_DIR="$PREBUILT_DIR/dev-tools/7zip/${VERSION}"

if [[ "${AIRGAP_OS:-}" == "windows" || "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "${OS:-}" == "Windows_NT" ]]; then
    PLATFORM="windows"
    DEFAULT_PREFIX="${LOCALAPPDATA:-$HOME/AppData/Local}/airgap-cpp-devkit/7zip"
else
    PLATFORM="linux"
    if [[ "$(id -u)" == "0" ]]; then
        DEFAULT_PREFIX="/opt/airgap-cpp-devkit/7zip"
    else
        DEFAULT_PREFIX="${HOME}/.local/share/airgap-cpp-devkit/7zip"
    fi
fi

PREFIX="${INSTALL_PREFIX:-$DEFAULT_PREFIX}"
while [[ $# -gt 0 ]]; do
    case "$1" in --prefix) PREFIX="$2"; shift 2 ;; *) shift ;; esac
done

echo "==> Installing 7-Zip ${VERSION} (${PLATFORM}) to ${PREFIX}"

if [[ "$PLATFORM" == "windows" ]]; then
    MSYS_NO_PATHCONV=1 cmd.exe /c mkdir "${PREFIX}\\bin" 2>/dev/null || true
    PREFIX="$(cygpath -u -- "$PREFIX")"
else
    mkdir -p "$PREFIX/bin"
fi

if [[ "$PLATFORM" == "windows" ]]; then
    INSTALLER="$PARTS_DIR/7z${VERSION/./}-x64.exe"
    if [[ ! -f "$INSTALLER" ]]; then
        echo "ERROR: Installer not found: $INSTALLER" >&2; exit 1
    fi
    # Run silent install
    "$INSTALLER" /S /D="$(cygpath -w "$PREFIX")"
else
    ARCHIVE="$PARTS_DIR/7z${VERSION/./}-linux-x64.tar.xz"
    if [[ ! -f "$ARCHIVE" ]]; then
        echo "ERROR: Archive not found: $ARCHIVE" >&2; exit 1
    fi
    tar -xJf "$ARCHIVE" -C "$PREFIX/bin" 7zzs 2>/dev/null || tar -xJf "$ARCHIVE" -C "$PREFIX/bin"
    # 7zip on Linux ships as 7zzs — create a 7z symlink
    if [[ -f "$PREFIX/bin/7zzs" && ! -f "$PREFIX/bin/7z" ]]; then
        ln -sf 7zzs "$PREFIX/bin/7z"
    fi
fi

cat > "$PREFIX/INSTALL_RECEIPT.txt" << RECEIPT
tool=${TOOL}
version=${VERSION}
platform=${PLATFORM}
install_prefix=${PREFIX}
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RECEIPT

echo "==> 7-Zip ${VERSION} installed to ${PREFIX}"
