#!/usr/bin/env bash
set -euo pipefail

TOOL="sourcetree"
VERSION="3.4.30"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/devkit-install.sh"

# SourceTree is Windows-only
if [[ "$DEVKIT_PLATFORM" != "windows" ]]; then
    echo "SourceTree is a Windows-only tool. Skipping on Linux." >&2
    exit 0
fi

PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"
PREFIX="${INSTALL_PREFIX:-$(devkit_default_prefix sourcetree)}"
devkit_parse_args "$@"

echo "==> Installing SourceTree ${VERSION} (Windows) ..."
echo "    Note: SourceTree installs to %LocalAppData%\\SourceTree (Squirrel default)."

PARTS_DIR="$PREBUILT_DIR/dev-tools/sourcetree/${VERSION}"
# `if ! X=$(…)`, not a bare assignment: under set -e a bare
# `INSTALLER=$(devkit_find_file …)` aborts on a non-zero resolve BEFORE the
# `[[ -z ]]` check could print an actionable error.
if ! INSTALLER=$(devkit_find_file "$PARTS_DIR"); then
    echo "ERROR: no SourceTree installer resolved in $PARTS_DIR" >&2; exit 1
fi

devkit_install_exe_silent "$INSTALLER"

devkit_write_receipt sourcetree "$VERSION" windows "$PREFIX"

echo "==> SourceTree ${VERSION} installed."
echo "    Launcher: %LocalAppData%\\SourceTree\\SourceTree.exe"
