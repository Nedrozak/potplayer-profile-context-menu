# PotPlayer Profile Context Menu v1.0 - release builder
# SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
    [string]$Version
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$VersionFile = Join-Path $RepoRoot 'VERSION'

if (-not (Test-Path -LiteralPath $VersionFile)) {
    throw 'VERSION file not found.'
}

$RepoVersion = (Get-Content -LiteralPath $VersionFile -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = $RepoVersion
}

if ($Version -cne $RepoVersion) {
    throw "Requested version '$Version' does not match VERSION '$RepoVersion'."
}

$Dist = Join-Path $RepoRoot 'dist'
$PackageName = "PotPlayer-Profile-Context-Menu-v$Version"
$PackageRoot = Join-Path $Dist $PackageName
$ZipPath = Join-Path $Dist ($PackageName + '.zip')
$ChecksumPath = Join-Path $Dist 'SHA256SUMS.txt'

if (Test-Path -LiteralPath $PackageRoot) { Remove-Item -LiteralPath $PackageRoot -Recurse -Force }
if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }
if (Test-Path -LiteralPath $ChecksumPath) { Remove-Item -LiteralPath $ChecksumPath -Force }
if (-not (Test-Path -LiteralPath $Dist)) { New-Item -ItemType Directory -Path $Dist -Force | Out-Null }
New-Item -ItemType Directory -Path $PackageRoot -Force | Out-Null

$RuntimeFiles = @(
    '1.Setup_PotPlayer_Profiles.cmd',
    '2.Remove_PotPlayer_Profiles.cmd',
    'PotPlayer_Profiles_Setup.ps1',
    'PotPlayer_Profiles_Remove.ps1'
)

foreach ($File in $RuntimeFiles) {
    $Source = Join-Path (Join-Path $RepoRoot 'app') $File
    if (-not (Test-Path -LiteralPath $Source)) { throw "Required app file missing: app/$File" }
    Copy-Item -LiteralPath $Source -Destination $PackageRoot
}

$ReleaseDocs = @(
    'README.txt',
    'LICENSE'
)

foreach ($File in $ReleaseDocs) {
    $Source = Join-Path $RepoRoot $File
    if (-not (Test-Path -LiteralPath $Source)) { throw "Required release file missing: $File" }
    Copy-Item -LiteralPath $Source -Destination $PackageRoot
}

# Compress the package directory itself so extracting the ZIP creates one clean
# top-level folder instead of dropping loose files into Downloads/Desktop.
Compress-Archive -LiteralPath $PackageRoot -DestinationPath $ZipPath -CompressionLevel Optimal

$Hash = Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256
("{0}  {1}" -f $Hash.Hash.ToLowerInvariant(), [System.IO.Path]::GetFileName($ZipPath)) |
    Set-Content -LiteralPath $ChecksumPath -Encoding ASCII

Write-Host "Release folder: $PackageRoot" -ForegroundColor Green
Write-Host "Release ZIP:    $ZipPath" -ForegroundColor Green
Write-Host "SHA256:         $ChecksumPath" -ForegroundColor Green
