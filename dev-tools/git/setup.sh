#!/usr/bin/env bash
set -euo pipefail

TOOL="git"
VERSION="2.53.0.3"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"

if [[ "${AIRGAP_OS:-}" == "windows" || "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "${OS:-}" == "Windows_NT" ]]; then
    PLATFORM="windows"
    DEFAULT_PREFIX="${LOCALAPPDATA:-$HOME/AppData/Local}/airgap-cpp-devkit/git"
else
    echo "ERROR: Git for Windows installer is Windows-only." >&2
    echo "  On Linux, install Git via your package manager: sudo dnf install git" >&2
    exit 1
fi

PREFIX="${INSTALL_PREFIX:-$DEFAULT_PREFIX}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)  PREFIX="$2"; shift 2 ;;
        --rebuild) rm -f "$PREFIX/INSTALL_RECEIPT.txt"; shift ;;
        *) shift ;;
    esac
done

echo "==> Installing Git ${VERSION} (${PLATFORM}) to ${PREFIX}"

INSTALLER="$PREBUILT_DIR/dev-tools/git/${VERSION}/Git-${VERSION}-64-bit.exe"
if [[ ! -f "$INSTALLER" ]]; then
    echo "ERROR: Installer not found: $INSTALLER" >&2
    exit 1
fi

INSTALLER_WIN="$(cygpath -w "$INSTALLER")"
PREFIX_WIN="$(cygpath -w "$PREFIX")"
echo "==> Installer : ${INSTALLER_WIN}"
echo "==> Prefix    : ${PREFIX_WIN}"

# Git for Windows is an NSIS installer. Invoke via cmd.exe so MSYS never
# rewrites the /VERYSILENT and /DIR arguments.
# /VERYSILENT   — no UI
# /NORESTART    — suppress reboot prompt
# /NOCANCEL     — prevent cancellation
# /SP-          — suppress "This will install…" prompt
# /DIR          — install directory
set +e
cmd.exe //c "\"${INSTALLER_WIN}\" /VERYSILENT /NORESTART /NOCANCEL /SP- /DIR=\"${PREFIX_WIN}\""
RC=$?
set -e

if [[ $RC -ne 0 ]]; then
    echo "ERROR: Git installer failed (exit $RC)." >&2
    echo "  Try running manually: ${INSTALLER_WIN}" >&2
    exit 1
fi

mkdir -p "$PREFIX"
cat > "$PREFIX/INSTALL_RECEIPT.txt" << RECEIPT
tool=${TOOL}
version=${VERSION}
platform=${PLATFORM}
install_prefix=${PREFIX}
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RECEIPT

echo "==> Git ${VERSION} installed to ${PREFIX}"
