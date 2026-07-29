#!/usr/bin/env bash
set -euo pipefail

TOOL="dotnet"
VERSION="10.0.301"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/devkit-install.sh"
PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"
PARTS_DIR="$PREBUILT_DIR/languages/dotnet/${VERSION}"

if [[ "$DEVKIT_PLATFORM" == "windows" ]]; then
    ARCHIVE_BASE="dotnet-sdk-${VERSION}-win-x64"
else
    ARCHIVE_BASE="dotnet-sdk-${VERSION}-linux-x64"
fi

PREFIX="${INSTALL_PREFIX:-$(devkit_default_prefix "$TOOL")}"
while [[ $# -gt 0 ]]; do
    case "$1" in --prefix) PREFIX="$2"; shift 2 ;; *) shift ;; esac
done

echo "==> Installing .NET SDK ${VERSION} (${DEVKIT_PLATFORM}) to ${PREFIX}"

if [[ ! -d "$PARTS_DIR" ]]; then
    echo "ERROR: Prebuilt parts not found at: $PARTS_DIR" >&2; exit 1
fi

# _strict distinguishes a missing artifact (exit 1) from one that failed integrity
# verification (exit 2) and prints the right message; set -e aborts on either.
ARCHIVE_PATH="$(devkit_resolve_archive_strict "$PARTS_DIR" "$ARCHIVE_BASE")"
devkit_verify_archive "$PARTS_DIR/manifest.json" "$ARCHIVE_PATH"

if [[ "$DEVKIT_PLATFORM" == "windows" ]]; then
    MSYS_NO_PATHCONV=1 cmd.exe /c mkdir "$PREFIX" 2>/dev/null || true
    PREFIX="$(cygpath -u -- "$PREFIX")"
else
    mkdir -p "$PREFIX"
fi
devkit_install_archive "$ARCHIVE_PATH" "$PREFIX"
if [[ "$DEVKIT_PLATFORM" == "linux" ]]; then
    [[ -f "$PREFIX/dotnet" ]] && chmod +x "$PREFIX/dotnet"
fi

# Wire DOTNET_ROOT for the current session
export DOTNET_ROOT="$PREFIX"

devkit_write_receipt "$TOOL" "$VERSION" "$DEVKIT_PLATFORM" "$PREFIX"

echo "==> .NET SDK ${VERSION} installed to ${PREFIX}"
echo "    Add ${PREFIX} to your PATH and set DOTNET_ROOT=${PREFIX}"
