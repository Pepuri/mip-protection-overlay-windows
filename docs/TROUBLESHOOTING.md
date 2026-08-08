# Troubleshooting

## Diagnostic order

Check the system in this order:

1. Does the offline MIP probe report `isProtected: true`?
2. Is the normalized file path in the user cache?
3. Is the x64 DLL registered in HKLM?
4. Has Explorer loaded the DLL?
5. Is another overlay consuming the available Explorer overlay position?

## 1. Test protection status

```powershell
cd C:\source\mip-protection-overlay-windows
.\scripts\Test-ProtectionStatus.ps1 -Path 'C:\test\protected.xlsx'
```

Expected:

```json
"isProtected": true
```

Exit codes:

- `0`: file inspected successfully;
- `2`: unsupported, inaccessible, invalid, or SDK inspection error.

## 2. Check the cache

```powershell
$cache = "$env:LOCALAPPDATA\PurviewProtectionOverlay\protected-files.txt"
$agent = "$env:ProgramFiles\PurviewProtectionOverlay\Agent\PurviewProtectionAgent.exe"
Get-Content $cache
```

The exact normalized full path must appear in the file. Run a one-time full scan:

```powershell
Start-Process $agent -ArgumentList '--once' -Wait
```

## 3. Check registration

```powershell
$clsid = '{3AF57D64-BC9A-4F16-AB7A-34C56498B0B1}'
Get-ItemProperty "HKLM:\SOFTWARE\Classes\CLSID\$clsid\InprocServer32"
Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ShellIconOverlayIdentifiers' |
    Select-Object PSChildName
```

## 4. Check whether Explorer loaded the DLL

Run an elevated 64-bit PowerShell:

```powershell
Get-Process explorer | ForEach-Object {
    $_.Modules | Where-Object ModuleName -eq 'PurviewProtectionOverlay.dll'
} | Select-Object ModuleName, FileName
```

If no result appears, sign out/in or restart Windows. A new Explorer window does
not necessarily create a new Explorer process.

## 5. Check Agent startup

```powershell
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' `
    -Name PurviewProtectionAgent
Get-Process PurviewProtectionAgent -ErrorAction SilentlyContinue
```

The Agent runs in each interactive user's context. It must not run solely as
SYSTEM because the cache is per-user.

## 6. Read logs

```powershell
$log = "$env:LOCALAPPDATA\PurviewProtectionOverlay\Logs\Agent.log"
Get-Content $log -Tail 100
```

`File watcher error` triggers a watcher rebuild. The periodic reconciliation
scan repairs missed file events.

## Overlay slot limitation

Windows has a limited number of classic overlay slots. OneDrive and other sync
clients may occupy available slots. Registration order is not an absolute
guarantee because Windows applies its own selection rules.

## OneDrive

OneDrive Files On-Demand paths are intentionally unsupported. Even when the
Agent detects and caches a protected OneDrive file, Windows may not call the
classic overlay handler for the placeholder item. Keep `excludeOneDrive` set to
`true` for the supported configuration.

## Installation reports success but files are missing

Intune install runs as SYSTEM. Check:

```text
C:\Program Files\PurviewProtectionOverlay
C:\ProgramData\PurviewProtectionOverlay\config.json
HKLM\SOFTWARE\PurviewProtectionOverlay
```

Then sign in as the target user and confirm that the Agent starts from the HKLM
Run entry.
