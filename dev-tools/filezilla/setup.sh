#!/usr/bin/env bash
set -euo pipefail

TOOL="filezilla"
VERSION="3.70.4"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/../../lib/devkit-install.sh"

PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"
PREFIX="${INSTALL_PREFIX:-$(devkit_default_prefix filezilla)}"
devkit_parse_args "$@"

echo "==> Installing FileZilla ${VERSION} (${DEVKIT_PLATFORM}) to ${PREFIX}"

PARTS_DIR="$PREBUILT_DIR/dev-tools/filezilla/${VERSION}"
INSTALLER=$(devkit_find_file "$PARTS_DIR")
if [[ -z "$INSTALLER" ]]; then
    echo "ERROR: No installer found in $PARTS_DIR" >&2; exit 1
fi

if [[ "$DEVKIT_PLATFORM" == "windows" ]]; then
    devkit_install_nsis_s "$INSTALLER" "$PREFIX"
else
    mkdir -p "$PREFIX"
    devkit_extract "$INSTALLER" "$PREFIX" 1
    mkdir -p "$PREFIX/bin"
    if [[ -f "$PREFIX/filezilla" && ! -f "$PREFIX/bin/filezilla" ]]; then
        ln -sf "$PREFIX/filezilla" "$PREFIX/bin/filezilla"
    fi
fi

devkit_write_receipt filezilla "$VERSION" "$DEVKIT_PLATFORM" "$PREFIX"

echo "==> FileZilla ${VERSION} installed to ${PREFIX}"
