[CmdletBinding()]
param(
    [string]$IntuneWinAppUtilPath,
    [string]$VCRedistPath,
    [switch]$SkipIntuneWin
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$artifactRoot = Join-Path $repoRoot 'artifacts'
$stageRoot = Join-Path $artifactRoot 'IntuneStage'
$payloadRoot = Join-Path $stageRoot 'payload'
$outputRoot = Join-Path $artifactRoot 'IntunePackage'

& (Join-Path $repoRoot 'scripts\Validate-Package.ps1') -RequireBuildArtifacts

Remove-Item $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item $payloadRoot -ItemType Directory -Force | Out-Null
New-Item $outputRoot -ItemType Directory -Force | Out-Null

Copy-Item (Join-Path $PSScriptRoot 'Install.cmd') $stageRoot
Copy-Item (Join-Path $PSScriptRoot 'Uninstall.cmd') $stageRoot
Copy-Item (Join-Path $PSScriptRoot 'Install.ps1') $stageRoot
Copy-Item (Join-Path $PSScriptRoot 'Uninstall.ps1') $stageRoot
Copy-Item (Join-Path $PSScriptRoot 'Detect.ps1') $stageRoot
Copy-Item (Join-Path $artifactRoot 'PurviewProtectionOverlay.dll') $payloadRoot
Copy-Item (Join-Path $artifactRoot 'Protected.ico') $payloadRoot
Copy-Item (Join-Path $artifactRoot 'Agent') $payloadRoot -Recurse
Copy-Item (Join-Path $repoRoot 'config\config.json') (Join-Path $payloadRoot 'config.json')
if ($VCRedistPath) {
    if (-not (Test-Path $VCRedistPath)) {
        throw "VC++ Redistributable not found: $VCRedistPath"
    }
    Copy-Item $VCRedistPath (Join-Path $payloadRoot 'VC_redist.x64.exe') -Force
}

if ($SkipIntuneWin) {
    Write-Host "Intune staging directory created: $stageRoot"
    return
}

if (-not $IntuneWinAppUtilPath) {
    $IntuneWinAppUtilPath = (Get-Command IntuneWinAppUtil.exe -ErrorAction SilentlyContinue).Source
}
if (-not $IntuneWinAppUtilPath -or -not (Test-Path $IntuneWinAppUtilPath)) {
    throw 'IntuneWinAppUtil.exe was not found. Pass -IntuneWinAppUtilPath or use -SkipIntuneWin.'
}

& $IntuneWinAppUtilPath -c $stageRoot -s Install.cmd -o $outputRoot -q
if ($LASTEXITCODE -ne 0) {
    throw "IntuneWinAppUtil failed. ExitCode=$LASTEXITCODE"
}

Write-Host "Intune package created: $outputRoot"
