#!/usr/bin/env bash
# tools/frameworks/conan-airgap/setup.sh
# Deploys the conan-airgap kit (repo-root conan-airgap/) to the install prefix so
# the offline-Conan seed/import scripts are available at a standard location, and
# checks that Conan itself is installed.
set -euo pipefail

TOOL="conan-airgap"
VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/devkit-install.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
KIT_SRC="${REPO_ROOT}/conan-airgap"

PREFIX="${INSTALL_PREFIX:-$(devkit_default_prefix "$TOOL")}"
while [[ $# -gt 0 ]]; do
    case "$1" in --prefix) PREFIX="$2"; shift 2 ;; *) shift ;; esac
done

echo "==> Deploying Conan Air-Gap Kit ${VERSION} to ${PREFIX}"

[[ -d "$KIT_SRC" ]] || { echo "ERROR: kit source not found: ${KIT_SRC}" >&2; exit 1; }

mkdir -p "$PREFIX"
cp -r "$KIT_SRC"/. "$PREFIX"/
rm -rf "$PREFIX/dist"   # never carry generated bundles into an install

# Conan is required to use the kit — inform (do not hard-fail the deploy).
if command -v conan &>/dev/null; then
    echo "    [OK] Conan present: $(conan --version 2>/dev/null | grep -oE '[0-9.]+$')"
else
    echo "    [!!] Conan not on PATH. Install it first: bash tools/dev-tools/conan/setup.sh" >&2
fi

devkit_write_receipt "$TOOL" "$VERSION" "$DEVKIT_PLATFORM" "$PREFIX"

echo "==> Conan Air-Gap Kit deployed."
echo "    Seed (connected host) : bash ${PREFIX}/scripts/seed-export.sh"
echo "    Import (air-gapped)    : bash ${PREFIX}/scripts/import-airgap.sh --bundle <file> --network offline"
echo "    Docs                   : ${PREFIX}/README.md"
