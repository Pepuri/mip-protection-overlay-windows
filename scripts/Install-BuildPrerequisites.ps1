[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this script from an elevated 64-bit Windows PowerShell session.'
    }
}

function Get-VsWherePath {
    $candidate = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path $candidate) { return $candidate }
    return $null
}

function Get-VsInstallation {
    $vsWhere = Get-VsWherePath
    if (-not $vsWhere) { return $null }
    $path = & $vsWhere -latest -products '*' -property installationPath
    if ($path) { return $path.Trim() }
    return $null
}

function Test-VsBuildComponents {
    $vsWhere = Get-VsWherePath
    if (-not $vsWhere) { return $false }
    $path = & $vsWhere -latest -products '*' `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
                  Microsoft.VisualStudio.Component.VC.CMake.Project `
        -property installationPath
    return -not [string]::IsNullOrWhiteSpace($path)
}

function Test-DotNet8Sdk {
    $dotnetCommand = Get-Command dotnet.exe -ErrorAction SilentlyContinue
    $dotnetPath = if ($dotnetCommand) { $dotnetCommand.Source } else { $null }
    if (-not $dotnetPath) {
        $candidate = Join-Path $env:ProgramFiles 'dotnet\dotnet.exe'
        if (Test-Path $candidate) { $dotnetPath = $candidate }
    }
    if (-not $dotnetPath) { return $false }
    $sdks = & $dotnetPath --list-sdks 2>$null
    return @($sdks | Where-Object { $_ -match '^8\.' }).Count -gt 0
}

function Invoke-Installer {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [Parameter(Mandatory)][string]$Name
    )

    $process = Start-Process $FilePath -ArgumentList $ArgumentList `
        -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -notin @(0, 3010)) {
        throw "$Name failed. ExitCode=$($process.ExitCode)"
    }
}

Assert-Administrator
if (-not [Environment]::Is64BitOperatingSystem) {
    throw 'Windows x64 is required.'
}

$winget = Get-Command winget.exe -ErrorAction SilentlyContinue
if ((-not (Test-DotNet8Sdk)) -or (-not (Test-VsBuildComponents))) {
    if (-not $winget) {
        throw 'winget.exe is required for automatic prerequisite installation.'
    }
}

if (-not (Test-DotNet8Sdk)) {
    & $winget.Source install --id Microsoft.DotNet.SDK.8 --exact --silent `
        --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "The .NET 8 SDK installation failed. ExitCode=$LASTEXITCODE"
    }
}

if (-not (Test-VsBuildComponents)) {
    $vsInstallation = Get-VsInstallation
    if ($vsInstallation) {
        $setup = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\setup.exe'
        if (-not (Test-Path $setup)) {
            throw 'The Visual Studio Installer setup executable was not found.'
        }
        Invoke-Installer -FilePath $setup -Name 'Visual Studio Build Tools modification' `
            -ArgumentList @(
                'modify', '--installPath', "`"$vsInstallation`"",
                '--quiet', '--wait', '--norestart', '--nocache',
                '--add', 'Microsoft.VisualStudio.Workload.VCTools',
                '--includeRecommended'
            )
    }
    else {
        & $winget.Source install --id Microsoft.VisualStudio.2022.BuildTools `
            --exact --silent --accept-package-agreements --accept-source-agreements `
            --override '--wait --quiet --norestart --nocache --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'
        if ($LASTEXITCODE -ne 0) {
            throw "Visual Studio Build Tools installation failed. ExitCode=$LASTEXITCODE"
        }
    }
}

if (-not (Test-DotNet8Sdk)) {
    throw 'The .NET 8 SDK is still unavailable. Restart Windows and run the script again.'
}
if (-not (Test-VsBuildComponents)) {
    throw 'The required C++ and CMake build components are still unavailable. Restart Windows and run the script again.'
}

Write-Host 'Build prerequisites are installed and ready.'
