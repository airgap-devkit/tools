#!/usr/bin/env bash
set -euo pipefail

TOOL="zlib"
VERSION="1.3.2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/../../lib/devkit-install.sh"

PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"
PREFIX="${INSTALL_PREFIX:-$(devkit_default_prefix "$TOOL")}"
JOBS="${MAKE_JOBS:-$(nproc 2>/dev/null || echo 4)}"
REBUILD=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)  PREFIX="$2"; shift 2 ;;
        --jobs)    JOBS="$2";   shift 2 ;;
        --rebuild) REBUILD=1;   shift ;;
        *) shift ;;
    esac
done

RECEIPT="$PREFIX/INSTALL_RECEIPT.txt"
if [[ "$REBUILD" -eq 0 && -f "$RECEIPT" ]]; then
    echo "==> zlib already installed at ${PREFIX} (use --rebuild to force). Skipping."
    exit 0
fi

echo "==> Installing zlib ${VERSION} (${DEVKIT_PLATFORM}, CMake source build) to ${PREFIX}"

# zlib source archives ship without a platform keyword in the filename, so the
# per-platform archive is selected explicitly (not via devkit_find_file).
PARTS_DIR="$PREBUILT_DIR/lib/zlib/${VERSION}"
if [[ "$DEVKIT_PLATFORM" == "windows" ]]; then
    ARCHIVE="$PARTS_DIR/zlib132.zip"
else
    ARCHIVE="$PARTS_DIR/zlib-1.3.2.tar.gz"
fi
if [[ ! -f "$ARCHIVE" ]]; then
    echo "ERROR: zlib source archive not found: $ARCHIVE" >&2; exit 1
fi
devkit_verify_archive "$PARTS_DIR/manifest.json" "$ARCHIVE"

# Build dependencies: CMake plus a C compiler (and mingw32-make on Windows).
MISSING=()
command -v cmake &>/dev/null || MISSING+=("cmake")
if [[ "$DEVKIT_PLATFORM" == "windows" ]]; then
    command -v gcc &>/dev/null || command -v cl &>/dev/null || MISSING+=("gcc or MSVC")
    command -v mingw32-make &>/dev/null || command -v make &>/dev/null \
        || command -v nmake &>/dev/null || MISSING+=("mingw32-make/make/nmake")
else
    command -v cc &>/dev/null || command -v gcc &>/dev/null || command -v clang &>/dev/null \
        || MISSING+=("cc/gcc/clang")
    command -v make &>/dev/null || MISSING+=("make")
fi
if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "ERROR: missing build dependencies: ${MISSING[*]}" >&2
    echo "       Install a devkit toolchain + CMake first (e.g. profile 'minimal')." >&2
    exit 1
fi

BUILD_DIR="$(mktemp -d)"
# Register via the lib helper, not a bare EXIT handler: the latter would replace
# the library's temp-root cleanup and leak it.
devkit_add_exit_trap 'rm -rf "$BUILD_DIR"'

echo "==> Extracting $(basename "$ARCHIVE")..."
devkit_extract "$ARCHIVE" "$BUILD_DIR" 0
SRC_DIR="$BUILD_DIR/zlib-${VERSION}"
[[ -d "$SRC_DIR" ]] || { echo "ERROR: expected source dir $SRC_DIR not found" >&2; exit 1; }

# On Windows the MinGW toolchain drives CMake through mingw32-make; on Linux the
# default Unix Makefiles generator picks up the system compiler.
GEN_ARGS=()
if [[ "$DEVKIT_PLATFORM" == "windows" ]] && command -v mingw32-make &>/dev/null; then
    GEN_ARGS=(-G "MinGW Makefiles" -DCMAKE_MAKE_PROGRAM=mingw32-make)
fi

# The devkit ships LLVM/clang, not gcc. When no cc/gcc is on PATH, point CMake
# at clang so the source build succeeds with the toolchain that is present.
if [[ "$DEVKIT_PLATFORM" != "windows" ]] \
   && ! command -v cc &>/dev/null && ! command -v gcc &>/dev/null \
   && command -v clang &>/dev/null; then
    export CC="${CC:-clang}" CXX="${CXX:-clang++}"
    echo "==> Using clang (${CC}/${CXX}) — no cc/gcc on PATH."
fi

echo "==> Configuring (CMake)..."
cmake -S "$SRC_DIR" -B "$SRC_DIR/build" "${GEN_ARGS[@]}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX"

echo "==> Building (${JOBS} job(s))..."
cmake --build "$SRC_DIR/build" --config Release --parallel "$JOBS"

echo "==> Installing..."
cmake --install "$SRC_DIR/build" --config Release

devkit_write_receipt "$TOOL" "$VERSION" "$DEVKIT_PLATFORM" "$PREFIX" \
    "includes=zlib.h,zconf.h" \
    "build=cmake-source"

echo "==> zlib ${VERSION} installed to ${PREFIX}"
