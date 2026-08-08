[CmdletBinding()]
param(
    [ValidateSet('Release', 'Debug')]
    [string]$Configuration = 'Release',
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$buildRoot = Join-Path $repoRoot 'build'
$artifactRoot = Join-Path $repoRoot 'artifacts'
$nativeBuild = Join-Path $buildRoot 'native'
$agentOutput = Join-Path $artifactRoot 'Agent'

if ($Clean) {
    Remove-Item $buildRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $artifactRoot -Recurse -Force -ErrorAction SilentlyContinue
}

New-Item $artifactRoot -ItemType Directory -Force | Out-Null

& (Join-Path $PSScriptRoot 'Generate-Icon.ps1')

$cmake = Get-Command cmake.exe -ErrorAction SilentlyContinue
if (-not $cmake) {
    throw 'cmake.exe was not found. Install Visual Studio Build Tools with Desktop development with C++ and CMake tools.'
}

& $cmake.Source `
    -S (Join-Path $repoRoot 'src\native') `
    -B $nativeBuild `
    -A x64
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed. ExitCode=$LASTEXITCODE" }

& $cmake.Source --build $nativeBuild --config $Configuration --parallel
if ($LASTEXITCODE -ne 0) { throw "Native build failed. ExitCode=$LASTEXITCODE" }

$nativeDll = Get-ChildItem $nativeBuild -Filter PurviewProtectionOverlay.dll -Recurse |
    Where-Object FullName -Match "\\$Configuration\\" |
    Select-Object -First 1
if (-not $nativeDll) { throw 'Native overlay DLL was not produced.' }
Copy-Item $nativeDll.FullName (Join-Path $artifactRoot 'PurviewProtectionOverlay.dll') -Force
Copy-Item (Join-Path $repoRoot 'assets\Protected.ico') $artifactRoot -Force

dotnet publish (Join-Path $repoRoot 'src\agent\ProtectionAgent.csproj') `
    -c $Configuration `
    -r win-x64 `
    --self-contained true `
    -o $agentOutput
if ($LASTEXITCODE -ne 0) { throw "Agent publish failed. ExitCode=$LASTEXITCODE" }

Write-Host "Built native x64 overlay DLL: $(Join-Path $artifactRoot 'PurviewProtectionOverlay.dll')"
Write-Host "Built self-contained MIP status agent: $agentOutput"

