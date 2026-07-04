#!/usr/bin/env bash
set -euo pipefail

TOOL="conan"
VERSION="2.30.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/devkit-install.sh"
PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"
PARTS_DIR="$PREBUILT_DIR/dev-tools/conan/${VERSION}"

if [[ "$DEVKIT_PLATFORM" == "windows" ]]; then
    ARCHIVE_BASE="conan-${VERSION}-windows-x86_64"
else
    ARCHIVE_BASE="conan-${VERSION}-linux-x86_64"
fi

PREFIX="${INSTALL_PREFIX:-$(devkit_default_prefix "$TOOL")}"
while [[ $# -gt 0 ]]; do
    case "$1" in --prefix) PREFIX="$2"; shift 2 ;; *) shift ;; esac
done

echo "==> Installing Conan ${VERSION} (${DEVKIT_PLATFORM}) to ${PREFIX}"

ARCHIVE_PATH="$(devkit_resolve_archive "$PARTS_DIR" "$ARCHIVE_BASE")" \
    || { echo "ERROR: Archive not found for ${ARCHIVE_BASE} in $PARTS_DIR" >&2; exit 1; }
devkit_verify_archive "$PARTS_DIR/manifest.json" "$ARCHIVE_PATH"

if [[ "$DEVKIT_PLATFORM" == "windows" ]]; then
    MSYS_NO_PATHCONV=1 cmd.exe /c mkdir "$PREFIX" 2>/dev/null || true
    PREFIX="$(cygpath -u -- "$PREFIX")"
    # Conan ships as a PyInstaller onedir (conan.exe + _internal/). Land it in
    # bin/ so <prefix>/bin is on PATH via env.sh and conan.exe keeps _internal
    # beside it.
    devkit_install_archive "$ARCHIVE_PATH" "$PREFIX/bin"
else
    devkit_install_archive "$ARCHIVE_PATH" "$PREFIX/bin"
    chmod +x "$PREFIX/bin/conan"
fi

devkit_write_receipt "$TOOL" "$VERSION" "$DEVKIT_PLATFORM" "$PREFIX"

echo "==> Conan ${VERSION} installed."
