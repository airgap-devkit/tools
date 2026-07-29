#!/usr/bin/env bash
set -euo pipefail

TOOL="sqlite"
VERSION="3.53.3"
# RHEL/Rocky vendored RPMs ship an older, distro-native SQLite than the upstream
# CLI-tools tarball; one RPM per major is staged (el8/el9/el10) and the installed
# version is read from the file name so the receipt reflects what actually landed.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/devkit-install.sh"
PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"
PARTS_DIR="$PREBUILT_DIR/dev-tools/sqlite/${VERSION}"

if [[ "$DEVKIT_PLATFORM" == "windows" ]]; then
    ARCHIVE_BASE="sqlite-tools-${VERSION}-windows-x64"
    DEFAULT_PREFIX="$(devkit_default_prefix "$TOOL")"
else
    DEFAULT_PREFIX="$(devkit_default_prefix "$TOOL")"

    # Two-family path (preferred): a static sqlite3 binary matching the host libc
    # needs no package manager and runs on every distro — glibc covers RHEL/Rocky/
    # Debian/Ubuntu/SUSE/Arch/Fedora; musl covers Alpine. Selection is by libc.
    _fam="$(devkit_libc)"
    STATIC="$PARTS_DIR/sqlite3-${VERSION}-linux-x64-${_fam}"
    if [[ -f "$STATIC" ]]; then
        _sprefix="${INSTALL_PREFIX:-$DEFAULT_PREFIX}"; _prev=""
        for _arg in "$@"; do [[ "$_prev" == "--prefix" ]] && _sprefix="$_arg"; _prev="$_arg"; done
        devkit_verify_archive "$PARTS_DIR/manifest.json" "$STATIC"
        mkdir -p "$_sprefix/bin"
        cp "$STATIC" "$_sprefix/bin/sqlite3"; chmod +x "$_sprefix/bin/sqlite3"
        devkit_write_receipt "$TOOL" "$VERSION" "linux-${_fam}-static" "$_sprefix"
        echo "==> SQLite ${VERSION} (static ${_fam}) installed to ${_sprefix}/bin"
        exit 0
    fi

    # RHEL/Rocky fallback: the vendored, glibc-native RPM for the host major,
    # preferred over the upstream tarball (which needs glibc 2.38+). One RPM per
    # major is staged; pick the one matching the host (el8/el9/el10).
    _major="$(devkit_rhel_major)"
    RPM="$(ls "$PARTS_DIR"/sqlite-*.el${_major}*.x86_64.rpm 2>/dev/null | head -1)"
    if command -v rpm &>/dev/null && [[ -n "$RPM" && -f "$RPM" ]]; then
        # Read the version straight from the file name (e.g. sqlite-3.26.0-...).
        _rpm_base="$(basename "$RPM")"
        RPM_VERSION="${_rpm_base#sqlite-}"; RPM_VERSION="${RPM_VERSION%%-*}"
        if [[ "$(id -u)" == "0" ]]; then
            echo "==> Installing SQLite via RPM (RHEL/Rocky ${_major}, root)..."
            rpm -ivh "$RPM"
            devkit_write_receipt "$TOOL" "$RPM_VERSION" "linux-rhel${_major}" "$DEFAULT_PREFIX"
            echo "==> SQLite (RHEL/Rocky ${_major} RPM) installed."
            exit 0
        else
            # Non-root: extract RPM payload into user prefix via rpm2cpio.
            if command -v rpm2cpio &>/dev/null && command -v cpio &>/dev/null; then
                echo "==> Installing SQLite via RPM (RHEL/Rocky ${_major}, non-root — rpm2cpio)..."
                _rpm_prefix="${INSTALL_PREFIX:-$DEFAULT_PREFIX}"
                while [[ $# -gt 0 ]]; do
                    case "$1" in --prefix) _rpm_prefix="$2"; shift 2 ;; *) shift ;; esac
                done
                mkdir -p "$_rpm_prefix"
                cd "$_rpm_prefix"
                rpm2cpio "$RPM" | cpio -idm --quiet 2>/dev/null
                # sqlite3 lands at ./usr/bin/sqlite3 inside the RPM
                if [[ -f "$_rpm_prefix/usr/bin/sqlite3" ]]; then
                    mkdir -p "$_rpm_prefix/bin"
                    cp "$_rpm_prefix/usr/bin/sqlite3" "$_rpm_prefix/bin/sqlite3"
                    chmod +x "$_rpm_prefix/bin/sqlite3"
                fi
                devkit_write_receipt "$TOOL" "$RPM_VERSION" "linux-rhel${_major}" "$_rpm_prefix"
                echo "==> SQLite (RHEL/Rocky ${_major} RPM, non-root) installed to ${_rpm_prefix}/bin"
                exit 0
            fi
            # rpm2cpio not available — fall through to the upstream tarball with a warning.
            echo "  [!!]  rpm2cpio/cpio not found. Falling back to upstream tarball (requires glibc 2.38)." >&2
        fi
    fi
    ARCHIVE_BASE="sqlite-tools-${VERSION}-linux-x64"
fi

PREFIX="${INSTALL_PREFIX:-$DEFAULT_PREFIX}"
while [[ $# -gt 0 ]]; do
    case "$1" in --prefix) PREFIX="$2"; shift 2 ;; *) shift ;; esac
done
# _strict distinguishes a missing artifact (exit 1) from one that failed integrity
# verification (exit 2) and prints the right message; set -e aborts on either.
ARCHIVE_PATH="$(devkit_resolve_archive_strict "$PARTS_DIR" "$ARCHIVE_BASE")"

echo "==> Installing SQLite CLI ${VERSION} (${DEVKIT_PLATFORM}) to ${PREFIX}/bin"

devkit_verify_archive "$PARTS_DIR/manifest.json" "$ARCHIVE_PATH"

if [[ "$DEVKIT_PLATFORM" == "windows" ]]; then
    MSYS_NO_PATHCONV=1 cmd.exe /c mkdir "${PREFIX}\\bin" 2>/dev/null || true
    PREFIX="$(cygpath -u -- "$PREFIX")"
else
    mkdir -p "$PREFIX/bin"
fi
devkit_install_archive "$ARCHIVE_PATH" "$PREFIX/bin"
if [[ "$DEVKIT_PLATFORM" == "linux" ]]; then
    find "$PREFIX/bin" -maxdepth 1 -type f -exec chmod +x {} +
fi

devkit_write_receipt "$TOOL" "$VERSION" "$DEVKIT_PLATFORM" "$PREFIX"

echo "==> SQLite CLI ${VERSION} installed to ${PREFIX}/bin"
