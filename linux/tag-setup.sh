#!/usr/bin/env bash
# Sets up the TAG workflow for one storm: creates Raw/Processed folders under
# TAG_HOME/Data, points Aspen's Directories/Auto Save settings and TAG
# Downloader's local/remote dirs at them, then launches both apps.
#
# Standalone-runnable: defaults TAG_HOME to ~/.tag if not already exported.
set -euo pipefail

TAG_HOME="${TAG_HOME:-$HOME/.tag}"
DATA_ROOT="$TAG_HOME/Data"
ASPEN_CONFIG="$HOME/.config/Aspen/aspen.xml"
QT_FILEDIALOG_CONFIG="$HOME/.config/QtProject.conf"
DOWNLOADER_CONFIG="$HOME/.tag_downloader/config.json"
ASPEN_BIN="$TAG_HOME/opt/Aspen-current/bin/run_aspen"
DOWNLOADER_BIN="$TAG_HOME/opt/TAG_Downloader/TAG_Downloader"

read -rp "Storm name/ID (e.g. 20260728N1): " STORM_ID
STORM_ID="$(echo -n "$STORM_ID" | xargs)"
if [ -z "$STORM_ID" ]; then
    echo "Storm ID can't be empty." >&2
    exit 1
fi
if [[ "$STORM_ID" == */* ]]; then
    echo "Storm ID can't contain '/'." >&2
    exit 1
fi

STORM_DIR="$DATA_ROOT/$STORM_ID"
RAW_DIR="$STORM_DIR/Raw"
PROCESSED_DIR="$STORM_DIR/Processed"

echo "Creating data folders..."
mkdir -p "$RAW_DIR" "$PROCESSED_DIR"
echo "  $RAW_DIR"
echo "  $PROCESSED_DIR"

if [ -f "$ASPEN_CONFIG" ]; then
    echo "Configuring Aspen ($ASPEN_CONFIG)..."
    cp -f "$ASPEN_CONFIG" "$ASPEN_CONFIG.bak"
    python3 - "$ASPEN_CONFIG" "$RAW_DIR" "$PROCESSED_DIR" <<'PYEOF'
import re
import sys

config_path, raw_dir, processed_dir = sys.argv[1:4]

with open(config_path, "r", encoding="utf-8") as f:
    xml = f.read()

# "Directories" preferences: where Aspen looks for raw soundings and where
# manual "Save" actions for each product land. FixedSrcDir is the "Fixed
# Data Source and Destination Directory" option, which, when its per-profile
# Enabled flag is on, overrides the open dialog's default location (left
# as whatever the user has it set to per profile - only the directory
# itself is synced here).
string_values = {
    "DataDir": raw_dir,
    "RawSaveDir": raw_dir,
    "FixedSrcDir": raw_dir,
    "QCSaveDir": processed_dir,
    "WmoSaveDir": processed_dir,
    "XYPlotSaveDir": processed_dir,
    "SkewTPlotSaveDir": processed_dir,
    "BatchSaveDir": processed_dir,
    "QCAutoSaveDir": processed_dir,
}
# "Auto Save" tab: automatically save output products for every file opened.
bool_values = {
    "QCAutoSaveEnable": "true",
    "QCAutoSaveFmtBufr": "true",
    "WmoAutoSaveFmtTxt": "true",
    "SkewtAutoSaveFmtPng": "true",
}

def set_current(xml, name, value):
    pattern = re.compile(
        r'(<option\b[^>]*\bname="%s"[^>]*>\s*<current>)[^<]*(</current>)' % re.escape(name)
    )
    xml, n = pattern.subn(lambda m: m.group(1) + value + m.group(2), xml)
    if n == 0:
        print(f"  warning: option '{name}' not found in aspen.xml, skipped", file=sys.stderr)
    return xml

for name, value in {**string_values, **bool_values}.items():
    xml = set_current(xml, name, value)

with open(config_path, "w", encoding="utf-8") as f:
    f.write(xml)
PYEOF
    echo "  data/save directories -> Raw: $RAW_DIR, Processed: $PROCESSED_DIR"
    echo "  QC auto save (BUFR, WMO, skew-T PNG) -> enabled"
else
    echo "warning: $ASPEN_CONFIG not found; launch Aspen once to create it, then re-run tag-setup." >&2
fi

# Qt's native file-open dialog remembers its last-visited folder in this
# desktop-wide settings file, independent of aspen.xml's DataDir - without
# this, Aspen's Open dialog keeps opening in the previous storm's folder
# until you manually browse to the new one.
echo "Configuring file-open dialog default location ($QT_FILEDIALOG_CONFIG)..."
[ -f "$QT_FILEDIALOG_CONFIG" ] && cp -f "$QT_FILEDIALOG_CONFIG" "$QT_FILEDIALOG_CONFIG.bak"
python3 - "$QT_FILEDIALOG_CONFIG" "$RAW_DIR" <<'PYEOF'
import os
import re
import sys

path, raw_dir = sys.argv[1:3]
file_url = f"file://{raw_dir}"

content = ""
if os.path.exists(path):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

if "[FileDialog]" not in content:
    if content and not content.endswith("\n"):
        content += "\n"
    content += "[FileDialog]\n"

def set_key(content, key, value):
    pattern = re.compile(rf'^{key}=.*$', re.MULTILINE)
    if pattern.search(content):
        return pattern.sub(f'{key}={value}', content, count=1)
    return re.sub(r'(\[FileDialog\]\n)', rf'\1{key}={value}\n', content, count=1)

content = set_key(content, "lastVisited", file_url)
content = set_key(content, "history", file_url)

with open(path, "w", encoding="utf-8") as f:
    f.write(content)
PYEOF
echo "  file dialog now opens at $RAW_DIR"

echo "Configuring TAG Downloader ($DOWNLOADER_CONFIG)..."
mkdir -p "$(dirname "$DOWNLOADER_CONFIG")"
python3 - "$DOWNLOADER_CONFIG" "$STORM_ID" "$RAW_DIR" <<'PYEOF'
import json
import os
import sys

config_path, storm_id, raw_dir = sys.argv[1:4]

defaults = {
    "protocol": "HTTP",
    "host": "",
    "port": 21,
    "url": "https://seb.omao.noaa.gov/pub/flight/aamps_ingest/avaps/received/",
    "username": "",
    "password": "",
    "passive": True,
    "remote_dir": "/",
    "local_dir": "",
    "interval_seconds": 60,
    "seen_files": [],
}

settings = dict(defaults)
if os.path.exists(config_path):
    try:
        with open(config_path, "r", encoding="utf-8") as f:
            settings.update(json.load(f))
    except (json.JSONDecodeError, OSError):
        pass

# New storm: point at its remote folder (adjust in-app if the server layout
# differs) and its local Raw folder, and drop the previous storm's seen-files
# baseline so nothing from this storm is skipped.
settings["remote_dir"] = f"/{storm_id}"
settings["local_dir"] = raw_dir
settings["seen_files"] = []

with open(config_path, "w", encoding="utf-8") as f:
    json.dump(settings, f, indent=2)
PYEOF
echo "  remote dir -> /$STORM_ID (change in the app if the server path differs)"
echo "  local dir  -> $RAW_DIR"

echo
if [ -x "$DOWNLOADER_BIN" ]; then
    echo "Launching TAG Downloader..."
    (
        cd "$(dirname "$DOWNLOADER_BIN")"
        nohup "$DOWNLOADER_BIN" >/dev/null 2>&1 &
    )
else
    echo "warning: $DOWNLOADER_BIN not found; run install-tag-downloader.sh first." >&2
fi

if [ -x "$ASPEN_BIN" ]; then
    echo "Launching Aspen..."
    exec "$ASPEN_BIN"
else
    echo "warning: $ASPEN_BIN not found; run install-aspen.sh first." >&2
fi
