[CmdletBinding()]
param(
    [string]$InstallRoot = "$env:ProgramFiles\PurviewProtectionOverlay",
    [string]$Version = '1.0.0',
    [switch]$RestartExplorer
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$clsid = '{3AF57D64-BC9A-4F16-AB7A-34C56498B0B1}'
$overlayName = '  MIP Protection Overlay'
$sourceRoot = Join-Path $PSScriptRoot 'payload'
$sourceAgent = Join-Path $sourceRoot 'Agent'
$sourceConfig = Join-Path $sourceRoot 'config.json'
$installAgent = Join-Path $InstallRoot 'Agent'
$installDll = Join-Path $InstallRoot 'PurviewProtectionOverlay.dll'
$installIcon = Join-Path $InstallRoot 'Protected.ico'
$programDataRoot = Join-Path $env:ProgramData 'PurviewProtectionOverlay'
$programDataConfig = Join-Path $programDataRoot 'config.json'
$agentExe = Join-Path $installAgent 'PurviewProtectionAgent.exe'
$uninstallSource = Join-Path $PSScriptRoot 'Uninstall.ps1'
$uninstallTarget = Join-Path $InstallRoot 'Uninstall.ps1'
$uninstallCmdSource = Join-Path $PSScriptRoot 'Uninstall.cmd'
$uninstallCmdTarget = Join-Path $InstallRoot 'Uninstall.cmd'
$legacyFiles = [System.Collections.Generic.List[string]]::new()

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Administrator or SYSTEM privileges are required.'
    }
}

function Stop-Agent {
    Get-Process -Name PurviewProtectionAgent -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}

function Test-VCRuntime {
    $key = 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64'
    $runtime = Get-ItemProperty $key -ErrorAction SilentlyContinue
    return $runtime -and $runtime.Installed -eq 1 -and $runtime.Major -ge 14 -and $runtime.Minor -ge 30
}

function Move-LockedFileAside {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { return }

    $timestamp = Get-Date -Format 'yyyyMMddHHmmssfff'
    $directory = Split-Path -Parent $Path
    $name = [IO.Path]::GetFileNameWithoutExtension($Path)
    $extension = [IO.Path]::GetExtension($Path)
    $legacy = Join-Path $directory "$name.legacy.$timestamp$extension"
    try {
        Move-Item $Path $legacy -Force
        $legacyFiles.Add($legacy)
    }
    catch {
        throw "Could not replace loaded file '$Path'. Restart Windows and retry. $($_.Exception.Message)"
    }
}

function Set-DefaultRegistryValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Value
    )
    New-Item $Path -Force | Out-Null
    Set-Item $Path -Value $Value
}

Assert-Administrator

if (-not (Test-VCRuntime)) {
    $redist = Join-Path $sourceRoot 'VC_redist.x64.exe'
    if (-not (Test-Path $redist)) {
        throw 'Microsoft Visual C++ Redistributable 2022 x64 (14.3 or later) is required. Deploy it as an Intune dependency or rebuild the package with -VCRedistPath.'
    }

    $redistProcess = Start-Process $redist -ArgumentList '/install', '/quiet', '/norestart' -Wait -PassThru
    if ($redistProcess.ExitCode -notin @(0, 1638, 3010)) {
        throw "VC++ Redistributable installation failed. ExitCode=$($redistProcess.ExitCode)"
    }
}

$required = @(
    (Join-Path $sourceRoot 'PurviewProtectionOverlay.dll'),
    (Join-Path $sourceRoot 'Protected.ico'),
    (Join-Path $sourceAgent 'PurviewProtectionAgent.exe'),
    $sourceConfig
)
$missing = @($required | Where-Object { -not (Test-Path $_) })
if ($missing.Count -gt 0) {
    throw "The package payload is incomplete: $($missing -join ', ')"
}

Stop-Agent
New-Item $InstallRoot -ItemType Directory -Force | Out-Null
New-Item $installAgent -ItemType Directory -Force | Out-Null
New-Item $programDataRoot -ItemType Directory -Force | Out-Null

Move-LockedFileAside $installDll
Copy-Item (Join-Path $sourceRoot 'PurviewProtectionOverlay.dll') $installDll -Force
Copy-Item (Join-Path $sourceRoot 'Protected.ico') $installIcon -Force

Get-ChildItem $sourceAgent -File -Recurse | ForEach-Object {
    $relative = $_.FullName.Substring($sourceAgent.Length).TrimStart('\')
    $destination = Join-Path $installAgent $relative
    New-Item (Split-Path -Parent $destination) -ItemType Directory -Force | Out-Null
    try {
        Copy-Item $_.FullName $destination -Force
    }
    catch {
        Move-LockedFileAside $destination
        Copy-Item $_.FullName $destination -Force
    }
}

if (-not (Test-Path $programDataConfig)) {
    Copy-Item $sourceConfig $programDataConfig -Force
}
Copy-Item $uninstallSource $uninstallTarget -Force
Copy-Item $uninstallCmdSource $uninstallCmdTarget -Force

$classKey = "HKLM:\SOFTWARE\Classes\CLSID\$clsid"
$inprocKey = Join-Path $classKey 'InprocServer32'
Set-DefaultRegistryValue -Path $classKey -Value 'Purview Protection Overlay'
Set-DefaultRegistryValue -Path $inprocKey -Value $installDll
New-ItemProperty $inprocKey -Name ThreadingModel -Value Apartment -PropertyType String -Force | Out-Null

$approvedKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved'
New-Item $approvedKey -Force | Out-Null
New-ItemProperty $approvedKey -Name $clsid -Value 'Purview Protection Overlay' -PropertyType String -Force | Out-Null

$overlayKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ShellIconOverlayIdentifiers\$overlayName"
Set-DefaultRegistryValue -Path $overlayKey -Value $clsid

$runKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
New-Item $runKey -Force | Out-Null
New-ItemProperty $runKey -Name PurviewProtectionAgent `
    -Value "`"$agentExe`"" -PropertyType String -Force | Out-Null

$productKey = 'HKLM:\SOFTWARE\PurviewProtectionOverlay'
New-Item $productKey -Force | Out-Null
New-ItemProperty $productKey -Name Version -Value $Version -PropertyType String -Force | Out-Null
New-ItemProperty $productKey -Name InstallPath -Value $InstallRoot -PropertyType String -Force | Out-Null
New-ItemProperty $productKey -Name OverlayClsid -Value $clsid -PropertyType String -Force | Out-Null
New-ItemProperty $productKey -Name InstalledOn -Value ([DateTimeOffset]::Now.ToString('o')) -PropertyType String -Force | Out-Null

$currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if ($currentSid -ne 'S-1-5-18') {
    Start-Process $agentExe
}

if ($RestartExplorer) {
    Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    Start-Process explorer.exe
    exit 0
}

Write-Host "Purview Protection Overlay $Version installed. Sign out or restart Windows to load the Explorer extension."
if ($legacyFiles.Count -gt 0) {
    Write-Warning "Old loaded files were renamed and can be removed after Windows restarts: $($legacyFiles -join '; ')"
}
exit 3010
