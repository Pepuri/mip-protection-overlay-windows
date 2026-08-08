# Configuration

The installer creates this file only when it does not already exist:

```text
C:\ProgramData\PurviewProtectionOverlay\config.json
```

Upgrades preserve the administrator's existing configuration.

## Default configuration

```json
{
  "watchRoots": ["%FIXED_DRIVES%"],
  "extensions": [
    ".doc", ".docx", ".xls", ".xlsx",
    ".ppt", ".pptx", ".pdf", ".pfile"
  ],
  "excludedPaths": [
    "%SystemRoot%",
    "%ProgramFiles%",
    "%ProgramFiles(x86)%",
    "%ProgramData%",
    "%USERPROFILE%\\AppData"
  ],
  "excludeOneDrive": true,
  "reconciliationMinutes": 15,
  "eventDebounceMilliseconds": 750,
  "maxConcurrentInspections": 2,
  "watcherBufferKilobytes": 64
}
```

## Settings

### `watchRoots`

Directories scanned and monitored by the Agent. `%FIXED_DRIVES%` expands to all
ready fixed NTFS volumes. Environment variables are supported.

To limit the workload to common user folders:

```json
"watchRoots": [
  "%USERPROFILE%\\Desktop",
  "%USERPROFILE%\\Documents",
  "%USERPROFILE%\\Downloads"
]
```

### `extensions`

Only listed extensions are inspected. The Explorer DLL currently recognizes the
same built-in Office/PDF/PFILE set. When adding another extension, update
`IsSupportedExtension()` in the native source and rebuild the DLL.

### `excludedPaths`

The scanner does not enumerate these directories or their descendants.
Environment variables are expanded in the logged-on user's context.

Never remove exclusions for Windows, Program Files, ProgramData, recovery, or
system metadata directories without measuring the resulting workload.

### `excludeOneDrive`

When `true`, paths discovered from `OneDrive`, `OneDriveCommercial`, and
`OneDriveConsumer` environment variables are excluded. OneDrive Files On-Demand
does not reliably invoke third-party classic overlay handlers, so scanning those
paths wastes resources in the supported configuration.

### `reconciliationMinutes`

Full scan interval. File system events update the cache between scans. The full
scan repairs missed events and stale entries.

### `maxConcurrentInspections`

Maximum concurrent MIP SDK status checks. Keep this between 1 and 4 on typical
client devices.

## Applying a change

```powershell
Stop-Process -Name PurviewProtectionAgent -Force -ErrorAction SilentlyContinue
Start-Process "$env:ProgramFiles\PurviewProtectionOverlay\Agent\PurviewProtectionAgent.exe"
```

The Explorer process does not need to be restarted for cache changes.

