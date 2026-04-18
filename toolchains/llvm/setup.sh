#!/usr/bin/env bash
set -euo pipefail

TOOL="llvm"
VERSION="22.1.3"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../../.." && pwd)/prebuilt}"

# Detect platform
if [[ "${AIRGAP_OS:-}" == "windows" || "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "${OS:-}" == "Windows_NT" ]]; then
    PLATFORM="windows"
    ARCHIVE="clang+llvm-${VERSION}-x86_64-pc-windows-msvc.tar.xz"
    DEFAULT_PREFIX="${LOCALAPPDATA:-$HOME/AppData/Local}/airgap-cpp-devkit/clang-llvm"
else
    PLATFORM="linux"
    ARCHIVE="LLVM-${VERSION}-Linux-X64.tar.xz"
    if [[ "$(id -u)" == "0" ]]; then
        DEFAULT_PREFIX="/opt/airgap-cpp-devkit/clang-llvm"
    else
        DEFAULT_PREFIX="${HOME}/.local/share/airgap-cpp-devkit/clang-llvm"
    fi
fi

PREFIX="${INSTALL_PREFIX:-$DEFAULT_PREFIX}"
while [[ $# -gt 0 ]]; do
    case "$1" in --prefix) PREFIX="$2"; shift 2 ;; *) shift ;; esac
done
PARTS_DIR="$PREBUILT_DIR/toolchains/llvm/${VERSION}"

echo "==> Installing LLVM/Clang ${VERSION} (${PLATFORM}) to ${PREFIX}"

if [[ ! -d "$PARTS_DIR" ]]; then
    echo "ERROR: Prebuilt parts not found at: $PARTS_DIR" >&2
    echo "       Clone the prebuilt submodule or run from the devkit root." >&2
    exit 1
fi

# Verify all parts present
PARTS=("$PARTS_DIR/${ARCHIVE}.part-"*)
if [[ ${#PARTS[@]} -eq 0 || ! -f "${PARTS[0]}" ]]; then
    echo "ERROR: No parts found matching ${ARCHIVE}.part-* in $PARTS_DIR" >&2
    exit 1
fi
echo "    Found ${#PARTS[@]} parts."

if [[ "$PLATFORM" == "windows" ]]; then
    MSYS_NO_PATHCONV=1 cmd.exe /c mkdir "$PREFIX" 2>/dev/null || true
    PREFIX="$(cygpath -u -- "$PREFIX")"
else
    mkdir -p "$PREFIX"
fi

echo "    Reassembling and extracting (this may take a moment)..."
cat "${PARTS[@]}" | tar -xJ --strip-components=1 -C "$PREFIX"

# Write install receipt
cat > "$PREFIX/INSTALL_RECEIPT.txt" << RECEIPT
tool=${TOOL}
version=${VERSION}
platform=${PLATFORM}
install_prefix=${PREFIX}
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
includes=clang,clang++,clang-format,clang-tidy,lld,llvm-ar,llvm-nm
RECEIPT

echo "==> LLVM/Clang ${VERSION} installed to ${PREFIX}"
echo "    Add ${PREFIX}/bin to your PATH."
