#!/usr/bin/env bash
set -euo pipefail

TOOL="conan"
VERSION="2.31.1"
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

# _strict distinguishes a missing artifact (exit 1) from one that failed integrity
# verification (exit 2) and prints the right message; set -e aborts on either.
ARCHIVE_PATH="$(devkit_resolve_archive_strict "$PARTS_DIR" "$ARCHIVE_BASE")"
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
