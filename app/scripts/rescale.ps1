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

$script:WinFormsLoaded = $false

function Import-WinFormsAssemblies {
    if ($script:WinFormsLoaded) {
        return
    }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $script:WinFormsLoaded = $true
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

function Invoke-ExternalProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$ArgumentList,
        [Parameter(Mandatory = $true)][string]$OperationName,
        [switch]$RunAsAdministrator
    )

    $startParams = @{
        FilePath     = $FilePath
        ArgumentList = $ArgumentList
        Wait         = $true
        PassThru     = $true
        ErrorAction  = 'Stop'
    }

    if ($RunAsAdministrator) {
        $startParams.Verb = 'RunAs'
    }
    else {
        $startParams.NoNewWindow = $true
    }

    $process = Start-Process @startParams
    if ($process.ExitCode -ne 0) {
        throw "$OperationName failed with exit code $($process.ExitCode)."
    }
}

function Get-CurrentResolution {
    Import-WinFormsAssemblies
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    return @{ Width = $bounds.Width; Height = $bounds.Height }
}

function Get-GreatestCommonDivisor {
    param(
        [Parameter(Mandatory = $true)][int]$A,
        [Parameter(Mandatory = $true)][int]$B
    )

    $x = [Math]::Abs($A)
    $y = [Math]::Abs($B)

    while ($y -ne 0) {
        $tmp = $y
        $y = $x % $y
        $x = $tmp
    }

    if ($x -eq 0) {
        return 1
    }

    return $x
}

function Get-ResolutionSummaryText {
    param(
        [Parameter(Mandatory = $true)][int]$Width,
        [Parameter(Mandatory = $true)][int]$Height,
        [Parameter(Mandatory = $true)][int]$NativeWidth,
        [Parameter(Mandatory = $true)][int]$NativeHeight
    )

    $gcd = Get-GreatestCommonDivisor -A $Width -B $Height
    $ratioW = [int]($Width / $gcd)
    $ratioH = [int]($Height / $gcd)
    $ratioDecimal = [Math]::Round(($Width / [double]$Height), 3)

    $widthPercent = [Math]::Round(($Width / [double]$NativeWidth) * 100, 1)
    $heightPercent = [Math]::Round(($Height / [double]$NativeHeight) * 100, 1)

    return "Aspect ratio: ${ratioW}:${ratioH} ($ratioDecimal)   |   Size vs native: ${widthPercent}% width, ${heightPercent}% height"
}

function Set-DisplayResolution {
    param(
        [Parameter(Mandatory = $true)][ValidateRange(640, 16384)][int]$Width,
        [Parameter(Mandatory = $true)][ValidateRange(480, 16384)][int]$Height,
        [Parameter(Mandatory = $true)][ValidateRange(16, 64)][int]$BitDepth
    )

    Assert-PathExists -Path $Paths.NirCmd -Label 'nircmd.exe'
    Write-Host "Changing resolution to ${Width}x${Height} (${BitDepth}-bit)"
    Invoke-ExternalProcess -FilePath $Paths.NirCmd -ArgumentList "setdisplay $Width $Height $BitDepth" -OperationName 'Display resolution update'
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-NVModesWithElevation {
    Assert-PathExists -Path $Paths.NVScript -Label 'NV_Modes script'

    $powerShellExe = (Get-Process -Id $PID).Path
    $argumentList = "-NoProfile -ExecutionPolicy Bypass -File `"$($Paths.NVScript)`""

    if (-not (Test-IsAdmin)) {
        Invoke-ExternalProcess -FilePath $powerShellExe -ArgumentList $argumentList -OperationName 'NV_Modes update' -RunAsAdministrator
        return
    }

    Invoke-ExternalProcess -FilePath $powerShellExe -ArgumentList $argumentList -OperationName 'NV_Modes update'
}

function Invoke-NvidiaFix {
    Invoke-NVModesWithElevation
}

function Set-ProfileResolution {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('game', 'native')][string]$ProfileName,
        [psobject]$Config
    )

    $cfg = if ($PSBoundParameters.ContainsKey('Config')) { $Config } else { Read-Config }
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
        Invoke-ExternalProcess -FilePath $Paths.NirCmd -ArgumentList "setdisplay monitor:$displayId 0 0 0" -OperationName "Secondary display toggle (monitor:$displayId)"
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
    Import-WinFormsAssemblies
    $cfg = Read-Config
    $current = Get-CurrentResolution
    $nativeWidth = [int]$cfg.native.width
    $nativeHeight = [int]$cfg.native.height
    $initialWidth = [Math]::Min(16384, [Math]::Max(640, [int]$cfg.game.width))
    $initialHeight = [Math]::Min(16384, [Math]::Max(480, [int]$cfg.game.height))

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'ResolutionTool Config'
    $form.Size = New-Object System.Drawing.Size(520, 360)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $lblHeader = New-Object System.Windows.Forms.Label
    $lblHeader.Text = 'Game Resolution Setup'
    $lblHeader.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
    $lblHeader.Location = New-Object System.Drawing.Point(18, 12)
    $lblHeader.Size = New-Object System.Drawing.Size(320, 26)
    $form.Controls.Add($lblHeader)

    $lblContext = New-Object System.Windows.Forms.Label
    $lblContext.Text = "Current display: $($current.Width)x$($current.Height)   |   Native profile: ${nativeWidth}x${nativeHeight}"
    $lblContext.Location = New-Object System.Drawing.Point(20, 38)
    $lblContext.Size = New-Object System.Drawing.Size(470, 20)
    $form.Controls.Add($lblContext)

    $group = New-Object System.Windows.Forms.GroupBox
    $group.Text = 'Target game resolution'
    $group.Location = New-Object System.Drawing.Point(20, 64)
    $group.Size = New-Object System.Drawing.Size(470, 175)
    $form.Controls.Add($group)

    $lblPreset = New-Object System.Windows.Forms.Label
    $lblPreset.Text = 'Preset:'
    $lblPreset.Location = New-Object System.Drawing.Point(16, 30)
    $lblPreset.Size = New-Object System.Drawing.Size(80, 22)
    $group.Controls.Add($lblPreset)

    $cmbPreset = New-Object System.Windows.Forms.ComboBox
    $cmbPreset.DropDownStyle = 'DropDownList'
    $cmbPreset.Location = New-Object System.Drawing.Point(110, 27)
    $cmbPreset.Size = New-Object System.Drawing.Size(340, 24)
    $group.Controls.Add($cmbPreset)

    $lblWidth = New-Object System.Windows.Forms.Label
    $lblWidth.Text = 'Width:'
    $lblWidth.Location = New-Object System.Drawing.Point(16, 67)
    $lblWidth.Size = New-Object System.Drawing.Size(80, 22)
    $group.Controls.Add($lblWidth)

    $numWidth = New-Object System.Windows.Forms.NumericUpDown
    $numWidth.Minimum = [decimal]640
    $numWidth.Maximum = [decimal]16384
    $numWidth.Increment = [decimal]2
    $numWidth.ThousandsSeparator = $true
    $numWidth.Location = New-Object System.Drawing.Point(110, 64)
    $numWidth.Size = New-Object System.Drawing.Size(140, 24)
    $numWidth.Value = [decimal]$initialWidth
    $group.Controls.Add($numWidth)

    $lblHeight = New-Object System.Windows.Forms.Label
    $lblHeight.Text = 'Height:'
    $lblHeight.Location = New-Object System.Drawing.Point(16, 102)
    $lblHeight.Size = New-Object System.Drawing.Size(80, 22)
    $group.Controls.Add($lblHeight)

    $numHeight = New-Object System.Windows.Forms.NumericUpDown
    $numHeight.Minimum = [decimal]480
    $numHeight.Maximum = [decimal]16384
    $numHeight.Increment = [decimal]2
    $numHeight.ThousandsSeparator = $true
    $numHeight.Location = New-Object System.Drawing.Point(110, 99)
    $numHeight.Size = New-Object System.Drawing.Size(140, 24)
    $numHeight.Value = [decimal]$initialHeight
    $group.Controls.Add($numHeight)

    $btnUseCurrent = New-Object System.Windows.Forms.Button
    $btnUseCurrent.Text = 'Use current display'
    $btnUseCurrent.Location = New-Object System.Drawing.Point(270, 81)
    $btnUseCurrent.Size = New-Object System.Drawing.Size(180, 30)
    $group.Controls.Add($btnUseCurrent)

    $lblSummary = New-Object System.Windows.Forms.Label
    $lblSummary.Location = New-Object System.Drawing.Point(16, 136)
    $lblSummary.Size = New-Object System.Drawing.Size(434, 30)
    $lblSummary.Text = Get-ResolutionSummaryText -Width $initialWidth -Height $initialHeight -NativeWidth $nativeWidth -NativeHeight $nativeHeight
    $group.Controls.Add($lblSummary)

    $lblNote = New-Object System.Windows.Forms.Label
    $lblNote.Text = 'Tip: Restart Windows once after the first NV_Modes update.'
    $lblNote.Location = New-Object System.Drawing.Point(20, 246)
    $lblNote.Size = New-Object System.Drawing.Size(470, 20)
    $form.Controls.Add($lblNote)

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Text = 'Ready.'
    $lblStatus.Location = New-Object System.Drawing.Point(20, 268)
    $lblStatus.Size = New-Object System.Drawing.Size(470, 20)
    $form.Controls.Add($lblStatus)

    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = 'Save and apply'
    $btnSave.Size = New-Object System.Drawing.Size(220, 36)
    $btnSave.Location = New-Object System.Drawing.Point(20, 292)
    $form.Controls.Add($btnSave)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = 'Cancel'
    $btnCancel.Size = New-Object System.Drawing.Size(120, 36)
    $btnCancel.Location = New-Object System.Drawing.Point(370, 292)
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($btnCancel)

    $form.AcceptButton = $btnSave
    $form.CancelButton = $btnCancel

    $presetEntries = @()
    $presetCandidates = @(
        @{ Label = 'Current display'; Width = $current.Width; Height = $current.Height },
        @{ Label = 'Native profile'; Width = $nativeWidth; Height = $nativeHeight },
        @{ Label = 'Common stretched'; Width = 2100; Height = 1440 },
        @{ Label = 'Common stretched'; Width = 1566; Height = 1080 },
        @{ Label = 'Common stretched'; Width = 1280; Height = 880 },
        @{ Label = 'Full HD baseline'; Width = 1920; Height = 1080 }
    )
    $seenResolutions = @{}
    foreach ($candidate in $presetCandidates) {
        $resolutionKey = "{0}x{1}" -f [int]$candidate.Width, [int]$candidate.Height
        if ($seenResolutions.ContainsKey($resolutionKey)) {
            continue
        }

        $seenResolutions[$resolutionKey] = $true
        $entry = [pscustomobject]@{
            Label  = $candidate.Label
            Width  = [int]$candidate.Width
            Height = [int]$candidate.Height
        }
        $presetEntries += $entry
        [void]$cmbPreset.Items.Add("{0} ({1}x{2})" -f $entry.Label, $entry.Width, $entry.Height)
    }

    $updateSummary = {
        $lblSummary.Text = Get-ResolutionSummaryText -Width ([int]$numWidth.Value) -Height ([int]$numHeight.Value) -NativeWidth $nativeWidth -NativeHeight $nativeHeight
    }

    $numWidth.Add_ValueChanged($updateSummary)
    $numHeight.Add_ValueChanged($updateSummary)

    $cmbPreset.Add_SelectedIndexChanged({
        if ($cmbPreset.SelectedIndex -lt 0) {
            return
        }

        $selected = $presetEntries[$cmbPreset.SelectedIndex]
        $numWidth.Value = [decimal]$selected.Width
        $numHeight.Value = [decimal]$selected.Height
    })

    $btnUseCurrent.Add_Click({
        $liveResolution = Get-CurrentResolution
        $numWidth.Value = [decimal]([Math]::Min(16384, [Math]::Max(640, [int]$liveResolution.Width)))
        $numHeight.Value = [decimal]([Math]::Min(16384, [Math]::Max(480, [int]$liveResolution.Height)))
        $cmbPreset.SelectedIndex = -1
    })

    $btnSave.Add_Click({
        $btnSave.Enabled = $false
        $form.UseWaitCursor = $true
        $lblStatus.Text = 'Applying NV_Modes and generating launchers...'

        try {
            $cfg.game.width = [int]$numWidth.Value
            $cfg.game.height = [int]$numHeight.Value
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
        finally {
            $btnSave.Enabled = $true
            $form.UseWaitCursor = $false
            $lblStatus.Text = 'Ready.'
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
            Set-ProfileResolution -ProfileName 'game' -Config $cfg
        }
        'normal-mode' {
            $cfg = Read-Config
            Set-SecondaryDisplays -DisplayIds (Get-SecondaryDisplayIds -Config $cfg)
            Set-ProfileResolution -ProfileName 'native' -Config $cfg
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
