#!/usr/bin/env bash
set -euo pipefail

TOOL="osslsigncode"
VERSION="2.13"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../../lib/devkit-install.sh
source "${SCRIPT_DIR}/../../lib/devkit-install.sh"

PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"
JOBS="${MAKE_JOBS:-$(nproc 2>/dev/null || echo 4)}"
PREFIX="${INSTALL_PREFIX:-$(devkit_default_prefix osslsigncode)}"
devkit_parse_args "$@"

echo "==> Installing osslsigncode ${VERSION} (${DEVKIT_PLATFORM}) to ${PREFIX}"

if [[ "$DEVKIT_PLATFORM" == "windows" ]]; then
    # ── Windows: extract prebuilt MINGW64 zip ──────────────────────────────
    PARTS_DIR="$PREBUILT_DIR/dev-tools/osslsigncode/${VERSION}"
    ARCHIVE=$(devkit_find_file "$PARTS_DIR" windows)
    if [[ -z "$ARCHIVE" ]]; then
        echo "ERROR: No Windows archive found in $PARTS_DIR" >&2
        echo "Run: bash scripts/download-prebuilt.sh --small" >&2
        exit 1
    fi

    TMP_EXTRACT=$(mktemp -d)
    trap 'rm -rf "$TMP_EXTRACT"' EXIT

    devkit_extract "$ARCHIVE" "$TMP_EXTRACT"

    # Locate osslsigncode.exe wherever it landed inside the zip
    EXE=$(find "$TMP_EXTRACT" -name "osslsigncode.exe" | head -1)
    if [[ -z "$EXE" ]]; then
        echo "ERROR: osslsigncode.exe not found inside $ARCHIVE" >&2
        exit 1
    fi
    EXE_DIR="$(dirname "$EXE")"

    mkdir -p "$PREFIX/bin"
    # Copy the exe and any DLLs bundled alongside it
    cp "$EXE_DIR"/*.exe "$PREFIX/bin/" 2>/dev/null || true
    cp "$EXE_DIR"/*.dll "$PREFIX/bin/" 2>/dev/null || true

    echo "==> osslsigncode ${VERSION} installed to ${PREFIX}"
    echo "    Binary: ${PREFIX}/bin/osslsigncode.exe"
    echo ""
    echo "    Add to PATH (add to ~/.bashrc for Git Bash):"
    BINDIR_POSIX="$(cygpath -u "$PREFIX/bin" 2>/dev/null || echo "$PREFIX/bin")"
    echo "      export PATH=\"${BINDIR_POSIX}:\$PATH\""

else
    # ── Linux: build from source (cmake + OpenSSL + libcurl + zlib) ────────
    SOURCE_ARCHIVE="$SCRIPT_DIR/sources/osslsigncode-${VERSION}.tar.gz"
    if [[ ! -f "$SOURCE_ARCHIVE" ]]; then
        echo "ERROR: Source archive not found: $SOURCE_ARCHIVE" >&2
        echo "Run: bash scripts/download-prebuilt.sh --small" >&2
        exit 1
    fi

    MISSING=()
    for cmd in gcc cmake pkg-config; do
        command -v "$cmd" &>/dev/null || MISSING+=("$cmd")
    done
    for pkg in openssl libcurl zlib; do
        pkg-config --exists "$pkg" 2>/dev/null || MISSING+=("pkg: $pkg (install $pkg-devel)")
    done
    if [[ ${#MISSING[@]} -gt 0 ]]; then
        echo "ERROR: Missing build dependencies:" >&2
        printf "  - %s\n" "${MISSING[@]}" >&2
        echo "" >&2
        echo "On RHEL 8:" >&2
        echo "  dnf install gcc cmake openssl-devel libcurl-devel zlib-devel pkg-config" >&2
        echo "  (cmake: install from airgap-devkit first if system cmake is <3.14)" >&2
        exit 1
    fi

    BUILD_DIR=$(mktemp -d)
    trap 'rm -rf "$BUILD_DIR"' EXIT

    echo "==> Extracting source..."
    tar -xzf "$SOURCE_ARCHIVE" -C "$BUILD_DIR"
    SRC_DIR="$BUILD_DIR/osslsigncode-${VERSION}"

    echo "==> Configuring (${JOBS} jobs)..."
    cmake -S "$SRC_DIR" -B "$SRC_DIR/build" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        2>&1

    echo "==> Building..."
    cmake --build "$SRC_DIR/build" --parallel "$JOBS" 2>&1

    echo "==> Installing..."
    cmake --install "$SRC_DIR/build" 2>&1

    echo "==> osslsigncode ${VERSION} installed to ${PREFIX}"
    echo "    Binary: ${PREFIX}/bin/osslsigncode"
fi

devkit_write_receipt osslsigncode "$VERSION" "$DEVKIT_PLATFORM" "$PREFIX"
