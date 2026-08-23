#!/usr/bin/env bash
set -euo pipefail

TOOL="servy"
VERSION="9.7"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/devkit-install.sh"

# Servy is Windows-only
if [[ "$DEVKIT_PLATFORM" != "windows" ]]; then
    echo "Servy is a Windows-only tool. Skipping on Linux." >&2
    exit 0
fi

PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"
PREFIX="${INSTALL_PREFIX:-$(devkit_default_prefix servy)}"
devkit_parse_args "$@"

echo "==> Installing Servy ${VERSION} (Windows) to ${PREFIX}"

PARTS_DIR="$PREBUILT_DIR/dev-tools/servy/${VERSION}"
# `if ! X=$(…)`: under set -e a bare assignment aborts on a non-zero resolve
# before the diagnostic below can run.
if ! INSTALLER=$(devkit_find_file "$PARTS_DIR"); then
    echo "ERROR: no Servy installer resolved in $PARTS_DIR" >&2; exit 1
fi

mkdir -p "$PREFIX"
# Servy 8.x ships as an Inno Setup installer exe
devkit_install_exe "$INSTALLER" "$PREFIX"
devkit_write_receipt servy "$VERSION" windows "$PREFIX"

echo "==> Servy ${VERSION} installed to ${PREFIX}"
