#!/usr/bin/env bash
set -euo pipefail

TOOL="7zip"
VERSION="26.01"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/../../lib/devkit-install.sh"

PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"
PREFIX="${INSTALL_PREFIX:-$(devkit_default_prefix 7zip)}"
devkit_parse_args "$@"

echo "==> Installing 7-Zip ${VERSION} (${DEVKIT_PLATFORM}) to ${PREFIX}"

PARTS_DIR="$PREBUILT_DIR/dev-tools/7zip/${VERSION}"
INSTALLER=$(devkit_find_file "$PARTS_DIR")
if [[ -z "$INSTALLER" ]]; then
    echo "ERROR: No installer found in $PARTS_DIR" >&2; exit 1
fi

if [[ "$DEVKIT_PLATFORM" == "windows" ]]; then
    devkit_install_nsis_s "$INSTALLER" "$PREFIX"
else
    mkdir -p "$PREFIX/bin"
    devkit_extract "$INSTALLER" "$PREFIX/bin" 0
    # 7zip on Linux ships as 7zzs — create a 7z symlink
    if [[ -f "$PREFIX/bin/7zzs" && ! -f "$PREFIX/bin/7z" ]]; then
        ln -sf 7zzs "$PREFIX/bin/7z"
    fi
fi

devkit_write_receipt 7zip "$VERSION" "$DEVKIT_PLATFORM" "$PREFIX"

echo "==> 7-Zip ${VERSION} installed to ${PREFIX}"
