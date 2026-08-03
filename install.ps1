# install.ps1 - Windows bootstrap for the TAG workflow installer.
[CmdletBinding()]
param(
    [string]$InstallDir,
    [switch]$Yes,
    [switch]$NoShortcuts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$onWindows = $true
if ($PSVersionTable.PSVersion.Major -ge 6) {
    $onWindows = [bool]$IsWindows
}
elseif (-not $env:OS -or $env:OS -ne 'Windows_NT') {
    $onWindows = $false
}
if (-not $onWindows) {
    Write-Error "install.ps1 is for Windows only. On Linux/macOS, use this repo's Linux installer instead."
    exit 1
}

$installDirExplicit = $PSBoundParameters.ContainsKey('InstallDir')

if (-not $InstallDir) {
    $InstallDir = if ($env:TAG_HOME) { $env:TAG_HOME } else { Join-Path $env:USERPROFILE 'tag' }
}
if (-not $Yes -and -not $installDirExplicit) {
    $resp = Read-Host "Install location [$InstallDir]"
    if (-not [string]::IsNullOrWhiteSpace($resp)) { $InstallDir = $resp }
}

$env:TAG_HOME = $InstallDir
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Write-Host "Installing TAG workflow tools to: $InstallDir"

$wantShortcuts = -not $NoShortcuts
if ($wantShortcuts -and -not $Yes) {
    $resp = Read-Host "Create Desktop/Start Menu shortcuts? [Y/n]"
    $wantShortcuts = ($resp -notmatch '^[Nn]')
}
$noShortcutsFlag = -not $wantShortcuts

$repoUrl = 'https://github.com/jjmurdock19/tag-workflow-installer.git'
$srcDir  = Join-Path $InstallDir 'src\tag-workflow-installer'
New-Item -ItemType Directory -Force -Path (Split-Path $srcDir -Parent) | Out-Null

$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if ($gitCmd) {
    if (Test-Path (Join-Path $srcDir '.git')) {
        Write-Host "Updating existing tag-workflow-installer checkout..."
        git -C $srcDir pull --ff-only
        if ($LASTEXITCODE -ne 0) { throw "git pull failed (exit $LASTEXITCODE)" }
    }
    else {
        Write-Host "Cloning tag-workflow-installer..."
        git clone --depth 1 $repoUrl $srcDir
        if ($LASTEXITCODE -ne 0) { throw "git clone failed (exit $LASTEXITCODE)" }
    }
}
else {
    Write-Host "git not found on PATH; downloading a repo archive instead..."
    $zipPath = $null
    foreach ($branch in 'main', 'master') {
        try {
            $candidate = Join-Path $env:TEMP "tag-workflow-installer-$branch.zip"
            Invoke-WebRequest -Uri "https://github.com/jjmurdock19/tag-workflow-installer/archive/refs/heads/$branch.zip" -OutFile $candidate -UseBasicParsing
            $zipPath = $candidate
            break
        }
        catch { continue }
    }
    if (-not $zipPath) {
        throw "Could not download tag-workflow-installer archive (tried main and master branches)."
    }

    $extractDir = Join-Path $env:TEMP 'tag-workflow-installer-extract'
    if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
    $extracted = Get-ChildItem -Path $extractDir -Directory | Select-Object -First 1
    if (-not $extracted) { throw "Downloaded archive did not contain the expected folder." }
    if (Test-Path $srcDir) { Remove-Item $srcDir -Recurse -Force }
    Move-Item -Path $extracted.FullName -Destination $srcDir
}

$windowsDir   = Join-Path $srcDir 'windows'
$tagSetupPath = Join-Path $windowsDir 'Tag-Setup.ps1'

$subArgs = @{ InstallDir = $InstallDir }
if ($Yes) { $subArgs.Yes = $true }
if ($noShortcutsFlag) { $subArgs.NoShortcuts = $true }

Write-Host ""
Write-Host "=== Installing Aspen ==="
& (Join-Path $windowsDir 'Install-Aspen.ps1') @subArgs

Write-Host ""
Write-Host "=== Installing TAG Downloader ==="
& (Join-Path $windowsDir 'Install-TagDownloader.ps1') @subArgs

if ($wantShortcuts) {
    try {
        . (Join-Path $windowsDir 'lib\Shortcuts.ps1')
        New-TagWorkflowShortcut -TagSetupScriptPath $tagSetupPath -WorkingDirectory $InstallDir
    }
    catch {
        Write-Warning "Could not create the 'TAG Workflow' shortcut: $($_.Exception.Message)"
    }
}

Write-Host ""
Write-Host "TAG workflow installation complete."
Write-Host "Repo checked out at: $srcDir"
Write-Host "Run the workflow any time via the 'TAG Workflow' shortcut, or directly:"
Write-Host "  powershell -ExecutionPolicy Bypass -File `"$tagSetupPath`""
