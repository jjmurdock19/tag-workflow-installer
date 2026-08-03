# Install-Aspen.ps1
#
# Aspen only ships an interactive Windows installer, so this downloads it,
# launches it, and has the user point it at $TAG_HOME\opt\Aspen to avoid
# Program Files / UAC. Then it locates the resulting Aspen.exe and saves
# its path for Tag-Setup.ps1.
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

$TagHome      = $InstallDir
$OptDir       = Join-Path $TagHome 'opt'
$AspenDir     = Join-Path $OptDir 'Aspen'
$DownloadsDir = Join-Path $TagHome 'downloads'
$MarkerFile   = Join-Path $OptDir 'aspen-path.txt'
$PageUrl      = 'https://www.eol.ucar.edu/software/aspen'

New-Item -ItemType Directory -Force -Path $OptDir, $AspenDir, $DownloadsDir | Out-Null

function ConvertTo-ComparableVersion {
    param([string]$VersionString)
    $parts = @($VersionString -split '\.' | ForEach-Object {
        $n = 0
        [void][int]::TryParse(($_ -replace '[^\d]', ''), [ref]$n)
        $n
    })
    while ($parts.Count -lt 4) { $parts += 0 }
    return [version]::new($parts[0], $parts[1], $parts[2], $parts[3])
}

Write-Host "Checking $PageUrl for available builds..."
try {
    $html = (Invoke-WebRequest -Uri $PageUrl -UseBasicParsing).Content
}
catch {
    Write-Error "Failed to fetch $PageUrl : $($_.Exception.Message)"
    exit 1
}

$linkMatches = [regex]::Matches($html, 'https?://archive\.eol\.ucar\.edu[^"''\s]*AspenV([0-9.]+)-Installer-win\.exe')
if ($linkMatches.Count -eq 0) {
    Write-Error "No Windows Aspen installer links found on $PageUrl"
    exit 1
}

$seenUrls = New-Object 'System.Collections.Generic.HashSet[string]'
$best = $null
foreach ($m in $linkMatches) {
    $url = $m.Value
    if (-not $seenUrls.Add($url)) { continue }
    $verObj = ConvertTo-ComparableVersion $m.Groups[1].Value
    if (-not $best -or $verObj -gt $best.VersionObj) {
        $best = [pscustomobject]@{ Url = $url; VersionObj = $verObj; VersionStr = $m.Groups[1].Value }
    }
}

Write-Host "Selected Aspen $($best.VersionStr): $($best.Url)"

$installerPath = Join-Path $DownloadsDir (Split-Path $best.Url -Leaf)
Write-Host "Downloading to $installerPath ..."
Invoke-WebRequest -Uri $best.Url -OutFile $installerPath -UseBasicParsing

Write-Host ""
Write-Host "================================================================"
Write-Host " The Aspen installer will now launch."
Write-Host ""
Write-Host " This install must run WITHOUT administrator rights. When the"
Write-Host " installer asks for a destination/install folder, change it to:"
Write-Host ""
Write-Host "     $AspenDir"
Write-Host ""
Write-Host " Do NOT install to 'Program Files' - that requires admin and"
Write-Host " will either fail or trigger a UAC prompt."
Write-Host ""
Write-Host " Click through the rest of the installer normally, then close it"
Write-Host " and return to this window."
Write-Host "================================================================"
Write-Host ""

if (-not $Yes) {
    Read-Host "Press Enter to launch the Aspen installer"
}

try {
    Start-Process -FilePath $installerPath -Wait
}
catch {
    Write-Warning "Aspen installer did not run cleanly: $($_.Exception.Message)"
}

if (-not $Yes) {
    Read-Host "Press Enter once you have finished clicking through the Aspen installer"
}

function Find-AspenExe {
    param([string[]]$SearchRoots)
    $rootsSeen = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($root in $SearchRoots) {
        if (-not $root -or -not (Test-Path $root)) { continue }
        $full = (Resolve-Path -Path $root -ErrorAction SilentlyContinue).Path
        if (-not $full -or -not $rootsSeen.Add($full)) { continue }
        try {
            $found = Get-ChildItem -Path $full -Recurse -Force -ErrorAction SilentlyContinue -Include 'Aspen.exe', 'aspen.exe' |
                Select-Object -First 1
            if ($found) { return $found.FullName }
        }
        catch {
            # inaccessible subfolder etc. - keep searching other roots
        }
    }
    return $null
}

Write-Host "Searching for Aspen.exe ..."
$searchRoots = @(
    $AspenDir,
    (Join-Path $env:LOCALAPPDATA 'Programs'),
    (Join-Path $env:USERPROFILE 'AppData\Local')
)
$aspenExe = Find-AspenExe -SearchRoots $searchRoots

if (-not $aspenExe) {
    Write-Warning "Could not automatically locate Aspen.exe under: $($searchRoots -join ', ')"
    if ($Yes) {
        Write-Warning "Non-interactive run: skipping manual path entry. Launch Aspen once to find its install location, then either create $MarkerFile containing the full path to Aspen.exe, or re-run Install-Aspen.ps1 interactively."
    }
    else {
        while ($true) {
            $manual = Read-Host "Enter the full path to Aspen.exe (or leave blank to skip)"
            if ([string]::IsNullOrWhiteSpace($manual)) { break }
            if (Test-Path $manual) { $aspenExe = $manual; break }
            Write-Host "That path doesn't exist - try again, or leave blank to skip."
        }
    }
}

if ($aspenExe) {
    Set-Content -Path $MarkerFile -Value $aspenExe -Encoding UTF8 -NoNewline
    Write-Host "Aspen located at: $aspenExe"
    Write-Host "Path saved to: $MarkerFile"
}
else {
    Write-Warning "Aspen path not recorded. Launch Aspen once to find its install location, then re-run Install-Aspen.ps1, or create $MarkerFile by hand containing the full path to Aspen.exe."
}

if (-not $NoShortcuts -and $aspenExe) {
    $createShortcuts = $Yes
    if (-not $Yes) {
        $resp = Read-Host "Create Aspen shortcuts (Desktop + Start Menu)? [Y/n]"
        $createShortcuts = ($resp -notmatch '^[Nn]')
    }
    if ($createShortcuts) {
        New-TagShortcut -Name 'Aspen' -TargetPath $aspenExe `
            -WorkingDirectory (Split-Path $aspenExe -Parent) -IconLocation "$aspenExe,0"
    }
}

Write-Host "Aspen install step complete."
