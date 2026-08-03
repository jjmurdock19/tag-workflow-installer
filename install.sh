#!/usr/bin/env bash
# One-stop installer for the TAG workflow (Aspen + TAG Downloader + tag-setup)
# on Linux. Meant to be run either directly from a checked-out copy of this
# repo, or piped straight from GitHub:
#
#   curl -fsSL https://raw.githubusercontent.com/jjmurdock19/tag-workflow-installer/main/install.sh | bash
#
# Requires no admin/sudo privileges. Everything is installed under a
# user-owned directory (default: ~/.tag, override with --install-dir or the
# TAG_HOME env var).
set -euo pipefail

REPO_URL="${TAG_INSTALLER_REPO_URL:-https://github.com/jjmurdock19/tag-workflow-installer}"
DEFAULT_TAG_HOME="$HOME/.tag"

INSTALL_DIR=""
ASSUME_YES=0
WANT_SHORTCUTS=""   # "" = ask, "0"/"1" = decided

usage() {
    cat <<EOF
Usage: install.sh [options]

  -d, --install-dir DIR   Install everything under DIR (default: $DEFAULT_TAG_HOME)
  -y, --yes                Don't prompt; accept defaults (install dir, shortcuts on)
      --no-shortcuts        Skip creating desktop / start menu shortcuts
      --shortcuts           Create desktop / start menu shortcuts (skip the prompt)
  -h, --help                Show this help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -d|--install-dir)
            INSTALL_DIR="$2"; shift 2 ;;
        --install-dir=*)
            INSTALL_DIR="${1#*=}"; shift ;;
        -y|--yes)
            ASSUME_YES=1; shift ;;
        --no-shortcuts)
            WANT_SHORTCUTS=0; shift ;;
        --shortcuts)
            WANT_SHORTCUTS=1; shift ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

if [ "$(uname -s)" != "Linux" ]; then
    echo "This script (install.sh) is for Linux. For Windows, run install.ps1 instead:" >&2
    echo "  irm https://raw.githubusercontent.com/jjmurdock19/tag-workflow-installer/main/install.ps1 | iex" >&2
    exit 1
fi

echo "=== TAG workflow installer ==="
echo

# --- Install location -------------------------------------------------
if [ -z "$INSTALL_DIR" ]; then
    if [ "$ASSUME_YES" = "1" ]; then
        INSTALL_DIR="$DEFAULT_TAG_HOME"
    else
        read -rp "Install location [$DEFAULT_TAG_HOME]: " reply
        INSTALL_DIR="${reply:-$DEFAULT_TAG_HOME}"
    fi
fi
# Expand ~ if the user typed it at the prompt.
INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"
export TAG_HOME="$INSTALL_DIR"
mkdir -p "$TAG_HOME"
echo "Installing to: $TAG_HOME"
echo

# --- Shortcuts ----------------------------------------------------------
if [ -z "$WANT_SHORTCUTS" ]; then
    if [ "$ASSUME_YES" = "1" ]; then
        WANT_SHORTCUTS=1
    else
        read -rp "Create desktop + start menu shortcuts? [Y/n] " reply
        case "$reply" in
            [nN]*) WANT_SHORTCUTS=0 ;;
            *) WANT_SHORTCUTS=1 ;;
        esac
    fi
fi
if [ "$WANT_SHORTCUTS" = "1" ]; then
    export TAG_SKIP_SHORTCUTS=0
else
    export TAG_SKIP_SHORTCUTS=1
fi
echo

# --- Fetch this repo into a persistent, updatable checkout --------------
SRC_DIR="$TAG_HOME/src/tag-workflow-installer"
mkdir -p "$TAG_HOME/src"
if command -v git >/dev/null 2>&1; then
    if [ -d "$SRC_DIR/.git" ]; then
        echo "Updating installer scripts at $SRC_DIR..."
        git -C "$SRC_DIR" pull --ff-only
    else
        echo "Fetching installer scripts..."
        rm -rf "$SRC_DIR"
        git clone --depth 1 "$REPO_URL.git" "$SRC_DIR"
    fi
else
    echo "git isn't installed; falling back to a plain tarball download..."
    tmp_dir=$(mktemp -d)
    trap 'rm -rf "$tmp_dir"' EXIT
    curl -fsSL "$REPO_URL/archive/refs/heads/main.tar.gz" -o "$tmp_dir/repo.tar.gz"
    tar xzf "$tmp_dir/repo.tar.gz" -C "$tmp_dir"
    rm -rf "$SRC_DIR"
    mv "$tmp_dir"/tag-workflow-installer-* "$SRC_DIR"
fi
echo

# --- Install Aspen + TAG Downloader --------------------------------------
echo "--- Installing Aspen ---"
"$SRC_DIR/linux/install-aspen.sh"
echo

echo "--- Installing TAG Downloader ---"
"$SRC_DIR/linux/install-tag-downloader.sh"
echo

# --- tag-setup command + "TAG Workflow" shortcut -------------------------
echo "--- Setting up tag-setup ---"
mkdir -p "$TAG_HOME/bin"
install -m 0755 "$SRC_DIR/linux/tag-setup.sh" "$TAG_HOME/bin/tag-setup"
echo "  installed: $TAG_HOME/bin/tag-setup"

if [ "$WANT_SHORTCUTS" = "1" ]; then
    source "$SRC_DIR/linux/lib/shortcuts.sh"
    make_shortcut "TAG Workflow" \
        "$TAG_HOME/bin/tag-setup" \
        "utilities-terminal" \
        "$TAG_HOME/bin" \
        true \
        "Utility"
    refresh_app_menu
fi
echo

echo "=== Done ==="
echo "TAG_HOME: $TAG_HOME"
echo
echo "To start a new storm: $TAG_HOME/bin/tag-setup"
if [ "$WANT_SHORTCUTS" = "1" ]; then
    echo "Or use the 'TAG Workflow' shortcut on your Desktop / in your app launcher."
fi
echo
echo "Tip: add $TAG_HOME/bin to your PATH to just run 'tag-setup' from anywhere:"
echo '  echo '"'"'export PATH="$TAG_HOME/bin:$PATH"'"'"' >> ~/.bashrc'
