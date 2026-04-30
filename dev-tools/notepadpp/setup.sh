#!/usr/bin/env bash
set -euo pipefail

# Notepad++ is Windows-only
if [[ "${AIRGAP_OS:-}" != "windows" && "$OSTYPE" != "msys" && "$OSTYPE" != "cygwin" && "${OS:-}" != "Windows_NT" ]]; then
    echo "Notepad++ is a Windows-only tool. Skipping on Linux." >&2
    exit 0
fi

TOOL="notepadpp"
VERSION="8.9.4"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/../../lib/devkit-install.sh"

PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"
PREFIX="${INSTALL_PREFIX:-$(devkit_default_prefix notepadpp)}"
devkit_parse_args "$@"

echo "==> Installing Notepad++ ${VERSION} (Windows, portable) to ${PREFIX}"

PARTS_DIR="$PREBUILT_DIR/dev-tools/notepadpp/${VERSION}"
INSTALLER=$(devkit_find_file "$PARTS_DIR")
if [[ -z "$INSTALLER" ]]; then
    echo "ERROR: No installer found in $PARTS_DIR" >&2; exit 1
fi

devkit_extract "$INSTALLER" "$PREFIX" 0
devkit_write_receipt notepadpp "$VERSION" windows "$PREFIX"

echo "==> Notepad++ ${VERSION} installed to ${PREFIX}"
echo "    Launcher: ${PREFIX}/notepad++.exe"
