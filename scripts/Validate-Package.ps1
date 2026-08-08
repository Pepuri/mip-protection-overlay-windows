[CmdletBinding()]
param(
    [switch]$RequireBuildArtifacts
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$requiredSource = @(
    'src\native\OverlayHandler.cpp',
    'src\native\CMakeLists.txt',
    'src\agent\Program.cs',
    'src\agent\ProtectionAgent.csproj',
    'packaging\intune\Install.ps1',
    'packaging\intune\Uninstall.ps1',
    'packaging\intune\Detect.ps1',
    'config\config.json',
    'README.md',
    'LICENSE'
)

$missing = @($requiredSource | Where-Object { -not (Test-Path (Join-Path $repoRoot $_)) })
if ($missing.Count -gt 0) {
    throw "Missing repository files: $($missing -join ', ')"
}

Get-ChildItem $repoRoot -File -Recurse |
    Where-Object Name -Match '\.(pfx|p12|snk)$' |
    ForEach-Object { throw "Private key material must not be published: $($_.FullName)" }

$suspicious = Get-ChildItem $repoRoot -File -Recurse |
    Where-Object {
        $_.FullName -NotMatch '\\(build|artifacts|\.git)\\' -and
        $_.FullName -ne $MyInvocation.MyCommand.Path
    } |
    Select-String -Pattern '(?i)(client[_-]?secret\s*[:=]\s*["''][^"'']+|BEGIN PRIVATE KEY|password\s*[:=]\s*["''][^"'']+)' `
        -ErrorAction SilentlyContinue
if ($suspicious) {
    throw "Potential secret found: $($suspicious[0].Path):$($suspicious[0].LineNumber)"
}

if ($RequireBuildArtifacts) {
    $requiredArtifacts = @(
        'artifacts\PurviewProtectionOverlay.dll',
        'artifacts\Protected.ico',
        'artifacts\Agent\PurviewProtectionAgent.exe'
    )
    $missingArtifacts = @($requiredArtifacts | Where-Object { -not (Test-Path (Join-Path $repoRoot $_)) })
    if ($missingArtifacts.Count -gt 0) {
        throw "Missing built artifacts: $($missingArtifacts -join ', ')"
    }
}

Write-Host 'Repository validation completed successfully.'
