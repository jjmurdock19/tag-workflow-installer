# tag-workflow-installer

Installer for my personal TAG workflow: 
- **[Aspen](https://www.eol.ucar.edu/software/aspen)** (NCAR sounding QC tool)
- **[TAG Downloader](https://github.com/jjmurdock19/TAG_Downloader)**
- `tag-setup` command that preps per-storm data folders, configures Aspen and the tag downloader, and launches them.

## Install

**Linux:**

```sh
curl -fsSL https://raw.githubusercontent.com/jjmurdock19/tag-workflow-installer/main/install.sh | bash
```

**Windows (PowerShell):**

```powershell
irm https://raw.githubusercontent.com/jjmurdock19/tag-workflow-installer/main/install.ps1 | iex
```

## Running the workflow

```sh
$TAG_HOME/bin/tag-setup        # Linux
```
```powershell
& "$env:TAG_HOME\src\tag-workflow-installer\windows\Tag-Setup.ps1"   # Windows
```

or use the **"TAG Workflow"** shortcut created during install.

