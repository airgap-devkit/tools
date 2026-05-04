#!/usr/bin/env bash
set -euo pipefail

TOOL="gcc"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"

if [[ "${AIRGAP_OS:-}" == "windows" || "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "${OS:-}" == "Windows_NT" ]]; then
    PLATFORM="windows"
    VERSION="15.2.0"
    ARCHIVE="winlibs-x86_64-posix-seh-gcc-${VERSION}-mingw-w64ucrt-14.0.0-r7.tar.xz"
    DEFAULT_PREFIX="${LOCALAPPDATA:-$HOME/AppData/Local}/airgap-cpp-devkit/winlibs-gcc-ucrt"
else
    PLATFORM="linux"
    VERSION="toolset-15"
    DEFAULT_PREFIX="/opt/rh/gcc-toolset-15"
fi

PREFIX="${INSTALL_PREFIX:-$DEFAULT_PREFIX}"
while [[ $# -gt 0 ]]; do
    case "$1" in --prefix) PREFIX="$2"; shift 2 ;; *) shift ;; esac
done
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
    MSYS_NO_PATHCONV=1 cmd.exe /c mkdir "$PREFIX" 2>/dev/null || true
    PREFIX="$(cygpath -u -- "$PREFIX")"
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
    PARTS=("$PARTS_DIR/gcc-toolset-15-rhel8-rpms.tar.xz.part-"*)
    if [[ ${#PARTS[@]} -eq 0 || ! -f "${PARTS[0]}" ]]; then
        echo "ERROR: No parts found for gcc-toolset-15-rhel8-rpms.tar.xz" >&2
        exit 1
    fi
    echo "    Found ${#PARTS[@]} parts. Extracting RPMs..."
    TMP=$(mktemp -d)
    cat "${PARTS[@]}" | tar -xJ -C "$TMP"

    if [[ "$(id -u)" == "0" ]]; then
        # Root: install system-wide via rpm so scl enable works
        echo "    Installing RPMs (system-wide)..."
        rpm -ivh "$TMP"/*.rpm
        rm -rf "$TMP"
        echo "==> GCC toolset-15 installed."
        echo "    Enable with: scl enable gcc-toolset-15 bash"
    else
        # Non-root: extract RPM payload into PREFIX with rpm2cpio | cpio
        if ! command -v rpm2cpio &>/dev/null; then
            echo "ERROR: Non-root install requires rpm2cpio (usually part of rpm package)." >&2
            rm -rf "$TMP"
            exit 1
        fi
        echo "    Non-root install: extracting RPM payloads to ${PREFIX} ..."
        mkdir -p "$PREFIX"
        for rpm_file in "$TMP"/*.rpm; do
            rpm2cpio "$rpm_file" | cpio -idmv --directory="$PREFIX" 2>/dev/null
        done
        rm -rf "$TMP"
        # Hoist the opt/rh/gcc-toolset-15 tree up to PREFIX if rpm2cpio nested it
        if [[ -d "$PREFIX/opt/rh/gcc-toolset-15/root" ]]; then
            cp -a "$PREFIX/opt/rh/gcc-toolset-15/root/." "$PREFIX/"
            rm -rf "$PREFIX/opt"
        fi
        cat > "$PREFIX/INSTALL_RECEIPT.txt" << RECEIPT
tool=${TOOL}
version=${VERSION}
platform=${PLATFORM}
install_prefix=${PREFIX}
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
install_mode=user
RECEIPT
        echo "==> GCC toolset-15 installed (user mode) to ${PREFIX}."
        echo "    Add ${PREFIX}/bin to your PATH."
    fi
fi
