# tag-workflow-installer

One-stop installer for the TAG dropsonde workflow: **Aspen** (NCAR/EOL sounding
QC tool) + **[TAG Downloader](https://github.com/jjmurdock19/TAG_Downloader)**
+ a `tag-setup` command that preps per-storm data folders, points both apps at
them, and launches the workflow.

Works on Linux and Windows. Auto-detects nothing needs elevated/admin
privileges to run — everything installs under a folder you own.

## Install

**Linux:**

```sh
curl -fsSL https://raw.githubusercontent.com/jjmurdock19/tag-workflow-installer/main/install.sh | bash
```

**Windows (PowerShell):**

```powershell
irm https://raw.githubusercontent.com/jjmurdock19/tag-workflow-installer/main/install.ps1 | iex
```

> `irm | iex` evaluates the script in-memory, so it isn't affected by
> PowerShell's script execution policy. If you later run one of the `.ps1`
> files directly (not via a generated shortcut, which already passes
> `-ExecutionPolicy Bypass`) and it's blocked, that's the execution policy —
> not admin rights. Fix it per-user, no admin needed:
> `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.

Both scripts:
- Install everything under a single folder you own — **`~/.tag`** on Linux,
  **`%USERPROFILE%\tag`** on Windows by default. Change it with
  `--install-dir DIR` (Linux) / `-InstallDir DIR` (Windows), or by exporting/
  setting `TAG_HOME` beforehand.
- Ask before creating Desktop / Start Menu shortcuts, unless you pass
  `-y`/`--yes` (Linux, accepts all defaults) or `-Yes` (Windows) to skip
  prompts entirely, or explicitly opt out with `--no-shortcuts` (Linux) /
  `-NoShortcuts` (Windows).
- Never require sudo/admin. See [No admin privileges](#no-admin-privileges)
  below for what that means in practice on each platform.
- Are safe to re-run — they update Aspen/TAG Downloader in place rather than
  reinstalling from scratch.

You can also clone the repo and run the scripts locally instead of piping
from curl/irm — `install.sh` / `install.ps1` work the same either way.

## What gets installed, and where

```
<TAG_HOME>/                  (~/.tag on Linux, %USERPROFILE%\tag on Windows)
├── bin/tag-setup               tag-setup entry point (Linux only)
├── opt/
│   ├── Aspen<version>/          extracted Aspen build (Linux)
│   ├── Aspen-current -> ...      symlink kept pointing at the current version (Linux)
│   ├── Aspen/                    where you point the Aspen installer's destination (Windows)
│   ├── aspen-path.txt            resolved path to Aspen.exe, saved after install (Windows)
│   ├── TAG_Downloader/           built TAG_Downloader binary/exe + icon
│   └── src/TAG_Downloader/       git checkout used to build TAG_Downloader
├── downloads/                   downloaded Aspen installer .exe (Windows only)
├── src/tag-workflow-installer/  this repo, kept checked out so re-runs don't need to re-curl
└── Data/<storm-id>/{Raw,Processed}/   created per storm by tag-setup, same layout on both platforms
```

A few things intentionally live **outside** `TAG_HOME`, because the apps
themselves — not this installer — decide where they go:
- Aspen's own config: `~/.config/Aspen/aspen.xml` (Linux) — Windows location
  varies by install, `tag-setup`/`Tag-Setup.ps1` search a few likely spots.
- TAG Downloader's config: `~/.tag_downloader/config.json` on both platforms.
- Shortcuts: `~/Desktop/TAG/` and `~/.local/share/applications/` (Linux, XDG
  standard locations), or your per-user Desktop and Start Menu folders on
  Windows — always per-user, never the machine-wide locations.

## Running the workflow for a new storm

```sh
$TAG_HOME/bin/tag-setup        # Linux
```
```powershell
& "$env:TAG_HOME\src\tag-workflow-installer\windows\Tag-Setup.ps1"   # Windows
```

or use the **"TAG Workflow"** shortcut created during install (if you opted
in) — it prompts for a storm ID, creates that storm's `Raw`/`Processed`
folders, points Aspen and TAG Downloader at them, and launches both.

## No admin privileges

This is a hard requirement, not just a default:

- **Linux**: if Aspen or TAG Downloader are missing a shared library, the
  installer prints the exact `sudo dnf install -y ...` command instead of
  running it for you — you decide whether to run it.
- **Windows**: Aspen only ships as a signed installer executable
  (`AspenV<version>-Installer-win.exe`) whose silent-install behavior isn't
  publicly documented, so `Install-Aspen.ps1` downloads it and launches it
  **interactively** — when its window opens, point the destination folder at
  `%USERPROFILE%\tag\opt\Aspen` (not `Program Files`) so Windows doesn't
  prompt for elevation. Everything else (TAG Downloader's build, shortcuts)
  is pure user-space: a Python venv and per-user Desktop/Start Menu folders.

## Notes / caveats

- The Windows side (`install.ps1`, `windows/*.ps1`) was written and reviewed
  without access to a Windows machine — the logic mirrors the Linux scripts
  as closely as platform differences allow, but hasn't been run end-to-end.
  If something doesn't work as expected, check `windows/` first. In
  particular:
  - Aspen's Windows config file path is auto-detected by checking a few
    likely locations (`%APPDATA%\Aspen\aspen.xml`, `%LOCALAPPDATA%\Aspen\aspen.xml`);
    if `Tag-Setup.ps1` can't find it, launch Aspen once (so it creates its
    config) and re-run `Tag-Setup.ps1`.
  - Aspen's install path is auto-detected after the interactive installer
    closes (searched under `opt\Aspen`, `%LOCALAPPDATA%\Programs`, etc.) and
    saved to `opt\aspen-path.txt`. If detection fails, you'll be prompted for
    the path once, or can edit that file by hand later.
  - Shortcuts go in the per-user Start Menu `Programs` folder (not the bare
    `Start Menu` folder, which Windows doesn't reliably index) — this is the
    one place the Windows implementation had to deviate from a literal port
    of the Linux logic, since there's no Linux equivalent to double-check
    against.
- `REPO_URL` in `install.sh` (and the matching URL in `install.ps1`) assumes
  this repo lives at `github.com/jjmurdock19/tag-workflow-installer` — update
  it in both files if you push it somewhere else.
- These scripts target Fedora/RHEL-family Linux (the shared-library check
  uses `dnf`) and Windows 10/11. macOS isn't covered, even though Aspen
  itself ships a macOS build.
- On a fresh Windows machine, `.ps1` files run directly (not through one of
  the generated shortcuts, which already pass `-ExecutionPolicy Bypass`) may
  be blocked by the default execution policy — that's a per-user setting,
  not admin: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.
