# PotPlayer Profile Context Menu v1.0 - removal utility
# Removes only entries owned by this utility.
# Requires Windows PowerShell 5.1 or newer.
# SPDX-License-Identifier: MIT

$ErrorActionPreference = 'Stop'
$AppName = 'PotPlayer Profile Context Menu'
$AppVersion = '1.0'
$ToolName = 'PotPlayerProfileContextMenu'
$SchemaVersion = '1.0'
$ScriptRoot = $PSScriptRoot
$LogsDir = Join-Path $ScriptRoot 'Logs'
$BackupsDir = Join-Path $ScriptRoot 'Backups'
$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$LogPath = Join-Path $LogsDir ("remove_{0}.log" -f $Stamp)

foreach ($dir in @($LogsDir, $BackupsDir)) {
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}
try { Start-Transcript -Path $LogPath -Append | Out-Null } catch {}

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host 'Administrator rights are required.' -ForegroundColor Yellow
        exit 1
    }
}

function Test-IsToolManagedEntry {
    param([Microsoft.Win32.RegistryKey]$RegistryKey)
    $managedBy = [string]$RegistryKey.GetValue('ManagedBy')
    return ($managedBy -ceq $ToolName)
}

function Get-DefaultValue {
    param([string]$Path)
    try { return [string](Get-Item $Path).GetValue('') } catch { return '' }
}

function Convert-RegistryPathForRegExe {
    param([string]$Path)
    if ($Path.StartsWith('Registry::HKEY_LOCAL_MACHINE\', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'HKLM\' + $Path.Substring('Registry::HKEY_LOCAL_MACHINE\'.Length)
    }
    return $null
}

function Backup-ShellPaths {
    param([string[]]$ShellPaths)
    $folder = Join-Path $BackupsDir ("remove_backup_{0}" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    $i = 0
    $failures = New-Object System.Collections.Generic.List[string]
    foreach ($shellPath in @($ShellPaths | Select-Object -Unique)) {
        if (-not (Test-Path $shellPath)) { continue }
        $regPath = Convert-RegistryPathForRegExe -Path $shellPath
        if ([string]::IsNullOrWhiteSpace($regPath)) { continue }
        $i++
        $leaf = ($regPath -replace '[\\/:*?"<>| ]', '_')
        $file = Join-Path $folder (('{0:D3}_{1}.reg' -f $i, $leaf))
        try {
            & reg.exe export $regPath $file /y | Out-Null
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $file)) { throw "reg.exe export failed" }
        } catch {
            $failures.Add($regPath)
        }
    }
    if ($i -eq 0 -or $failures.Count -gt 0) {
        throw 'Registry backup was incomplete. Removal was cancelled; no entries were removed.'
    }
    return $folder
}

Assert-Administrator
Write-Host ("{0} v{1}" -f $AppName, $AppVersion) -ForegroundColor Cyan
Write-Host '-----------------------------------'
Write-Host ''

$videoExts = @(
    '3G2','3GP','3GP2','3GPP','AMV','ASF','AVI','AVS','DIVX','DMSKM','DPG','DVR-MS',
    'EVO','F4V','FLV','IFO','K3G','LMP4','M1V','M2T','M2TS','M2V','M4V','MKV','MOV',
    'MP2V','MP4','MPE','MPEG','MPG','MPV2','MQV','MTS','MXF','NSR','NSV','OGM','OGV',
    'PMP','PSS','PVA','QT','RM','RMVB','SKM','TP','TPR','TRP','TS','VOB','VP6','WEBM',
    'WM','WMP','WMV','WTV'
)

$shellPaths = New-Object System.Collections.Generic.List[string]
$profiles = New-Object System.Collections.Generic.List[string]
foreach ($ext in $videoExts) {
    $shellPath = "Registry::HKEY_LOCAL_MACHINE\Software\Classes\PotPlayerMini64.$ext\shell"
    if (-not (Test-Path $shellPath)) { continue }
    $shellPaths.Add($shellPath)
    foreach ($child in @(Get-ChildItem $shellPath -ErrorAction SilentlyContinue)) {
        if (-not (Test-IsToolManagedEntry -RegistryKey $child)) { continue }
        $name = [string]$child.GetValue('PotPlayerConfig')
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $exists = $false
        foreach ($p in $profiles) { if ($p.Equals($name, [System.StringComparison]::OrdinalIgnoreCase)) { $exists = $true; break } }
        if (-not $exists) { $profiles.Add($name) }
    }
}

if ($profiles.Count -eq 0) {
    Write-Host 'No tool-managed PotPlayer profile entries were found.' -ForegroundColor Yellow
    [void](Read-Host 'Press Enter to close')
    try { Stop-Transcript | Out-Null } catch {}
    exit 0
}

$sorted = @($profiles | Sort-Object)
Write-Host 'Tool-managed Explorer profiles:' -ForegroundColor Cyan
for ($i = 0; $i -lt $sorted.Count; $i++) { Write-Host ('  {0,2}. {1}' -f ($i + 1), $sorted[$i]) }
Write-Host ''
Write-Host 'Enter numbers separated by commas, ALL, or press Enter to cancel.'
$inputText = (Read-Host 'Remove').Trim()
if ([string]::IsNullOrWhiteSpace($inputText)) {
    Write-Host 'Nothing was changed.' -ForegroundColor Yellow
    [void](Read-Host 'Press Enter to close')
    try { Stop-Transcript | Out-Null } catch {}
    exit 0
}

$targets = New-Object System.Collections.Generic.List[string]
if ($inputText -ieq 'ALL') {
    foreach ($p in $sorted) { $targets.Add($p) }
} else {
    foreach ($part in @($inputText -split ',')) {
        $idx = 0
        if ([int]::TryParse($part.Trim(), [ref]$idx) -and $idx -ge 1 -and $idx -le $sorted.Count) {
            $name = $sorted[$idx - 1]
            if (-not $targets.Contains($name)) { $targets.Add($name) }
        }
    }
}

if ($targets.Count -eq 0) {
    Write-Host 'No valid profiles selected.' -ForegroundColor Yellow
    [void](Read-Host 'Press Enter to close')
    try { Stop-Transcript | Out-Null } catch {}
    exit 0
}

Write-Host ''
Write-Host ('Will remove only tool-managed entries for: ' + ($targets.ToArray() -join ', ')) -ForegroundColor Yellow
$confirm = (Read-Host 'Continue? [y/N]').Trim()
if (-not ($confirm -ieq 'Y' -or $confirm -ieq 'YES')) {
    Write-Host 'Nothing was changed.' -ForegroundColor Yellow
    [void](Read-Host 'Press Enter to close')
    try { Stop-Transcript | Out-Null } catch {}
    exit 0
}

try {
    $backup = Backup-ShellPaths -ShellPaths $shellPaths.ToArray()
} catch {
    Write-Host ''
    Write-Host ('Backup failed: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host 'No entries were removed.' -ForegroundColor Yellow
    Write-Host "Log: $LogPath"
    [void](Read-Host 'Press Enter to close')
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}
$removed = 0
foreach ($shellPath in $shellPaths) {
    foreach ($child in @(Get-ChildItem $shellPath -ErrorAction SilentlyContinue)) {
        if (-not (Test-IsToolManagedEntry -RegistryKey $child)) { continue }
        $name = [string]$child.GetValue('PotPlayerConfig')
        foreach ($target in $targets) {
            if (-not [string]::IsNullOrWhiteSpace($name) -and $name.Equals($target, [System.StringComparison]::OrdinalIgnoreCase)) {
                Remove-Item $child.PSPath -Recurse -Force
                $removed++
                break
            }
        }
    }
    Set-Item -Path $shellPath -Value 'open'
}

Write-Host ''
Write-Host ("Removed {0} tool-managed registry entries." -f $removed) -ForegroundColor Green
Write-Host "Backup: $backup"
Write-Host "Log: $LogPath"
Write-Host 'Native PotPlayer Open and unrelated Explorer verbs were left intact.'
[void](Read-Host 'Press Enter to close')
try { Stop-Transcript | Out-Null } catch {}
