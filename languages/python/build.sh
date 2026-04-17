#!/usr/bin/env bash
# Builds Python 3.14.4 from source on Linux.
# Windows: use the embeddable package from prebuilt/ via setup.sh.
# Requires: gcc, make, libssl-dev (or openssl-devel), zlib-devel, ~500MB disk.
# Build time: ~10-20 min.
set -euo pipefail

VERSION="3.14.4"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCES_DIR="$SCRIPT_DIR/sources"
SOURCE_ARCHIVE="$SOURCES_DIR/Python-${VERSION}.tar.xz"

if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OS" == "Windows_NT" ]]; then
    echo "ERROR: Python source build is not supported on Windows." >&2
    echo "       Use setup.sh to install the embeddable package instead." >&2
    exit 1
fi

if [[ "$(id -u)" == "0" ]]; then
    DEFAULT_PREFIX="/opt/airgap-cpp-devkit/python"
else
    DEFAULT_PREFIX="${HOME}/.local/share/airgap-cpp-devkit/python"
fi

PREFIX="${INSTALL_PREFIX:-$DEFAULT_PREFIX}"
BUILD_DIR="${BUILD_DIR:-/tmp/python-build-${VERSION}}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"

echo "==> Building Python ${VERSION} from source"
echo "    Prefix   : ${PREFIX}"
echo "    Build dir: ${BUILD_DIR}"

if [[ ! -f "$SOURCE_ARCHIVE" ]]; then
    echo "ERROR: Source archive not found: $SOURCE_ARCHIVE" >&2
    exit 1
fi

mkdir -p "$BUILD_DIR"
echo "    Extracting source..."
tar -xJf "$SOURCE_ARCHIVE" --strip-components=1 -C "$BUILD_DIR"

echo "    Configuring..."
cd "$BUILD_DIR"
./configure \
    --prefix="$PREFIX" \
    --enable-optimizations \
    --with-ensurepip=install \
    --enable-shared \
    LDFLAGS="-Wl,-rpath,$PREFIX/lib"

echo "    Building (${JOBS} jobs)..."
make -j"$JOBS"
make install

cat > "$PREFIX/INSTALL_RECEIPT.txt" << RECEIPT
tool=python
version=${VERSION}
platform=linux
install_prefix=${PREFIX}
build_type=source
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RECEIPT

rm -rf "$BUILD_DIR"
echo "==> Python ${VERSION} installed to ${PREFIX}"
echo "    Executable: ${PREFIX}/bin/python3"
