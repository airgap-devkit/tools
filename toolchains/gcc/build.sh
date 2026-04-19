#!/usr/bin/env bash
# Builds GCC 15.2.0 from source on Linux.
# Windows: WinLibs provides prebuilt-only — source build not supported here.
# Requires: make, gcc (existing), binutils, flex, bison, texinfo, ~10GB disk.
# Build time: 60-180 min depending on CPU cores.
set -euo pipefail

VERSION="15.2.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCES_DIR="$SCRIPT_DIR/sources"
SOURCE_ARCHIVE="$SOURCES_DIR/gcc-${VERSION}.tar.xz"

if [[ "${AIRGAP_OS:-}" == "windows" || "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "${OS:-}" == "Windows_NT" ]] || command -v cmd.exe &>/dev/null 2>&1; then
    echo "ERROR: GCC source build is not supported on Windows." >&2
    echo "       Use setup.sh to install the WinLibs prebuilt instead." >&2
    exit 1
fi

if [[ "$(id -u)" == "0" ]]; then
    DEFAULT_PREFIX="/opt/airgap-cpp-devkit/gcc"
else
    DEFAULT_PREFIX="${HOME}/.local/share/airgap-cpp-devkit/gcc"
fi

PREFIX="${INSTALL_PREFIX:-$DEFAULT_PREFIX}"
BUILD_DIR="${BUILD_DIR:-/tmp/gcc-build-${VERSION}}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"

echo "==> Building GCC ${VERSION} from source"
echo "    Prefix   : ${PREFIX}"
echo "    Build dir: ${BUILD_DIR}"
echo "    Jobs     : ${JOBS}"
echo "    WARNING  : This takes 60-180 minutes and ~10GB disk space."
echo ""

if [[ ! -f "$SOURCE_ARCHIVE" ]]; then
    echo "ERROR: Source archive not found: $SOURCE_ARCHIVE" >&2
    exit 1
fi

# Check required build deps
for dep in make flex bison makeinfo; do
    if ! command -v "$dep" &>/dev/null; then
        echo "WARNING: '$dep' not found — build may fail." >&2
    fi
done

mkdir -p "$BUILD_DIR/src" "$BUILD_DIR/build"
echo "    Extracting source..."
tar -xJf "$SOURCE_ARCHIVE" --strip-components=1 -C "$BUILD_DIR/src"

echo "    Downloading GCC prerequisites (gmp, mpfr, mpc)..."
cd "$BUILD_DIR/src"
# contrib/download_prerequisites pulls from GNU mirrors — needs internet or vendored copies
if [[ -f "contrib/download_prerequisites" ]]; then
    bash contrib/download_prerequisites
else
    echo "ERROR: contrib/download_prerequisites not found in source tree." >&2
    exit 1
fi

echo "    Configuring..."
cd "$BUILD_DIR/build"
"$BUILD_DIR/src/configure" \
    --prefix="$PREFIX" \
    --enable-languages=c,c++ \
    --disable-multilib \
    --enable-checking=release \
    --with-system-zlib

echo "    Building (${JOBS} jobs)..."
make -j"$JOBS"
make install

cat > "$PREFIX/INSTALL_RECEIPT.txt" << RECEIPT
tool=gcc
version=${VERSION}
platform=linux
install_prefix=${PREFIX}
build_type=source
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
includes=gcc,g++,gcov
RECEIPT

echo ""
echo "==> GCC ${VERSION} built and installed to ${PREFIX}"
echo "    Add ${PREFIX}/bin to your PATH."
