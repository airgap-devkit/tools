#!/usr/bin/env bash
set -euo pipefail

# SourceTree is Windows-only
if [[ "${AIRGAP_OS:-}" != "windows" && "$OSTYPE" != "msys" && "$OSTYPE" != "cygwin" && "${OS:-}" != "Windows_NT" ]]; then
    echo "SourceTree is a Windows-only tool. Skipping on Linux." >&2
    exit 0
fi

TOOL="sourcetree"
VERSION="3.4.30"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/../../lib/devkit-install.sh"

PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"
PREFIX="${INSTALL_PREFIX:-$(devkit_default_prefix sourcetree)}"
devkit_parse_args "$@"

echo "==> Installing SourceTree ${VERSION} (Windows) ..."
echo "    Note: SourceTree installs to %LocalAppData%\\SourceTree (Squirrel default)."

PARTS_DIR="$PREBUILT_DIR/dev-tools/sourcetree/${VERSION}"
INSTALLER=$(devkit_find_file "$PARTS_DIR")
if [[ -z "$INSTALLER" ]]; then
    echo "ERROR: No installer found in $PARTS_DIR" >&2; exit 1
fi

devkit_install_exe_silent "$INSTALLER"

devkit_write_receipt sourcetree "$VERSION" windows "$PREFIX"

echo "==> SourceTree ${VERSION} installed."
echo "    Launcher: %LocalAppData%\\SourceTree\\SourceTree.exe"
