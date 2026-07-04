#!/usr/bin/env bash
set -euo pipefail

TOOL="ninja"
VERSION="1.13.2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/devkit-install.sh"
PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"

if [[ "$DEVKIT_PLATFORM" == "windows" ]]; then
    ARCHIVE_BASE="ninja-${VERSION}-windows"
    BINARY="ninja.exe"
else
    ARCHIVE_BASE="ninja-${VERSION}-linux"
    BINARY="ninja"
fi

PREFIX="${INSTALL_PREFIX:-$(devkit_default_prefix "$TOOL")}"
while [[ $# -gt 0 ]]; do
    case "$1" in --prefix) PREFIX="$2"; shift 2 ;; *) shift ;; esac
done
PARTS_DIR="$PREBUILT_DIR/toolchains/ninja/${VERSION}"
ARCHIVE_PATH="$(devkit_resolve_archive "$PARTS_DIR" "$ARCHIVE_BASE")" \
    || { echo "ERROR: Archive not found for ${ARCHIVE_BASE} in $PARTS_DIR" >&2; exit 1; }

echo "==> Installing Ninja ${VERSION} (${DEVKIT_PLATFORM}) to ${PREFIX}/bin"

devkit_verify_archive "$PARTS_DIR/manifest.json" "$ARCHIVE_PATH"

if [[ "$DEVKIT_PLATFORM" == "windows" ]]; then
    MSYS_NO_PATHCONV=1 cmd.exe /c mkdir "${PREFIX}\\bin" 2>/dev/null || true
    PREFIX="$(cygpath -u -- "$PREFIX")"
else
    mkdir -p "$PREFIX/bin"
fi
# The ninja archive is a single bare binary at the root (no wrapper dir) — the
# auto-normalizer leaves it as-is and drops it into bin.
devkit_install_archive "$ARCHIVE_PATH" "$PREFIX/bin"
chmod +x "$PREFIX/bin/$BINARY"

devkit_write_receipt "$TOOL" "$VERSION" "$DEVKIT_PLATFORM" "$PREFIX"

echo "==> Ninja ${VERSION} installed to ${PREFIX}/bin/${BINARY}"
