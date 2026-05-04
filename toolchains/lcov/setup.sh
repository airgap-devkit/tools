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
SOURCES_DIR="$SCRIPT_DIR/sources"

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
PERL_VENDOR="$PREBUILT_DIR/toolchains/lcov/${VERSION}/perl-vendor-lcov.tar.xz"

# Install Capture::Tiny (and any other vendored Perl deps) into the lcov lib dir.
# lcov's own fix.pl rewrites 'use lib' to an absolute path at install time.
# We mirror that: source installs use $PREFIX/lib/lcov; RPM installs use /usr/lib/lcov.
_install_perl_vendor() {
    local lib_dir="$1"
    if [[ -f "$PERL_VENDOR" ]]; then
        echo "    Vendoring Perl dependencies into ${lib_dir}..."
        mkdir -p "$lib_dir"
        tar -xJf "$PERL_VENDOR" -C "$lib_dir"
    fi
}

echo "==> Installing lcov ${VERSION}"

# Prefer RPM install if rpm is available (RHEL 8/9)
if command -v rpm &>/dev/null && [[ "$(id -u)" == "0" ]] && [[ -f "$RPM" ]]; then
    echo "    Installing via RPM..."
    rpm -ivh "$RPM"
    _install_perl_vendor "/usr/lib/lcov"
elif [[ -f "$SOURCE_ARCHIVE" ]]; then
    echo "    Installing from source archive..."
    TMP=$(mktemp -d)
    tar -xJf "$SOURCE_ARCHIVE" -C "$TMP"
    make -C "$TMP/lcov-${VERSION}" install PREFIX="$PREFIX"
    rm -rf "$TMP"
    _install_perl_vendor "$PREFIX/lib/lcov"
else
    echo "ERROR: Neither RPM nor source archive found for lcov ${VERSION}" >&2
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
