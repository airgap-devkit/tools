#!/usr/bin/env bash
set -euo pipefail

TOOL="git"
VERSION="2.54.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/../../lib/devkit-install.sh"

if [[ "$DEVKIT_PLATFORM" != "windows" ]]; then
    echo "Skipping: Git for Windows is Windows-only. On Linux, Git is provided by the OS."
    exit 0
fi

PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"
PREFIX="${INSTALL_PREFIX:-$(devkit_default_prefix git)}"
devkit_parse_args "$@"

echo "==> Installing Git ${VERSION} (windows) to ${PREFIX}"

PARTS_DIR="$PREBUILT_DIR/dev-tools/git/${VERSION}"
INSTALLER=$(devkit_find_file "$PARTS_DIR")
if [[ -z "$INSTALLER" ]]; then
    echo "ERROR: No installer found in $PARTS_DIR" >&2; exit 1
fi

devkit_install_exe "$INSTALLER" "$PREFIX"
devkit_write_receipt git "$VERSION" windows "$PREFIX"

echo "==> Git ${VERSION} installed to ${PREFIX}"
