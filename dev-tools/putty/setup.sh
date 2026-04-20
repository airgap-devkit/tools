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
    echo "==> Installer: ${INSTALLER_WIN}"
    export _PUTTY_MSI="$INSTALLER_WIN"
    # Use PowerShell Start-Process -Wait to block until msiexec + all child
    # processes finish.  set +e so bash doesn't exit on a non-zero RC before
    # we can capture it.  INSTALLDIR omitted — some MSI versions reject it
    # with ERROR_BAD_NET_NAME (67); PuTTY installs to its default path and
    # the receipt below is always written to our custom PREFIX.
    set +e
    powershell.exe -NoProfile -NonInteractive -Command '
        $p = Start-Process msiexec.exe `
            -ArgumentList @("/i", $env:_PUTTY_MSI, "/quiet", "/qn", "/norestart") `
            -Wait -PassThru
        exit $p.ExitCode
    '
    RC=$?
    set -e
    unset _PUTTY_MSI
    if [[ $RC -ne 0 && $RC -ne 3010 ]]; then
        echo "ERROR: msiexec.exe failed (exit $RC)." >&2
        echo "  Try the installer manually: ${INSTALLER_WIN}" >&2
        exit 1
    fi
    if [[ $RC -eq 3010 ]]; then
        echo "==> Note: Installation succeeded (restart may be required)"
    fi
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
