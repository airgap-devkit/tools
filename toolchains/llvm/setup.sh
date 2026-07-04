#!/usr/bin/env bash
set -euo pipefail

TOOL="llvm"
VERSION="22.1.8"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/devkit-install.sh"
PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"

if [[ "$DEVKIT_PLATFORM" == "windows" ]]; then
    ARCHIVE_BASE="clang+llvm-${VERSION}-x86_64-pc-windows-msvc"
else
    # RHEL 8 ships glibc 2.28; the standard build needs glibc >= 2.32, so older
    # hosts get the dedicated RHEL 8 build. Missing ldd → the safer RHEL 8 build.
    ARCHIVE_BASE="$(devkit_linux_asset \
        "LLVM-${VERSION}-Linux-X64" \
        "LLVM-${VERSION}-Linux-X64-rhel8")"
fi

PREFIX="${INSTALL_PREFIX:-$(devkit_default_prefix "clang-llvm")}"
while [[ $# -gt 0 ]]; do
    case "$1" in --prefix) PREFIX="$2"; shift 2 ;; *) shift ;; esac
done
PARTS_DIR="$PREBUILT_DIR/toolchains/llvm/${VERSION}"

echo "==> Installing LLVM/Clang ${VERSION} (${DEVKIT_PLATFORM}) to ${PREFIX}"

if [[ ! -d "$PARTS_DIR" ]]; then
    echo "ERROR: Prebuilt parts not found at: $PARTS_DIR" >&2
    echo "       Clone the prebuilt submodule or run from the devkit root." >&2
    exit 1
fi

# Resolve the archive (native .zip/.tar.gz preferred; assembles split parts).
if ! ARCHIVE_PATH="$(devkit_resolve_archive "$PARTS_DIR" "$ARCHIVE_BASE")"; then
    echo "ERROR: No archive found matching ${ARCHIVE_BASE}.* in $PARTS_DIR" >&2
    if [[ "${ARCHIVE_BASE}" == *"-rhel8"* ]]; then
        echo "       This system requires the RHEL 8 compatible LLVM binary (glibc 2.28)." >&2
        echo "       Trigger the 'Build LLVM tools for RHEL 8' workflow in GitHub Actions" >&2
        echo "       (.github/workflows/build-llvm-rhel8.yml) then re-initialise prebuilt/." >&2
    fi
    exit 1
fi
devkit_verify_archive "$PARTS_DIR/manifest.json" "$ARCHIVE_PATH"

mkdir -p "$PREFIX"
if [[ "$DEVKIT_PLATFORM" == "windows" ]]; then
    PREFIX="$(cygpath -u -- "$PREFIX")"
fi

echo "    Reassembling and extracting (this may take a moment)..."
# Auto-strips the sole wrapper dir on either platform. On Linux the .tar.gz is
# transcoded (symlinks intact) and extracted here on the target host.
devkit_install_archive "$ARCHIVE_PATH" "$PREFIX"

# Verify the installed binaries actually execute on this system.
# A mismatch here means the wrong binary variant was selected above.
if [[ "$DEVKIT_PLATFORM" == "linux" ]]; then
    if ! "$PREFIX/bin/clang-format" --version &>/dev/null; then
        echo "ERROR: clang-format was extracted but cannot execute — runtime library mismatch." >&2
        echo "       Selected archive: ${ARCHIVE}" >&2
        echo "       Run the 'Build LLVM tools for RHEL 8' workflow to produce a compatible binary." >&2
        exit 1
    fi
fi

devkit_write_receipt "$TOOL" "$VERSION" "$DEVKIT_PLATFORM" "$PREFIX" \
    "includes=clang,clang++,clang-format,clang-tidy,lld,llvm-ar,llvm-nm"

echo "==> LLVM/Clang ${VERSION} installed to ${PREFIX}"
echo "    Add ${PREFIX}/bin to your PATH."
