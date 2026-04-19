#!/usr/bin/env bash
set -euo pipefail

TOOL="matlab"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${AIRGAP_OS:-}" == "windows" || "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "${OS:-}" == "Windows_NT" ]]; then
    PLATFORM="windows"
    DEFAULT_PREFIX="${LOCALAPPDATA:-$HOME/AppData/Local}/airgap-cpp-devkit/matlab"
else
    PLATFORM="linux"
    if [[ "$(id -u)" == "0" ]]; then
        DEFAULT_PREFIX="/opt/airgap-cpp-devkit/matlab"
    else
        DEFAULT_PREFIX="${HOME}/.local/share/airgap-cpp-devkit/matlab"
    fi
fi
PREFIX="${INSTALL_PREFIX:-$DEFAULT_PREFIX}"
while [[ $# -gt 0 ]]; do
    case "$1" in --prefix) PREFIX="$2"; shift 2 ;; *) shift ;; esac
done

echo "==> MATLAB Verification"
echo "    This tool checks for an existing MATLAB installation."
echo "    It does NOT install MATLAB."
echo ""

MATLAB_PATH=""
if command -v matlab &>/dev/null; then
    MATLAB_PATH="$(command -v matlab)"
fi

if [[ -z "$MATLAB_PATH" ]]; then
    echo "    MATLAB not found on PATH."
    echo "    Install MATLAB separately and add it to PATH, then re-run this script."
    echo ""
    exit 0
fi

MATLAB_VERSION="$(matlab -batch "disp(version)" 2>/dev/null | grep -m1 '[0-9]' || echo "unknown")"
echo "    Found MATLAB: ${MATLAB_PATH}"
echo "    Version:      ${MATLAB_VERSION}"
echo ""

# Check for required toolboxes
REQUIRED_TOOLBOXES=("Database Toolbox" "MATLAB Compiler")
MISSING=()

echo "    Checking toolboxes..."
for tb in "${REQUIRED_TOOLBOXES[@]}"; do
    result="$(matlab -batch \
        "v = ver; names = {v.Name}; disp(any(strcmp(names, '${tb}')))" \
        2>/dev/null | tail -1 || echo "0")"
    if [[ "$result" == "1" ]]; then
        echo "    [OK]  ${tb}"
    else
        echo "    [!!]  ${tb} -- NOT found"
        MISSING+=("${tb}")
    fi
done

echo ""
mkdir -p "$PREFIX"
cat > "$PREFIX/INSTALL_RECEIPT.txt" << RECEIPT
tool=${TOOL}
version=${MATLAB_VERSION}
platform=${PLATFORM}
install_prefix=${MATLAB_PATH}
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RECEIPT

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "    WARNING: Missing toolboxes: ${MISSING[*]}"
    echo "    Contact your MATLAB administrator for license access."
else
    echo "    All required toolboxes present."
fi

echo ""
echo "==> MATLAB verification complete."
