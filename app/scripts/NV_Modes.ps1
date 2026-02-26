#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Applies NV_Modes registry entries to persist custom NVIDIA resolutions.
.DESCRIPTION
    Reads the game resolution from config/settings.json, checks existing
    NV_Modes registry values, and appends the custom resolution entry
    only if it does not already exist.
#>

$ErrorActionPreference = "Stop"
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ConfigPath = Join-Path (Split-Path -Parent $ScriptRoot) "config\settings.json"

if (-not (Test-Path $ConfigPath)) {
    Write-Error "Config not found: $ConfigPath"
    exit 1
}

$cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$gameRes = "$($cfg.game.width)x$($cfg.game.height)"
$newEntry = "${gameRes}x8,16,32,64=1F;"

$displayClassGuid = '{4d36e968-e325-11ce-bfc1-08002be10318}'
$displayClassPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$displayClassGuid"
if (-not (Test-Path -Path $displayClassPath)) {
    Write-Warning "Display adapter class key not found: $displayClassPath"
    exit 1
}

$adapterKeys = @(
    Get-ChildItem -Path $displayClassPath -ErrorAction SilentlyContinue |
    Where-Object { $_.PSChildName -match '^\d{4}$' }
)

if ($adapterKeys.Count -eq 0) {
    Write-Warning "No display adapter entries found under: $displayClassPath"
    exit 1
}

$keysWithNVMode = 0
$updatedCount = 0
$alreadyPresentCount = 0

foreach ($adapterKey in $adapterKeys) {
    try {
        $prop = Get-ItemProperty -Path $adapterKey.PSPath -Name 'NV_Modes' -ErrorAction Stop
    }
    catch {
        continue
    }

    $keysWithNVMode++
    $current = $prop.NV_Modes
    # Handle string array (registry REG_MULTI_SZ)
    if ($current -is [array]) {
        $current = $current -join ''
    }

    if ([string]::IsNullOrWhiteSpace($current)) {
        $updated = $newEntry
    }
    else {
        if ($current -match [regex]::Escape("${gameRes}x")) {
            $alreadyPresentCount++
            Write-Host "Already present in: $($adapterKey.PSPath)"
            continue
        }

        # Append before the trailing entries, or at the end of the string
        $updated = ($current.TrimEnd() + " $newEntry").Trim()
    }

    Set-ItemProperty -Path $adapterKey.PSPath -Name 'NV_Modes' -Value @($updated)
    $updatedCount++
    Write-Host "Appended ${gameRes} to: $($adapterKey.PSPath)"
}

if ($keysWithNVMode -eq 0) {
    Write-Warning "No NV_Modes registry values found under display adapter keys. Is an NVIDIA driver installed?"
    exit 1
}

Write-Host "NV_Modes check complete for: $gameRes (updated: $updatedCount, unchanged: $alreadyPresentCount)"
