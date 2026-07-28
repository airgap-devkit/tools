#!/usr/bin/env bash
set -euo pipefail
# Report the exact failing command/line if this script aborts (diagnostic).
trap 'rc=$?; echo "ERROR: lcov/setup.sh aborted at line ${LINENO} (exit ${rc}): ${BASH_COMMAND}" >&2' ERR

TOOL="lcov"
VERSION="2.5"
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
    # The archive may or may not carry a top-level lcov-<version>/ wrapper dir;
    # locate the Makefile root either way.
    SRC="$TMP/lcov-${VERSION}"
    [[ -f "$SRC/Makefile" ]] || SRC="$TMP"
    # A .zip source archive does not preserve the execute bit, so the helper
    # scripts that `make install` invokes come out non-executable (make would
    # otherwise fail with exit 126). Restore it before installing. Use a bash
    # glob rather than `find` so the install works on hosts without findutils.
    ( shopt -s globstar nullglob
      for _f in "$SRC"/**/*.pl "$SRC"/**/*.sh "$SRC"/bin/* "$SRC"/**/bin/*; do
          [[ -f "$_f" ]] && chmod +x "$_f" 2>/dev/null || true
      done )
    make -C "$SRC" install PREFIX="$PREFIX"
    rm -rf "$TMP"
    _install_perl_vendor "$PREFIX/lib/lcov"
else
    echo "ERROR: Neither RPM nor source archive found for lcov ${VERSION}" >&2
    exit 1
fi

# lcov (coverage capture) runs on core Perl, but genhtml's HTML-report step needs
# extra Perl modules (DateTime, Date::Parse, Capture::Tiny, ...) that ship in the
# perl-vendor-lcov archive. If they aren't resolvable, say so plainly rather than
# reporting a clean success that hides a genhtml which cannot run.
_verify_genhtml() {
    local gh="$PREFIX/bin/genhtml"
    [[ -x "$gh" ]] || gh="$(command -v genhtml 2>/dev/null || true)"
    [[ -n "$gh" && -x "$gh" ]] || return 0
    local plib="$PREFIX/lib/lcov:$PREFIX/lib:/usr/lib/lcov"
    local out
    if out="$(PERL5LIB="${plib}${PERL5LIB:+:$PERL5LIB}" "$gh" --version 2>&1)"; then
        return 0
    fi
    echo "  [!!] lcov installed, but genhtml cannot run — its HTML-report step is unavailable." >&2
    local mods
    mods="$(printf '%s\n' "$out" \
        | grep -oE "Can't locate [A-Za-z0-9_/]+\.pm" \
        | sed "s#Can't locate ##; s#/#::#g; s#\.pm##" \
        | sort -u | paste -sd', ' - || true)"
    [[ -n "$mods" ]] && echo "       Missing Perl modules: ${mods}" >&2
    echo "       Coverage capture (lcov) still works; only genhtml HTML output is affected." >&2
    echo "       Stage these modules into the perl-vendor-lcov prebuilt archive to enable it." >&2
}
_verify_genhtml

devkit_write_receipt "$TOOL" "$VERSION" "$DEVKIT_PLATFORM" "$PREFIX"

echo "==> lcov ${VERSION} installed."
