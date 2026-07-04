#!/usr/bin/env bash
set -euo pipefail

TOOL="lcov"
VERSION="2.4"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/devkit-install.sh"
PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"
SOURCES_DIR="$SCRIPT_DIR/sources"

# lcov is Linux-only
if [[ "$DEVKIT_PLATFORM" == "windows" ]]; then
    echo "lcov is a Linux-only tool. Skipping on Windows." >&2
    exit 0
fi

PREFIX="${INSTALL_PREFIX:-$(devkit_default_prefix "$TOOL")}"
while [[ $# -gt 0 ]]; do
    case "$1" in --prefix) PREFIX="$2"; shift 2 ;; *) shift ;; esac
done

LCOV_DIR="$PREBUILT_DIR/toolchains/lcov/${VERSION}"
RPM="$LCOV_DIR/lcov-${VERSION}-0.noarch.rpm"
SOURCE_ARCHIVE="$(devkit_resolve_archive "$LCOV_DIR" "lcov-${VERSION}" 2>/dev/null || true)"
PERL_VENDOR="$(devkit_resolve_archive "$LCOV_DIR" "perl-vendor-lcov" 2>/dev/null || true)"

# Install Capture::Tiny (and any other vendored Perl deps) into the lcov lib dir.
# lcov's own fix.pl rewrites 'use lib' to an absolute path at install time.
# We mirror that: source installs use $PREFIX/lib/lcov; RPM installs use /usr/lib/lcov.
_install_perl_vendor() {
    local lib_dir="$1"
    if [[ -f "$PERL_VENDOR" ]]; then
        echo "    Vendoring Perl dependencies into ${lib_dir}..."
        mkdir -p "$lib_dir"
        devkit_extract "$PERL_VENDOR" "$lib_dir" 0
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
    devkit_extract "$SOURCE_ARCHIVE" "$TMP" 0
    make -C "$TMP/lcov-${VERSION}" install PREFIX="$PREFIX"
    rm -rf "$TMP"
    _install_perl_vendor "$PREFIX/lib/lcov"
else
    echo "ERROR: Neither RPM nor source archive found for lcov ${VERSION}" >&2
    exit 1
fi

devkit_write_receipt "$TOOL" "$VERSION" "$DEVKIT_PLATFORM" "$PREFIX"

echo "==> lcov ${VERSION} installed."
