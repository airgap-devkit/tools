#!/usr/bin/env bash
set -euo pipefail

# Servy is Windows-only
if [[ "${AIRGAP_OS:-}" != "windows" && "$OSTYPE" != "msys" && "$OSTYPE" != "cygwin" && "${OS:-}" != "Windows_NT" ]]; then
    echo "Servy is a Windows-only tool. Skipping on Linux." >&2
    exit 0
fi

TOOL="servy"
VERSION="7.9"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/../../lib/devkit-install.sh"

PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"
PREFIX="${INSTALL_PREFIX:-$(devkit_default_prefix servy)}"
devkit_parse_args "$@"

echo "==> Installing Servy ${VERSION} (Windows) to ${PREFIX}"

PARTS_DIR="$PREBUILT_DIR/dev-tools/servy/${VERSION}"
INSTALLER=$(devkit_find_file "$PARTS_DIR")
if [[ -z "$INSTALLER" ]]; then
    echo "ERROR: No installer found in $PARTS_DIR" >&2; exit 1
fi

mkdir -p "$PREFIX"
devkit_extract "$INSTALLER" "$PREFIX" 0
devkit_write_receipt servy "$VERSION" windows "$PREFIX"

echo "==> Servy ${VERSION} installed to ${PREFIX}"
