[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,
    [switch]$RestartExplorer
)

$ErrorActionPreference = 'Stop'
$resolved = (Resolve-Path $Path).Path
$cacheRoot = Join-Path $env:LOCALAPPDATA 'PurviewProtectionOverlay'
$cachePath = Join-Path $cacheRoot 'protected-files.txt'
$dll = "$env:ProgramFiles\PurviewProtectionOverlay\PurviewProtectionOverlay.dll"
$clsid = '{3AF57D64-BC9A-4F16-AB7A-34C56498B0B1}'
$overlayKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ShellIconOverlayIdentifiers\  MIP Protection Overlay'
$classKey = "HKLM:\SOFTWARE\Classes\CLSID\$clsid\InprocServer32"

New-Item $cacheRoot -ItemType Directory -Force | Out-Null
$cached = if (Test-Path $cachePath) { @(Get-Content $cachePath) } else { @() }
if ($cached -notcontains $resolved) {
    @($cached + $resolved | Sort-Object -Unique) |
        Set-Content $cachePath -Encoding UTF8
}

if ($RestartExplorer) {
    Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    Start-Process explorer.exe
    Start-Sleep -Seconds 3
}

$loaded = @(Get-Process explorer -ErrorAction SilentlyContinue | ForEach-Object {
    $_.Modules | Where-Object ModuleName -eq 'PurviewProtectionOverlay.dll'
})

[pscustomobject]@{
    File = $resolved
    CachePath = $cachePath
    CacheContainsFile = @((Get-Content $cachePath) | Where-Object { $_ -ieq $resolved }).Count -gt 0
    NativeDllExists = Test-Path $dll
    RegisteredNativeDll = if (Test-Path $classKey) { (Get-Item $classKey).GetValue('') } else { $null }
    NativeRegistrationOK = (Test-Path $classKey) -and ((Get-Item $classKey).GetValue('') -ieq $dll)
    OverlayRegistrationOK = (Test-Path $overlayKey) -and ((Get-Item $overlayKey).GetValue('') -eq $clsid)
    ExplorerLoadedDll = $loaded.Count -gt 0
}

Write-Host "Open the containing folder and refresh Explorer. This test forces cache membership; it does not prove MIP status."
