#!/usr/bin/env bash
set -euo pipefail

TOOL="conan"
VERSION="2.27.1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"
PARTS_DIR="$PREBUILT_DIR/dev-tools/conan/${VERSION}"

if [[ "${AIRGAP_OS:-}" == "windows" || "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "${OS:-}" == "Windows_NT" ]]; then
    PLATFORM="windows"
    ARCHIVE="conan-${VERSION}-windows-x86_64.tar.xz"
    DEFAULT_PREFIX="${LOCALAPPDATA:-$HOME/AppData/Local}/airgap-cpp-devkit/conan"
else
    PLATFORM="linux"
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

if [[ "$PLATFORM" == "windows" ]]; then
    ARCHIVE_PATH="$PARTS_DIR/$ARCHIVE"
    if [[ ! -f "$ARCHIVE_PATH" ]]; then
        echo "ERROR: Archive not found: $ARCHIVE_PATH" >&2; exit 1
    fi
    MSYS_NO_PATHCONV=1 cmd.exe /c mkdir "$PREFIX" 2>/dev/null || true
    PREFIX="$(cygpath -u -- "$PREFIX")"
    tar -xJf "$ARCHIVE_PATH" -C "$PREFIX" --strip-components=0
else
    DEB="$PARTS_DIR/conan-${VERSION}-amd64.deb"
    if [[ ! -f "$DEB" ]]; then
        echo "ERROR: .deb not found: $DEB" >&2; exit 1
    fi
    if command -v dpkg &>/dev/null; then
        dpkg -i "$DEB"
    elif command -v rpm &>/dev/null; then
        # RHEL 8: install via pip from the Windows zip fallback is not available
        # Extract conan binary from .deb manually
        mkdir -p "$PREFIX/bin"
        _tmp_deb="$(mktemp -d)"
        trap 'rm -rf "$_tmp_deb"' EXIT
        dpkg-deb --extract "$DEB" "$_tmp_deb" 2>/dev/null || ar x "$DEB" --output="$_tmp_deb"
        find "$_tmp_deb" -name "conan" -type f -exec cp {} "$PREFIX/bin/" \;
        chmod +x "$PREFIX/bin/conan"
    else
        echo "ERROR: Neither dpkg nor rpm found. Cannot install .deb on this system." >&2
        exit 1
    fi
fi

cat > "$PREFIX/INSTALL_RECEIPT.txt" << RECEIPT
tool=${TOOL}
version=${VERSION}
platform=${PLATFORM}
install_prefix=${PREFIX}
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RECEIPT

echo "==> Conan ${VERSION} installed."
