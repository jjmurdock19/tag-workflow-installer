#!/usr/bin/env bash
# Installs the latest Linux x86_64 build of Aspen (NCAR/EOL sounding QC tool)
# from https://www.eol.ucar.edu/software/aspen, checks for missing shared
# library dependencies (no admin privileges used - see lib/shortcuts.sh), and
# (re)creates the desktop + start menu launcher.
#
# Standalone-runnable: defaults TAG_HOME to ~/.tag if not already exported.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/shortcuts.sh"

TAG_HOME="${TAG_HOME:-$HOME/.tag}"
INSTALL_ROOT="$TAG_HOME/opt"
PAGE_URL="https://www.eol.ucar.edu/software/aspen"

if [ "$(uname -s)" != "Linux" ] || [ "$(uname -m)" != "x86_64" ]; then
    echo "This script only handles the Linux x86_64 Aspen build." >&2
    exit 1
fi

echo "Checking $PAGE_URL for available builds..."
page_html=$(curl -sL "$PAGE_URL")

# Every Linux x86_64 tarball link on the page, e.g.:
#   https://archive.eol.ucar.edu/docs/software/aspen/AspenV4.1.1_RedHatEnterpriseLinux9.7_x86_64.tar.gz
mapfile -t urls < <(grep -oE 'https?://archive\.eol\.ucar\.edu[^"'"'"']*AspenV[0-9.]+_[A-Za-z0-9._]+_x86_64\.tar\.gz' <<<"$page_html" | sort -u)

if [ "${#urls[@]}" -eq 0 ]; then
    echo "Couldn't find any download links on $PAGE_URL - the page layout may have changed." >&2
    exit 1
fi

# Pick the highest version number. Ties (same version, different base OS) keep the first found.
latest_url=""
latest_version=""
for url in "${urls[@]}"; do
    version=$(grep -oE 'AspenV[0-9.]+' <<<"$url" | sed 's/AspenV//')
    if [ -z "$latest_version" ] || [ "$(printf '%s\n%s\n' "$version" "$latest_version" | sort -V | tail -1)" = "$version" ] && [ "$version" != "$latest_version" ]; then
        latest_version="$version"
        latest_url="$url"
    fi
done

echo "Latest available: Aspen $latest_version"
echo "  $latest_url"

target_dir="$INSTALL_ROOT/Aspen$latest_version"

if [ -x "$target_dir/bin/aspen" ]; then
    echo "Already installed at $target_dir, skipping download."
else
    tmp_dir=$(mktemp -d)
    trap 'rm -rf "$tmp_dir"' EXIT

    tarball="$tmp_dir/$(basename "$latest_url")"
    echo "Downloading..."
    curl -L --progress-bar -o "$tarball" "$latest_url"

    echo "Extracting..."
    tar xzf "$tarball" -C "$tmp_dir"

    extracted_dir=$(find "$tmp_dir" -maxdepth 1 -mindepth 1 -type d -name 'Aspen*')
    mkdir -p "$INSTALL_ROOT"
    rm -rf "$target_dir"
    mv "$extracted_dir" "$target_dir"
    echo "Installed to $target_dir"
fi

ln -sfn "$target_dir" "$INSTALL_ROOT/Aspen-current"

echo "Checking dependencies..."
check_missing_libs "$INSTALL_ROOT/Aspen-current/bin/aspen" "$INSTALL_ROOT/Aspen-current/lib"

echo "Creating shortcuts..."
make_shortcut "Aspen" \
    "$INSTALL_ROOT/Aspen-current/bin/run_aspen" \
    "$INSTALL_ROOT/Aspen-current/bin/AspenIcon.png" \
    "$INSTALL_ROOT/Aspen-current/bin" \
    true \
    "Science"
refresh_app_menu

echo "Done. Aspen $latest_version is installed at $INSTALL_ROOT/Aspen-current (symlink to $target_dir)."
