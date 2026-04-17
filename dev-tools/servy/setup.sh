#!/usr/bin/env bash
set -euo pipefail

# Servy is Windows-only
if [[ "$OSTYPE" != "msys" && "$OSTYPE" != "cygwin" && "$OS" != "Windows_NT" ]]; then
    echo "Servy is a Windows-only tool. Skipping on Linux." >&2
    exit 0
fi

TOOL="servy"
VERSION="7.9"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"
PARTS_DIR="$PREBUILT_DIR/dev-tools/servy/${VERSION}"
ARCHIVE="$PARTS_DIR/servy-${VERSION}-windows-x64.tar.xz"
DEFAULT_PREFIX="${LOCALAPPDATA}/airgap-cpp-devkit/servy"
PREFIX="${INSTALL_PREFIX:-$DEFAULT_PREFIX}"

echo "==> Installing Servy ${VERSION} (Windows) to ${PREFIX}"

if [[ ! -f "$ARCHIVE" ]]; then
    echo "ERROR: Archive not found: $ARCHIVE" >&2; exit 1
fi

mkdir -p "$PREFIX"
tar -xJf "$ARCHIVE" -C "$PREFIX" --strip-components=0

cat > "$PREFIX/INSTALL_RECEIPT.txt" << RECEIPT
tool=${TOOL}
version=${VERSION}
platform=windows
install_prefix=${PREFIX}
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RECEIPT

echo "==> Servy ${VERSION} installed to ${PREFIX}"
