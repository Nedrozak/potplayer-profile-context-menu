# PotPlayer Profile Context Menu v1.0
# Public release: automatic PotPlayer profile detection, exact Explorer command sync,
# diagnostics, dry-run preview, registry backup, selective repair, and Windows PowerShell 5.1 support.
# SPDX-License-Identifier: MIT

$ErrorActionPreference = 'Stop'

$AppName = 'PotPlayer Profile Context Menu'
$AppVersion = '1.0'
$ToolName = 'PotPlayerProfileContextMenu'
$SchemaVersion = '1.0'
$ScriptRoot = $PSScriptRoot
$LogsDir = Join-Path $ScriptRoot 'Logs'
$BackupsDir = Join-Path $ScriptRoot 'Backups'
$SettingsPath = Join-Path $ScriptRoot 'PotPlayer_Profile_Context_Menu.settings.json'
$SessionStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$LogPath = Join-Path $LogsDir ("setup_{0}.log" -f $SessionStamp)
$EventLogPath = Join-Path $LogsDir ("setup_{0}_events.log" -f $SessionStamp)
$script:BackupFolder = $null
$script:TranscriptStarted = $false

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

Ensure-Directory -Path $LogsDir
Ensure-Directory -Path $BackupsDir
try {
    Start-Transcript -Path $LogPath -Append | Out-Null
    $script:TranscriptStarted = $true
} catch {}

function Write-LogLine {
    param([string]$Message)
    try {
        Add-Content -LiteralPath $EventLogPath -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $Message) -Encoding UTF8
    } catch {}
}

function Pause-Continue {
    param([string]$Text = 'Press Enter to continue')
    [void](Read-Host $Text)
}

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host 'Administrator rights are required.' -ForegroundColor Yellow
        Write-LogLine 'ERROR: Script was not elevated.'
        exit 1
    }
}

function Add-UniqueProfile {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Name
    )
    if ([string]::IsNullOrWhiteSpace($Name)) { return }
    $clean = $Name.Trim()
    foreach ($existing in $List) {
        if ($existing.Equals($clean, [System.StringComparison]::OrdinalIgnoreCase)) { return }
    }
    $List.Add($clean)
}

function Test-ProfileInList {
    param([object[]]$List, [string]$Name)
    foreach ($item in @($List)) {
        if ($null -ne $item -and ([string]$item).Equals($Name, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Get-ProfileVerbName {
    param([string]$ConfigName)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($ConfigName.ToLowerInvariant())
        $hash = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').Substring(0, 16)
        return "open_profile_$hash"
    }
    finally {
        $sha.Dispose()
    }
}

function Test-ProfileNameSafe {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    if ($Name.IndexOf([char]0) -ge 0) { return $false }
    # PotPlayer's config="..." syntax cannot safely represent an embedded quote.
    if ($Name.Contains('"')) { return $false }
    return $true
}

function Get-ExpectedCommand {
    param([string]$Exe, [string]$ConfigName)
    return ('"{0}" "%1" config="{1}"' -f $Exe, $ConfigName)
}

function Get-ToolSettings {
    $settings = [PSCustomObject]@{
        DefaultProfile = ''
    }
    if (Test-Path -LiteralPath $SettingsPath) {
        try {
            $json = Get-Content -LiteralPath $SettingsPath -Raw -ErrorAction Stop | ConvertFrom-Json
            if ($null -ne $json.DefaultProfile) {
                $settings.DefaultProfile = [string]$json.DefaultProfile
            }
        } catch {
            Write-LogLine ("WARNING: Could not read settings file: {0}" -f $_.Exception.Message)
        }
    }
    return $settings
}

function Save-ToolSettings {
    param([string]$DefaultProfile)
    $obj = [PSCustomObject]@{
        SchemaVersion = $SchemaVersion
        DefaultProfile = $DefaultProfile
    }
    $obj | ConvertTo-Json | Set-Content -LiteralPath $SettingsPath -Encoding UTF8
    Write-LogLine ("Saved settings. DefaultProfile='{0}'" -f $DefaultProfile)
}

function Get-ExpectedPosition {
    param([string]$ConfigName, [string]$DefaultProfile)
    if (-not [string]::IsNullOrWhiteSpace($DefaultProfile) -and $ConfigName.Equals($DefaultProfile, [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'Top'
    }
    return ''
}

function Get-ProfileNameFromOptionValue {
    param([object]$Value)
    if ($null -eq $Value) { return $null }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    $tick = $text.IndexOf([char]96)
    if ($tick -ge 0) { return $text.Substring(0, $tick).Trim() }
    return $text.Trim()
}

function Get-PotPlayerProfilesFromRegistry {
    $profiles = New-Object System.Collections.Generic.List[string]
    $root = 'Registry::HKEY_CURRENT_USER\Software\Daum\PotPlayerMini64'
    $optionListPath = Join-Path $root 'OptionList'

    if (Test-Path $optionListPath) {
        try {
            $key = Get-Item $optionListPath
            $names = @($key.GetValueNames()) | Sort-Object {
                $n = 0
                if ([int]::TryParse($_, [ref]$n)) { return $n }
                return [int]::MaxValue
            }
            foreach ($valueName in $names) {
                $optionValue = $key.GetValue($valueName)
                $profileName = Get-ProfileNameFromOptionValue -Value $optionValue
                Add-UniqueProfile -List $profiles -Name $profileName
            }
        } catch {
            Write-LogLine ("Registry profile detection error: {0}" -f $_.Exception.Message)
        }
    }

    if ($profiles.Count -eq 0 -and (Test-Path $root)) {
        try {
            foreach ($child in Get-ChildItem $root -ErrorAction SilentlyContinue) {
                if ($child.PSChildName -like 'OptionList_*') {
                    Add-UniqueProfile -List $profiles -Name $child.PSChildName.Substring('OptionList_'.Length)
                }
            }
        } catch {}
    }
    return $profiles.ToArray()
}

function Get-PotPlayerProfilesFromIni {
    param([string[]]$CandidatePaths)
    $profiles = New-Object System.Collections.Generic.List[string]
    $usedPaths = New-Object System.Collections.Generic.List[string]

    foreach ($iniPath in @($CandidatePaths | Select-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($iniPath) -or -not (Test-Path -LiteralPath $iniPath)) { continue }
        try {
            $inOptionList = $false
            $foundAny = $false
            foreach ($line in Get-Content -LiteralPath $iniPath -ErrorAction Stop) {
                $trimmed = $line.Trim()
                if ($trimmed -match '^\[(.+)\]$') {
                    $inOptionList = ($Matches[1] -ieq 'OptionList')
                    continue
                }
                if (-not $inOptionList) { continue }
                if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith(';')) { continue }
                if ($trimmed -match '^\d+=(.*)$') {
                    $profileName = Get-ProfileNameFromOptionValue $Matches[1]
                    if (-not [string]::IsNullOrWhiteSpace($profileName)) {
                        Add-UniqueProfile -List $profiles -Name $profileName
                        $foundAny = $true
                    }
                }
            }
            if ($foundAny) { $usedPaths.Add($iniPath) }
        } catch {
            Write-LogLine ("INI profile detection error for '{0}': {1}" -f $iniPath, $_.Exception.Message)
        }
    }

    return [PSCustomObject]@{
        Profiles = $profiles.ToArray()
        UsedPaths = $usedPaths.ToArray()
    }
}

function Get-DetectedProfileInfo {
    param([string[]]$IniCandidates)

    $all = New-Object System.Collections.Generic.List[string]
    $sources = New-Object System.Collections.Generic.List[string]
    $duplicates = New-Object System.Collections.Generic.List[string]

    $regProfiles = @(Get-PotPlayerProfilesFromRegistry)
    if ($regProfiles.Count -gt 0) {
        $sources.Add('Registry: HKCU\Software\Daum\PotPlayerMini64\OptionList')
        foreach ($name in $regProfiles) { Add-UniqueProfile -List $all -Name $name }
    }

    $iniInfo = Get-PotPlayerProfilesFromIni -CandidatePaths $IniCandidates
    foreach ($p in @($iniInfo.UsedPaths)) { $sources.Add("INI: $p") }
    foreach ($name in @($iniInfo.Profiles)) {
        if (Test-ProfileInList -List $all.ToArray() -Name $name) {
            Add-UniqueProfile -List $duplicates -Name $name
        }
        Add-UniqueProfile -List $all -Name $name
    }

    $safe = New-Object System.Collections.Generic.List[string]
    $unsafe = New-Object System.Collections.Generic.List[string]
    foreach ($name in $all) {
        if (Test-ProfileNameSafe -Name $name) { $safe.Add($name) } else { $unsafe.Add($name) }
    }

    return [PSCustomObject]@{
        Profiles = @($safe.ToArray() | Sort-Object)
        UnsafeProfiles = @($unsafe.ToArray() | Sort-Object)
        Sources = $sources.ToArray()
        DuplicateNames = @($duplicates.ToArray() | Sort-Object)
    }
}

function ConvertTo-PotPlayerExePath {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }

    try {
        $candidate = [Environment]::ExpandEnvironmentVariables($Value).Trim()
    } catch {
        $candidate = $Value.Trim()
    }

    # Registry values can legally be stored as any of these:
    #   C:\...\PotPlayerMini64.exe
    #   "C:\...\PotPlayerMini64.exe"
    #   "C:\...\PotPlayerMini64.exe",0       (Icon style)
    #   "C:\...\PotPlayerMini64.exe" "%1" ... (full command line)
    # Extract the executable before asking Test-Path to validate it.
    if ($candidate.StartsWith('"')) {
        $closingQuote = $candidate.IndexOf('"', 1)
        if ($closingQuote -gt 1) {
            $candidate = $candidate.Substring(1, $closingQuote - 1)
        }
    }
    elseif ($candidate -match '(?i)^(?<exe>.*?PotPlayerMini64\.exe)(?:\s|,|$)') {
        $candidate = $Matches['exe']
    }

    $candidate = $candidate.Trim().Trim('"')
    if ([string]::IsNullOrWhiteSpace($candidate)) { return $null }

    # We only want PotPlayer's 64-bit executable here. Reject unrelated command text.
    if (-not $candidate.EndsWith('PotPlayerMini64.exe', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }

    return $candidate
}

function Test-SafeFilePath {
    param([AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try {
        return [bool](Test-Path -LiteralPath $Path -PathType Leaf -ErrorAction Stop)
    }
    catch {
        Write-LogLine ("WARNING: Ignored malformed executable candidate [{0}]: {1}" -f $Path, $_.Exception.Message)
        return $false
    }
}

function Add-PotPlayerExeCandidate {
    param(
        [System.Collections.Generic.List[string]]$List,
        [AllowNull()][string]$Value
    )
    $normalized = ConvertTo-PotPlayerExePath -Value $Value
    if ([string]::IsNullOrWhiteSpace($normalized)) { return }
    foreach ($existing in $List) {
        if ($existing.Equals($normalized, [System.StringComparison]::OrdinalIgnoreCase)) { return }
    }
    $List.Add($normalized)
}

function Get-ExistingManagedExeCandidates {
    $candidates = New-Object System.Collections.Generic.List[string]
    # Check a small representative set rather than enumerating all HKLM\Software\Classes.
    foreach ($ext in @('MKV','MP4','AVI','TS','M2TS','WEBM','WMV')) {
        $shellPath = "Registry::HKEY_LOCAL_MACHINE\Software\Classes\PotPlayerMini64.$ext\shell"
        if (-not (Test-Path $shellPath)) { continue }
        try {
            foreach ($child in @(Get-ChildItem $shellPath -ErrorAction SilentlyContinue)) {
                $managedBy = [string]$child.GetValue('ManagedBy')
                if ($managedBy -cne $ToolName) { continue }
                Add-PotPlayerExeCandidate -List $candidates -Value ([string]$child.GetValue('Icon'))

                # A managed entry may provide the executable path in the command value.
                try {
                    $commandKey = $child.OpenSubKey('command')
                    if ($null -ne $commandKey) {
                        try { Add-PotPlayerExeCandidate -List $candidates -Value ([string]$commandKey.GetValue('')) }
                        finally { $commandKey.Close() }
                    }
                } catch {}
            }
        } catch {}
    }
    return $candidates.ToArray()
}

function Get-PotPlayerExecutable {
    $candidates = New-Object System.Collections.Generic.List[string]

    foreach ($appPath in @(
        'Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\App Paths\PotPlayerMini64.exe',
        'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\App Paths\PotPlayerMini64.exe'
    )) {
        if (Test-Path $appPath) {
            try {
                Add-PotPlayerExeCandidate -List $candidates -Value ([string](Get-Item $appPath).GetValue(''))
            } catch {}
        }
    }

    foreach ($p in @(Get-ExistingManagedExeCandidates)) {
        Add-PotPlayerExeCandidate -List $candidates -Value $p
    }

    if ($env:ProgramFiles) {
        Add-PotPlayerExeCandidate -List $candidates -Value (Join-Path $env:ProgramFiles 'DAUM\PotPlayer\PotPlayerMini64.exe')
    }
    if (${env:ProgramFiles(x86)}) {
        Add-PotPlayerExeCandidate -List $candidates -Value (Join-Path ${env:ProgramFiles(x86)} 'DAUM\PotPlayer\PotPlayerMini64.exe')
    }

    try {
        $cmd = Get-Command 'PotPlayerMini64.exe' -ErrorAction SilentlyContinue
        if ($null -ne $cmd) { Add-PotPlayerExeCandidate -List $candidates -Value ([string]$cmd.Source) }
    } catch {}

    foreach ($candidate in $candidates) {
        if (Test-SafeFilePath -Path $candidate) {
            try { return [string](Get-Item -LiteralPath $candidate -ErrorAction Stop).FullName }
            catch {
                Write-LogLine ("WARNING: Could not resolve executable candidate [{0}]: {1}" -f $candidate, $_.Exception.Message)
            }
        }
    }
    return $null
}

function Get-ManagedShellPaths {
    param([string[]]$VideoExts)
    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($ext in $VideoExts) {
        $shellPath = "Registry::HKEY_LOCAL_MACHINE\Software\Classes\PotPlayerMini64.$ext\shell"
        if (Test-Path $shellPath) { $paths.Add($shellPath) }
    }
    return $paths.ToArray()
}

function Get-RegistryDefaultValue {
    param([string]$Path)
    try { return [string](Get-Item $Path).GetValue('') } catch { return '' }
}

function Get-RegistryNamedValue {
    param([string]$Path, [string]$Name)
    try { return [string](Get-Item $Path).GetValue($Name) } catch { return '' }
}

function Test-IsToolManagedEntry {
    param([Microsoft.Win32.RegistryKey]$RegistryKey)
    $managedBy = [string]$RegistryKey.GetValue('ManagedBy')
    return ($managedBy -ceq $ToolName)
}

function Get-ExplorerInventory {
    param([string[]]$ShellPaths)

    $entries = New-Object System.Collections.Generic.List[object]
    $brokenPaths = New-Object System.Collections.Generic.List[string]
    $duplicatePaths = New-Object System.Collections.Generic.List[string]
    $names = New-Object System.Collections.Generic.List[string]

    foreach ($shellPath in $ShellPaths) {
        foreach ($child in @(Get-ChildItem $shellPath -ErrorAction SilentlyContinue)) {
            if (-not (Test-IsToolManagedEntry -RegistryKey $child)) { continue }

            $name = [string]$child.GetValue('PotPlayerConfig')
            $commandPath = Join-Path $child.PSPath 'command'
            $command = ''
            if (Test-Path $commandPath) { $command = Get-RegistryDefaultValue -Path $commandPath }

            if ([string]::IsNullOrWhiteSpace($name) -and $command -match 'config="([^"]+)"') {
                $name = $Matches[1]
            }

            if ([string]::IsNullOrWhiteSpace($name)) {
                $brokenPaths.Add($child.PSPath)
                continue
            }

            # Any tool-managed key for this profile that is not the canonical
            # hashed verb is a duplicate. Never mark the canonical key
            # for deletion merely because registry enumeration order changed.
            $canonicalVerb = Get-ProfileVerbName -ConfigName $name
            $isDuplicate = ($child.PSChildName -cne $canonicalVerb)
            if ($isDuplicate) { $duplicatePaths.Add($child.PSPath) }

            Add-UniqueProfile -List $names -Name $name
            $entries.Add([PSCustomObject]@{
                Name = $name
                ShellPath = $shellPath
                VerbPath = $child.PSPath
                VerbName = $child.PSChildName
                CommandPath = $commandPath
                Command = $command
                ManagedBy = [string]$child.GetValue('ManagedBy')
                SchemaVersion = [string]$child.GetValue('SchemaVersion')
                IsDuplicate = $isDuplicate
            })
        }

    }

    return [PSCustomObject]@{
        Entries = $entries.ToArray()
        Names = @($names.ToArray() | Sort-Object)
        BrokenPaths = @($brokenPaths.ToArray() | Select-Object -Unique)
        DuplicatePaths = @($duplicatePaths.ToArray() | Select-Object -Unique)
    }
}

function Get-ProfileRegistrationIssues {
    param(
        [string]$ConfigName,
        [string[]]$ShellPaths,
        [string]$Exe,
        [string]$DefaultProfile
    )

    $issues = New-Object System.Collections.Generic.List[object]
    $verbName = Get-ProfileVerbName -ConfigName $ConfigName
    $expectedCommand = Get-ExpectedCommand -Exe $Exe -ConfigName $ConfigName
    $expectedMenuText = "Open with ($ConfigName)"
    $expectedPosition = Get-ExpectedPosition -ConfigName $ConfigName -DefaultProfile $DefaultProfile

    foreach ($shellPath in $ShellPaths) {
        $verbPath = Join-Path $shellPath $verbName
        $commandPath = Join-Path $verbPath 'command'
        $reasons = New-Object System.Collections.Generic.List[string]
        $actualCommand = ''

        if (-not (Test-Path $verbPath)) {
            $reasons.Add('missing verb')
        } else {
            $actualMenuText = Get-RegistryDefaultValue -Path $verbPath
            $actualIcon = Get-RegistryNamedValue -Path $verbPath -Name 'Icon'
            $actualConfig = Get-RegistryNamedValue -Path $verbPath -Name 'PotPlayerConfig'
            $actualManagedBy = Get-RegistryNamedValue -Path $verbPath -Name 'ManagedBy'
            $actualSchema = Get-RegistryNamedValue -Path $verbPath -Name 'SchemaVersion'
            $actualPosition = Get-RegistryNamedValue -Path $verbPath -Name 'Position'

            if ($actualMenuText -cne $expectedMenuText) { $reasons.Add('menu text mismatch') }
            if ($actualIcon -cne $Exe) { $reasons.Add('icon/executable path mismatch') }
            if ($actualConfig -cne $ConfigName) { $reasons.Add('profile metadata mismatch') }
            if ($actualManagedBy -cne $ToolName) { $reasons.Add('ownership metadata mismatch') }
            if ($actualSchema -cne $SchemaVersion) { $reasons.Add('schema version mismatch') }
            if ($actualPosition -cne $expectedPosition) { $reasons.Add('menu position mismatch') }
        }

        if (-not (Test-Path $commandPath)) {
            $reasons.Add('missing command')
        } else {
            $actualCommand = Get-RegistryDefaultValue -Path $commandPath
            if ($actualCommand -cne $expectedCommand) { $reasons.Add('complete command mismatch') }
        }

        if ($reasons.Count -gt 0) {
            $issues.Add([PSCustomObject]@{
                Profile = $ConfigName
                ShellPath = $shellPath
                VerbPath = $verbPath
                CommandPath = $commandPath
                Reasons = $reasons.ToArray()
                ExpectedCommand = $expectedCommand
                ActualCommand = $actualCommand
            })
        }
    }
    return $issues.ToArray()
}

function Get-SyncState {
    param(
        [string[]]$DetectedProfiles,
        [object]$Inventory,
        [string[]]$ShellPaths,
        [string]$Exe,
        [string]$DefaultProfile
    )

    $missing = New-Object System.Collections.Generic.List[string]
    $repairProfiles = New-Object System.Collections.Generic.List[string]
    $repairIssues = New-Object System.Collections.Generic.List[object]
    $explorerOnly = New-Object System.Collections.Generic.List[string]

    foreach ($name in @($DetectedProfiles)) {
        if (-not (Test-ProfileInList -List @($Inventory.Names) -Name $name)) {
            Add-UniqueProfile -List $missing -Name $name
        } else {
            $issues = @(Get-ProfileRegistrationIssues -ConfigName $name -ShellPaths $ShellPaths -Exe $Exe -DefaultProfile $DefaultProfile)
            if ($issues.Count -gt 0) {
                Add-UniqueProfile -List $repairProfiles -Name $name
                foreach ($issue in $issues) { $repairIssues.Add($issue) }
            }
        }
    }

    foreach ($name in @($Inventory.Names)) {
        if (-not (Test-ProfileInList -List $DetectedProfiles -Name $name)) {
            Add-UniqueProfile -List $explorerOnly -Name $name
        }
    }

    $isInSync = (
        $missing.Count -eq 0 -and
        $repairIssues.Count -eq 0 -and
        $explorerOnly.Count -eq 0 -and
        @($Inventory.BrokenPaths).Count -eq 0 -and
        @($Inventory.DuplicatePaths).Count -eq 0
    )

    return [PSCustomObject]@{
        Missing = $missing.ToArray()
        RepairProfiles = $repairProfiles.ToArray()
        RepairIssues = $repairIssues.ToArray()
        ExplorerOnly = $explorerOnly.ToArray()
        IsInSync = $isInSync
    }
}

function Convert-RegistryPathForRegExe {
    param([string]$Path)
    $p = $Path
    if ($p.StartsWith('Registry::HKEY_LOCAL_MACHINE\', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'HKLM\' + $p.Substring('Registry::HKEY_LOCAL_MACHINE\'.Length)
    }
    if ($p.StartsWith('Registry::HKEY_CURRENT_USER\', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'HKCU\' + $p.Substring('Registry::HKEY_CURRENT_USER\'.Length)
    }
    return $null
}

function Ensure-RegistryBackup {
    param([string[]]$ShellPaths)

    if (-not [string]::IsNullOrWhiteSpace($script:BackupFolder)) { return $script:BackupFolder }

    $folder = Join-Path $BackupsDir ("backup_{0}" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    Ensure-Directory -Path $folder
    $index = 0
    $failures = New-Object System.Collections.Generic.List[string]
    foreach ($shellPath in @($ShellPaths | Select-Object -Unique)) {
        if (-not (Test-Path $shellPath)) { continue }
        $regPath = Convert-RegistryPathForRegExe -Path $shellPath
        if ([string]::IsNullOrWhiteSpace($regPath)) { continue }
        $index++
        $leaf = ($regPath -replace '[\\/:*?"<>| ]', '_')
        $file = Join-Path $folder (('{0:D3}_{1}.reg' -f $index, $leaf))
        try {
            & reg.exe export $regPath $file /y | Out-Null
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $file)) {
                throw "reg.exe export returned exit code $LASTEXITCODE"
            }
        } catch {
            $failures.Add(("{0}: {1}" -f $regPath, $_.Exception.Message))
        }
    }
    if ($index -eq 0) {
        throw 'No registry paths were available to back up. No changes were made.'
    }
    if ($failures.Count -gt 0) {
        foreach ($failure in $failures) { Write-LogLine ("BACKUP FAILURE: {0}" -f $failure) }
        throw ("Registry backup was incomplete ({0} failure(s)). No changes were made. See the log." -f $failures.Count)
    }

    $readme = @(
        ($AppName + ' v' + $AppVersion + ' registry backup'),
        ('Created: ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')),
        ('Application version: ' + $AppVersion),
        ('Registry schema: ' + $SchemaVersion),
        '',
        'Each .reg file is an export of a PotPlayer video ProgID shell key before this session made changes.'
    )
    $readme | Set-Content -LiteralPath (Join-Path $folder 'README.txt') -Encoding UTF8
    $script:BackupFolder = $folder
    Write-LogLine ("Registry backup created: {0}" -f $folder)
    return $folder
}

function Set-ExplorerProfileAtShell {
    param(
        [string]$ConfigName,
        [string]$ShellPath,
        [string]$Exe,
        [string]$DefaultProfile
    )
    if (-not (Test-ProfileNameSafe -Name $ConfigName)) { throw "Unsafe profile name: $ConfigName" }

    $verbName = Get-ProfileVerbName -ConfigName $ConfigName
    $verbPath = Join-Path $ShellPath $verbName
    $commandPath = Join-Path $verbPath 'command'
    $menuText = "Open with ($ConfigName)"
    $command = Get-ExpectedCommand -Exe $Exe -ConfigName $ConfigName
    $position = Get-ExpectedPosition -ConfigName $ConfigName -DefaultProfile $DefaultProfile

    New-Item -Path $verbPath -Force | Out-Null
    Set-Item -Path $verbPath -Value $menuText
    New-ItemProperty -Path $verbPath -Name 'Icon' -PropertyType String -Value $Exe -Force | Out-Null
    New-ItemProperty -Path $verbPath -Name 'PotPlayerConfig' -PropertyType String -Value $ConfigName -Force | Out-Null
    New-ItemProperty -Path $verbPath -Name 'ManagedBy' -PropertyType String -Value $ToolName -Force | Out-Null
    New-ItemProperty -Path $verbPath -Name 'SchemaVersion' -PropertyType String -Value $SchemaVersion -Force | Out-Null

    if ([string]::IsNullOrWhiteSpace($position)) {
        Remove-ItemProperty -Path $verbPath -Name 'Position' -ErrorAction SilentlyContinue
    } else {
        New-ItemProperty -Path $verbPath -Name 'Position' -PropertyType String -Value $position -Force | Out-Null
    }

    New-Item -Path $commandPath -Force | Out-Null
    Set-Item -Path $commandPath -Value $command
    Set-Item -Path $ShellPath -Value 'open'
    Write-LogLine ("WRITE profile='{0}' shell='{1}' command='{2}'" -f $ConfigName, $ShellPath, $command)
}

function Add-MissingProfiles {
    param([string[]]$Profiles, [string[]]$ShellPaths, [string]$Exe, [string]$DefaultProfile)
    foreach ($name in @($Profiles)) {
        foreach ($shellPath in $ShellPaths) {
            Set-ExplorerProfileAtShell -ConfigName $name -ShellPath $shellPath -Exe $Exe -DefaultProfile $DefaultProfile
        }
    }
}

function Repair-ProfileIssues {
    param([object[]]$Issues, [string]$Exe, [string]$DefaultProfile)
    $done = New-Object System.Collections.Generic.List[string]
    foreach ($issue in @($Issues)) {
        $key = ([string]$issue.Profile).ToLowerInvariant() + '|' + ([string]$issue.ShellPath).ToLowerInvariant()
        if ($done.Contains($key)) { continue }
        $done.Add($key)
        Set-ExplorerProfileAtShell -ConfigName $issue.Profile -ShellPath $issue.ShellPath -Exe $Exe -DefaultProfile $DefaultProfile
    }
}

function Remove-ExplorerProfiles {
    param([string[]]$ProfileNames, [string[]]$ShellPaths)
    $removed = 0
    foreach ($shellPath in $ShellPaths) {
        foreach ($child in @(Get-ChildItem $shellPath -ErrorAction SilentlyContinue)) {
            if (-not (Test-IsToolManagedEntry -RegistryKey $child)) { continue }
            $name = [string]$child.GetValue('PotPlayerConfig')
            foreach ($target in @($ProfileNames)) {
                if (-not [string]::IsNullOrWhiteSpace($name) -and $name.Equals($target, [System.StringComparison]::OrdinalIgnoreCase)) {
                    Write-LogLine ("REMOVE profile='{0}' path='{1}'" -f $name, $child.PSPath)
                    Remove-Item $child.PSPath -Recurse -Force
                    $removed++
                    break
                }
            }
        }
        Set-Item -Path $shellPath -Value 'open'
    }
    return $removed
}

function Remove-PathsSafely {
    param([string[]]$Paths)
    $removed = 0
    foreach ($path in @($Paths | Select-Object -Unique)) {
        if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path $path)) {
            Write-LogLine ("REMOVE path='{0}'" -f $path)
            Remove-Item $path -Recurse -Force
            $removed++
        }
    }
    return $removed
}

function Remove-AllToolManagedEntries {
    param([string[]]$ShellPaths)
    $removed = 0
    foreach ($shellPath in $ShellPaths) {
        foreach ($child in @(Get-ChildItem $shellPath -ErrorAction SilentlyContinue)) {
            if (Test-IsToolManagedEntry -RegistryKey $child) {
                Write-LogLine ("REMOVE managed path='{0}'" -f $child.PSPath)
                Remove-Item $child.PSPath -Recurse -Force
                $removed++
            }
        }
        Set-Item -Path $shellPath -Value 'open'
    }
    return $removed
}

function Read-ManualProfiles {
    $result = New-Object System.Collections.Generic.List[string]
    Write-Host ''
    Write-Host 'Enter one profile name at a time. Press Enter on an empty line when finished.' -ForegroundColor Cyan
    Write-Host 'Most special characters are supported; a double quote (") is not supported.'
    while ($true) {
        $name = Read-Host 'Profile name'
        if ([string]::IsNullOrWhiteSpace($name)) { break }
        $name = $name.Trim()
        if (-not (Test-ProfileNameSafe -Name $name)) {
            Write-Host 'That profile name cannot be represented safely in PotPlayer config="..." syntax.' -ForegroundColor Red
            continue
        }
        Add-UniqueProfile -List $result -Name $name
    }
    return @($result.ToArray() | Sort-Object)
}

function Select-ProfilesToRemove {
    param([string[]]$InstalledProfiles)
    if ($InstalledProfiles.Count -eq 0) {
        Write-Host 'No Explorer profile entries are installed.' -ForegroundColor Yellow
        return @()
    }
    $sorted = @($InstalledProfiles | Sort-Object)
    Write-Host ''
    Write-Host 'Explorer profiles:' -ForegroundColor Cyan
    for ($i = 0; $i -lt $sorted.Count; $i++) { Write-Host ('  {0,2}. {1}' -f ($i + 1), $sorted[$i]) }
    Write-Host ''
    Write-Host 'Enter numbers separated by commas, ALL, or press Enter to cancel.'
    $choiceText = (Read-Host 'Remove').Trim()
    if ([string]::IsNullOrWhiteSpace($choiceText)) { return @() }
    if ($choiceText -ieq 'ALL') { return @($sorted) }

    $selected = New-Object System.Collections.Generic.List[string]
    foreach ($part in @($choiceText -split ',')) {
        $index = 0
        if ([int]::TryParse($part.Trim(), [ref]$index) -and $index -ge 1 -and $index -le $sorted.Count) {
            Add-UniqueProfile -List $selected -Name $sorted[$index - 1]
        }
    }
    return $selected.ToArray()
}

function Format-ProfileSummary {
    param([string[]]$Profiles, [int]$MaxShown = 5)
    $items = @($Profiles | Sort-Object)
    if ($items.Count -eq 0) { return 'None' }
    if ($items.Count -le $MaxShown) { return ($items -join ', ') }
    $shown = @($items[0..($MaxShown - 1)]) -join ', '
    return ('{0} (+{1} more)' -f $shown, ($items.Count - $MaxShown))
}

function Show-CompactPlan {
    param([object]$State, [object]$Inventory, [switch]$IncludeRemovals)

    Write-Host ''
    Write-Host 'Planned:' -ForegroundColor Cyan
    $anything = $false

    if (@($State.Missing).Count -gt 0) {
        Write-Host ('  Add:    ' + (@($State.Missing) -join ', ')) -ForegroundColor Green
        $anything = $true
    }
    if (@($State.RepairProfiles).Count -gt 0) {
        Write-Host ('  Repair: ' + (@($State.RepairProfiles) -join ', ')) -ForegroundColor Yellow
        $anything = $true
    }

    if ($IncludeRemovals) {
        if (@($State.ExplorerOnly).Count -gt 0) {
            Write-Host ('  Remove extra profiles (confirmation required): ' + (@($State.ExplorerOnly) -join ', ')) -ForegroundColor DarkYellow
            $anything = $true
        }
        $cleanupCount = @($Inventory.BrokenPaths).Count + @($Inventory.DuplicatePaths).Count
        if ($cleanupCount -gt 0) {
            Write-Host ("  Cleanup stale/duplicate registrations (confirmation required): $cleanupCount") -ForegroundColor DarkYellow
            $anything = $true
        }
    }

    if (-not $anything) {
        Write-Host '  Nothing to change.' -ForegroundColor Green
    }
    Write-Host ''
}

function Show-Preview {
    param([object]$State, [object]$Inventory, [string[]]$ShellPaths, [string]$Exe, [string]$DefaultProfile, [switch]$IncludeRemovals)
    Write-Host ''
    Write-Host 'Planned changes (dry run):' -ForegroundColor Cyan
    $hasWrites = (@($State.Missing).Count -gt 0 -or @($State.RepairIssues).Count -gt 0)
    if (-not $hasWrites -and -not $IncludeRemovals) {
        Write-Host '  No writes are required.' -ForegroundColor Green
    }

    foreach ($name in @($State.Missing)) {
        $expectedCommand = Get-ExpectedCommand -Exe $Exe -ConfigName $name
        Write-Host ("  ADD {0} on {1} managed video type(s)" -f $name, $ShellPaths.Count) -ForegroundColor Green
        foreach ($shellPath in $ShellPaths) {
            $verbPath = Join-Path $shellPath (Get-ProfileVerbName -ConfigName $name)
            Write-Host ("      Key:     {0}" -f $verbPath)
            Write-Host ("      Command: {0}" -f $expectedCommand)
        }
    }

    $groups = @($State.RepairIssues | Group-Object Profile)
    foreach ($group in $groups) {
        Write-Host ("  REPAIR {0} on {1} video type(s)" -f $group.Name, $group.Count) -ForegroundColor Yellow
        foreach ($issue in @($group.Group)) {
            Write-Host ("      Key:      {0}" -f $issue.VerbPath)
            Write-Host ("      Reasons:  {0}" -f (@($issue.Reasons) -join ', '))
            Write-Host ("      Expected: {0}" -f $issue.ExpectedCommand)
            if (-not [string]::IsNullOrWhiteSpace([string]$issue.ActualCommand)) {
                Write-Host ("      Actual:   {0}" -f $issue.ActualCommand)
            } else {
                Write-Host '      Actual:   (missing)'
            }
        }
    }

    if ($IncludeRemovals) {
        foreach ($name in @($State.ExplorerOnly)) {
            Write-Host "  REMOVE Explorer-only profile: $name" -ForegroundColor DarkYellow
            foreach ($entry in @($Inventory.Entries | Where-Object { $_.Name -ieq $name })) {
                Write-Host ("      Key: {0}" -f $entry.VerbPath)
            }
        }
        foreach ($path in @($Inventory.BrokenPaths)) { Write-Host "  REMOVE broken managed entry: $path" -ForegroundColor DarkYellow }
        foreach ($path in @($Inventory.DuplicatePaths)) { Write-Host "  REMOVE duplicate managed entry: $path" -ForegroundColor DarkYellow }
    }

    if (-not [string]::IsNullOrWhiteSpace($DefaultProfile)) {
        Write-Host "  Default/top profile: $DefaultProfile"
    }
    Write-Host ''
}

function Write-DiagnosticsReport {
    param(
        [string]$Exe,
        [string[]]$ShellPaths,
        [object]$Detection,
        [object]$Inventory,
        [object]$State,
        [string]$DefaultProfile,
        [bool]$PotPlayerRunning
    )

    $reportPath = Join-Path $LogsDir ("diagnostics_{0}.txt" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(($AppName + ' v' + $AppVersion + ' diagnostics'))
    $lines.Add(('Generated: ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))
    $lines.Add(('Application version: ' + $AppVersion))
    $lines.Add(('Registry schema: ' + $SchemaVersion))
    $lines.Add(('Script folder: ' + $ScriptRoot))
    $lines.Add(('Log folder: ' + $LogsDir))
    $lines.Add(('Backup folder: ' + $BackupsDir))
    $lines.Add(('PotPlayer executable: ' + $Exe))
    $lines.Add(('PotPlayer executable exists: ' + (Test-Path -LiteralPath $Exe)))
    $lines.Add(('PotPlayer running: ' + $PotPlayerRunning))
    $lines.Add(('Default/top profile: ' + $DefaultProfile))
    $lines.Add(('Managed video ProgIDs: ' + $ShellPaths.Count))
    $lines.Add('')
    $lines.Add('Profile detection sources:')
    if (@($Detection.Sources).Count -eq 0) { $lines.Add('  (none)') } else { foreach ($s in @($Detection.Sources)) { $lines.Add('  ' + $s) } }
    $lines.Add('')
    $lines.Add('Detected PotPlayer profiles:')
    if (@($Detection.Profiles).Count -eq 0) { $lines.Add('  (none)') } else { foreach ($p in @($Detection.Profiles)) { $lines.Add('  ' + $p) } }
    if (@($Detection.UnsafeProfiles).Count -gt 0) {
        $lines.Add('Unsafe/unrepresentable profiles:')
        foreach ($p in @($Detection.UnsafeProfiles)) { $lines.Add('  ' + $p) }
    }
    $lines.Add('')
    $lines.Add('Explorer profiles:')
    if (@($Inventory.Names).Count -eq 0) { $lines.Add('  (none)') } else { foreach ($p in @($Inventory.Names)) { $lines.Add('  ' + $p) } }
    $lines.Add('')
    $lines.Add(('In sync: ' + $State.IsInSync))
    $lines.Add(('Missing profiles: ' + (@($State.Missing) -join ', ')))
    $lines.Add(('Explorer-only profiles: ' + (@($State.ExplorerOnly) -join ', ')))
    $lines.Add(('Broken managed entries: ' + @($Inventory.BrokenPaths).Count))
    $lines.Add(('Duplicate managed entries: ' + @($Inventory.DuplicatePaths).Count))
    $lines.Add('')
    $lines.Add('Registration issues:')
    if (@($State.RepairIssues).Count -eq 0) {
        $lines.Add('  (none)')
    } else {
        foreach ($issue in @($State.RepairIssues)) {
            $lines.Add(('  Profile: ' + $issue.Profile))
            $lines.Add(('  Shell:   ' + $issue.ShellPath))
            $lines.Add(('  Reason:  ' + (@($issue.Reasons) -join ', ')))
            $lines.Add(('  Expected command: ' + $issue.ExpectedCommand))
            $lines.Add(('  Actual command:   ' + $issue.ActualCommand))
            $lines.Add('')
        }
    }
    if (@($Inventory.BrokenPaths).Count -gt 0) {
        $lines.Add('Broken paths:')
        foreach ($p in @($Inventory.BrokenPaths)) { $lines.Add('  ' + $p) }
    }
    if (@($Inventory.DuplicatePaths).Count -gt 0) {
        $lines.Add('Duplicate paths:')
        foreach ($p in @($Inventory.DuplicatePaths)) { $lines.Add('  ' + $p) }
    }

    $lines | Set-Content -LiteralPath $reportPath -Encoding UTF8
    Write-Host ''
    Write-Host 'Detailed diagnostics:' -ForegroundColor Cyan
    foreach ($line in $lines) { Write-Host $line }
    Write-Host ''
    Write-Host "Diagnostics saved to: $reportPath" -ForegroundColor Green
    Write-LogLine ("Diagnostics saved: {0}" -f $reportPath)
    return $reportPath
}

function Set-DefaultProfileInteractive {
    param([string[]]$DetectedProfiles, [string]$CurrentDefault)
    Write-Host ''
    Write-Host 'Default/top profile setting' -ForegroundColor Cyan
    Write-Host 'Windows supports Position=Top for one verb. Other entries keep their normal Explorer ordering.'
    Write-Host ''
    Write-Host '0. No forced top profile'
    for ($i = 0; $i -lt $DetectedProfiles.Count; $i++) {
        $marker = ''
        if (-not [string]::IsNullOrWhiteSpace($CurrentDefault) -and $DetectedProfiles[$i].Equals($CurrentDefault, [System.StringComparison]::OrdinalIgnoreCase)) { $marker = ' [current]' }
        Write-Host ('{0,2}. {1}{2}' -f ($i + 1), $DetectedProfiles[$i], $marker)
    }
    Write-Host ''
    $choiceText = (Read-Host 'Selection [cancel]').Trim()
    if ([string]::IsNullOrWhiteSpace($choiceText)) { return $CurrentDefault }
    $index = -1
    if (-not [int]::TryParse($choiceText, [ref]$index)) { return $CurrentDefault }
    if ($index -eq 0) { return '' }
    if ($index -ge 1 -and $index -le $DetectedProfiles.Count) { return $DetectedProfiles[$index - 1] }
    return $CurrentDefault
}

Assert-Administrator
Write-LogLine ("Starting {0} v{1}; registry schema {2}" -f $AppName, $AppVersion, $SchemaVersion)

$exe = Get-PotPlayerExecutable
if ([string]::IsNullOrWhiteSpace($exe) -or -not (Test-SafeFilePath -Path $exe)) {
    Write-Host 'PotPlayerMini64.exe could not be found automatically.' -ForegroundColor Red
    Write-Host 'Checked App Paths, existing managed entries, Program Files, and PATH.'
    Write-Host ''
    $manualExeRaw = Read-Host 'Enter the full path to PotPlayerMini64.exe, or press Enter to quit'
    $manualExe = ConvertTo-PotPlayerExePath -Value $manualExeRaw
    if ([string]::IsNullOrWhiteSpace($manualExe) -or -not (Test-SafeFilePath -Path $manualExe)) {
        Write-Host 'No valid PotPlayer executable was supplied.' -ForegroundColor Red
        Write-LogLine 'ERROR: PotPlayer executable not found.'
        Pause-Continue 'Press Enter to close'
        exit 1
    }
    $exe = [string](Get-Item -LiteralPath $manualExe).FullName
}

$exeDir = [System.IO.Path]::GetDirectoryName($exe)
if ([string]::IsNullOrWhiteSpace($exeDir)) {
    Write-Host "Could not determine the PotPlayer installation folder from: $exe" -ForegroundColor Red
    Pause-Continue 'Press Enter to close'
    exit 1
}

$videoExts = @(
    '3G2','3GP','3GP2','3GPP','AMV','ASF','AVI','AVS','DIVX','DMSKM','DPG','DVR-MS',
    'EVO','F4V','FLV','IFO','K3G','LMP4','M1V','M2T','M2TS','M2V','M4V','MKV','MOV',
    'MP2V','MP4','MPE','MPEG','MPG','MPV2','MQV','MTS','MXF','NSR','NSV','OGM','OGV',
    'PMP','PSS','PVA','QT','RM','RMVB','SKM','TP','TPR','TRP','TS','VOB','VP6','WEBM',
    'WM','WMP','WMV','WTV'
)

$shellPaths = @(Get-ManagedShellPaths -VideoExts $videoExts)
if ($shellPaths.Count -eq 0) {
    Write-Host 'No PotPlayer video ProgID shell registrations were found.' -ForegroundColor Red
    Write-LogLine 'ERROR: No PotPlayerMini64.* shell paths found.'
    Pause-Continue 'Press Enter to close'
    exit 1
}

$iniCandidates = New-Object System.Collections.Generic.List[string]
if (-not [string]::IsNullOrWhiteSpace($env:APPDATA)) { $iniCandidates.Add((Join-Path $env:APPDATA 'PotPlayerMini64\PotPlayerMini64.ini')) }
if (-not [string]::IsNullOrWhiteSpace($exeDir)) { $iniCandidates.Add((Join-Path $exeDir 'PotPlayerMini64.ini')) }

try {
    $quitRequested = $false
    while ($true) {
        Clear-Host
        $settings = Get-ToolSettings
        $detection = Get-DetectedProfileInfo -IniCandidates $iniCandidates.ToArray()
        $detected = @($detection.Profiles)
        $inventory = Get-ExplorerInventory -ShellPaths $shellPaths
        $installed = @($inventory.Names)
        $defaultProfile = [string]$settings.DefaultProfile
        if (-not [string]::IsNullOrWhiteSpace($defaultProfile) -and -not (Test-ProfileInList -List $detected -Name $defaultProfile)) {
            $defaultProfile = ''
        }
        $state = Get-SyncState -DetectedProfiles $detected -Inventory $inventory -ShellPaths $shellPaths -Exe $exe -DefaultProfile $defaultProfile
        $potPlayerRunning = (@(Get-Process -Name 'PotPlayerMini64' -ErrorAction SilentlyContinue).Count -gt 0)

        Write-Host ("{0} v{1}" -f $AppName, $AppVersion) -ForegroundColor Cyan
        Write-Host '-----------------------------------'
        Write-Host ('PotPlayer profiles: ' + (Format-ProfileSummary -Profiles $detected))

        if ($detected.Count -eq 0) {
            Write-Host 'Explorer status: Automatic sync unavailable' -ForegroundColor Yellow
        }
        elseif ($state.IsInSync) {
            Write-Host 'Explorer status: Up to date' -ForegroundColor Green
        }
        else {
            $parts = New-Object System.Collections.Generic.List[string]
            if (@($state.Missing).Count -gt 0) { $parts.Add(('{0} to add' -f @($state.Missing).Count)) }
            if (@($state.RepairProfiles).Count -gt 0) { $parts.Add(('{0} to repair' -f @($state.RepairProfiles).Count)) }
            if (@($state.ExplorerOnly).Count -gt 0) { $parts.Add(('{0} extra profile(s)' -f @($state.ExplorerOnly).Count)) }
            $cleanupCount = @($inventory.BrokenPaths).Count + @($inventory.DuplicatePaths).Count
            if ($cleanupCount -gt 0) { $parts.Add(('{0} stale item(s)' -f $cleanupCount)) }
            $summary = if ($parts.Count -gt 0) { $parts.ToArray() -join ', ' } else { 'changes needed' }
            Write-Host ("Explorer status: Needs sync ($summary)") -ForegroundColor Yellow
        }

        if (@($detection.UnsafeProfiles).Count -gt 0) {
            Write-Host ("Skipped profiles: {0} (see Advanced > Diagnostics)" -f @($detection.UnsafeProfiles).Count) -ForegroundColor Yellow
        }

        Write-Host ''
        if ($detected.Count -eq 0) {
            Write-Host '[Enter] Exit'
            Write-Host 'A       Advanced'
            Write-Host 'Q       Quit'
            Write-Host ''
            $choice = (Read-Host 'Selection').Trim()
            if ([string]::IsNullOrWhiteSpace($choice) -or $choice -ieq 'Q') { break }
        }
        elseif ($state.IsInSync) {
            Write-Host '[Enter] Exit'
            Write-Host 'A       Advanced'
            Write-Host ''
            $choice = (Read-Host 'Selection').Trim()
            if ([string]::IsNullOrWhiteSpace($choice) -or $choice -ieq 'Q') { break }
        }
        else {
            Write-Host '[Enter] Sync'
            Write-Host 'A       Advanced'
            Write-Host 'Q       Quit'
            Write-Host ''
            $choice = (Read-Host 'Selection').Trim()
            if ([string]::IsNullOrWhiteSpace($choice)) { $choice = 'S' }
            if ($choice -ieq 'Q') { break }
        }

        if ($choice -ieq 'A') {
            $leaveAdvanced = $false
            while (-not $leaveAdvanced) {
                Clear-Host
                Write-Host 'Advanced' -ForegroundColor Cyan
                Write-Host '--------'
                Write-Host ('PotPlayer: ' + $exe)
                Write-Host ('Profiles:  ' + (Format-ProfileSummary -Profiles $detected -MaxShown 10))
                Write-Host ("Video types: $($shellPaths.Count)")
                Write-Host ''
                Write-Host 'P = detailed dry-run preview'
                Write-Host 'D = diagnostics + save report'
                if ($detected.Count -gt 0) {
                    Write-Host 'N = add/repair only'
                    Write-Host 'R = rebuild tool-managed entries'
                    Write-Host 'O = choose/clear top profile'
                }
                Write-Host 'M = add profile manually'
                Write-Host 'U = manage/remove Explorer profiles'
                Write-Host 'F = refresh detection'
                Write-Host 'B = back'
                Write-Host 'Q = quit'
                Write-Host ''
                $advancedChoice = (Read-Host 'Selection [B]').Trim()
                if ([string]::IsNullOrWhiteSpace($advancedChoice)) { $advancedChoice = 'B' }

                if ($advancedChoice -ieq 'B') { $leaveAdvanced = $true; continue }
                if ($advancedChoice -ieq 'Q') { $quitRequested = $true; $leaveAdvanced = $true; continue }
                if ($advancedChoice -ieq 'F') { $leaveAdvanced = $true; continue }

                if ($advancedChoice -ieq 'D') {
                    [void](Write-DiagnosticsReport -Exe $exe -ShellPaths $shellPaths -Detection $detection -Inventory $inventory -State $state -DefaultProfile $defaultProfile -PotPlayerRunning $potPlayerRunning)
                    Pause-Continue
                    continue
                }
                if ($advancedChoice -ieq 'P') {
                    Show-Preview -State $state -Inventory $inventory -ShellPaths $shellPaths -Exe $exe -DefaultProfile $defaultProfile -IncludeRemovals
                    Pause-Continue
                    continue
                }
                if ($advancedChoice -ieq 'O' -and $detected.Count -gt 0) {
                    $newDefault = Set-DefaultProfileInteractive -DetectedProfiles $detected -CurrentDefault $defaultProfile
                    if ($newDefault -cne $defaultProfile) {
                        Save-ToolSettings -DefaultProfile $newDefault
                        Write-Host 'Top-profile preference saved.' -ForegroundColor Green
                        Pause-Continue
                    }
                    $leaveAdvanced = $true
                    continue
                }
                if ($advancedChoice -ieq 'M') {
                    $manualProfiles = @(Read-ManualProfiles)
                    if ($manualProfiles.Count -gt 0) {
                        Show-CompactPlan -State ([PSCustomObject]@{ Missing=$manualProfiles; RepairProfiles=@(); ExplorerOnly=@() }) -Inventory $inventory
                        $confirm = (Read-Host 'Apply? [y/N]').Trim()
                        if ($confirm -ieq 'Y' -or $confirm -ieq 'YES') {
                            [void](Ensure-RegistryBackup -ShellPaths $shellPaths)
                            Add-MissingProfiles -Profiles $manualProfiles -ShellPaths $shellPaths -Exe $exe -DefaultProfile $defaultProfile
                            Write-Host 'Manual profile entries written.' -ForegroundColor Green
                        }
                        Pause-Continue
                    }
                    $leaveAdvanced = $true
                    continue
                }
                if ($advancedChoice -ieq 'U') {
                    $targets = @(Select-ProfilesToRemove -InstalledProfiles $installed)
                    if ($targets.Count -gt 0) {
                        Write-Host ('Would remove: ' + ($targets -join ', '))
                        $confirm = (Read-Host 'Apply removal? [y/N]').Trim()
                        if ($confirm -ieq 'Y' -or $confirm -ieq 'YES') {
                            [void](Ensure-RegistryBackup -ShellPaths $shellPaths)
                            [void](Remove-ExplorerProfiles -ProfileNames $targets -ShellPaths $shellPaths)
                            Write-Host 'Selected Explorer profile entries removed.' -ForegroundColor Green
                        }
                        Pause-Continue
                    }
                    $leaveAdvanced = $true
                    continue
                }
                if ($advancedChoice -ieq 'R' -and $detected.Count -gt 0) {
                    Write-Host ''
                    Write-Host 'Rebuild recreates only this tool''s managed entries.' -ForegroundColor Yellow
                    $confirm = (Read-Host 'Rebuild now? [y/N]').Trim()
                    if ($confirm -ieq 'Y' -or $confirm -ieq 'YES') {
                        [void](Ensure-RegistryBackup -ShellPaths $shellPaths)
                        [void](Remove-AllToolManagedEntries -ShellPaths $shellPaths)
                        Add-MissingProfiles -Profiles $detected -ShellPaths $shellPaths -Exe $exe -DefaultProfile $defaultProfile
                        Write-Host 'Tool-managed entries rebuilt.' -ForegroundColor Green
                    }
                    Pause-Continue
                    $leaveAdvanced = $true
                    continue
                }
                if ($advancedChoice -ieq 'N' -and $detected.Count -gt 0) {
                    Show-CompactPlan -State $state -Inventory $inventory
                    if (@($state.Missing).Count -eq 0 -and @($state.RepairIssues).Count -eq 0) {
                        Write-Host 'No add/repair changes are needed.' -ForegroundColor Green
                        Pause-Continue
                    } else {
                        if ($potPlayerRunning) { Write-Host 'PotPlayer is running; unsaved profile edits inside PotPlayer may not be visible yet.' -ForegroundColor Yellow }
                        $confirm = (Read-Host 'Apply add/repair changes? [Y/n]').Trim()
                        if ([string]::IsNullOrWhiteSpace($confirm)) { $confirm = 'Y' }
                        if ($confirm -ieq 'Y' -or $confirm -ieq 'YES') {
                            [void](Ensure-RegistryBackup -ShellPaths $shellPaths)
                            if (@($state.Missing).Count -gt 0) { Add-MissingProfiles -Profiles @($state.Missing) -ShellPaths $shellPaths -Exe $exe -DefaultProfile $defaultProfile }
                            if (@($state.RepairIssues).Count -gt 0) { Repair-ProfileIssues -Issues @($state.RepairIssues) -Exe $exe -DefaultProfile $defaultProfile }
                            Write-Host 'Done. Backup saved under Backups.' -ForegroundColor Green
                        }
                        Pause-Continue
                    }
                    $leaveAdvanced = $true
                    continue
                }
            }
            if ($quitRequested) { break }
            continue
        }

        if ($choice -ieq 'S' -and $detected.Count -gt 0) {
            Show-CompactPlan -State $state -Inventory $inventory -IncludeRemovals
            if ($potPlayerRunning) {
                Write-Host 'PotPlayer is running; unsaved profile edits inside PotPlayer may not be visible yet.' -ForegroundColor Yellow
            }

            $didChange = $false
            $hasWrites = (@($state.Missing).Count -gt 0 -or @($state.RepairIssues).Count -gt 0)
            if ($hasWrites) {
                $confirm = (Read-Host 'Apply add/repair changes? [Y/n]').Trim()
                if ([string]::IsNullOrWhiteSpace($confirm)) { $confirm = 'Y' }
                if (-not ($confirm -ieq 'Y' -or $confirm -ieq 'YES')) { continue }

                [void](Ensure-RegistryBackup -ShellPaths $shellPaths)
                if (@($state.Missing).Count -gt 0) {
                    Add-MissingProfiles -Profiles @($state.Missing) -ShellPaths $shellPaths -Exe $exe -DefaultProfile $defaultProfile
                }
                if (@($state.RepairIssues).Count -gt 0) {
                    Repair-ProfileIssues -Issues @($state.RepairIssues) -Exe $exe -DefaultProfile $defaultProfile
                }
                $didChange = $true
            }

            $hasRemovals = (@($state.ExplorerOnly).Count -gt 0 -or @($inventory.BrokenPaths).Count -gt 0 -or @($inventory.DuplicatePaths).Count -gt 0)
            if ($hasRemovals) {
                $removeConfirm = (Read-Host 'Also remove extra/invalid entries? [y/N]').Trim()
                if ($removeConfirm -ieq 'Y' -or $removeConfirm -ieq 'YES') {
                    [void](Ensure-RegistryBackup -ShellPaths $shellPaths)
                    if (@($state.ExplorerOnly).Count -gt 0) { [void](Remove-ExplorerProfiles -ProfileNames @($state.ExplorerOnly) -ShellPaths $shellPaths) }
                    if (@($inventory.BrokenPaths).Count -gt 0) { [void](Remove-PathsSafely -Paths @($inventory.BrokenPaths)) }
                    if (@($inventory.DuplicatePaths).Count -gt 0) { [void](Remove-PathsSafely -Paths @($inventory.DuplicatePaths)) }
                    $didChange = $true
                }
            }

            if ($didChange) {
                Write-Host 'Done. Backup saved under Backups.' -ForegroundColor Green
            } else {
                Write-Host 'No changes made.' -ForegroundColor Yellow
            }
            Pause-Continue 'Press Enter to refresh'
            continue
        }
    }
}
catch {
    Write-Host ''
    Write-Host ('Unexpected error: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host ('Exception type: ' + $_.Exception.GetType().FullName) -ForegroundColor DarkYellow
    if (-not [string]::IsNullOrWhiteSpace([string]$_.InvocationInfo.PositionMessage)) {
        Write-Host $_.InvocationInfo.PositionMessage -ForegroundColor DarkYellow
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$_.ScriptStackTrace)) {
        Write-Host 'Stack trace:' -ForegroundColor DarkYellow
        Write-Host $_.ScriptStackTrace -ForegroundColor DarkYellow
    }
    Write-LogLine ("FATAL TYPE: {0}`r`nMESSAGE: {1}`r`nPOSITION: {2}`r`nSTACK: {3}" -f $_.Exception.GetType().FullName, $_.Exception.Message, $_.InvocationInfo.PositionMessage, $_.ScriptStackTrace)
    Write-Host "Log: $LogPath"
    Write-Host "Events: $EventLogPath"
    Pause-Continue 'Press Enter to close'
    exit 1
}
finally {
    if ($script:TranscriptStarted) {
        try { Stop-Transcript | Out-Null } catch {}
    }
}
