#!/usr/bin/env bash
set -euo pipefail

TOOL="vscode"
VERSION="1.127.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/../../lib/devkit-install.sh"

PREBUILT_DIR="${PREBUILT_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/prebuilt}"
PREFIX="${INSTALL_PREFIX:-$(devkit_default_prefix vscode)}"
devkit_parse_args "$@"

PARTS_DIR="$PREBUILT_DIR/dev-tools/vscode/${VERSION}"

if [[ "$DEVKIT_PLATFORM" == "windows" ]]; then
    echo "==> Installing Visual Studio Code ${VERSION} (windows) to ${PREFIX}"

    INSTALLER=$(devkit_find_file "$PARTS_DIR" windows)
    if [[ -z "$INSTALLER" ]]; then
        echo "ERROR: No VS Code installer found in $PARTS_DIR" >&2; exit 1
    fi

    # VS Code uses Inno Setup; /MERGETASKS=!runcode suppresses launch-on-finish.
    # /DIR must be quoted: the default prefix is under %LOCALAPPDATA%, so a user
    # whose profile path contains a space (C:\Users\John Smith\...) would word-split
    # an unquoted /DIR when the lib interpolates the flags into the cmd.exe line.
    devkit_install_exe "$INSTALLER" "$PREFIX" \
        "/VERYSILENT" "/NORESTART" "/MERGETASKS=!runcode" "/DIR=\"$(cygpath -w "$PREFIX")\""

    devkit_write_receipt "$TOOL" "$VERSION" windows "$PREFIX"
    echo "==> Visual Studio Code ${VERSION} installed to ${PREFIX}"

elif [[ "$DEVKIT_PLATFORM" == "linux" ]]; then
    echo "==> Installing Visual Studio Code ${VERSION} (linux)"

    INSTALLER=$(devkit_find_file "$PARTS_DIR" linux)
    if [[ -z "$INSTALLER" ]]; then
        echo "ERROR: No VS Code package found in $PARTS_DIR" >&2; exit 1
    fi

    case "${INSTALLER,,}" in
        *.rpm)
            if [[ "$(id -u)" == "0" ]]; then
                echo "==> Installing RPM (root): $INSTALLER"
                rpm -ivh --force "$INSTALLER"
                INSTALL_ROOT="/usr"
            else
                # Non-root: extract RPM contents into user prefix
                echo "==> Non-root install: extracting RPM to ${PREFIX}"
                if ! command -v rpm2cpio &>/dev/null || ! command -v cpio &>/dev/null; then
                    echo "ERROR: rpm2cpio and cpio are required for a non-root VS Code install." >&2
                    echo "       Install them (RHEL/Rocky: 'dnf install rpm cpio') and retry." >&2
                    exit 1
                fi
                mkdir -p "$PREFIX"
                cd "$PREFIX"
                # A payload that fails mid-extraction leaves a partial tree that
                # would masquerade as a broken install; scrub it so the failure is
                # unambiguous and re-runnable. Distinguish this from a missing tool.
                if ! rpm2cpio "$INSTALLER" | cpio -idm --quiet 2>/dev/null; then
                    echo "ERROR: VS Code RPM payload could not be extracted (corrupt or rejected)." >&2
                    echo "       Removing the partial install at ${PREFIX}." >&2
                    cd /; rm -rf "$PREFIX"
                    exit 1
                fi
                INSTALL_ROOT="$PREFIX"
                # Wire up a bin/code shim pointing at the extracted binary.
                CODE_BIN="$PREFIX/usr/share/code/bin/code"
                if [[ -f "$CODE_BIN" ]]; then
                    chmod +x "$CODE_BIN"
                    mkdir -p "$PREFIX/bin"
                    ln -sf "../usr/share/code/bin/code" "$PREFIX/bin/code"
                    echo "    Symlink: $PREFIX/bin/code -> $CODE_BIN"
                fi
            fi
            ;;
        *.tar.gz)
            echo "==> Extracting tarball to ${PREFIX}"
            devkit_extract "$INSTALLER" "$PREFIX" 1
            INSTALL_ROOT="$PREFIX"
            ;;
        *)
            echo "ERROR: Unsupported installer format: $INSTALLER" >&2; exit 1
            ;;
    esac

    devkit_write_receipt "$TOOL" "$VERSION" linux "${INSTALL_ROOT}"
    echo "==> Visual Studio Code ${VERSION} installed"
    echo "    Run: code --version"

else
    echo "ERROR: Unsupported platform: $DEVKIT_PLATFORM" >&2; exit 1
fi
