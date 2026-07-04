#!/usr/bin/env bash
set -euo pipefail

TOOL="sqlite"
VERSION="3.53.3"
# RHEL 8 vendored RPM ships an older SQLite than the upstream CLI tools tarball;
# its version is tracked separately so the receipt reflects what was installed.
RPM_VERSION="3.26.0"
RPM_FILE="sqlite-${RPM_VERSION}-20.el8_10.x86_64.rpm"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/devkit-install.sh"
PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"
PARTS_DIR="$PREBUILT_DIR/dev-tools/sqlite/${VERSION}"

if [[ "$DEVKIT_PLATFORM" == "windows" ]]; then
    ARCHIVE_BASE="sqlite-tools-${VERSION}-windows-x64"
    DEFAULT_PREFIX="$(devkit_default_prefix "$TOOL")"
else
    DEFAULT_PREFIX="$(devkit_default_prefix "$TOOL")"
    # RHEL 8: use the vendored RPM (glibc-compatible) in preference to the
    # upstream tarball which requires glibc 2.38+.
    RPM="$PARTS_DIR/$RPM_FILE"
    if command -v rpm &>/dev/null && [[ -f "$RPM" ]]; then
        if [[ "$(id -u)" == "0" ]]; then
            echo "==> Installing SQLite via RPM (RHEL 8, root)..."
            rpm -ivh "$RPM"
            devkit_write_receipt "$TOOL" "$RPM_VERSION" "linux-rhel8" "$DEFAULT_PREFIX"
            echo "==> SQLite (RHEL 8 RPM) installed."
            exit 0
        else
            # Non-root: extract RPM payload into user prefix via rpm2cpio.
            if command -v rpm2cpio &>/dev/null && command -v cpio &>/dev/null; then
                echo "==> Installing SQLite via RPM (RHEL 8, non-root — rpm2cpio)..."
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
                devkit_write_receipt "$TOOL" "$RPM_VERSION" "linux-rhel8" "$_rpm_prefix"
                echo "==> SQLite (RHEL 8 RPM, non-root) installed to ${_rpm_prefix}/bin"
                exit 0
            fi
            # rpm2cpio not available — fall through to the upstream tarball with a warning.
            echo "  [!!]  rpm2cpio not found. Falling back to upstream tarball (requires glibc 2.38)." >&2
        fi
    fi
    ARCHIVE_BASE="sqlite-tools-${VERSION}-linux-x64"
fi

PREFIX="${INSTALL_PREFIX:-$DEFAULT_PREFIX}"
while [[ $# -gt 0 ]]; do
    case "$1" in --prefix) PREFIX="$2"; shift 2 ;; *) shift ;; esac
done
ARCHIVE_PATH="$(devkit_resolve_archive "$PARTS_DIR" "$ARCHIVE_BASE")" \
    || { echo "ERROR: Archive not found for ${ARCHIVE_BASE} in $PARTS_DIR" >&2; exit 1; }

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
