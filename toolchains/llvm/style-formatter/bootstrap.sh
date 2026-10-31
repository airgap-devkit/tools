#!/usr/bin/env bash
# Installs a git pre-commit hook that enforces LLVM C++ style via clang-format.
# Run from inside any git repository you want to enforce style on.
# Requires: clang-format (install LLVM first via tools/toolchains/llvm/setup.sh)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Find git root of the target repo (default: current working directory)
TARGET_REPO="${TARGET_REPO:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
HOOK_DIR="$TARGET_REPO/.git/hooks"
HOOK_FILE="$HOOK_DIR/pre-commit"

echo "==> Installing LLVM style formatter pre-commit hook"
echo "    Target repo: ${TARGET_REPO}"

# Verify clang-format is available
if ! command -v clang-format &>/dev/null; then
    echo "ERROR: clang-format not found in PATH." >&2
    echo "       Install LLVM first: bash tools/toolchains/llvm/setup.sh" >&2
    exit 1
fi

CLANG_FORMAT_VERSION=$(clang-format --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
echo "    clang-format version: ${CLANG_FORMAT_VERSION}"

# Never install the hook / .clang-format into the devkit's OWN checkout. When the
# CLI installer runs this, the git root IS the devkit repo, so we would otherwise
# leave an untracked .clang-format and a pre-commit hook behind (git status dirty).
# The formatter is meant for the USER's project — skip cleanly here, but still drop
# a receipt so the tool is accounted for.
if [[ -f "$TARGET_REPO/scripts/internal/install-cli.sh" && -f "$TARGET_REPO/tools/lib/devkit-install.sh" ]]; then
    echo "    [--] Target is the airgap-devkit checkout itself — not installing the hook here." >&2
    echo "         Re-run inside your own project's git repo to enable the clang-format pre-commit hook." >&2
    _receipt_root="${INSTALL_PREFIX_OVERRIDE:-${HOME}/.local/share/airgap-cpp-devkit}"
    _receipt_dir="${_receipt_root}/clang-style-formatter"
    mkdir -p "$_receipt_dir" 2>/dev/null || true
    cat > "$_receipt_dir/INSTALL_RECEIPT.txt" 2>/dev/null <<RECEIPT || true
tool=clang-style-formatter
version=${CLANG_FORMAT_VERSION}
platform=both
install_prefix=${_receipt_dir}
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
note=hook-skipped-in-devkit-checkout
RECEIPT
    exit 0
fi

if [[ ! -d "$HOOK_DIR" ]]; then
    # The pre-commit hook only makes sense inside a git working tree. When the
    # devkit is installed outside one (e.g. CI containers, fresh servers), skip
    # gracefully rather than failing the whole install.
    echo "    [--] Not a git repository (no .git/hooks at $TARGET_REPO) — skipping hook install." >&2
    echo "         Re-run this inside your project's git repo to install the clang-format hook." >&2
    exit 0
fi

# Backup existing hook if present
if [[ -f "$HOOK_FILE" ]]; then
    cp "$HOOK_FILE" "${HOOK_FILE}.bak"
    echo "    Existing hook backed up to ${HOOK_FILE}.bak"
fi

cat > "$HOOK_FILE" << 'HOOK'
#!/usr/bin/env bash
# LLVM style pre-commit hook — installed by airgap-devkit style-formatter
set -euo pipefail

CLANG_FORMAT=$(command -v clang-format 2>/dev/null || echo "")
if [[ -z "$CLANG_FORMAT" ]]; then
    echo "WARNING: clang-format not found — skipping style check." >&2
    exit 0
fi

FILES=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.(cpp|cc|cxx|c|h|hpp|hxx)$' || true)
if [[ -z "$FILES" ]]; then
    exit 0
fi

FAILED=0
while IFS= read -r file; do
    if ! "$CLANG_FORMAT" --dry-run --Werror --style=LLVM "$file" 2>/dev/null; then
        echo "  Style violation: $file"
        echo "  Fix with: clang-format --style=LLVM -i \"$file\""
        FAILED=1
    fi
done <<< "$FILES"

if [[ "$FAILED" -eq 1 ]]; then
    echo ""
    echo "Commit blocked: clang-format style violations found."
    echo "Run: git diff --cached --name-only | grep -E '\\.(cpp|h)$' | xargs clang-format --style=LLVM -i"
    exit 1
fi
HOOK

chmod +x "$HOOK_FILE"

# Write a .clang-format file at repo root if one doesn't exist
CLANG_FORMAT_CFG="$TARGET_REPO/.clang-format"
if [[ ! -f "$CLANG_FORMAT_CFG" ]]; then
    cat > "$CLANG_FORMAT_CFG" << 'CFG'
BasedOnStyle: LLVM
IndentWidth: 4
ColumnLimit: 120
CFG
    echo "    Created ${CLANG_FORMAT_CFG} (BasedOnStyle: LLVM, indent 4, column 120)"
fi

# Drop the install receipt under the devkit prefix (receipt_name
# "clang-style-formatter") so the dashboard and smoke tests can discover it —
# and so we don't leave an INSTALL_RECEIPT.txt sitting in the user's own repo.
# INSTALL_PREFIX_OVERRIDE is exported by install-cli.sh; fall back to the
# standard per-user prefix when the bootstrap is run standalone.
_receipt_root="${INSTALL_PREFIX_OVERRIDE:-${HOME}/.local/share/airgap-cpp-devkit}"
_receipt_dir="${_receipt_root}/clang-style-formatter"
mkdir -p "$_receipt_dir" 2>/dev/null || true
cat > "$_receipt_dir/INSTALL_RECEIPT.txt" << RECEIPT 2>/dev/null || true
tool=clang-style-formatter
version=${CLANG_FORMAT_VERSION}
platform=both
install_prefix=${_receipt_dir}
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
hook=${HOOK_FILE}
RECEIPT

echo "==> Style formatter hook installed at ${HOOK_FILE}"
echo "    Every commit on .cpp/.h files will be checked against LLVM style."
