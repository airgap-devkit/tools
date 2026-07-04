#!/usr/bin/env bash
set -euo pipefail

TOOL="gdb"
VERSION="17.1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/devkit-install.sh"

# GDB is Linux-only (source build)
if [[ "$DEVKIT_PLATFORM" == "windows" ]]; then
    echo "GDB source build is a Linux-only operation. Skipping on Windows." >&2
    exit 0
fi

SOURCES_DIR="$SCRIPT_DIR/sources"
SOURCE_ARCHIVE="$SOURCES_DIR/gdb-${VERSION}.tar.gz"

PREFIX="${INSTALL_PREFIX:-$(devkit_default_prefix "$TOOL")}"
JOBS="${MAKE_JOBS:-$(nproc)}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix) PREFIX="$2"; shift 2 ;;
        --jobs)   JOBS="$2";   shift 2 ;;
        --rebuild) rm -f "$PREFIX/INSTALL_RECEIPT.txt"; shift ;;
        *) shift ;;
    esac
done

echo "==> Installing GDB ${VERSION} (Linux, source build) to ${PREFIX}"
echo "    Using ${JOBS} parallel job(s). This typically takes 20-30 minutes."

if [[ ! -f "$SOURCE_ARCHIVE" ]]; then
    echo "ERROR: Source archive not found: $SOURCE_ARCHIVE" >&2
    exit 1
fi

# Check required build dependencies
MISSING=()
for cmd in gcc g++ make; do
    command -v "$cmd" &>/dev/null || MISSING+=("$cmd")
done
for lib in readline/readline.h ncurses.h expat.h; do
    header="/usr/include/${lib}"
    [[ -f "$header" ]] || MISSING+=("header: $lib (install readline-devel / ncurses-devel / expat-devel)")
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "ERROR: Missing build dependencies:" >&2
    printf "  - %s\n" "${MISSING[@]}" >&2
    echo "" >&2
    echo "On RHEL 8, install via:" >&2
    echo "  dnf install gcc gcc-c++ make readline-devel ncurses-devel expat-devel" >&2
    exit 1
fi

BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT

echo "==> Extracting source archive..."
tar -xzf "$SOURCE_ARCHIVE" -C "$BUILD_DIR"
SRC_DIR="$BUILD_DIR/gdb-${VERSION}"

echo "==> Configuring..."
mkdir -p "$SRC_DIR/build"
cd "$SRC_DIR/build"
"$SRC_DIR/configure" \
    --prefix="$PREFIX" \
    --disable-sim \
    --with-python=no \
    --disable-werror \
    2>&1

echo "==> Building (${JOBS} jobs)..."
make -j"$JOBS" 2>&1

echo "==> Installing..."
make install 2>&1

devkit_write_receipt "$TOOL" "$VERSION" "$DEVKIT_PLATFORM" "$PREFIX"

echo "==> GDB ${VERSION} installed to ${PREFIX}"
echo "    Binary: ${PREFIX}/bin/gdb"
