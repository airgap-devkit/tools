#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# tools/frameworks/grpc/setup.sh
#
# Installs a prebuilt gRPC package for Windows x64 from the prebuilt submodule.
#
# The prebuilt distribution is the dso-suite maintainer build (release config),
# vendored into this repo per MSVC toolset. Because the static libraries are
# ABI-locked to the toolset they were built with, one package is shipped per
# Visual Studio version:
#
#   --toolset v142   MSVC v142   Visual Studio 2019
#   --toolset v143   MSVC v143   Visual Studio 2022   (default)
#   --toolset v145   MSVC v145   Visual Studio 2026
#
# Each toolset installs into its own sibling directory
# (<prefix>/grpc-<version>-msvc<NNN>) so multiple toolsets can coexist.
#
# USAGE (called by devkit-ui or install-cli.sh):
#   bash tools/frameworks/grpc/setup.sh [--toolset v143] [--rebuild]
#
# Reads VERSION from devkit.json alongside this script.
# Extracts prebuilt/frameworks/grpc/windows/<version>/<archive>.part-* to the
# install prefix. The package is self-describing: it drops activate.ps1 and
# grpc-toolchain.cmake at the install root alongside bin/ include/ lib/ share/.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
source "${REPO_ROOT}/scripts/internal/install-mode.sh"

# ---------------------------------------------------------------------------
# Version — read from devkit.json so there is a single source of truth
# ---------------------------------------------------------------------------
VERSION="$(grep '"version"' "${SCRIPT_DIR}/devkit.json" 2>/dev/null \
    | head -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
if [[ -z "${VERSION}" ]]; then
    echo "  [!!] Could not read version from devkit.json" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Parse args: --toolset <v142|v143|v145|142|143|145>, --rebuild
# ---------------------------------------------------------------------------
TOOLSET="v143"          # default: Visual Studio 2022
REBUILD=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --toolset) TOOLSET="$2"; shift 2 ;;
        --toolset=*) TOOLSET="${1#*=}"; shift ;;
        --rebuild) REBUILD=true; shift ;;
        # Back-compat: install-cli historically passed "--version X"; ignore it,
        # the version is authoritative in devkit.json.
        --version) shift 2 ;;
        *) shift ;;
    esac
done
TOOLSET="${TOOLSET#v}"   # normalise "v143" -> "143"

case "${TOOLSET}" in
    142) VS_LABEL="Visual Studio 2019" ;;
    143) VS_LABEL="Visual Studio 2022" ;;
    145) VS_LABEL="Visual Studio 2026" ;;
    *)
        echo "  [!!] Unknown toolset 'v${TOOLSET}'. Valid: v142, v143, v145." >&2
        exit 1 ;;
esac

TOOL_NAME="grpc-${VERSION}-msvc${TOOLSET}"

# ---------------------------------------------------------------------------
# Windows only
# ---------------------------------------------------------------------------
if [[ "$(_im_os)" != "windows" ]]; then
    echo "  [--] gRPC prebuilt is Windows only. Nothing to do."
    exit 0
fi

# ---------------------------------------------------------------------------
# install-mode setup
# ---------------------------------------------------------------------------
install_mode_init "${TOOL_NAME}" "${VERSION}" "$@"
install_log_capture_start

echo "  Toolset : v${TOOLSET}  (${VS_LABEL})"

# ---------------------------------------------------------------------------
# Deterministic per-toolset install dir so multiple toolsets coexist and
# status.sh can report each one. This normalises the two entry points:
#   - CLI passes TOOL_NAME -> prefix already ends in grpc-<ver>-msvc<NNN>
#   - devkit-ui overrides the prefix to <base>/grpc (via receipt_name)
# ---------------------------------------------------------------------------
case "$(basename "${INSTALL_PREFIX}")" in
    grpc|grpc-*)
        INSTALL_PREFIX="$(dirname "${INSTALL_PREFIX}")/${TOOL_NAME}" ;;
    *)
        INSTALL_PREFIX="${INSTALL_PREFIX}/${TOOL_NAME}" ;;
esac
export INSTALL_PREFIX
export INSTALL_BIN_DIR="${INSTALL_PREFIX}/bin"
export INSTALL_RECEIPT="${INSTALL_PREFIX}/INSTALL_RECEIPT.txt"

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
ARCHIVE_NAME="grpc-${VERSION}-msvc${TOOLSET}-x64-release.zip"

if [[ ! -d "${PREBUILT_DIR}" ]]; then
    echo "  [!!] Prebuilt directory not found: ${PREBUILT_DIR}"
    echo "       Ensure the prebuilt submodule is initialized:"
    echo "         git submodule update --init prebuilt"
    exit 1
fi
if ! ls "${PREBUILT_DIR}/${ARCHIVE_NAME}".part-* &>/dev/null \
        && [[ ! -f "${PREBUILT_DIR}/${ARCHIVE_NAME}" ]]; then
    echo "  [!!] Prebuilt package not found: ${ARCHIVE_NAME} in ${PREBUILT_DIR}"
    echo "       Available packages:"
    ls "${PREBUILT_DIR}" 2>/dev/null | sed 's/^/         /'
    echo "       Ensure the prebuilt submodule is initialized:"
    echo "         git submodule update --init prebuilt"
    exit 1
fi

# ---------------------------------------------------------------------------
# Best-effort part integrity check against manifest.json
# ---------------------------------------------------------------------------
MANIFEST="${PREBUILT_DIR}/manifest.json"
if [[ -f "${MANIFEST}" ]] && command -v python3 &>/dev/null && command -v sha256sum &>/dev/null; then
    im_progress_start "Verifying package integrity"
    if ! python3 - "${MANIFEST}" "${PREBUILT_DIR}" "${TOOLSET}" <<'PY'
import hashlib, json, os, sys
manifest, pdir, ts = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(manifest))
pv = d.get("platforms", {}).get(f"windows-msvc{ts}")
if not pv or not pv.get("part_sha256"):
    sys.exit(0)  # nothing to verify -> not fatal
def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(65536), b""):
            h.update(c)
    return h.hexdigest()
for part, want in pv["part_sha256"].items():
    fp = os.path.join(pdir, part)
    if not os.path.isfile(fp):
        print(f"missing part {part}", file=sys.stderr); sys.exit(3)
    if sha(fp) != want:
        print(f"checksum mismatch {part}", file=sys.stderr); sys.exit(3)
PY
    then
        im_progress_stop "Integrity check FAILED"
        echo "  [!!] Prebuilt parts failed checksum verification. Aborting." >&2
        exit 1
    fi
    im_progress_stop "Integrity verified"
fi

# ---------------------------------------------------------------------------
# Reassemble parts into a temporary archive (do NOT pollute the submodule)
# ---------------------------------------------------------------------------
INSTALL_PREFIX="$(cygpath -u -- "${INSTALL_PREFIX}" 2>/dev/null || echo "${INSTALL_PREFIX}")"
export INSTALL_PREFIX
export INSTALL_BIN_DIR="${INSTALL_PREFIX}/bin"
export INSTALL_RECEIPT="${INSTALL_PREFIX}/INSTALL_RECEIPT.txt"
mkdir -p "${INSTALL_PREFIX}"

TMP_ARCHIVE="${INSTALL_PREFIX}/.${ARCHIVE_NAME}"
if [[ -f "${PREBUILT_DIR}/${ARCHIVE_NAME}" ]]; then
    cp -f "${PREBUILT_DIR}/${ARCHIVE_NAME}" "${TMP_ARCHIVE}"
else
    im_progress_start "Reassembling ${ARCHIVE_NAME}"
    cat "${PREBUILT_DIR}/${ARCHIVE_NAME}".part-* > "${TMP_ARCHIVE}"
    im_progress_stop "Reassembled"
fi

# ---------------------------------------------------------------------------
# Extract
# ---------------------------------------------------------------------------
im_progress_start "Extracting to ${INSTALL_PREFIX}"
if command -v unzip &>/dev/null; then
    unzip -qo "${TMP_ARCHIVE}" -d "${INSTALL_PREFIX}"
else
    powershell.exe -NoProfile -NonInteractive -Command \
        "Expand-Archive -Force -Path '$(cygpath -w "${TMP_ARCHIVE}")' -DestinationPath '$(cygpath -w "${INSTALL_PREFIX}")'"
fi
rm -f "${TMP_ARCHIVE}"
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
echo "  Toolset : v${TOOLSET}  (${VS_LABEL})"
echo "  The package ships activate.ps1 + grpc-toolchain.cmake at:"
echo "    ${INSTALL_PREFIX}"
echo ""
echo "  To build your own gRPC app against it, from a Developer PowerShell:"
echo "    . \"${INSTALL_PREFIX}/activate.ps1\""
echo "  or run the environment check helper:"
echo "    powershell -File \"${SCRIPT_DIR}/Check-Environment.ps1\""
echo ""
echo "  Restart your shell or run:"
echo "    source \"${ENV_FILE}\""
echo ""
