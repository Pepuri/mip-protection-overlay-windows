$ErrorActionPreference = 'SilentlyContinue'
$productKey = 'HKLM:\SOFTWARE\PurviewProtectionOverlay'
$installRoot = "$env:ProgramFiles\PurviewProtectionOverlay"
$requiredVersion = [Version]'1.0.0'

$installedVersionText = (Get-ItemProperty $productKey -Name Version).Version
$dll = Join-Path $installRoot 'PurviewProtectionOverlay.dll'
$icon = Join-Path $installRoot 'Protected.ico'
$agent = Join-Path $installRoot 'Agent\PurviewProtectionAgent.exe'

$validVersion = $false
try {
    $validVersion = ([Version]$installedVersionText -ge $requiredVersion)
}
catch {
    $validVersion = $false
}

if ($validVersion -and (Test-Path $dll) -and (Test-Path $icon) -and (Test-Path $agent)) {
    Write-Output "Purview Protection Overlay $installedVersionText is installed."
    exit 0
}

exit 1

