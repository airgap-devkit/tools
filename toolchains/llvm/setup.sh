#!/usr/bin/env bash
set -euo pipefail

TOOL="llvm"
VERSION="22.1.8"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/devkit-install.sh"
PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"

if [[ "$DEVKIT_PLATFORM" == "windows" ]]; then
    # The staged Windows parts keep the upstream URL-encoded '+' (%2B) in their
    # filename, so the archive base must match that encoded form byte-for-byte.
    ARCHIVE_BASES=("clang%2Bllvm-${VERSION}-x86_64-pc-windows-msvc")
else
    # Per-distro builds for RHEL/Rocky 8, 9 and 10. Try the closest EL variant
    # at or below the host's glibc, then fall back toward the universal
    # glibc-2.28 (rhel8) floor, which runs on every supported major.
    ARCHIVE_BASES=()
    for _tag in $(devkit_rhel_tag_fallbacks); do
        ARCHIVE_BASES+=("LLVM-${VERSION}-Linux-X64-${_tag}")
    done
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
# Try each candidate base in fallback order; the first that resolves wins.
ARCHIVE_BASE=""
ARCHIVE_PATH=""
for _base in "${ARCHIVE_BASES[@]}"; do
    if ARCHIVE_PATH="$(devkit_resolve_archive "$PARTS_DIR" "$_base")"; then
        ARCHIVE_BASE="$_base"; break
    fi
    ARCHIVE_PATH=""
done
if [[ -z "$ARCHIVE_PATH" ]]; then
    echo "ERROR: No LLVM archive found (${ARCHIVE_BASES[*]}) in $PARTS_DIR" >&2
    if [[ "$DEVKIT_PLATFORM" == "linux" ]]; then
        echo "       This host (glibc 2.$(devkit_glibc_minor), $(devkit_rhel_tag)) needs a matching LLVM build." >&2
        echo "       Trigger the 'Build LLVM tools (Linux, per-distro)' workflow" >&2
        echo "       (.github/workflows/build-llvm-linux.yml) then re-initialise prebuilt/." >&2
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
        echo "       Selected archive: ${ARCHIVE_BASE}" >&2
        echo "       Run the 'Build LLVM tools (Linux, per-distro)' workflow to produce a compatible binary." >&2
        exit 1
    fi
fi

devkit_write_receipt "$TOOL" "$VERSION" "$DEVKIT_PLATFORM" "$PREFIX" \
    "includes=clang,clang++,clang-format,clang-tidy,lld,llvm-ar,llvm-nm"

echo "==> LLVM/Clang ${VERSION} installed to ${PREFIX}"
echo "    Add ${PREFIX}/bin to your PATH."
