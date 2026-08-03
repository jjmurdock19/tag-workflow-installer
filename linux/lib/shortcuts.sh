# Shared by install-aspen.sh and install-tag-downloader.sh.

# make_shortcut NAME EXEC_PATH ICON_PATH WORKDIR TERMINAL(true|false) CATEGORY
make_shortcut() {
    if [ "${TAG_SKIP_SHORTCUTS:-0}" = "1" ]; then
        return 0
    fi

    local name="$1" exec_path="$2" icon_path="$3" workdir="$4" terminal="$5" category="$6"
    local desktop_dir="$HOME/Desktop/TAG"
    local menu_dir="$HOME/.local/share/applications"
    mkdir -p "$desktop_dir" "$menu_dir"

    local content
    content=$(cat <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$name
Exec=$exec_path
Icon=$icon_path
Path=$workdir
Terminal=$terminal
Categories=$category;
EOF
)
    local desktop_file="$desktop_dir/$name.desktop"
    local menu_file="$menu_dir/$name.desktop"

    printf '%s\n' "$content" > "$desktop_file"
    printf '%s\n' "$content" > "$menu_file"
    chmod +x "$desktop_file" "$menu_file"
    gio set "$desktop_file" metadata::trusted true 2>/dev/null || true

    echo "  shortcut: $desktop_file"
    echo "  start menu: $menu_file"
}

refresh_app_menu() {
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
}

# check_missing_libs BINARY LIB_DIR
# ldd's a binary, maps any missing deps to Fedora packages via `dnf provides`,
# and prints the install command (never runs sudo itself).
check_missing_libs() {
    local binary="$1" lib_dir="$2"
    local missing
    missing=$(LD_LIBRARY_PATH="$lib_dir" ldd "$binary" 2>/dev/null | awk '/not found/ {print $1}' | sort -u)

    if [ -z "$missing" ]; then
        echo "  dependency check: all shared libraries resolved, nothing to install"
        return 0
    fi

    echo "  missing shared libraries:"
    echo "$missing" | sed 's/^/    /'

    local pkgs=()
    local lib
    for lib in $missing; do
        local pkg
        pkg=$(dnf provides "*/${lib}" 2>/dev/null | grep -m1 -oP '^\S+(?=-\d[\w.+~-]*-\d)')
        if [ -n "$pkg" ]; then
            echo "    $lib -> $pkg"
            pkgs+=("$pkg")
        else
            echo "    $lib -> no Fedora package found automatically, you'll need to track this one down yourself"
        fi
    done

    if [ "${#pkgs[@]}" -eq 0 ]; then
        return 0
    fi

    local unique_pkgs
    unique_pkgs=$(printf '%s\n' "${pkgs[@]}" | sort -u | tr '\n' ' ')
    echo "  this installer doesn't run as admin, so it won't install these itself. Run:"
    echo "    sudo dnf install -y $unique_pkgs"
}
