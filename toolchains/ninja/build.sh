#!/usr/bin/env bash
# Builds Ninja 1.13.2 from source.
# Requires: cmake (or python3 + re-gen.py), a C++11 compiler.
# Build time: ~1 minute.
set -euo pipefail

VERSION="1.13.2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCES_DIR="$SCRIPT_DIR/sources"
SOURCE_ARCHIVE="$SOURCES_DIR/ninja-${VERSION}-src.tar.xz"

if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OS" == "Windows_NT" ]]; then
    PLATFORM="windows"
    BINARY="ninja.exe"
    DEFAULT_PREFIX="${LOCALAPPDATA}/airgap-cpp-devkit/ninja"
else
    PLATFORM="linux"
    BINARY="ninja"
    if [[ "$(id -u)" == "0" ]]; then
        DEFAULT_PREFIX="/opt/airgap-cpp-devkit/ninja"
    else
        DEFAULT_PREFIX="${HOME}/.local/share/airgap-cpp-devkit/ninja"
    fi
fi

PREFIX="${INSTALL_PREFIX:-$DEFAULT_PREFIX}"
BUILD_DIR="${BUILD_DIR:-/tmp/ninja-build-${VERSION}}"

echo "==> Building Ninja ${VERSION} from source (${PLATFORM})"

if [[ ! -f "$SOURCE_ARCHIVE" ]]; then
    echo "ERROR: Source archive not found: $SOURCE_ARCHIVE" >&2
    exit 1
fi

mkdir -p "$BUILD_DIR"
tar -xJf "$SOURCE_ARCHIVE" --strip-components=1 -C "$BUILD_DIR"

if command -v cmake &>/dev/null; then
    echo "    Building via CMake..."
    cmake -S "$BUILD_DIR" -B "$BUILD_DIR/cmake-build" \
          -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_INSTALL_PREFIX="$PREFIX"
    cmake --build "$BUILD_DIR/cmake-build" --target install -- -j"$(nproc 2>/dev/null || echo 4)"
else
    echo "    CMake not found — falling back to bootstrap build..."
    cd "$BUILD_DIR"
    python3 configure.py --bootstrap
    mkdir -p "$PREFIX/bin"
    cp "$BUILD_DIR/$BINARY" "$PREFIX/bin/$BINARY"
    chmod +x "$PREFIX/bin/$BINARY"
fi

cat > "$PREFIX/INSTALL_RECEIPT.txt" << RECEIPT
tool=ninja
version=${VERSION}
platform=${PLATFORM}
install_prefix=${PREFIX}
build_type=source
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RECEIPT

rm -rf "$BUILD_DIR"
echo "==> Ninja ${VERSION} installed to ${PREFIX}/bin/${BINARY}"
