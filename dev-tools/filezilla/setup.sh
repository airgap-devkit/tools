#!/usr/bin/env bash
set -euo pipefail

TOOL="filezilla"
VERSION="3.70.4"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"
PARTS_DIR="$PREBUILT_DIR/dev-tools/filezilla/${VERSION}"

if [[ "${AIRGAP_OS:-}" == "windows" || "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "${OS:-}" == "Windows_NT" ]]; then
    PLATFORM="windows"
    DEFAULT_PREFIX="${LOCALAPPDATA:-$HOME/AppData/Local}/airgap-cpp-devkit/filezilla"
else
    PLATFORM="linux"
    if [[ "$(id -u)" == "0" ]]; then
        DEFAULT_PREFIX="/opt/airgap-cpp-devkit/filezilla"
    else
        DEFAULT_PREFIX="${HOME}/.local/share/airgap-cpp-devkit/filezilla"
    fi
fi

PREFIX="${INSTALL_PREFIX:-$DEFAULT_PREFIX}"
while [[ $# -gt 0 ]]; do
    case "$1" in --prefix) PREFIX="$2"; shift 2 ;; *) shift ;; esac
done

echo "==> Installing FileZilla ${VERSION} (${PLATFORM}) to ${PREFIX}"

if [[ "$PLATFORM" == "windows" ]]; then
    INSTALLER="$PARTS_DIR/FileZilla_${VERSION}_win64_sponsored2-setup.exe"
    if [[ ! -f "$INSTALLER" ]]; then
        echo "ERROR: Installer not found: $INSTALLER" >&2; exit 1
    fi
    MSYS_NO_PATHCONV=1 cmd.exe /c mkdir "${PREFIX}" 2>/dev/null || true
    PREFIX_WIN="$(cygpath -w "$PREFIX")"
    "$INSTALLER" /S /D="$PREFIX_WIN"
else
    ARCHIVE="$PARTS_DIR/FileZilla_${VERSION}_x86_64-linux-gnu.tar.xz"
    if [[ ! -f "$ARCHIVE" ]]; then
        echo "ERROR: Archive not found: $ARCHIVE" >&2; exit 1
    fi
    mkdir -p "$PREFIX"
    tar -xJf "$ARCHIVE" -C "$PREFIX" --strip-components=1
    mkdir -p "$PREFIX/bin"
    if [[ -f "$PREFIX/filezilla" && ! -f "$PREFIX/bin/filezilla" ]]; then
        ln -sf "$PREFIX/filezilla" "$PREFIX/bin/filezilla"
    fi
fi

cat > "$PREFIX/INSTALL_RECEIPT.txt" << RECEIPT
tool=${TOOL}
version=${VERSION}
platform=${PLATFORM}
install_prefix=${PREFIX}
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RECEIPT

echo "==> FileZilla ${VERSION} installed to ${PREFIX}"
