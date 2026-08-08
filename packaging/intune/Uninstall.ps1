[CmdletBinding()]
param(
    [string]$InstallRoot = "$env:ProgramFiles\PurviewProtectionOverlay",
    [switch]$RestartExplorer,
    [switch]$RemoveUserCaches
)

$ErrorActionPreference = 'Stop'
$clsid = '{3AF57D64-BC9A-4F16-AB7A-34C56498B0B1}'
$overlayName = '  MIP Protection Overlay'
$requiresRestart = $false

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DelayedDelete {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool MoveFileEx(string existingFile, string newFile, int flags);
    public static bool Schedule(string path) { return MoveFileEx(path, null, 0x4); }
}
'@

# Unload the native extension before deleting its DLL. Doing this after the
# deletion attempt can schedule a newly reinstalled file for deletion at reboot.
if ($RestartExplorer) {
    Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
}

Get-Process -Name PurviewProtectionAgent -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

$registryPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ShellIconOverlayIdentifiers\$overlayName",
    "HKLM:\SOFTWARE\Classes\CLSID\$clsid",
    'HKLM:\SOFTWARE\PurviewProtectionOverlay'
)
foreach ($path in $registryPaths) {
    Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
}

Remove-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved' `
    -Name $clsid -Force -ErrorAction SilentlyContinue
Remove-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' `
    -Name PurviewProtectionAgent -Force -ErrorAction SilentlyContinue

if (Test-Path $InstallRoot) {
    try {
        Remove-Item $InstallRoot -Recurse -Force
    }
    catch {
        $requiresRestart = $true
        Get-ChildItem $InstallRoot -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            [void][DelayedDelete]::Schedule($_.FullName)
        }
        Write-Warning 'Some loaded files are scheduled for deletion during the next Windows restart.'
    }
}

if ($RemoveUserCaches) {
    Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $cache = Join-Path $_.FullName 'AppData\Local\PurviewProtectionOverlay'
        Remove-Item $cache -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($RestartExplorer) {
    Start-Process explorer.exe
    exit 0
}

Write-Host 'Purview Protection Overlay uninstalled. Sign out or restart Windows to unload the Explorer extension.'
if ($requiresRestart) { exit 3010 }
exit 3010
