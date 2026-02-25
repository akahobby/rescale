#Requires -Version 5.1
<#
.SYNOPSIS
    rescale - Resolution profile manager for gaming and desktop use.
.DESCRIPTION
    Switches between configured game/native resolutions, applies NVIDIA NV_Modes,
    and optionally toggles configured secondary displays for gaming/normal modes.
.EXAMPLE
    .\rescale.ps1 game
.EXAMPLE
    .\rescale.ps1 native
.EXAMPLE
    .\rescale.ps1 status
#>

param(
    [Parameter(Position = 0)]
    [ValidateSet('game', 'native', 'fix-nvidia', 'gaming-mode', 'normal-mode', 'status', 'config', 'help')]
    [string]$Command = 'help'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
$ProjectRoot = Split-Path -Parent $ScriptDir

$Paths = @{
    NirCmd   = Join-Path $ProjectRoot 'bin\nircmd.exe'
    Config   = Join-Path $ProjectRoot 'config\settings.json'
    NVScript = Join-Path $ScriptDir 'NV_Modes.ps1'
}

function Assert-PathExists {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not (Test-Path -Path $Path)) {
        throw "$Label not found: $Path"
    }
}

function Assert-ResolutionObject {
    param(
        [Parameter(Mandatory = $true)][psobject]$Config,
        [Parameter(Mandatory = $true)][ValidateSet('native', 'game')][string]$ProfileName
    )

    if (-not $Config.PSObject.Properties.Name.Contains($ProfileName)) {
        throw "Missing '$ProfileName' in config file: $($Paths.Config)"
    }

    $profile = $Config.$ProfileName
    foreach ($key in @('width', 'height')) {
        if (-not $profile.PSObject.Properties.Name.Contains($key)) {
            throw "Missing '$ProfileName.$key' in config file: $($Paths.Config)"
        }
    }
}

function Read-Config {
    Assert-PathExists -Path $Paths.Config -Label 'Config file'
    $cfg = Get-Content -Path $Paths.Config -Raw | ConvertFrom-Json

    if (-not $cfg.PSObject.Properties.Name.Contains('bitDepth')) {
        throw "Missing 'bitDepth' in config file: $($Paths.Config)"
    }

    Assert-ResolutionObject -Config $cfg -ProfileName 'native'
    Assert-ResolutionObject -Config $cfg -ProfileName 'game'

    return $cfg
}

function Write-Config {
    param([Parameter(Mandatory = $true)][psobject]$Config)
    $Config | ConvertTo-Json -Depth 4 | Set-Content -Path $Paths.Config -Encoding UTF8
}

function Get-CurrentResolution {
    Add-Type -AssemblyName System.Windows.Forms
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    return @{ Width = $bounds.Width; Height = $bounds.Height }
}

function Set-DisplayResolution {
    param(
        [Parameter(Mandatory = $true)][ValidateRange(640, 16384)][int]$Width,
        [Parameter(Mandatory = $true)][ValidateRange(480, 16384)][int]$Height,
        [Parameter(Mandatory = $true)][ValidateRange(16, 64)][int]$BitDepth
    )

    Assert-PathExists -Path $Paths.NirCmd -Label 'nircmd.exe'
    Write-Host "Changing resolution to ${Width}x${Height} (${BitDepth}-bit)"
    Start-Process -FilePath $Paths.NirCmd -ArgumentList "setdisplay $Width $Height $BitDepth" -Wait -NoNewWindow
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Restart-Elevated {
    param([Parameter(Mandatory = $true)][string]$ScriptArgs)

    $powerShellExe = (Get-Process -Id $PID).Path
    Start-Process -FilePath $powerShellExe -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$($MyInvocation.ScriptName)`" $ScriptArgs" -WindowStyle Hidden
    exit
}

function Invoke-NVModesWithElevation {
    Assert-PathExists -Path $Paths.NVScript -Label 'NV_Modes script'

    if (-not (Test-IsAdmin)) {
        $powerShellExe = (Get-Process -Id $PID).Path
        Start-Process -FilePath $powerShellExe -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$($Paths.NVScript)`"" -Wait
        return
    }

    & $Paths.NVScript
}

function Invoke-NvidiaFix {
    if (-not (Test-IsAdmin)) {
        Restart-Elevated -ScriptArgs 'fix-nvidia'
        return
    }

    Assert-PathExists -Path $Paths.NVScript -Label 'NV_Modes script'
    & $Paths.NVScript
}

function Set-ProfileResolution {
    param([Parameter(Mandatory = $true)][ValidateSet('game', 'native')][string]$ProfileName)

    $cfg = Read-Config
    Set-DisplayResolution -Width $cfg.$ProfileName.width -Height $cfg.$ProfileName.height -BitDepth $cfg.bitDepth
}

function Get-SecondaryDisplayIds {
    param([Parameter(Mandatory = $true)][psobject]$Config)

    if (-not $Config.PSObject.Properties.Name.Contains('secondaryDisplays')) {
        return @()
    }

    if ($null -eq $Config.secondaryDisplays) {
        return @()
    }

    return @($Config.secondaryDisplays)
}

function Set-SecondaryDisplays {
    param([Parameter(Mandatory = $true)][array]$DisplayIds)

    if ($DisplayIds.Count -eq 0) {
        Write-Host 'No secondary displays configured; skipping display toggle.'
        return
    }

    Assert-PathExists -Path $Paths.NirCmd -Label 'nircmd.exe'
    foreach ($displayId in $DisplayIds) {
        Start-Process -FilePath $Paths.NirCmd -ArgumentList "setdisplay monitor:$displayId 0 0 0" -Wait -NoNewWindow
    }
}

function New-LauncherFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$WorkingDirectoryExpression,
        [Parameter(Mandatory = $true)][string]$ScriptPathExpression,
        [Parameter(Mandatory = $true)][string]$CliCommand
    )

    $content = @(
        '@echo off',
        "cd /d `"$WorkingDirectoryExpression`"",
        "powershell -NoProfile -ExecutionPolicy Bypass -File `"$ScriptPathExpression`" $CliCommand",
        'if errorlevel 1 (',
        '  echo.',
        '  echo Command failed. Press any key to close this window.',
        '  pause >nul',
        ')',
        'exit'
    ) -join "`r`n"

    Set-Content -Path $Path -Value $content -Encoding ASCII
}

function New-LauncherFiles {
    $launcherDir = Join-Path $ProjectRoot 'launchers'
    if (-not (Test-Path -Path $launcherDir)) {
        New-Item -ItemType Directory -Path $launcherDir -Force | Out-Null
    }

    New-LauncherFile -Path (Join-Path $launcherDir 'ResolutionTool Config.bat') -WorkingDirectoryExpression '%~dp0..' -ScriptPathExpression '%~dp0..\scripts\rescale.ps1' -CliCommand 'config'
    New-LauncherFile -Path (Join-Path $launcherDir 'Enable Custom Resolution.bat') -WorkingDirectoryExpression '%~dp0..' -ScriptPathExpression '%~dp0..\scripts\rescale.ps1' -CliCommand 'game'
    New-LauncherFile -Path (Join-Path $launcherDir 'Restore Native Resolution.bat') -WorkingDirectoryExpression '%~dp0..' -ScriptPathExpression '%~dp0..\scripts\rescale.ps1' -CliCommand 'native'

    $rootDir = Split-Path -Parent $ProjectRoot
    New-LauncherFile -Path (Join-Path $rootDir 'Enable Custom Resolution.bat') -WorkingDirectoryExpression '%~dp0' -ScriptPathExpression '%~dp0app\scripts\rescale.ps1' -CliCommand 'game'
    New-LauncherFile -Path (Join-Path $rootDir 'Restore Native Resolution.bat') -WorkingDirectoryExpression '%~dp0' -ScriptPathExpression '%~dp0app\scripts\rescale.ps1' -CliCommand 'native'
}

function Show-ConfigWindow {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $cfg = Read-Config

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'ResolutionTool Config'
    $form.Size = New-Object System.Drawing.Size(340, 220)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false

    $lblWidth = New-Object System.Windows.Forms.Label
    $lblWidth.Text = 'Game resolution width:'
    $lblWidth.Location = New-Object System.Drawing.Point(20, 20)
    $lblWidth.Size = New-Object System.Drawing.Size(160, 20)
    $form.Controls.Add($lblWidth)

    $txtWidth = New-Object System.Windows.Forms.TextBox
    $txtWidth.Text = "$($cfg.game.width)"
    $txtWidth.Location = New-Object System.Drawing.Point(190, 18)
    $txtWidth.Size = New-Object System.Drawing.Size(120, 20)
    $form.Controls.Add($txtWidth)

    $lblHeight = New-Object System.Windows.Forms.Label
    $lblHeight.Text = 'Game resolution height:'
    $lblHeight.Location = New-Object System.Drawing.Point(20, 55)
    $lblHeight.Size = New-Object System.Drawing.Size(160, 20)
    $form.Controls.Add($lblHeight)

    $txtHeight = New-Object System.Windows.Forms.TextBox
    $txtHeight.Text = "$($cfg.game.height)"
    $txtHeight.Location = New-Object System.Drawing.Point(190, 53)
    $txtHeight.Size = New-Object System.Drawing.Size(120, 20)
    $form.Controls.Add($txtHeight)

    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = 'Save and apply'
    $btnSave.Size = New-Object System.Drawing.Size(290, 35)
    $btnSave.Location = New-Object System.Drawing.Point(20, 95)
    $form.Controls.Add($btnSave)
    $form.AcceptButton = $btnSave

    $lblNote = New-Object System.Windows.Forms.Label
    $lblNote.Text = 'Tip: Restart Windows once after the first NV_Modes update.'
    $lblNote.Location = New-Object System.Drawing.Point(20, 140)
    $lblNote.Size = New-Object System.Drawing.Size(300, 30)
    $form.Controls.Add($lblNote)

    $btnSave.Add_Click({
        $w = $txtWidth.Text.Trim()
        $h = $txtHeight.Text.Trim()

        if ($w -notmatch '^\d+$' -or $h -notmatch '^\d+$') {
            [System.Windows.Forms.MessageBox]::Show(
                'Width and height must be whole numbers.',
                'Validation error',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            return
        }

        try {
            $cfg.game.width = [int]$w
            $cfg.game.height = [int]$h
            Write-Config -Config $cfg

            Invoke-NVModesWithElevation
            New-LauncherFiles

            [System.Windows.Forms.MessageBox]::Show(
                'Saved. Launchers were generated and NV_Modes was applied.',
                'Success',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )

            $form.Close()
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                $_.Exception.Message,
                'Error',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
    })

    [void]$form.ShowDialog()
}

function Show-Status {
    $res = Get-CurrentResolution
    $cfg = Read-Config

    Write-Host ("Current   : {0}x{1}" -f $res.Width, $res.Height)
    Write-Host ("Native    : {0}x{1}" -f $cfg.native.width, $cfg.native.height)
    Write-Host ("Game      : {0}x{1}" -f $cfg.game.width, $cfg.game.height)
    Write-Host ("Bit depth : {0}" -f $cfg.bitDepth)
}

function Show-Help {
    Write-Host @"
rescale - Resolution Profile Manager

Usage:
  rescale <command>

Commands:
  game          Set gaming resolution
  native        Restore native resolution
  fix-nvidia    Apply NV_Modes registry fix (requires admin)
  gaming-mode   Toggle configured secondary displays and set game resolution
  normal-mode   Toggle configured secondary displays and restore native resolution
  status        Show current and configured resolutions
  config        Open settings, apply NV_Modes, and regenerate launchers
  help          Show this help message

Config file:
  app\config\settings.json
"@
}

try {
    switch ($Command) {
        'game' { Set-ProfileResolution -ProfileName 'game' }
        'native' { Set-ProfileResolution -ProfileName 'native' }
        'fix-nvidia' { Invoke-NvidiaFix }
        'gaming-mode' {
            $cfg = Read-Config
            Set-SecondaryDisplays -DisplayIds (Get-SecondaryDisplayIds -Config $cfg)
            Set-ProfileResolution -ProfileName 'game'
        }
        'normal-mode' {
            $cfg = Read-Config
            Set-SecondaryDisplays -DisplayIds (Get-SecondaryDisplayIds -Config $cfg)
            Set-ProfileResolution -ProfileName 'native'
        }
        'status' { Show-Status }
        'config' { Show-ConfigWindow }
        default { Show-Help }
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
