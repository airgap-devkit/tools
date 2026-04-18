#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# tools/frameworks/grpc/setup.sh
#
# Installs gRPC prebuilt binaries for Windows x64 from the prebuilt submodule.
#
# USAGE (called by devkit-ui or install-cli.sh):
#   bash tools/frameworks/grpc/setup.sh [--rebuild]
#
# Reads VERSION from devkit.json alongside this script.
# Extracts prebuilt/frameworks/grpc/windows/<version>/*.zip.part-* to install prefix.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# ---------------------------------------------------------------------------
# Version — read from devkit.json so there is a single source of truth
# ---------------------------------------------------------------------------
VERSION="$(grep '"version"' "${SCRIPT_DIR}/devkit.json" 2>/dev/null \
    | head -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
if [[ -z "${VERSION}" ]]; then
    echo "  [!!] Could not read version from devkit.json" >&2
    exit 1
fi
TOOL_NAME="grpc-${VERSION}"

# ---------------------------------------------------------------------------
# Windows only
# ---------------------------------------------------------------------------
if ! [[ "${AIRGAP_OS:-}" == "windows" || "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "${OS:-}" == "Windows_NT" ]]; then
    echo "  [--] gRPC prebuilt is Windows only. Nothing to do."
    exit 0
fi

# ---------------------------------------------------------------------------
# Rebuild flag
# ---------------------------------------------------------------------------
REBUILD=false
for arg in "$@"; do
    [[ "${arg}" == "--rebuild" ]] && REBUILD=true
done

# ---------------------------------------------------------------------------
# install-mode setup
# ---------------------------------------------------------------------------
source "${REPO_ROOT}/scripts/install-mode.sh"
install_mode_init "${TOOL_NAME}" "${VERSION}" "$@"
install_log_capture_start

# ---------------------------------------------------------------------------
# Short-circuit if already installed
# ---------------------------------------------------------------------------
if [[ "${REBUILD}" == "false" && -f "${INSTALL_RECEIPT}" ]]; then
    echo "  [OK] ${TOOL_NAME} already installed at ${INSTALL_PREFIX}"
    echo "       Use --rebuild to force reinstall."
    exit 0
fi

# ---------------------------------------------------------------------------
# Locate prebuilt parts
# ---------------------------------------------------------------------------
PREBUILT_DIR="${REPO_ROOT}/prebuilt/frameworks/grpc/windows/${VERSION}"

if [[ ! -d "${PREBUILT_DIR}" ]]; then
    echo "  [!!] Prebuilt directory not found: ${PREBUILT_DIR}"
    echo "       Ensure the prebuilt submodule is initialized:"
    echo "         git submodule update --init prebuilt"
    exit 1
fi

ARCHIVE="${PREBUILT_DIR}/grpc-${VERSION}-windows-x64.tar.xz"
if [[ ! -f "${ARCHIVE}" ]]; then
    echo "  [!!] Prebuilt archive not found: ${ARCHIVE}"
    echo "       Ensure the prebuilt submodule is initialized:"
    echo "         git submodule update --init prebuilt"
    exit 1
fi

# ---------------------------------------------------------------------------
# Extract
# ---------------------------------------------------------------------------
MSYS_NO_PATHCONV=1 cmd.exe /c mkdir "${INSTALL_PREFIX}" 2>/dev/null || true
INSTALL_PREFIX="$(cygpath -u -- "${INSTALL_PREFIX}")"
export INSTALL_PREFIX

im_progress_start "Extracting to ${INSTALL_PREFIX}"
tar -xJf "${ARCHIVE}" -C "${INSTALL_PREFIX}"
im_progress_stop "Extraction complete"

# ---------------------------------------------------------------------------
# Register PATH and write receipt
# ---------------------------------------------------------------------------
ENV_FILE="$(install_env_register "${INSTALL_BIN_DIR}")"

install_receipt_write "success" \
    "grpc_cpp_plugin:${INSTALL_BIN_DIR}/grpc_cpp_plugin.exe" \
    "protoc:${INSTALL_BIN_DIR}/protoc.exe"

install_mode_print_footer "success" \
    "grpc_cpp_plugin:${INSTALL_BIN_DIR}/grpc_cpp_plugin.exe" \
    "protoc:${INSTALL_BIN_DIR}/protoc.exe"

echo ""
echo "  Restart your shell or run:"
echo "    source \"${ENV_FILE}\""
echo ""
