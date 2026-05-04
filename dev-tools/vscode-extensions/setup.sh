#!/usr/bin/env bash
set -euo pipefail

TOOL="vscode-extensions"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"
# Look for .vsix files first in the dedicated extensions subdir, then fall back
# to the vscode prebuilt dir (which is where they land when prebuilt/ is laid
# out with a flat vscode/ directory rather than a vscode-extensions/ sibling).
VSIX_DIR="$PREBUILT_DIR/dev-tools/vscode-extensions"
if [[ ! -d "$VSIX_DIR" ]]; then
    VSIX_DIR="$PREBUILT_DIR/dev-tools/vscode/extensions"
fi
if [[ ! -d "$VSIX_DIR" ]]; then
    VSIX_DIR="$PREBUILT_DIR/dev-tools/vscode"
fi

if [[ "${AIRGAP_OS:-}" == "windows" || "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "${OS:-}" == "Windows_NT" ]]; then
    PLATFORM="windows"
    DEFAULT_PREFIX="${LOCALAPPDATA:-$HOME/AppData/Local}/airgap-cpp-devkit/vscode-extensions"
else
    PLATFORM="linux"
    if [[ "$(id -u)" == "0" ]]; then
        DEFAULT_PREFIX="/opt/airgap-cpp-devkit/vscode-extensions"
    else
        DEFAULT_PREFIX="${HOME}/.local/share/airgap-cpp-devkit/vscode-extensions"
    fi
fi
PREFIX="${INSTALL_PREFIX:-$DEFAULT_PREFIX}"
while [[ $# -gt 0 ]]; do
    case "$1" in --prefix) PREFIX="$2"; shift 2 ;; *) shift ;; esac
done

echo "==> Installing VS Code Extensions (offline)"

# Reassemble any split VSIX archives (*.vsix.part-aa, *.vsix.part-ab, …)
# into a temp directory before installing. Split parts are used for files
# that exceed GitHub's 100 MB per-file limit.
EXTRA_VSIX_DIR=""
mapfile -t SPLIT_BASES < <(
    find "$VSIX_DIR" -maxdepth 1 -name "*.vsix.part-aa" 2>/dev/null | sort | sed 's/\.part-aa$//'
)
if [[ ${#SPLIT_BASES[@]} -gt 0 ]]; then
    EXTRA_VSIX_DIR="$(mktemp -d)"
    trap 'rm -rf "$EXTRA_VSIX_DIR"' EXIT
    for base in "${SPLIT_BASES[@]}"; do
        name="$(basename "$base")"
        parts=("${base}.part-"*)
        echo "    Assembling ${name} from ${#parts[@]} parts..."
        cat "${parts[@]}" > "$EXTRA_VSIX_DIR/${name}"
    done
fi

if ! command -v code &>/dev/null; then
    echo "ERROR: 'code' not found in PATH." >&2
    echo "       Install VS Code and ensure the 'code' command is available on PATH." >&2
    exit 1
fi

if [[ ! -d "$VSIX_DIR" ]]; then
    echo "ERROR: VS Code extensions directory not found: $VSIX_DIR" >&2
    echo "       Ensure the prebuilt submodule is initialised:" >&2
    echo "       git submodule update --init --recursive" >&2
    exit 1
fi

mapfile -t VSIX_FILES < <(
    find "$VSIX_DIR" -maxdepth 1 -name "*.vsix" 2>/dev/null
    [[ -n "$EXTRA_VSIX_DIR" ]] && find "$EXTRA_VSIX_DIR" -maxdepth 1 -name "*.vsix" 2>/dev/null
    true
)
# Sort deduplicated list (assembled files take precedence over any stray originals)
mapfile -t VSIX_FILES < <(printf '%s\n' "${VSIX_FILES[@]}" | sort -u)
if [[ ${#VSIX_FILES[@]} -eq 0 ]]; then
    echo "ERROR: No .vsix files found in ${VSIX_DIR}" >&2
    exit 1
fi

echo "    Found ${#VSIX_FILES[@]} extension(s) in ${VSIX_DIR}"
echo ""

INSTALLED=()
FAILED=()

for vsix in "${VSIX_FILES[@]}"; do
    name="$(basename "$vsix")"
    printf "  [....] %s\n" "$name"
    if code --install-extension "$vsix" --force 2>/dev/null; then
        printf "  [OK]  %s\n" "$name"
        INSTALLED+=("$name")
    else
        printf "  [!!]  FAILED: %s\n" "$name" >&2
        FAILED+=("$name")
    fi
done

echo ""
mkdir -p "$PREFIX"
cat > "$PREFIX/INSTALL_RECEIPT.txt" << RECEIPT
tool=${TOOL}
version=various
platform=${PLATFORM}
install_prefix=${PREFIX}
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
installed_count=${#INSTALLED[@]}
RECEIPT

echo "==> VS Code Extensions: ${#INSTALLED[@]} installed, ${#FAILED[@]} failed."
if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo "    Failed: ${FAILED[*]}" >&2
    exit 1
fi
