#!/usr/bin/env bash
set -euo pipefail

TOOL="gcc"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../../.." && pwd)/prebuilt}"

if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OS" == "Windows_NT" ]]; then
    PLATFORM="windows"
    VERSION="15.2.0"
    ARCHIVE="winlibs-x86_64-posix-seh-gcc-${VERSION}-mingw-w64ucrt-14.0.0-r7.tar.xz"
    DEFAULT_PREFIX="${LOCALAPPDATA}/airgap-cpp-devkit/winlibs-gcc-ucrt"
else
    PLATFORM="linux"
    VERSION="toolset-15"
    DEFAULT_PREFIX="/opt/rh/gcc-toolset-15"
fi

PREFIX="${INSTALL_PREFIX:-$DEFAULT_PREFIX}"
PARTS_DIR="$PREBUILT_DIR/toolchains/gcc/${PLATFORM}"

echo "==> Installing GCC ${VERSION} (${PLATFORM})"

if [[ ! -d "$PARTS_DIR" ]]; then
    echo "ERROR: Prebuilt parts not found at: $PARTS_DIR" >&2
    exit 1
fi

if [[ "$PLATFORM" == "windows" ]]; then
    PARTS=("$PARTS_DIR/${ARCHIVE}.part-"*)
    if [[ ${#PARTS[@]} -eq 0 || ! -f "${PARTS[0]}" ]]; then
        echo "ERROR: No parts found for $ARCHIVE" >&2
        exit 1
    fi
    echo "    Found ${#PARTS[@]} parts. Extracting to ${PREFIX}..."
    mkdir -p "$PREFIX"
    cat "${PARTS[@]}" | tar -xJ --strip-components=1 -C "$PREFIX"

    cat > "$PREFIX/INSTALL_RECEIPT.txt" << RECEIPT
tool=${TOOL}
version=${VERSION}
platform=${PLATFORM}
install_prefix=${PREFIX}
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
includes=gcc,g++,gcov,gdb,gfortran,mingw-w64
RECEIPT

    echo "==> GCC ${VERSION} (WinLibs) installed to ${PREFIX}"
    echo "    Add ${PREFIX}/bin to your PATH."

else
    # Linux: install RPMs (requires root)
    if [[ "$(id -u)" != "0" ]]; then
        echo "ERROR: Root required to install GCC toolset RPMs." >&2
        exit 1
    fi
    PARTS=("$PARTS_DIR/gcc-toolset-15-rhel8-rpms.tar.xz.part-"*)
    if [[ ${#PARTS[@]} -eq 0 || ! -f "${PARTS[0]}" ]]; then
        echo "ERROR: No parts found for gcc-toolset-15-rhel8-rpms.tar.xz" >&2
        exit 1
    fi
    echo "    Found ${#PARTS[@]} parts. Extracting RPMs..."
    TMP=$(mktemp -d)
    cat "${PARTS[@]}" | tar -xJ -C "$TMP"
    echo "    Installing RPMs..."
    rpm -ivh "$TMP"/*.rpm
    rm -rf "$TMP"

    echo "==> GCC toolset-15 installed."
    echo "    Enable with: scl enable gcc-toolset-15 bash"
fi
