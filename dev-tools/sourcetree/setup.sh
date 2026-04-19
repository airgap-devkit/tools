#!/usr/bin/env bash
set -euo pipefail

# SourceTree is Windows-only
if [[ "${AIRGAP_OS:-}" != "windows" && "$OSTYPE" != "msys" && "$OSTYPE" != "cygwin" && "${OS:-}" != "Windows_NT" ]]; then
    echo "SourceTree is a Windows-only tool. Skipping on Linux." >&2
    exit 0
fi

TOOL="sourcetree"
VERSION="3.4.30"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"
PARTS_DIR="$PREBUILT_DIR/dev-tools/sourcetree/${VERSION}"
INSTALLER="$PARTS_DIR/SourceTreeSetup-${VERSION}.exe"

# SourceTree's Squirrel installer always targets %LocalAppData%\SourceTree.
# The devkit prefix is used only to store the install receipt.
DEFAULT_PREFIX="${LOCALAPPDATA:-$HOME/AppData/Local}/airgap-cpp-devkit/sourcetree"
PREFIX="${INSTALL_PREFIX:-$DEFAULT_PREFIX}"
while [[ $# -gt 0 ]]; do
    case "$1" in --prefix) PREFIX="$2"; shift 2 ;; *) shift ;; esac
done

echo "==> Installing SourceTree ${VERSION} (Windows) ..."
echo "    Note: SourceTree installs to %LocalAppData%\\SourceTree (Squirrel default)."

if [[ ! -f "$INSTALLER" ]]; then
    echo "ERROR: Installer not found: $INSTALLER" >&2; exit 1
fi

"$INSTALLER" --silent

MSYS_NO_PATHCONV=1 cmd.exe /c mkdir "${PREFIX}" 2>/dev/null || true
PREFIX="$(cygpath -u -- "$PREFIX")"

cat > "$PREFIX/INSTALL_RECEIPT.txt" << RECEIPT
tool=${TOOL}
version=${VERSION}
platform=windows
install_prefix=${LOCALAPPDATA}/SourceTree
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RECEIPT

echo "==> SourceTree ${VERSION} installed."
echo "    Launcher: %LocalAppData%\\SourceTree\\SourceTree.exe"
