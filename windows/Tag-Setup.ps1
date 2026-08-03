#
# Tag-Setup.ps1
#
# Per-storm setup: creates Raw/Processed folders, points Aspen's config and
# TAG Downloader's config at them, and launches both apps. Mirrors the Linux
# tag-setup script; every config-patch step is best-effort and degrades
# gracefully (warns and continues) since Aspen's Windows config location and
# the Qt ini-file fallback are both unverified on a real Windows box.
#
[CmdletBinding()]
param(
    [string]$InstallDir = $(if ($env:TAG_HOME) { $env:TAG_HOME } else { Join-Path $env:USERPROFILE 'tag' })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TagHome          = $InstallDir
$DataRoot         = Join-Path $TagHome 'Data'
$DownloaderConfig = Join-Path $env:USERPROFILE '.tag_downloader\config.json'
$AspenPathMarker  = Join-Path $TagHome 'opt\aspen-path.txt'
$DownloaderExe    = Join-Path $TagHome 'opt\TAG_Downloader\TAG_Downloader.exe'

# --- storm ID ---
$StormId = (Read-Host "Storm name/ID (e.g. 20260728N1)").Trim()
if ([string]::IsNullOrWhiteSpace($StormId)) {
    Write-Error "Storm ID can't be empty."
    exit 1
}
if ($StormId -match '[\\/]') {
    Write-Error "Storm ID can't contain '/' or '\'."
    exit 1
}

$StormDir     = Join-Path $DataRoot $StormId
$RawDir       = Join-Path $StormDir 'Raw'
$ProcessedDir = Join-Path $StormDir 'Processed'
New-Item -ItemType Directory -Force -Path $RawDir, $ProcessedDir | Out-Null
Write-Host "Storm folders ready:"
Write-Host "  Raw:       $RawDir"
Write-Host "  Processed: $ProcessedDir"

# --- Aspen config ---
function Set-AspenOptionValue {
    param([string]$Content, [string]$OptionName, [string]$Value)
    $escaped = $Value -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'
    $pattern = '(?s)(<option\s+name="' + [regex]::Escape($OptionName) + '"[^>]*>\s*<current>)(.*?)(</current>)'
    $m = [regex]::Match($Content, $pattern)
    if (-not $m.Success) {
        Write-Warning "Aspen config: option '$OptionName' not found; skipping."
        return $Content
    }
    return $Content.Substring(0, $m.Groups[2].Index) + $escaped + `
        $Content.Substring($m.Groups[2].Index + $m.Groups[2].Length)
}

$aspenConfigCandidates = @(
    (Join-Path $env:APPDATA 'Aspen\aspen.xml'),
    (Join-Path $env:LOCALAPPDATA 'Aspen\aspen.xml'),
    (Join-Path $env:USERPROFILE '.config\Aspen\aspen.xml')
)
$aspenConfig = $aspenConfigCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($aspenConfig) {
    Write-Host "Patching Aspen config: $aspenConfig"
    try {
        Copy-Item -Path $aspenConfig -Destination "$aspenConfig.bak" -Force

        $content = Get-Content -Path $aspenConfig -Raw

        # DataDir/RawSaveDir/FixedSrcDir only sync the *directory* Aspen reads
        # from - not the per-profile Enabled flag for FixedSrcDir, which is
        # left as the user configured it (matches the Linux script).
        $rawDirOptions = @('DataDir', 'RawSaveDir', 'FixedSrcDir')
        $processedDirOptions = @('QCSaveDir', 'WmoSaveDir', 'XYPlotSaveDir', 'SkewTPlotSaveDir', 'BatchSaveDir', 'QCAutoSaveDir')
        $boolOptions = @('QCAutoSaveEnable', 'QCAutoSaveFmtBufr', 'WmoAutoSaveFmtTxt', 'SkewtAutoSaveFmtPng')

        foreach ($opt in $rawDirOptions)       { $content = Set-AspenOptionValue -Content $content -OptionName $opt -Value $RawDir }
        foreach ($opt in $processedDirOptions) { $content = Set-AspenOptionValue -Content $content -OptionName $opt -Value $ProcessedDir }
        foreach ($opt in $boolOptions)         { $content = Set-AspenOptionValue -Content $content -OptionName $opt -Value 'true' }

        Set-Content -Path $aspenConfig -Value $content -NoNewline
    }
    catch {
        Write-Warning "Failed to patch Aspen config ($aspenConfig): $($_.Exception.Message)"
        if (Test-Path "$aspenConfig.bak") {
            Copy-Item -Path "$aspenConfig.bak" -Destination $aspenConfig -Force
            Write-Warning "Restored Aspen config from backup."
        }
    }
}
else {
    Write-Warning "Aspen config not found in any known location (checked: $($aspenConfigCandidates -join ', ')). Launch Aspen once to create it, then re-run Tag-Setup.ps1 to sync data folders."
}

# --- Qt file-dialog last-visited (best-effort, cosmetic only) ---
$qtConfigPath = Join-Path $env:APPDATA 'QtProject\QtProject.conf'
if (Test-Path $qtConfigPath) {
    try {
        Write-Host "Patching Qt file dialog config: $qtConfigPath"
        Copy-Item -Path $qtConfigPath -Destination "$qtConfigPath.bak" -Force

        $rawDirUri = 'file:///' + ($RawDir -replace '\\', '/')
        $qtContent = Get-Content -Path $qtConfigPath -Raw

        $sectionPattern = '(?ms)(\[FileDialog\]\r?\n)(.*?)(?=^\[|\z)'
        $secMatch = [regex]::Match($qtContent, $sectionPattern)

        if ($secMatch.Success) {
            $body = $secMatch.Groups[2].Value
            if ($body -match '(?m)^lastVisited\s*=.*$') {
                $body = [regex]::Replace($body, '(?m)^lastVisited\s*=.*$', "lastVisited=$rawDirUri")
            }
            else {
                $body = "lastVisited=$rawDirUri`r`n" + $body
            }
            if ($body -match '(?m)^history\s*=.*$') {
                $body = [regex]::Replace($body, '(?m)^history\s*=.*$', "history=$rawDirUri")
            }
            else {
                $body = "history=$rawDirUri`r`n" + $body
            }
            $qtContent = $qtContent.Substring(0, $secMatch.Groups[2].Index) + $body + `
                $qtContent.Substring($secMatch.Groups[2].Index + $secMatch.Groups[2].Length)
        }
        else {
            if ($qtContent -and -not $qtContent.EndsWith("`n")) { $qtContent += "`r`n" }
            $qtContent += "[FileDialog]`r`nlastVisited=$rawDirUri`r`nhistory=$rawDirUri`r`n"
        }

        Set-Content -Path $qtConfigPath -Value $qtContent -NoNewline
    }
    catch {
        Write-Warning "Could not patch Qt file dialog config ($qtConfigPath): $($_.Exception.Message)"
    }
}
else {
    # Most Windows Qt builds use the registry, not an ini file - this is expected and fine.
    Write-Host "Qt file dialog config not found at $qtConfigPath (cosmetic only); skipping."
}

# --- TAG Downloader config ---
try {
    $downloaderConfigDir = Split-Path $DownloaderConfig -Parent
    New-Item -ItemType Directory -Force -Path $downloaderConfigDir | Out-Null

    $defaults = [ordered]@{
        protocol         = 'HTTP'
        host             = ''
        port             = 21
        url              = 'https://seb.omao.noaa.gov/pub/flight/aamps_ingest/avaps/received/'
        username         = ''
        password         = ''
        passive          = $true
        remote_dir       = '/'
        local_dir        = ''
        interval_seconds = 60
        seen_files       = @()
    }

    $config = $null
    if (Test-Path $DownloaderConfig) {
        try {
            $config = Get-Content -Path $DownloaderConfig -Raw | ConvertFrom-Json
        }
        catch {
            Write-Warning "Existing TAG Downloader config at $DownloaderConfig is not valid JSON; rebuilding from defaults."
            $config = $null
        }
    }

    if (-not $config) {
        $config = [pscustomobject]$defaults
    }
    else {
        foreach ($key in $defaults.Keys) {
            if (-not (Get-Member -InputObject $config -Name $key -MemberType NoteProperty)) {
                $config | Add-Member -MemberType NoteProperty -Name $key -Value $defaults[$key]
            }
        }
    }

    $config.remote_dir = "/$StormId"
    $config.local_dir  = $RawDir
    $config.seen_files = @()

    ($config | ConvertTo-Json -Depth 5) | Set-Content -Path $DownloaderConfig -Encoding UTF8
    Write-Host "TAG Downloader config updated: $DownloaderConfig"
}
catch {
    Write-Warning "Failed to update TAG Downloader config ($DownloaderConfig): $($_.Exception.Message)"
}

# --- launch apps ---
Write-Host ""
if (Test-Path $DownloaderExe) {
    Write-Host "Starting TAG Downloader..."
    Start-Process -FilePath $DownloaderExe -WorkingDirectory (Split-Path $DownloaderExe -Parent)
}
else {
    Write-Warning "TAG Downloader executable not found at $DownloaderExe. Run Install-TagDownloader.ps1 first."
}

$aspenExe = $null
if (Test-Path $AspenPathMarker) {
    $candidate = (Get-Content -Path $AspenPathMarker -Raw).Trim()
    if ($candidate -and (Test-Path $candidate)) {
        $aspenExe = $candidate
    }
}

if ($aspenExe) {
    Write-Host "Starting Aspen..."
    # -Wait ties this script's lifetime to Aspen's, mirroring the Linux
    # script's `exec aspen` handoff (the console stays open afterward only
    # because the launching shortcut uses -NoExit, so warnings stay readable).
    Start-Process -FilePath $aspenExe -WorkingDirectory (Split-Path $aspenExe -Parent) -Wait
}
else {
    Write-Warning "Aspen path not found (checked $AspenPathMarker). Launch Aspen once, then run Install-Aspen.ps1 again so it can locate and save the path, or edit $AspenPathMarker by hand with the full path to Aspen.exe."
}
