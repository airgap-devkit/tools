#!/usr/bin/env bash
set -euo pipefail

TOOL="vscode"
VERSION="1.99.3"
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

    # VS Code uses Inno Setup; /MERGETASKS=!runcode suppresses launch-on-finish
    devkit_install_exe "$INSTALLER" "$PREFIX" \
        "/VERYSILENT" "/NORESTART" "/MERGETASKS=!runcode" "/DIR=$(cygpath -w "$PREFIX")"

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
                mkdir -p "$PREFIX"
                cd "$PREFIX"
                rpm2cpio "$INSTALLER" | cpio -idm --quiet 2>/dev/null || \
                    { echo "ERROR: rpm2cpio failed — ensure it is installed (dnf install rpm2cpio)" >&2; exit 1; }
                INSTALL_ROOT="$PREFIX"
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
