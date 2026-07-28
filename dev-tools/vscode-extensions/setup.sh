#!/usr/bin/env bash
set -euo pipefail

TOOL="vscode-extensions"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/devkit-install.sh"
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

PLATFORM="$DEVKIT_PLATFORM"
PREFIX="${INSTALL_PREFIX:-$(devkit_default_prefix "$TOOL")}"
while [[ $# -gt 0 ]]; do
    case "$1" in --prefix) PREFIX="$2"; shift 2 ;; *) shift ;; esac
done

echo "==> Installing VS Code Extensions (offline)"

# Fail-closed integrity gate: every VSIX (whole or split) must match the sha256
# recorded in the bundle manifest before it is installed. Without this the
# extensions — including a split 120 MB cpptools payload — would install with no
# verification at all.
MANIFEST="$VSIX_DIR/manifest.json"
if [[ ! -f "$MANIFEST" ]]; then
    echo "ERROR: integrity: no manifest.json in ${VSIX_DIR}; refusing to install extensions unverified." >&2
    exit 1
fi

# Reassemble any split VSIX archives (*.vsix.part-aa, *.vsix.part-ab, …)
# into a temp directory before installing. Split parts are used for files
# that exceed GitHub's 100 MB per-file limit. Each part is verified against the
# manifest before it is concatenated, so a tampered part never reaches 'code'.
EXTRA_VSIX_DIR=""
mapfile -t SPLIT_BASES < <(
    find "$VSIX_DIR" -maxdepth 1 -name "*.vsix.part-aa" 2>/dev/null | sort | sed 's/\.part-aa$//'
)
if [[ ${#SPLIT_BASES[@]} -gt 0 ]]; then
    EXTRA_VSIX_DIR="$(mktemp -d)"
    trap 'rm -rf "$EXTRA_VSIX_DIR"' EXIT
    for base in "${SPLIT_BASES[@]}"; do
        name="$(basename "$base")"
        devkit_verify_staged "$VSIX_DIR" "$name"      # fail-closed: aborts on mismatch
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

# Verify every shipped whole-file VSIX against the manifest before installing any
# of them (assembled split files came from parts already verified above). A bad
# hash aborts the whole bundle rather than installing part of it.
for vsix in "${VSIX_FILES[@]}"; do
    [[ "$(dirname "$vsix")" == "$VSIX_DIR" ]] || continue   # skip assembled temp files
    _vname="$(basename "$vsix")"
    _vhash="$(devkit_manifest_sha256 "$MANIFEST" "$_vname")"
    if [[ -z "$_vhash" ]]; then
        echo "ERROR: integrity: no sha256 for ${_vname} in ${MANIFEST}; refusing to install unverified." >&2
        exit 1
    fi
    devkit_verify_sha256 "$vsix" "$_vhash"
done
echo ""

INSTALLED=()
FAILED=()
DECOMP_DIR=""

_cleanup_decomp() { [[ -n "$DECOMP_DIR" ]] && rm -rf "$DECOMP_DIR"; }
trap '_cleanup_decomp' EXIT

for vsix in "${VSIX_FILES[@]}"; do
    name="$(basename "$vsix")"
    printf "  [....] %s\n" "$name"

    # .vsix files are ZIP archives. If the first two bytes are the gzip magic
    # (1f 8b), the file was compressed a second time before being stored in
    # prebuilt/. Decompress to a temp file so 'code' receives a valid ZIP.
    install_from="$vsix"
    magic="$(od -An -N2 -tx1 "$vsix" 2>/dev/null | tr -d ' \n')"
    if [[ "$magic" == "1f8b" ]]; then
        [[ -z "$DECOMP_DIR" ]] && DECOMP_DIR="$(mktemp -d)"
        tmp_vsix="$DECOMP_DIR/$name"
        if ! gunzip -c "$vsix" > "$tmp_vsix" 2>/dev/null; then
            printf "  [!!]  FAILED (gunzip error): %s\n" "$name" >&2
            FAILED+=("$name")
            continue
        fi
        install_from="$tmp_vsix"
    fi

    if code --install-extension "$install_from" --force 2>/dev/null; then
        printf "  [OK]  %s\n" "$name"
        INSTALLED+=("$name")
    else
        printf "  [!!]  FAILED: %s\n" "$name" >&2
        FAILED+=("$name")
    fi
done

echo ""
# Only attest success when at least one extension actually installed. Writing a
# receipt unconditionally (combined with a "code --version" check) is what made
# the bundle report installed=true with zero extensions present; the bundle's
# real state is the per-package status (/api/tool/<id>/packages/status).
if [[ ${#INSTALLED[@]} -gt 0 ]]; then
    devkit_write_receipt "$TOOL" "various" "$DEVKIT_PLATFORM" "$PREFIX" \
        "installed_count=${#INSTALLED[@]}"
else
    echo "  [!!] No extensions installed — not writing a success receipt." >&2
fi

echo "==> VS Code Extensions: ${#INSTALLED[@]} installed, ${#FAILED[@]} failed."
if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo "    Failed: ${FAILED[*]}" >&2
    exit 1
fi
