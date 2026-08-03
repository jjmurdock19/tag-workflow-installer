#!/usr/bin/env bash
# Clones/updates and builds TAG_Downloader from
# https://github.com/jjmurdock19/TAG_Downloader, then (re)creates the
# desktop + start menu launcher for the built binary.
#
# Standalone-runnable: defaults TAG_HOME to ~/.tag if not already exported.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/shortcuts.sh"

TAG_HOME="${TAG_HOME:-$HOME/.tag}"
REPO_URL="https://github.com/jjmurdock19/TAG_Downloader"
INSTALL_ROOT="$TAG_HOME/opt"
SRC_DIR="$INSTALL_ROOT/src/TAG_Downloader"
APP_DIR="$INSTALL_ROOT/TAG_Downloader"
VENV_DIR="$APP_DIR/venv"

mkdir -p "$INSTALL_ROOT/src"
if command -v git >/dev/null 2>&1; then
    if [ -d "$SRC_DIR/.git" ]; then
        echo "Updating existing checkout at $SRC_DIR..."
        git -C "$SRC_DIR" pull --ff-only
    else
        echo "Cloning $REPO_URL..."
        rm -rf "$SRC_DIR"
        git clone "$REPO_URL.git" "$SRC_DIR"
    fi
else
    echo "git isn't installed (install it with 'sudo dnf install -y git' for incremental updates)."
    echo "Falling back to a plain tarball download..."
    tmp_dir=$(mktemp -d)
    trap 'rm -rf "$tmp_dir"' EXIT
    curl -sL "$REPO_URL/archive/refs/heads/master.tar.gz" -o "$tmp_dir/repo.tar.gz"
    tar xzf "$tmp_dir/repo.tar.gz" -C "$tmp_dir"
    rm -rf "$SRC_DIR"
    mv "$tmp_dir"/TAG_Downloader-* "$SRC_DIR"
fi

echo "Setting up build virtualenv..."
mkdir -p "$APP_DIR"
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
fi
source "$VENV_DIR/bin/activate"
pip install --quiet --upgrade pip
# pyinstaller's pin in requirements.txt may predate this system's python3;
# install everything else pinned, then let pyinstaller float to a compatible version.
pip install --quiet $(grep -vi '^pyinstaller' "$SRC_DIR/requirements.txt")
pip install --quiet pyinstaller

echo "Building with PyInstaller..."
cd "$SRC_DIR"
pyinstaller --noconfirm --onefile --windowed --name TAG_Downloader \
    --distpath "$SRC_DIR/dist" --workpath "$SRC_DIR/build" \
    tag_downloader/main.py
deactivate

echo "Installing built binary..."
cp "$SRC_DIR/dist/TAG_Downloader" "$APP_DIR/TAG_Downloader"
cp "$SRC_DIR/assets/downloader.png" "$APP_DIR/downloader.png"
chmod +x "$APP_DIR/TAG_Downloader"

echo "Checking dependencies..."
check_missing_libs "$APP_DIR/TAG_Downloader" "$APP_DIR"

echo "Creating shortcuts..."
make_shortcut "TAG Downloader" \
    "$APP_DIR/TAG_Downloader" \
    "$APP_DIR/downloader.png" \
    "$APP_DIR" \
    false \
    "Utility"
refresh_app_menu

echo "Done. TAG Downloader is installed at $APP_DIR."
