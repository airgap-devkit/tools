#!/usr/bin/env bash
set -euo pipefail

TOOL="sqlite"
VERSION="3.53.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"
PARTS_DIR="$PREBUILT_DIR/dev-tools/sqlite/${VERSION}"

if [[ "${AIRGAP_OS:-}" == "windows" || "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "${OS:-}" == "Windows_NT" ]]; then
    PLATFORM="windows"
    ARCHIVE="sqlite-tools-${VERSION}-windows-x64.tar.xz"
    DEFAULT_PREFIX="${LOCALAPPDATA:-$HOME/AppData/Local}/airgap-cpp-devkit/sqlite"
else
    PLATFORM="linux"
    if [[ "$(id -u)" == "0" ]]; then
        DEFAULT_PREFIX="/opt/airgap-cpp-devkit/sqlite"
    else
        DEFAULT_PREFIX="${HOME}/.local/share/airgap-cpp-devkit/sqlite"
    fi
    # RHEL 8: use the vendored RPM (glibc-compatible) in preference to the
    # upstream tarball which requires glibc 2.38+.
    RPM="$PARTS_DIR/sqlite-3.26.0-20.el8_10.x86_64.rpm"
    if command -v rpm &>/dev/null && [[ -f "$RPM" ]]; then
        if [[ "$(id -u)" == "0" ]]; then
            echo "==> Installing SQLite via RPM (RHEL 8, root)..."
            rpm -ivh "$RPM"
            mkdir -p "$DEFAULT_PREFIX"
            cat > "$DEFAULT_PREFIX/INSTALL_RECEIPT.txt" << RECEIPT
tool=${TOOL}
version=3.26.0
platform=linux-rhel8
install_prefix=system
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RECEIPT
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
                cat > "$_rpm_prefix/INSTALL_RECEIPT.txt" << RECEIPT
tool=${TOOL}
version=3.26.0
platform=linux-rhel8
install_prefix=${_rpm_prefix}
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RECEIPT
                echo "==> SQLite (RHEL 8 RPM, non-root) installed to ${_rpm_prefix}/bin"
                exit 0
            fi
            # rpm2cpio not available — fall through to the upstream tarball with a warning.
            echo "  [!!]  rpm2cpio not found. Falling back to upstream tarball (requires glibc 2.38)." >&2
        fi
    fi
    ARCHIVE="sqlite-tools-${VERSION}-linux-x64.tar.xz"
fi

PREFIX="${INSTALL_PREFIX:-$DEFAULT_PREFIX}"
while [[ $# -gt 0 ]]; do
    case "$1" in --prefix) PREFIX="$2"; shift 2 ;; *) shift ;; esac
done
ARCHIVE_PATH="$PARTS_DIR/$ARCHIVE"

echo "==> Installing SQLite CLI ${VERSION} (${PLATFORM}) to ${PREFIX}/bin"

if [[ ! -f "$ARCHIVE_PATH" ]]; then
    echo "ERROR: Archive not found: $ARCHIVE_PATH" >&2; exit 1
fi

if [[ "$PLATFORM" == "windows" ]]; then
    MSYS_NO_PATHCONV=1 cmd.exe /c mkdir "${PREFIX}\\bin" 2>/dev/null || true
    PREFIX="$(cygpath -u -- "$PREFIX")"
else
    mkdir -p "$PREFIX/bin"
fi
tar -xJf "$ARCHIVE_PATH" -C "$PREFIX/bin" --strip-components=0
if [[ "$PLATFORM" == "linux" ]]; then
    find "$PREFIX/bin" -maxdepth 1 -type f -exec chmod +x {} +
fi

cat > "$PREFIX/INSTALL_RECEIPT.txt" << RECEIPT
tool=${TOOL}
version=${VERSION}
platform=${PLATFORM}
install_prefix=${PREFIX}
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RECEIPT

echo "==> SQLite CLI ${VERSION} installed to ${PREFIX}/bin"
