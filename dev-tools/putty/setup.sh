#!/usr/bin/env bash
set -euo pipefail

TOOL="putty"
VERSION="0.83"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"

if [[ "${AIRGAP_OS:-}" == "windows" || "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "${OS:-}" == "Windows_NT" ]]; then
    PLATFORM="windows"
    DEFAULT_PREFIX="${LOCALAPPDATA:-$HOME/AppData/Local}/airgap-cpp-devkit/putty"
else
    PLATFORM="linux"
    if [[ "$(id -u)" == "0" ]]; then
        DEFAULT_PREFIX="/opt/airgap-cpp-devkit/putty"
    else
        DEFAULT_PREFIX="${HOME}/.local/share/airgap-cpp-devkit/putty"
    fi
fi

PREFIX="${INSTALL_PREFIX:-$DEFAULT_PREFIX}"
JOBS="${MAKE_JOBS:-$(nproc 2>/dev/null || echo 4)}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)  PREFIX="$2"; shift 2 ;;
        --jobs)    JOBS="$2";   shift 2 ;;
        --rebuild) rm -f "$PREFIX/INSTALL_RECEIPT.txt"; shift ;;
        *) shift ;;
    esac
done

echo "==> Installing PuTTY ${VERSION} (${PLATFORM}) to ${PREFIX}"

if [[ "$PLATFORM" == "windows" ]]; then
    INSTALLER="$PREBUILT_DIR/dev-tools/putty/${VERSION}/putty-64bit-${VERSION}-installer.msi"
    if [[ ! -f "$INSTALLER" ]]; then
        echo "ERROR: Installer not found: $INSTALLER" >&2; exit 1
    fi
    INSTALLER_WIN="$(cygpath -w "$INSTALLER")"
    PREFIX_WIN="$(cygpath -w "$PREFIX")"
    # MSYS_NO_PATHCONV=1 prevents Git Bash from re-mangling the Windows paths
    # that cygpath already produced, avoiding msiexec ERROR_BAD_NET_NAME (exit 67)
    MSYS_NO_PATHCONV=1 msiexec.exe /i "${INSTALLER_WIN}" /quiet /qn \
        "INSTALLDIR=${PREFIX_WIN}\\" || {
        echo "ERROR: msiexec.exe failed (exit $?)." >&2
        echo "  Try the installer manually: ${INSTALLER_WIN}" >&2
        exit 1
    }
else
    # Linux: build CLI tools from source (no GTK required)
    SOURCE_ARCHIVE="$SCRIPT_DIR/sources/putty-${VERSION}.tar.gz"
    if [[ ! -f "$SOURCE_ARCHIVE" ]]; then
        echo "ERROR: Source archive not found: $SOURCE_ARCHIVE" >&2; exit 1
    fi

    MISSING=()
    for cmd in gcc cmake make; do
        command -v "$cmd" &>/dev/null || MISSING+=("$cmd")
    done
    if [[ ${#MISSING[@]} -gt 0 ]]; then
        echo "ERROR: Missing build dependencies: ${MISSING[*]}" >&2
        echo "  Install cmake from the devkit first: bash tools/dev-tools/../build-tools/cmake/setup.sh" >&2
        echo "  Install gcc via: dnf install gcc gcc-c++ make" >&2
        exit 1
    fi

    BUILD_DIR=$(mktemp -d)
    trap 'rm -rf "$BUILD_DIR"' EXIT

    echo "==> Extracting source..."
    tar -xzf "$SOURCE_ARCHIVE" -C "$BUILD_DIR"
    SRC_DIR="$BUILD_DIR/putty-${VERSION}"

    echo "==> Configuring (CLI-only, no GTK)..."
    cmake -S "$SRC_DIR" -B "$SRC_DIR/build" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DPUTTY_GTK_VERSION=NONE \
        2>&1

    echo "==> Building (${JOBS} jobs)..."
    cmake --build "$SRC_DIR/build" --parallel "$JOBS" 2>&1

    echo "==> Installing..."
    cmake --install "$SRC_DIR/build" 2>&1
fi

mkdir -p "$PREFIX"
cat > "$PREFIX/INSTALL_RECEIPT.txt" << RECEIPT
tool=${TOOL}
version=${VERSION}
platform=${PLATFORM}
install_prefix=${PREFIX}
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RECEIPT

echo "==> PuTTY ${VERSION} installed to ${PREFIX}"
if [[ "$PLATFORM" == "linux" ]]; then
    echo "    CLI tools: plink, pscp, psftp, puttygen"
fi
