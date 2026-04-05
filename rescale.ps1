#Requires -Version 5.1
<#
.SYNOPSIS
  Switch Windows display resolution (primary display). For gaming stretched modes.
.PARAMETER Configure
  Open setup window (default if no mode switch is requested).
.PARAMETER Game
  Apply saved game resolution.
.PARAMETER Desktop
  Apply saved desktop (native) resolution.
#>
param(
    [switch]$Configure,
    [switch]$Game,
    [switch]$Desktop
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $PSCommandPath
if (-not $ScriptDir) { $ScriptDir = $PWD.Path }
$RescaleScriptPath = $PSCommandPath
if (-not $RescaleScriptPath) { $RescaleScriptPath = Join-Path $ScriptDir 'rescale.ps1' }
$ConfigPath = Join-Path $ScriptDir 'rescale.config.json'
$GameBat = Join-Path $ScriptDir 'Switch to Game Resolution.bat'
$DesktopBat = Join-Path $ScriptDir 'Switch to Desktop Resolution.bat'

#region Display API (user32)
if (-not ([System.Management.Automation.PSTypeName]'RescaleDisplay').Type) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class RescaleDisplay
{
    private const int ENUM_CURRENT_SETTINGS = -1;
    private const int DM_PELSWIDTH = 0x80000;
    private const int DM_PELSHEIGHT = 0x100000;
    private const int DM_BITSPERPEL = 0x40000;
    private const int DM_DISPLAYFREQUENCY = 0x400000;

    [DllImport("user32.dll", CharSet = CharSet.Ansi)]
    private static extern int EnumDisplaySettings(string lpszDeviceName, int iModeNum, ref DEVMODE lpDevMode);

    [DllImport("user32.dll", CharSet = CharSet.Ansi)]
    private static extern int ChangeDisplaySettingsEx(string lpszDeviceName, ref DEVMODE lpDevMode, IntPtr hwnd, int dwflags, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    private struct DEVMODE
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmDeviceName;
        public short dmSpecVersion;
        public short dmDriverVersion;
        public short dmSize;
        public short dmDriverExtra;
        public int dmFields;
        public int dmPositionX;
        public int dmPositionY;
        public int dmDisplayOrientation;
        public int dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel;
        public int dmPelsWidth;
        public int dmPelsHeight;
        public int dmDisplayFlags;
        public int dmDisplayFrequency;
        public int dmICMMethod;
        public int dmICMIntent;
        public int dmMediaType;
        public int dmDitherType;
        public int dmReserved1;
        public int dmReserved2;
        public int dmPanningWidth;
        public int dmPanningHeight;
    }

    public static bool TryGetCurrentResolution(out int width, out int height, out int bpp, out int hz)
    {
        width = height = bpp = hz = 0;
        var dm = new DEVMODE();
        dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        if (EnumDisplaySettings(null, ENUM_CURRENT_SETTINGS, ref dm) == 0)
            return false;
        width = dm.dmPelsWidth;
        height = dm.dmPelsHeight;
        bpp = dm.dmBitsPerPel;
        hz = dm.dmDisplayFrequency;
        return true;
    }

    public static int SetResolution(int width, int height)
    {
        var dm = new DEVMODE();
        dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        if (EnumDisplaySettings(null, ENUM_CURRENT_SETTINGS, ref dm) == 0)
            return -1;
        dm.dmPelsWidth = width;
        dm.dmPelsHeight = height;
        dm.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT | DM_BITSPERPEL | DM_DISPLAYFREQUENCY;
        return ChangeDisplaySettingsEx(null, ref dm, IntPtr.Zero, 0, IntPtr.Zero);
    }
}
'@
}
#endregion

function Get-RescaleConfig {
    if (-not (Test-Path -LiteralPath $ConfigPath)) { return $null }
    try {
        Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    } catch { return $null }
}

function Save-RescaleConfig {
    param(
        [int]$NativeWidth,
        [int]$NativeHeight,
        [int]$GameWidth,
        [int]$GameHeight
    )
    $obj = [ordered]@{
        NativeWidth  = $NativeWidth
        NativeHeight = $NativeHeight
        GameWidth    = $GameWidth
        GameHeight   = $GameHeight
    }
    ($obj | ConvertTo-Json -Compress) | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
}

function Write-SwitchBatchFiles {
    param([string]$Ps1Path)
    $gameBody = @"
@echo off
title Game resolution
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$Ps1Path" -Game
if errorlevel 1 pause
"@
    $deskBody = @"
@echo off
title Desktop resolution
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$Ps1Path" -Desktop
if errorlevel 1 pause
"@
    Set-Content -LiteralPath $GameBat -Value $gameBody -Encoding ASCII
    Set-Content -LiteralPath $DesktopBat -Value $deskBody -Encoding ASCII
}

function Invoke-ResolutionSwitch {
    param([int]$Width, [int]$Height, [string]$Label)
    Add-Type -AssemblyName System.Windows.Forms
    if ($Width -lt 640 -or $Height -lt 480) {
        Write-Error "Invalid dimensions: ${Width}x${Height}"
    }
    $code = [RescaleDisplay]::SetResolution($Width, $Height)
    if ($code -ne 0) {
        $msg = switch ($code) {
            1 { 'Windows requested a restart for this mode.' }
            -1 { 'EnumDisplaySettings failed.' }
            -2 { 'Mode not available (BADMODE). Add this resolution in NVIDIA Control Panel (Customize) or CRU, then try again.' }
            default { "ChangeDisplaySettingsEx returned $code." }
        }
        [System.Windows.Forms.MessageBox]::Show(
            $msg,
            "Rescale - $Label",
            'OK',
            'Error'
        ) | Out-Null
        exit 1
    }
    exit 0
}

# --- CLI switches ---
if ($Game) {
    $cfg = Get-RescaleConfig
    if (-not $cfg) {
        [System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms') | Out-Null
        [System.Windows.Forms.MessageBox]::Show(
            "No configuration found. Run rescale.bat first.",
            'Rescale',
            'OK',
            'Information'
        ) | Out-Null
        exit 1
    }
    Invoke-ResolutionSwitch -Width $cfg.GameWidth -Height $cfg.GameHeight -Label 'Game'
}

if ($Desktop) {
    $cfg = Get-RescaleConfig
    if (-not $cfg) {
        [System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms') | Out-Null
        [System.Windows.Forms.MessageBox]::Show(
            "No configuration found. Run rescale.bat first.",
            'Rescale',
            'OK',
            'Information'
        ) | Out-Null
        exit 1
    }
    Invoke-ResolutionSwitch -Width $cfg.NativeWidth -Height $cfg.NativeHeight -Label 'Desktop'
}

# Default: configuration UI
if (-not $Configure -and -not $Game -and -not $Desktop) {
    $Configure = $true
}

if (-not $Configure) { exit 0 }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$presets = @(
    @{ Label = '1440 x 1080 (4:3 @ 1080p)'; W = 1440; H = 1080 },
    @{ Label = '1280 x 960'; W = 1280; H = 960 },
    @{ Label = '1024 x 768'; W = 1024; H = 768 },
    @{ Label = '1728 x 1080 (16:10-ish stretch)'; W = 1728; H = 1080 },
    @{ Label = '1280 x 1024 (5:4)'; W = 1280; H = 1024 },
    @{ Label = '1152 x 864 (4:3)'; W = 1152; H = 864 },
    @{ Label = '960 x 720'; W = 960; H = 720 },
    @{ Label = '1680 x 1050'; W = 1680; H = 1050 }
)

$DM = @{
    Bg        = [System.Drawing.Color]::FromArgb(45, 45, 48)
    Surface   = [System.Drawing.Color]::FromArgb(30, 30, 32)
    Text      = [System.Drawing.Color]::FromArgb(230, 230, 235)
    Muted     = [System.Drawing.Color]::FromArgb(150, 155, 165)
    Btn       = [System.Drawing.Color]::FromArgb(62, 62, 68)
    BtnBorder = [System.Drawing.Color]::FromArgb(90, 90, 98)
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Rescale - resolution setup'
$form.Size = New-Object System.Drawing.Size(420, 520)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.BackColor = $DM.Bg
$form.ForeColor = $DM.Text

$lblNative = New-Object System.Windows.Forms.Label
$lblNative.Location = New-Object System.Drawing.Point(12, 12)
$lblNative.Size = New-Object System.Drawing.Size(380, 40)
$lblNative.Text = 'Desktop (native): not captured yet'
$lblNative.ForeColor = $DM.Text
$lblNative.BackColor = $DM.Bg

$btnCapture = New-Object System.Windows.Forms.Button
$btnCapture.Location = New-Object System.Drawing.Point(12, 55)
$btnCapture.Size = New-Object System.Drawing.Size(380, 28)
$btnCapture.Text = 'Save current resolution as desktop (native)'

$lblGame = New-Object System.Windows.Forms.Label
$lblGame.Location = New-Object System.Drawing.Point(12, 95)
$lblGame.Size = New-Object System.Drawing.Size(200, 20)
$lblGame.Text = 'Game resolution'
$lblGame.ForeColor = $DM.Text
$lblGame.BackColor = $DM.Bg

$numGameW = New-Object System.Windows.Forms.NumericUpDown
$numGameW.Location = New-Object System.Drawing.Point(12, 118)
$numGameW.Size = New-Object System.Drawing.Size(100, 24)
$numGameW.Minimum = 640
$numGameW.Maximum = 8192
$numGameW.Value = 1440
$numGameW.BackColor = $DM.Surface
$numGameW.ForeColor = $DM.Text

$numGameH = New-Object System.Windows.Forms.NumericUpDown
$numGameH.Location = New-Object System.Drawing.Point(130, 118)
$numGameH.Size = New-Object System.Drawing.Size(100, 24)
$numGameH.Minimum = 480
$numGameH.Maximum = 8192
$numGameH.Value = 1080
$numGameH.BackColor = $DM.Surface
$numGameH.ForeColor = $DM.Text

$lblPresets = New-Object System.Windows.Forms.Label
$lblPresets.Location = New-Object System.Drawing.Point(12, 152)
$lblPresets.Size = New-Object System.Drawing.Size(200, 20)
$lblPresets.Text = 'Common stretched presets'
$lblPresets.ForeColor = $DM.Text
$lblPresets.BackColor = $DM.Bg

$listPresets = New-Object System.Windows.Forms.ListBox
$listPresets.Location = New-Object System.Drawing.Point(12, 175)
$listPresets.Size = New-Object System.Drawing.Size(380, 140)
$listPresets.BackColor = $DM.Surface
$listPresets.ForeColor = $DM.Text
$listPresets.BorderStyle = 'FixedSingle'
foreach ($p in $presets) { [void]$listPresets.Items.Add($p.Label) }

$lblNote = New-Object System.Windows.Forms.Label
$lblNote.Location = New-Object System.Drawing.Point(12, 322)
$lblNote.Size = New-Object System.Drawing.Size(380, 60)
$lblNote.Text = 'NVIDIA: Windows must know the mode. If a switch fails, add the custom resolution once in NVIDIA Control Panel (Change resolution > Customize) or with CRU. This tool only applies modes the driver exposes.'
$lblNote.ForeColor = $DM.Muted
$lblNote.BackColor = $DM.Bg

$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Location = New-Object System.Drawing.Point(12, 384)
$btnSave.Size = New-Object System.Drawing.Size(120, 44)
$btnSave.Text = 'Save config and create .bat files'
$btnSave.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter

$btnTryGame = New-Object System.Windows.Forms.Button
$btnTryGame.Location = New-Object System.Drawing.Point(140, 384)
$btnTryGame.Size = New-Object System.Drawing.Size(120, 44)
$btnTryGame.Text = 'Try game now'

$btnTryDesk = New-Object System.Windows.Forms.Button
$btnTryDesk.Location = New-Object System.Drawing.Point(268, 384)
$btnTryDesk.Size = New-Object System.Drawing.Size(124, 44)
$btnTryDesk.Text = 'Try desktop now'

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Location = New-Object System.Drawing.Point(300, 436)
$btnClose.Size = New-Object System.Drawing.Size(92, 28)
$btnClose.Text = 'Close'
$btnClose.DialogResult = 'Cancel'

foreach ($b in @($btnCapture, $btnSave, $btnTryGame, $btnTryDesk, $btnClose)) {
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.FlatAppearance.BorderColor = $DM.BtnBorder
    $b.FlatAppearance.BorderSize = 1
    $b.BackColor = $DM.Btn
    $b.ForeColor = $DM.Text
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
}

$script:nativeW = 0
$script:nativeH = 0

function Update-NativeLabel {
    if ($script:nativeW -gt 0 -and $script:nativeH -gt 0) {
        $lblNative.Text = "Desktop (native): $($script:nativeW) x $($script:nativeH)"
    }
}

$btnCapture.Add_Click({
    $w = 0; $h = 0; $bpp = 0; $hz = 0
    $ok = [RescaleDisplay]::TryGetCurrentResolution([ref]$w, [ref]$h, [ref]$bpp, [ref]$hz)
    if (-not $ok) {
        [System.Windows.Forms.MessageBox]::Show('Could not read current display settings.', 'Rescale', 'OK', 'Error') | Out-Null
        return
    }
    $script:nativeW = $w
    $script:nativeH = $h
    Update-NativeLabel
})

$listPresets.Add_SelectedIndexChanged({
    if ($listPresets.SelectedIndex -lt 0) { return }
    $p = $presets[$listPresets.SelectedIndex]
    $numGameW.Value = [Math]::Max([int]$numGameW.Minimum, [Math]::Min([int]$numGameW.Maximum, $p.W))
    $numGameH.Value = [Math]::Max([int]$numGameH.Minimum, [Math]::Min([int]$numGameH.Maximum, $p.H))
})

$btnSave.Add_Click({
    if ($script:nativeW -le 0 -or $script:nativeH -le 0) {
        [System.Windows.Forms.MessageBox]::Show(
            'Click "Save current resolution as desktop (native)" first.',
            'Rescale',
            'OK',
            'Warning'
        ) | Out-Null
        return
    }
    $gw = [int]$numGameW.Value
    $gh = [int]$numGameH.Value
    Save-RescaleConfig -NativeWidth $script:nativeW -NativeHeight $script:nativeH -GameWidth $gw -GameHeight $gh
    Write-SwitchBatchFiles -Ps1Path $RescaleScriptPath
    [System.Windows.Forms.MessageBox]::Show(
        "Saved.`n`nCreated:`n  Switch to Game Resolution.bat`n  Switch to Desktop Resolution.bat",
        'Rescale',
        'OK',
        'Information'
    ) | Out-Null
})

$btnTryGame.Add_Click({
    $gw = [int]$numGameW.Value
    $gh = [int]$numGameH.Value
    $code = [RescaleDisplay]::SetResolution($gw, $gh)
    if ($code -ne 0) {
        $msg = if ($code -eq -2) {
            'Mode not available. Add it in NVIDIA / CRU first.'
        } else { "Error code: $code" }
        [System.Windows.Forms.MessageBox]::Show($msg, 'Rescale', 'OK', 'Error') | Out-Null
    }
})

$btnTryDesk.Add_Click({
    if ($script:nativeW -le 0 -or $script:nativeH -le 0) {
        [System.Windows.Forms.MessageBox]::Show('Capture desktop resolution first.', 'Rescale', 'OK', 'Warning') | Out-Null
        return
    }
    $code = [RescaleDisplay]::SetResolution($script:nativeW, $script:nativeH)
    if ($code -ne 0) {
        [System.Windows.Forms.MessageBox]::Show("Error code: $code", 'Rescale', 'OK', 'Error') | Out-Null
    }
})

$form.Controls.AddRange(@(
    $lblNative, $btnCapture, $lblGame, $numGameW, $numGameH,
    $lblPresets, $listPresets, $lblNote, $btnSave, $btnTryGame, $btnTryDesk, $btnClose
))

# Load existing config
$existing = Get-RescaleConfig
if ($existing) {
    $script:nativeW = [int]$existing.NativeWidth
    $script:nativeH = [int]$existing.NativeHeight
    Update-NativeLabel
    $numGameW.Value = [Math]::Max([int]$numGameW.Minimum, [Math]::Min([int]$numGameW.Maximum, [int]$existing.GameWidth))
    $numGameH.Value = [Math]::Max([int]$numGameH.Minimum, [Math]::Min([int]$numGameH.Maximum, [int]$existing.GameHeight))
} else {
    $w0 = 0; $h0 = 0; $b0 = 0; $z0 = 0
    if ([RescaleDisplay]::TryGetCurrentResolution([ref]$w0, [ref]$h0, [ref]$b0, [ref]$z0)) {
        $script:nativeW = $w0
        $script:nativeH = $h0
    }
    Update-NativeLabel
}

[void]$form.ShowDialog()
