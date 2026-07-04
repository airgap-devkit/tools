#!/usr/bin/env bash
set -euo pipefail

TOOL="git-bundle"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/devkit-install.sh"

PLATFORM="$DEVKIT_PLATFORM"
PREFIX="${INSTALL_PREFIX:-$(devkit_default_prefix "$TOOL")}"
while [[ $# -gt 0 ]]; do
    case "$1" in --prefix) PREFIX="$2"; shift 2 ;; *) shift ;; esac
done

echo "==> Setting up git-bundle transfer tool"

PYTHON_BIN=""
for candidate in python3 python; do
    if command -v "$candidate" &>/dev/null; then
        PYTHON_BIN="$candidate"
        break
    fi
done
if [[ -z "$PYTHON_BIN" ]]; then
    echo "ERROR: Python 3 is required for the git-bundle transfer tool." >&2
    echo "       Install Python first: bash tools/languages/python/setup.sh" >&2
    exit 1
fi

if ! command -v git &>/dev/null; then
    echo "ERROR: git is required for the git-bundle transfer tool." >&2
    exit 1
fi

PYTHON_VERSION="$("$PYTHON_BIN" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
GIT_VERSION="$(git --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
echo "    Python: ${PYTHON_VERSION}   Git: ${GIT_VERSION}"
echo "    Scripts: ${SCRIPT_DIR}"

mkdir -p "$PREFIX"
cat > "$PREFIX/INSTALL_RECEIPT.txt" << RECEIPT
tool=${TOOL}
version=1.0.0
platform=${PLATFORM}
install_prefix=${SCRIPT_DIR}
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RECEIPT

echo "==> git-bundle transfer tool ready."
echo "    Use the scripts in ${SCRIPT_DIR} to bundle and transfer git repositories."
