#!/usr/bin/env bash
set -euo pipefail

TOOL="gcc"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/devkit-install.sh"
PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"

if [[ "$DEVKIT_PLATFORM" == "windows" ]]; then
    VERSION="16.1.0"
    ARCHIVE="winlibs-x86_64-posix-seh-gcc-${VERSION}-mingw-w64ucrt-14.0.0-r3.zip"
    DEFAULT_PREFIX="${LOCALAPPDATA:-$HOME/AppData/Local}/airgap-cpp-devkit/winlibs-gcc-ucrt"
else
    VERSION="toolset-15"
    GCC_VERSION="16.1.0"  # actual compiler release inside gcc-toolset-15 RPMs
    DEFAULT_PREFIX="/opt/rh/gcc-toolset-15"
fi

PREFIX="${INSTALL_PREFIX:-$DEFAULT_PREFIX}"
while [[ $# -gt 0 ]]; do
    case "$1" in --prefix) PREFIX="$2"; shift 2 ;; *) shift ;; esac
done
PARTS_DIR="$PREBUILT_DIR/toolchains/gcc/${DEVKIT_PLATFORM}"

echo "==> Installing GCC ${VERSION} (${DEVKIT_PLATFORM})"

if [[ ! -d "$PARTS_DIR" ]]; then
    echo "ERROR: Prebuilt parts not found at: $PARTS_DIR" >&2
    exit 1
fi

if [[ "$DEVKIT_PLATFORM" == "windows" ]]; then
    PARTS=("$PARTS_DIR/${ARCHIVE}.part-"*)
    if [[ ${#PARTS[@]} -eq 0 || ! -f "${PARTS[0]}" ]]; then
        echo "ERROR: No parts found for $ARCHIVE" >&2
        exit 1
    fi
    echo "    Found ${#PARTS[@]} parts. Assembling and extracting to ${PREFIX}..."
    MSYS_NO_PATHCONV=1 cmd.exe /c mkdir "$PREFIX" 2>/dev/null || true
    PREFIX="$(cygpath -u -- "$PREFIX")"

    # Assemble split zip, extract (strip the single top-level mingw64/ dir)
    TMP_ZIP=$(mktemp --suffix=.zip)
    TMP_DIR=$(mktemp -d)
    cat "${PARTS[@]}" > "$TMP_ZIP"
    if command -v unzip &>/dev/null; then
        unzip -q "$TMP_ZIP" -d "$TMP_DIR"
    else
        fw="$(cygpath -w "$TMP_ZIP")"
        dw="$(cygpath -w "$TMP_DIR")"
        powershell.exe -NoProfile -NonInteractive -Command \
            "Expand-Archive -Force -Path '$fw' -DestinationPath '$dw'"
    fi
    rm -f "$TMP_ZIP"
    for item in "$TMP_DIR"/*/; do
        cp -a "$item/." "$PREFIX/"
    done
    rm -rf "$TMP_DIR"

    devkit_write_receipt "$TOOL" "$VERSION" "$DEVKIT_PLATFORM" "$PREFIX" \
        "includes=gcc,g++,gcov,gdb,gfortran,mingw-w64"

    echo "==> GCC ${VERSION} (WinLibs) installed to ${PREFIX}"
    echo "    Add ${PREFIX}/bin to your PATH."

else
    if ! BUNDLE="$(devkit_resolve_archive "$PARTS_DIR" "gcc-toolset-15-rhel8-rpms")"; then
        echo "ERROR: No archive found for gcc-toolset-15-rhel8-rpms in $PARTS_DIR" >&2
        exit 1
    fi
    echo "    Extracting RPMs..."
    TMP=$(mktemp -d)
    devkit_extract "$BUNDLE" "$TMP" 0

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
        devkit_write_receipt "$TOOL" "$GCC_VERSION" "$DEVKIT_PLATFORM" "$PREFIX" \
            "install_mode=user"
        echo "==> GCC toolset-15 installed (user mode) to ${PREFIX}."
        echo "    Add ${PREFIX}/bin to your PATH."
    fi
fi
