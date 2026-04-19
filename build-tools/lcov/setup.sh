#!/usr/bin/env bash
set -euo pipefail

# lcov is Linux-only
if [[ "${AIRGAP_OS:-}" == "windows" || "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "${OS:-}" == "Windows_NT" ]]; then
    echo "lcov is a Linux-only tool. Skipping on Windows." >&2
    exit 0
fi

TOOL="lcov"
VERSION="2.4"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"

if [[ "$(id -u)" == "0" ]]; then
    DEFAULT_PREFIX="/opt/airgap-cpp-devkit/lcov"
else
    DEFAULT_PREFIX="${HOME}/.local/share/airgap-cpp-devkit/lcov"
fi
PREFIX="${INSTALL_PREFIX:-$DEFAULT_PREFIX}"
while [[ $# -gt 0 ]]; do
    case "$1" in --prefix) PREFIX="$2"; shift 2 ;; *) shift ;; esac
done

RPM="$PREBUILT_DIR/toolchains/lcov/${VERSION}/lcov-${VERSION}-0.noarch.rpm"
SOURCE_ARCHIVE="$PREBUILT_DIR/toolchains/lcov/${VERSION}/lcov-${VERSION}.tar.xz"

echo "==> Installing lcov ${VERSION}"

# Prefer RPM install if rpm is available (RHEL 8/9)
if command -v rpm &>/dev/null && [[ "$(id -u)" == "0" ]] && [[ -f "$RPM" ]]; then
    echo "    Installing via RPM..."
    rpm -ivh "$RPM"
elif [[ -f "$SOURCE_ARCHIVE" ]]; then
    echo "    Installing from source archive..."
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    tar -xJf "$SOURCE_ARCHIVE" -C "$TMP"
    make -C "$TMP/lcov-${VERSION}" install PREFIX="$PREFIX"
else
    echo "ERROR: Neither RPM nor source archive found for lcov ${VERSION}" >&2
    echo "       Expected RPM at: ${RPM}" >&2
    echo "       Expected tarball at: ${SOURCE_ARCHIVE}" >&2
    exit 1
fi

mkdir -p "$(dirname "$PREFIX/INSTALL_RECEIPT.txt")"
cat > "$PREFIX/INSTALL_RECEIPT.txt" << RECEIPT
tool=${TOOL}
version=${VERSION}
platform=linux
install_prefix=${PREFIX}
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RECEIPT

echo "==> lcov ${VERSION} installed."
