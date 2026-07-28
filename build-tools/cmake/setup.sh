#!/usr/bin/env bash
set -euo pipefail

TOOL="cmake"
VERSION="4.3.3"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/devkit-install.sh"
PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"
PARTS_DIR="$PREBUILT_DIR/build-tools/cmake/${VERSION}"

if [[ "$DEVKIT_PLATFORM" == "windows" ]]; then
    ARCHIVE_BASE="cmake-${VERSION}-windows-x86_64"
elif [[ "$(devkit_libc)" == "musl" ]]; then
    # Kitware ships glibc-only binaries; musl hosts (Alpine) need the musl build.
    ARCHIVE_BASE="cmake-${VERSION}-linux-x86_64-musl"
else
    ARCHIVE_BASE="cmake-${VERSION}-linux-x86_64"
fi

PREFIX="${INSTALL_PREFIX:-$(devkit_default_prefix "$TOOL")}"
while [[ $# -gt 0 ]]; do
    case "$1" in --prefix) PREFIX="$2"; shift 2 ;; *) shift ;; esac
done
ARCHIVE_PATH="$(devkit_resolve_archive "$PARTS_DIR" "$ARCHIVE_BASE")" \
    || { echo "ERROR: Archive not found for ${ARCHIVE_BASE} in $PARTS_DIR" >&2; exit 1; }

echo "==> Installing CMake ${VERSION} (${DEVKIT_PLATFORM}) to ${PREFIX}"

devkit_verify_archive "$PARTS_DIR/manifest.json" "$ARCHIVE_PATH"

mkdir -p "$PREFIX"
if [[ "$DEVKIT_PLATFORM" == "windows" ]]; then
    PREFIX="$(cygpath -u -- "$PREFIX")"
fi
devkit_install_archive "$ARCHIVE_PATH" "$PREFIX"
if [[ "$DEVKIT_PLATFORM" == "linux" ]]; then
    # Bash glob instead of `find`: minimal hosts (stripped RHEL 8 containers) may
    # not ship findutils, and the whole install shouldn't die for a chmod.
    for _f in "$PREFIX"/bin/*; do [[ -f "$_f" ]] && chmod +x "$_f"; done
fi

devkit_write_receipt "$TOOL" "$VERSION" "$DEVKIT_PLATFORM" "$PREFIX"

echo "==> CMake ${VERSION} installed to ${PREFIX}"
echo "    Add ${PREFIX}/bin to your PATH."
