#!/usr/bin/env bash
# Installs lcov 2.4 from source (Perl scripts — no compilation needed).
# This is the same as setup.sh source-path but explicit for build pipeline use.
set -euo pipefail

VERSION="2.4"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCES_DIR="$SCRIPT_DIR/sources"
SOURCE_ARCHIVE="$SOURCES_DIR/lcov-${VERSION}.tar.xz"

if [[ "${AIRGAP_OS:-}" == "windows" || "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "${OS:-}" == "Windows_NT" ]] || command -v cmd.exe &>/dev/null 2>&1; then
    echo "lcov is a Linux-only tool. Skipping on Windows." >&2
    exit 0
fi

if [[ "$(id -u)" == "0" ]]; then
    DEFAULT_PREFIX="/usr/local"
else
    DEFAULT_PREFIX="${HOME}/.local/share/airgap-cpp-devkit/lcov"
fi

PREFIX="${INSTALL_PREFIX:-$DEFAULT_PREFIX}"
BUILD_DIR=$(mktemp -d)

echo "==> Installing lcov ${VERSION} from source to ${PREFIX}"

if [[ ! -f "$SOURCE_ARCHIVE" ]]; then
    echo "ERROR: Source archive not found: $SOURCE_ARCHIVE" >&2
    exit 1
fi

if ! command -v perl &>/dev/null; then
    echo "ERROR: perl not found — lcov requires Perl." >&2
    exit 1
fi

tar -xJf "$SOURCE_ARCHIVE" --strip-components=1 -C "$BUILD_DIR"
make -C "$BUILD_DIR" install PREFIX="$PREFIX"
rm -rf "$BUILD_DIR"

cat > "$PREFIX/INSTALL_RECEIPT.txt" << RECEIPT
tool=lcov
version=${VERSION}
platform=linux
install_prefix=${PREFIX}
build_type=source
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RECEIPT

echo "==> lcov ${VERSION} installed to ${PREFIX}"
