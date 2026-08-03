# Install-TagDownloader.ps1
#
# Clones/builds TAG_Downloader into a standalone .exe via PyInstaller in a
# per-user venv, and installs it under $TAG_HOME\opt\TAG_Downloader.
[CmdletBinding()]
param(
    [string]$InstallDir = $(if ($env:TAG_HOME) { $env:TAG_HOME } else { Join-Path $env:USERPROFILE 'tag' }),
    [switch]$Yes,
    [switch]$NoShortcuts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'lib\Shortcuts.ps1')

$TagHome  = $InstallDir
$RepoUrl  = 'https://github.com/jjmurdock19/TAG_Downloader'
$OptDir   = Join-Path $TagHome 'opt'
$SrcDir   = Join-Path $OptDir 'src\TAG_Downloader'
$AppDir   = Join-Path $OptDir 'TAG_Downloader'
$VenvDir  = Join-Path $AppDir 'venv'

New-Item -ItemType Directory -Force -Path (Join-Path $OptDir 'src'), $AppDir | Out-Null

function Assert-Success {
    param([string]$Message)
    if ($LASTEXITCODE -ne 0) {
        throw "$Message (exit code $LASTEXITCODE)"
    }
}

function Find-PythonCommand {
    foreach ($cmd in 'python', 'py') {
        if (Get-Command $cmd -ErrorAction SilentlyContinue) { return $cmd }
    }
    return $null
}

$pythonCmd = Find-PythonCommand
if (-not $pythonCmd) {
    Write-Error "Python was not found on PATH. Install it from https://www.python.org/downloads/windows/ (check 'Add python.exe to PATH' during setup), then re-run this script."
    exit 1
}

$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if ($gitCmd) {
    if (Test-Path (Join-Path $SrcDir '.git')) {
        Write-Host "Updating existing TAG_Downloader checkout..."
        git -C $SrcDir pull --ff-only
        Assert-Success "git pull failed in $SrcDir"
    }
    else {
        Write-Host "Cloning TAG_Downloader..."
        git clone "$RepoUrl.git" $SrcDir
        Assert-Success "git clone failed"
    }
}
else {
    Write-Host "git not found on PATH; downloading TAG_Downloader archive instead..."
    $zipPath = $null
    foreach ($branch in 'master', 'main') {
        try {
            $candidate = Join-Path $env:TEMP "TAG_Downloader-$branch.zip"
            Invoke-WebRequest -Uri "$RepoUrl/archive/refs/heads/$branch.zip" -OutFile $candidate -UseBasicParsing
            $zipPath = $candidate
            break
        }
        catch { continue }
    }
    if (-not $zipPath) {
        throw "Could not download TAG_Downloader archive (tried master and main branches)."
    }

    $extractDir = Join-Path $env:TEMP 'TAG_Downloader-extract'
    if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
    $extracted = Get-ChildItem -Path $extractDir -Directory | Select-Object -First 1
    if (-not $extracted) { throw "Downloaded archive did not contain the expected folder." }
    if (Test-Path $SrcDir) { Remove-Item $SrcDir -Recurse -Force }
    Move-Item -Path $extracted.FullName -Destination $SrcDir
}

if (-not (Test-Path $VenvDir)) {
    Write-Host "Creating virtual environment..."
    & $pythonCmd -m venv $VenvDir
    Assert-Success "python -m venv failed"
}

$venvPython      = Join-Path $VenvDir 'Scripts\python.exe'
$venvPip         = Join-Path $VenvDir 'Scripts\pip.exe'
$venvPyInstaller = Join-Path $VenvDir 'Scripts\pyinstaller.exe'

& $venvPython -m pip install --quiet --upgrade pip
Assert-Success "pip upgrade failed"

$requirementsPath = Join-Path $SrcDir 'requirements.txt'
if (-not (Test-Path $requirementsPath)) {
    throw "requirements.txt not found at $requirementsPath"
}
# pyinstaller pin may predate this system's Python, so drop it and install unpinned below
$reqLines = Get-Content $requirementsPath | Where-Object { $_.Trim() -ne '' -and $_ -notmatch '^\s*pyinstaller\s*([=<>!~].*)?$' }
if ($reqLines) {
    $tempReq = Join-Path $env:TEMP 'tag_downloader_requirements.txt'
    Set-Content -Path $tempReq -Value $reqLines
    & $venvPip install --quiet -r $tempReq
    Assert-Success "pip install -r requirements.txt failed"
}
& $venvPip install --quiet pyinstaller
Assert-Success "pip install pyinstaller failed"

Write-Host "Building TAG_Downloader.exe with PyInstaller..."
$distPath = Join-Path $SrcDir 'dist'
$workPath = Join-Path $SrcDir 'build'
$entryPoint = Join-Path $SrcDir 'tag_downloader\main.py'
if (-not (Test-Path $entryPoint)) {
    throw "Entry point not found: $entryPoint"
}

& $venvPyInstaller --noconfirm --onefile --windowed --name TAG_Downloader `
    --distpath $distPath --workpath $workPath $entryPoint
Assert-Success "pyinstaller build failed"

$builtExe = Join-Path $distPath 'TAG_Downloader.exe'
if (-not (Test-Path $builtExe)) {
    throw "PyInstaller did not produce the expected output: $builtExe"
}
Copy-Item -Path $builtExe -Destination (Join-Path $AppDir 'TAG_Downloader.exe') -Force

$iconSrc = Join-Path $SrcDir 'assets\downloader.png'
if (Test-Path $iconSrc) {
    Copy-Item -Path $iconSrc -Destination (Join-Path $AppDir 'downloader.png') -Force
}
else {
    Write-Warning "Icon asset not found at $iconSrc; shortcuts will fall back to the exe's own embedded icon."
}

$appExe = Join-Path $AppDir 'TAG_Downloader.exe'
Write-Host "TAG Downloader installed at $appExe"

if (-not $NoShortcuts) {
    $createShortcuts = $Yes
    if (-not $Yes) {
        $resp = Read-Host "Create TAG Downloader shortcuts (Desktop + Start Menu)? [Y/n]"
        $createShortcuts = ($resp -notmatch '^[Nn]')
    }
    if ($createShortcuts) {
        New-TagShortcut -Name 'TAG Downloader' -TargetPath $appExe `
            -WorkingDirectory $AppDir -IconLocation "$appExe,0"
    }
}

Write-Host "TAG Downloader install step complete."
