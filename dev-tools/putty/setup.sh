#!/usr/bin/env bash
set -euo pipefail

TOOL="putty"
VERSION="0.83"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/../../lib/devkit-install.sh"

PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"
JOBS="${MAKE_JOBS:-$(nproc 2>/dev/null || echo 4)}"
PREFIX="${INSTALL_PREFIX:-$(devkit_default_prefix putty)}"
devkit_parse_args "$@"

echo "==> Installing PuTTY ${VERSION} (${DEVKIT_PLATFORM}) to ${PREFIX}"

if [[ "$DEVKIT_PLATFORM" == "windows" ]]; then
    PARTS_DIR="$PREBUILT_DIR/dev-tools/putty/${VERSION}"
    INSTALLER=$(devkit_find_file "$PARTS_DIR")
    if [[ -z "$INSTALLER" ]]; then
        echo "ERROR: No installer found in $PARTS_DIR" >&2; exit 1
    fi
    devkit_install_msi "$INSTALLER"
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

devkit_write_receipt putty "$VERSION" "$DEVKIT_PLATFORM" "$PREFIX"

echo "==> PuTTY ${VERSION} installed to ${PREFIX}"
if [[ "$DEVKIT_PLATFORM" == "linux" ]]; then
    echo "    CLI tools: plink, pscp, psftp, puttygen"
fi
