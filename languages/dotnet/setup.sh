#!/usr/bin/env bash
set -euo pipefail

TOOL="dotnet"
VERSION="10.0.203"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"
PARTS_DIR="$PREBUILT_DIR/languages/dotnet/${VERSION}"

if [[ "${AIRGAP_OS:-}" == "windows" || "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "${OS:-}" == "Windows_NT" ]]; then
    PLATFORM="windows"
    ARCHIVE="dotnet-sdk-${VERSION}-win-x64.tar.xz"
    DEFAULT_PREFIX="${LOCALAPPDATA:-$HOME/AppData/Local}/airgap-cpp-devkit/dotnet"
else
    PLATFORM="linux"
    ARCHIVE="dotnet-sdk-${VERSION}-linux-x64.tar.xz"
    if [[ "$(id -u)" == "0" ]]; then
        DEFAULT_PREFIX="/opt/airgap-cpp-devkit/dotnet"
    else
        DEFAULT_PREFIX="${HOME}/.local/share/airgap-cpp-devkit/dotnet"
    fi
fi

PREFIX="${INSTALL_PREFIX:-$DEFAULT_PREFIX}"
while [[ $# -gt 0 ]]; do
    case "$1" in --prefix) PREFIX="$2"; shift 2 ;; *) shift ;; esac
done

echo "==> Installing .NET SDK ${VERSION} (${PLATFORM}) to ${PREFIX}"

if [[ ! -d "$PARTS_DIR" ]]; then
    echo "ERROR: Prebuilt parts not found at: $PARTS_DIR" >&2; exit 1
fi

PARTS=("$PARTS_DIR/${ARCHIVE}.part-"*)
if [[ ${#PARTS[@]} -eq 0 || ! -f "${PARTS[0]}" ]]; then
    echo "ERROR: No parts found for ${ARCHIVE}" >&2; exit 1
fi
echo "    Found ${#PARTS[@]} parts."

if [[ "$PLATFORM" == "windows" ]]; then
    MSYS_NO_PATHCONV=1 cmd.exe /c mkdir "$PREFIX" 2>/dev/null || true
    PREFIX="$(cygpath -u -- "$PREFIX")"
else
    mkdir -p "$PREFIX"
fi
cat "${PARTS[@]}" | tar -xJ -C "$PREFIX"

# Wire DOTNET_ROOT for the current session
export DOTNET_ROOT="$PREFIX"

cat > "$PREFIX/INSTALL_RECEIPT.txt" << RECEIPT
tool=${TOOL}
version=${VERSION}
platform=${PLATFORM}
install_prefix=${PREFIX}
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RECEIPT

echo "==> .NET SDK ${VERSION} installed to ${PREFIX}"
echo "    Add ${PREFIX} to your PATH and set DOTNET_ROOT=${PREFIX}"
