#!/usr/bin/env bash
set -euo pipefail

# Notepad++ is Windows-only
if [[ "${AIRGAP_OS:-}" != "windows" && "$OSTYPE" != "msys" && "$OSTYPE" != "cygwin" && "${OS:-}" != "Windows_NT" ]]; then
    echo "Notepad++ is a Windows-only tool. Skipping on Linux." >&2
    exit 0
fi

TOOL="notepadpp"
VERSION="8.9.3"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"
PARTS_DIR="$PREBUILT_DIR/dev-tools/notepadpp/${VERSION}"
PORTABLE_ZIP="$PARTS_DIR/npp.${VERSION}.portable.x64.zip"
DEFAULT_PREFIX="${LOCALAPPDATA:-$HOME/AppData/Local}/airgap-cpp-devkit/notepadpp"
PREFIX="${INSTALL_PREFIX:-$DEFAULT_PREFIX}"

while [[ $# -gt 0 ]]; do
    case "$1" in --prefix) PREFIX="$2"; shift 2 ;; *) shift ;; esac
done

echo "==> Installing Notepad++ ${VERSION} (Windows, portable) to ${PREFIX}"

if [[ ! -f "$PORTABLE_ZIP" ]]; then
    echo "ERROR: Portable archive not found: $PORTABLE_ZIP" >&2
    exit 1
fi

MSYS_NO_PATHCONV=1 cmd.exe /c mkdir "${PREFIX}" 2>/dev/null || true
PREFIX="$(cygpath -u -- "$PREFIX")"

unzip -qo "$PORTABLE_ZIP" -d "$PREFIX"

cat > "$PREFIX/INSTALL_RECEIPT.txt" << RECEIPT
tool=${TOOL}
version=${VERSION}
platform=windows
install_prefix=${PREFIX}
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RECEIPT

echo "==> Notepad++ ${VERSION} installed to ${PREFIX}"
echo "    Launcher: ${PREFIX}/notepad++.exe"
echo "    Tip: for a full system-wide install, run the installer manually:"
echo "         ${PARTS_DIR}/npp.${VERSION}.Installer.x64.exe"
