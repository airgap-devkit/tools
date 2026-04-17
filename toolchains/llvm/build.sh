#!/usr/bin/env bash
# Builds LLVM/Clang 22.1.3 from source.
# Requires: cmake, ninja, a C++17 compiler, python3, ~30GB free disk, ~8GB RAM.
# Build time: 45-120 min depending on CPU cores.
set -euo pipefail

VERSION="22.1.3"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCES_DIR="$SCRIPT_DIR/sources"

# Components to build — minimal set needed for devkit
LLVM_COMPONENTS="clang;clang-tools-extra;lld"

if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OS" == "Windows_NT" ]]; then
    PLATFORM="windows"
    DEFAULT_PREFIX="${LOCALAPPDATA}/airgap-cpp-devkit/clang-llvm"
    CMAKE_GENERATOR="Ninja"
else
    PLATFORM="linux"
    if [[ "$(id -u)" == "0" ]]; then
        DEFAULT_PREFIX="/opt/airgap-cpp-devkit/clang-llvm"
    else
        DEFAULT_PREFIX="${HOME}/.local/share/airgap-cpp-devkit/clang-llvm"
    fi
    CMAKE_GENERATOR="Ninja"
fi

PREFIX="${INSTALL_PREFIX:-$DEFAULT_PREFIX}"
BUILD_DIR="${BUILD_DIR:-/tmp/llvm-build-${VERSION}}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"

echo "==> Building LLVM/Clang ${VERSION} from source"
echo "    Platform : ${PLATFORM}"
echo "    Prefix   : ${PREFIX}"
echo "    Build dir: ${BUILD_DIR}"
echo "    Jobs     : ${JOBS}"
echo "    WARNING  : This takes 45-120 minutes and ~30GB disk space."
echo ""

# Locate source parts
PARTS=("$SOURCES_DIR/llvm-project-${VERSION}.src.tar.xz.part-"*)
if [[ ${#PARTS[@]} -eq 0 || ! -f "${PARTS[0]}" ]]; then
    echo "ERROR: Source parts not found in $SOURCES_DIR" >&2
    echo "       Expected: llvm-project-${VERSION}.src.tar.xz.part-*" >&2
    exit 1
fi

# Verify dependencies
for dep in cmake ninja python3; do
    if ! command -v "$dep" &>/dev/null; then
        echo "ERROR: '$dep' not found in PATH. Install it first." >&2
        exit 1
    fi
done

echo "    Found ${#PARTS[@]} source parts. Extracting..."
mkdir -p "$BUILD_DIR/src"
cat "${PARTS[@]}" | tar -xJ --strip-components=1 -C "$BUILD_DIR/src"

echo "    Configuring with CMake..."
cmake -S "$BUILD_DIR/src/llvm" \
      -B "$BUILD_DIR/build" \
      -G "$CMAKE_GENERATOR" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$PREFIX" \
      -DLLVM_ENABLE_PROJECTS="$LLVM_COMPONENTS" \
      -DLLVM_TARGETS_TO_BUILD="X86" \
      -DLLVM_BUILD_TOOLS=ON \
      -DLLVM_INCLUDE_TESTS=OFF \
      -DLLVM_INCLUDE_EXAMPLES=OFF \
      -DLLVM_INCLUDE_BENCHMARKS=OFF \
      -DCLANG_INCLUDE_TESTS=OFF \
      -DLLVM_ENABLE_ASSERTIONS=OFF \
      -DLLVM_PARALLEL_LINK_JOBS=2

echo "    Building (${JOBS} jobs)..."
cmake --build "$BUILD_DIR/build" --target install -- -j"$JOBS"

# Write receipt
cat > "$PREFIX/INSTALL_RECEIPT.txt" << RECEIPT
tool=llvm
version=${VERSION}
platform=${PLATFORM}
install_prefix=${PREFIX}
build_type=source
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
includes=clang,clang++,clang-format,clang-tidy,lld
RECEIPT

echo ""
echo "==> LLVM/Clang ${VERSION} built and installed to ${PREFIX}"
echo "    Add ${PREFIX}/bin to your PATH."
echo "    Build artifacts left in ${BUILD_DIR} — remove to free disk space."
