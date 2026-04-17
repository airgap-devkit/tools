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

if [[ ! -d "$HOOK_DIR" ]]; then
    echo "ERROR: Not a git repository (no .git/hooks at $TARGET_REPO)" >&2
    exit 1
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

cat > "$TARGET_REPO/INSTALL_RECEIPT.txt" << RECEIPT 2>/dev/null || true
tool=clang-style-formatter
version=${CLANG_FORMAT_VERSION}
platform=both
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RECEIPT

echo "==> Style formatter hook installed at ${HOOK_FILE}"
echo "    Every commit on .cpp/.h files will be checked against LLVM style."
