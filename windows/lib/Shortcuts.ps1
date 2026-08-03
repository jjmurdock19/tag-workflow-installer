# Shortcuts.ps1 - dot-sourceable helpers for creating per-user Desktop/Start
# Menu shortcuts (.lnk files via the WScript.Shell COM object).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Creates a .lnk shortcut under Desktop\TAG and/or Start Menu\Programs\TAG.
function New-TagShortcut {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$TargetPath,
        [string]$Arguments = '',
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [string]$IconLocation = '',
        [switch]$SkipDesktop,
        [switch]$SkipStartMenu
    )

    $shell = $null
    try {
        $desktopDir   = Join-Path ([Environment]::GetFolderPath('Desktop')) 'TAG'
        $startMenuDir = Join-Path ([Environment]::GetFolderPath('Programs')) 'TAG'

        if (-not $SkipDesktop)   { New-Item -ItemType Directory -Force -Path $desktopDir   | Out-Null }
        if (-not $SkipStartMenu) { New-Item -ItemType Directory -Force -Path $startMenuDir | Out-Null }

        $shell = New-Object -ComObject WScript.Shell

        $lnkPaths = @()
        if (-not $SkipDesktop)   { $lnkPaths += (Join-Path $desktopDir "$Name.lnk") }
        if (-not $SkipStartMenu) { $lnkPaths += (Join-Path $startMenuDir "$Name.lnk") }

        foreach ($lnkPath in $lnkPaths) {
            $sc = $shell.CreateShortcut($lnkPath)
            $sc.TargetPath = $TargetPath
            if ($Arguments) { $sc.Arguments = $Arguments }
            $sc.WorkingDirectory = $WorkingDirectory
            if ($IconLocation) { $sc.IconLocation = $IconLocation }
            $sc.Save()
            Write-Host "  shortcut: $lnkPath"
        }
    }
    catch {
        Write-Warning "Could not create shortcut(s) for '$Name': $($_.Exception.Message)"
    }
    finally {
        if ($shell) {
            [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
        }
    }
}

# Creates the "TAG Workflow" shortcut: opens a console running Tag-Setup.ps1.
function New-TagWorkflowShortcut {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TagSetupScriptPath,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [switch]$SkipDesktop,
        [switch]$SkipStartMenu
    )

    $hostExe = $null
    try {
        $hostExe = (Get-Process -Id $PID -ErrorAction Stop).Path
    } catch { }
    if (-not $hostExe -or -not (Test-Path $hostExe)) {
        $cmd = Get-Command powershell.exe -ErrorAction SilentlyContinue
        $hostExe = if ($cmd) { $cmd.Source } else { 'powershell.exe' }
    }

    $arguments = "-NoExit -ExecutionPolicy Bypass -File `"$TagSetupScriptPath`""

    New-TagShortcut -Name 'TAG Workflow' -TargetPath $hostExe -Arguments $arguments `
        -WorkingDirectory $WorkingDirectory -IconLocation "$hostExe,0" `
        -SkipDesktop:$SkipDesktop -SkipStartMenu:$SkipStartMenu
}
