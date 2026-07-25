#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# tools/frameworks/grpc/setup.sh
#
# Installs a prebuilt gRPC package from the prebuilt submodule.
#
# Windows: a maintainer build (Release or Debug), vendored per MSVC toolset.
# Because the static libraries are ABI-locked to the toolset they were built
# with, one package is shipped per Visual Studio version and configuration:
#
#   --toolset v142   MSVC v142   Visual Studio 2019
#   --toolset v143   MSVC v143   Visual Studio 2022   (default)
#   --toolset v145   MSVC v145   Visual Studio 2026
#   --config  release|debug      (default: release)
#
# Linux: a RHEL/Rocky 8/9/10 (x86_64) build with a statically linked C++ runtime, so the
# single package runs on RHEL/Rocky 8, 9 and 10 (and ABI-compatible rebuilds) with no
# gcc-toolset runtime installed:
#
#   --platform linux
#
# Each Windows package installs into its own sibling directory
# (<prefix>/grpc-<version>-msvc<NNN>-<config>) so multiple toolsets and configs
# can coexist; Linux installs into <prefix>/grpc-<version>-linux.
#
# USAGE (called by devkit-ui or install-cli.sh):
#   bash tools/frameworks/grpc/setup.sh [--toolset v143] [--config release] [--rebuild]
#   bash tools/frameworks/grpc/setup.sh --platform linux [--rebuild]
#
# Reads VERSION from devkit.json alongside this script.
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
# Parse args
# ---------------------------------------------------------------------------
TOOLSET="v143"          # default: Visual Studio 2022
CONFIG="release"        # default: release
PLATFORM=""             # empty -> derive from host OS
REBUILD=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --toolset)   TOOLSET="$2"; shift 2 ;;
        --toolset=*) TOOLSET="${1#*=}"; shift ;;
        --config)    CONFIG="$2"; shift 2 ;;
        --config=*)  CONFIG="${1#*=}"; shift ;;
        --platform)  PLATFORM="$2"; shift 2 ;;
        --platform=*) PLATFORM="${1#*=}"; shift ;;
        --rebuild)   REBUILD=true; shift ;;
        # Back-compat: install-cli historically passed "--version X"; ignore it,
        # the version is authoritative in devkit.json.
        --version) shift 2 ;;
        *) shift ;;
    esac
done

# Target platform: explicit --platform wins, else derive from host OS.
# Anything that is not Windows collapses to the single Linux package.
if [[ -z "${PLATFORM}" ]]; then
    PLATFORM="$(_im_os)"
fi
[[ "${PLATFORM}" != "windows" ]] && PLATFORM="linux"

# ---------------------------------------------------------------------------
# Shared helper: verify every part of <platform_key> in <manifest> against its
# recorded SHA256. Returns non-zero on any missing/mismatched part. Best-effort:
# a manifest without part_sha256 for the key is treated as "nothing to verify".
# ---------------------------------------------------------------------------
_grpc_verify_parts() {
    local manifest="$1" pdir="$2" platform_key="$3"
    [[ -f "${manifest}" ]] || return 0
    command -v python3 &>/dev/null || return 0
    python3 - "${manifest}" "${pdir}" "${platform_key}" <<'PY'
import hashlib, json, os, sys
manifest, pdir, key = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(manifest))
pv = d.get("platforms", {}).get(key)
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
}

# =============================================================================
# LINUX branch — RHEL/Rocky 8/9/10 static-runtime tarball
# =============================================================================
if [[ "${PLATFORM}" == "linux" ]]; then
    TOOL_NAME="grpc-${VERSION}-linux"
    ARCHIVE_NAME="grpc-${VERSION}-linux-x86_64.tar.gz"
    PREBUILT_DIR="${REPO_ROOT}/prebuilt/frameworks/grpc/linux/${VERSION}"
    PLATFORM_KEY="linux-x86_64"

    install_mode_init "${TOOL_NAME}" "${VERSION}" "$@"
    install_log_capture_start
    echo "  Platform: Linux x86_64 (RHEL/Rocky 8/9/10)"

    # Deterministic per-package install dir (normalise the two entry points:
    # CLI passes TOOL_NAME; devkit-ui overrides the prefix to <base>/grpc).
    case "$(basename "${INSTALL_PREFIX}")" in
        grpc|grpc-*) INSTALL_PREFIX="$(dirname "${INSTALL_PREFIX}")/${TOOL_NAME}" ;;
        *)           INSTALL_PREFIX="${INSTALL_PREFIX}/${TOOL_NAME}" ;;
    esac
    export INSTALL_PREFIX
    export INSTALL_BIN_DIR="${INSTALL_PREFIX}/bin"
    export INSTALL_RECEIPT="${INSTALL_PREFIX}/INSTALL_RECEIPT.txt"

    if [[ "${REBUILD}" == "false" && -f "${INSTALL_RECEIPT}" ]]; then
        echo "  [OK] ${TOOL_NAME} already installed at ${INSTALL_PREFIX}"
        echo "       Use --rebuild to force reinstall."
        exit 0
    fi

    if [[ ! -d "${PREBUILT_DIR}" ]]; then
        echo "  [!!] Prebuilt directory not found: ${PREBUILT_DIR}"
        echo "       git submodule update --init prebuilt"
        exit 1
    fi
    if ! ls "${PREBUILT_DIR}/${ARCHIVE_NAME}".part-* &>/dev/null \
            && [[ ! -f "${PREBUILT_DIR}/${ARCHIVE_NAME}" ]]; then
        echo "  [!!] Prebuilt package not found: ${ARCHIVE_NAME} in ${PREBUILT_DIR}"
        ls "${PREBUILT_DIR}" 2>/dev/null | sed 's/^/         /'
        exit 1
    fi

    MANIFEST="${PREBUILT_DIR}/manifest.json"
    if command -v sha256sum &>/dev/null; then
        im_progress_start "Verifying package integrity"
        if ! _grpc_verify_parts "${MANIFEST}" "${PREBUILT_DIR}" "${PLATFORM_KEY}"; then
            im_progress_stop "Integrity check FAILED"
            echo "  [!!] Prebuilt parts failed checksum verification. Aborting." >&2
            exit 1
        fi
        im_progress_stop "Integrity verified"
    fi

    mkdir -p "${INSTALL_PREFIX}"
    TMP_ARCHIVE="${INSTALL_PREFIX}/.${ARCHIVE_NAME}"
    if [[ -f "${PREBUILT_DIR}/${ARCHIVE_NAME}" ]]; then
        cp -f "${PREBUILT_DIR}/${ARCHIVE_NAME}" "${TMP_ARCHIVE}"
    else
        im_progress_start "Reassembling ${ARCHIVE_NAME}"
        cat "${PREBUILT_DIR}/${ARCHIVE_NAME}".part-* > "${TMP_ARCHIVE}"
        im_progress_stop "Reassembled"
    fi

    im_progress_start "Extracting to ${INSTALL_PREFIX}"
    tar -xzf "${TMP_ARCHIVE}" -C "${INSTALL_PREFIX}"
    rm -f "${TMP_ARCHIVE}"
    im_progress_stop "Extraction complete"

    ENV_FILE="$(install_env_register "${INSTALL_BIN_DIR}")"
    install_receipt_write "success" \
        "grpc_cpp_plugin:${INSTALL_BIN_DIR}/grpc_cpp_plugin" \
        "protoc:${INSTALL_BIN_DIR}/protoc"
    install_mode_print_footer "success" \
        "grpc_cpp_plugin:${INSTALL_BIN_DIR}/grpc_cpp_plugin" \
        "protoc:${INSTALL_BIN_DIR}/protoc"

    echo ""
    echo "  Platform: Linux x86_64 (RHEL/Rocky 8/9/10)"
    echo "  The package ships activate.sh + grpc-toolchain.cmake at:"
    echo "    ${INSTALL_PREFIX}"
    echo ""
    echo "  To build your own gRPC app against it:"
    echo "    source \"${INSTALL_PREFIX}/activate.sh\""
    echo ""
    echo "  Restart your shell or run:"
    echo "    source \"${ENV_FILE}\""
    echo ""
    exit 0
fi

# =============================================================================
# WINDOWS branch — per-toolset, per-config MSVC package
# =============================================================================
TOOLSET="${TOOLSET#v}"   # normalise "v143" -> "143"

case "${TOOLSET}" in
    142) VS_LABEL="Visual Studio 2019" ;;
    143) VS_LABEL="Visual Studio 2022" ;;
    145) VS_LABEL="Visual Studio 2026" ;;
    *)
        echo "  [!!] Unknown toolset 'v${TOOLSET}'. Valid: v142, v143, v145." >&2
        exit 1 ;;
esac

case "${CONFIG}" in
    release|debug) ;;
    *)
        echo "  [!!] Unknown config '${CONFIG}'. Valid: release, debug." >&2
        exit 1 ;;
esac

TOOL_NAME="grpc-${VERSION}-msvc${TOOLSET}-${CONFIG}"

# ---------------------------------------------------------------------------
# Windows only (host guard — the MSVC packages are Windows binaries)
# ---------------------------------------------------------------------------
if [[ "$(_im_os)" != "windows" ]]; then
    echo "  [--] gRPC MSVC packages are Windows only. For Linux use --platform linux."
    exit 0
fi

# ---------------------------------------------------------------------------
# install-mode setup
# ---------------------------------------------------------------------------
install_mode_init "${TOOL_NAME}" "${VERSION}" "$@"
install_log_capture_start

echo "  Toolset : v${TOOLSET}  (${VS_LABEL})   Config: ${CONFIG}"

# ---------------------------------------------------------------------------
# Deterministic per-package install dir so multiple toolsets/configs coexist and
# status.sh can report each one. This normalises the two entry points:
#   - CLI passes TOOL_NAME -> prefix already ends in grpc-<ver>-msvc<NNN>-<cfg>
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
ARCHIVE_NAME="grpc-${VERSION}-msvc${TOOLSET}-x64-${CONFIG}.zip"
PLATFORM_KEY="windows-msvc${TOOLSET}-${CONFIG}"

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
    if ! _grpc_verify_parts "${MANIFEST}" "${PREBUILT_DIR}" "${PLATFORM_KEY}"; then
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
echo "  Toolset : v${TOOLSET}  (${VS_LABEL})   Config: ${CONFIG}"
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
