[CmdletBinding()]
param(
    [switch]$InstallBuildPrerequisites,
    [string]$VCRedistPath,
    [switch]$RestartExplorer
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$repoRoot = Split-Path -Parent $PSScriptRoot
$artifactRoot = Join-Path $repoRoot 'artifacts'
$stageRoot = Join-Path $artifactRoot 'LocalStage'
$payloadRoot = Join-Path $stageRoot 'payload'
$sourceAgent = Join-Path $artifactRoot 'Agent'

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this script from an elevated 64-bit Windows PowerShell session.'
    }
}

function Test-VCRuntime {
    $key = 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64'
    $runtime = Get-ItemProperty $key -ErrorAction SilentlyContinue
    return $runtime -and $runtime.Installed -eq 1 -and `
        $runtime.Major -ge 14 -and $runtime.Minor -ge 30
}

function Assert-MicrosoftVCRedist {
    param([Parameter(Mandatory)][string]$Path)

    $signature = Get-AuthenticodeSignature $Path
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        throw "The Visual C++ Redistributable signature is not valid: $Path"
    }
    if ($signature.SignerCertificate.Subject -notmatch 'Microsoft Corporation') {
        throw "The Visual C++ Redistributable is not signed by Microsoft Corporation: $Path"
    }
}

function Get-VCRedist {
    if ($VCRedistPath) {
        $resolved = (Resolve-Path $VCRedistPath -ErrorAction Stop).Path
        Assert-MicrosoftVCRedist $resolved
        return $resolved
    }
    if (Test-VCRuntime) { return $null }

    $prerequisiteRoot = Join-Path $artifactRoot 'Prerequisites'
    $downloadPath = Join-Path $prerequisiteRoot 'VC_redist.x64.exe'
    New-Item $prerequisiteRoot -ItemType Directory -Force | Out-Null
    Write-Host 'Downloading Microsoft Visual C++ Redistributable 2022 x64...'
    Invoke-WebRequest 'https://aka.ms/vs/17/release/vc_redist.x64.exe' `
        -OutFile $downloadPath -UseBasicParsing
    Assert-MicrosoftVCRedist $downloadPath
    return $downloadPath
}

Assert-Administrator
if (-not [Environment]::Is64BitOperatingSystem) {
    throw 'Windows x64 is required.'
}
if (-not [Environment]::Is64BitProcess) {
    throw 'Run the script with 64-bit Windows PowerShell.'
}

if ($InstallBuildPrerequisites) {
    & (Join-Path $PSScriptRoot 'Install-BuildPrerequisites.ps1')
}

Write-Host 'Building the native overlay and protection agent...'
& (Join-Path $PSScriptRoot 'Build.ps1') -Clean
& (Join-Path $PSScriptRoot 'Validate-Package.ps1') -RequireBuildArtifacts

$redist = Get-VCRedist

Remove-Item $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item $payloadRoot -ItemType Directory -Force | Out-Null

$installerRoot = Join-Path $repoRoot 'packaging\intune'
Copy-Item (Join-Path $installerRoot 'Install.cmd') $stageRoot
Copy-Item (Join-Path $installerRoot 'Install.ps1') $stageRoot
Copy-Item (Join-Path $installerRoot 'Uninstall.cmd') $stageRoot
Copy-Item (Join-Path $installerRoot 'Uninstall.ps1') $stageRoot
Copy-Item (Join-Path $artifactRoot 'PurviewProtectionOverlay.dll') $payloadRoot
Copy-Item (Join-Path $artifactRoot 'Protected.ico') $payloadRoot
Copy-Item $sourceAgent $payloadRoot -Recurse
Copy-Item (Join-Path $repoRoot 'config\config.json') `
    (Join-Path $payloadRoot 'config.json')

if ($redist) {
    Copy-Item $redist (Join-Path $payloadRoot 'VC_redist.x64.exe') -Force
}

$powerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$arguments = @(
    '-NoLogo', '-NoProfile', '-NonInteractive',
    '-ExecutionPolicy', 'Bypass',
    '-File', "`"$(Join-Path $stageRoot 'Install.ps1')`""
)
if ($RestartExplorer) { $arguments += '-RestartExplorer' }

Write-Host 'Running the local installer without user interaction...'
$install = Start-Process $powerShell -ArgumentList $arguments `
    -Wait -PassThru -WindowStyle Hidden

if ($install.ExitCode -notin @(0, 3010)) {
    throw "Silent installation failed. ExitCode=$($install.ExitCode)"
}

if ($install.ExitCode -eq 3010) {
    Write-Host 'Installation completed. Sign out or restart Windows to load the Explorer extension.'
}
else {
    Write-Host 'Installation completed successfully.'
}

exit $install.ExitCode
