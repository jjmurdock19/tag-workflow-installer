#
# Shortcuts.ps1 - dot-sourceable helpers for creating per-user Desktop/Start Menu
# shortcuts. Mirrors the intent of tag-shortcuts-lib.sh's make_shortcut, adapted
# to Windows .lnk files via the WScript.Shell COM object.
#
# All locations used here are per-user (no admin rights required):
#   Desktop:    [Environment]::GetFolderPath('Desktop')
#   Start Menu: [Environment]::GetFolderPath('Programs')
#               (the per-user "Start Menu\Programs" folder - this is the folder
#               Windows actually indexes into the Start Menu app list; the bare
#               'StartMenu' special folder is one level up and is NOT reliably
#               shown in the app list, so 'Programs' is used instead. Neither
#               requires admin; 'CommonPrograms'/'CommonStartMenu' are avoided
#               on purpose since those are machine-wide.)
#
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-TagShortcut {
    <#
    Creates a .lnk shortcut under Desktop\TAG and/or Start Menu\Programs\TAG.
    Best-effort: failures are reported as warnings, never terminate the caller.
    #>
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

function New-TagWorkflowShortcut {
    <#
    Creates the primary "TAG Workflow" entry point: a shortcut that opens a
    visible PowerShell console running Tag-Setup.ps1. -NoExit keeps the window
    open after the script finishes so the user can read prompts/warnings.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TagSetupScriptPath,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [switch]$SkipDesktop,
        [switch]$SkipStartMenu
    )

    # Use the exe of the currently running PowerShell host (works for both
    # Windows PowerShell 5.1's powershell.exe and PowerShell 7's pwsh.exe).
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
