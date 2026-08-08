# MIP Protection Overlay for Windows

An independent community project that displays a red `MIP` icon overlay in
Windows File Explorer for **MIP-encrypted and protected Office and PDF files**.

> This is not an official Microsoft product and is not affiliated with,
> endorsed by, or supported by Microsoft. Validate the project on a dedicated
> test device and review your organization's code-signing and application
> control policies before deploying it to a production environment.

## Support matrix

| Item | Status |
|---|---|
| Windows 10/11 x64 | Supported |
| Standard local NTFS folders | Supported |
| DOC/DOCX/XLS/XLSX/PPT/PPTX/PDF/PFILE | Supported |
| Protected/unprotected status detection | Supported |
| Tenant ID or user authentication | Not required |
| Default system-folder exclusions | Included |
| Custom watch and exclusion paths | Supported |
| Intune Win32 app deployment | Supported |
| OneDrive Files On-Demand | **Not supported** |
| Network drives | Not validated |
| Windows on ARM64 | Not validated |

Windows does not guarantee that a standard `IShellIconOverlayIdentifier`
extension will be displayed inside a OneDrive sync root because Cloud Files
status indicators take precedence. The default configuration also excludes
OneDrive paths from inspection.

## Architecture

```mermaid
flowchart LR
    A[File created or changed] --> B[Per-user agent]
    B --> C[MIP SDK GetFileStatus]
    C --> D[Protected-file path cache]
    D --> E[Explorer overlay DLL]
    E --> F[Red MIP overlay]
```

The Explorer process does not load the MIP SDK or inspect document contents.
The native overlay DLL only compares paths against the following per-user
cache:

```text
%LOCALAPPDATA%\PurviewProtectionOverlay\protected-files.txt
```

The agent uses `FileHandler.GetFileStatus()`, available in MIP SDK 1.15 and
later. This API checks whether protection information exists in a file without
creating a file engine, authenticating a user, or requiring an internet
connection. It does not validate whether a label still exists in the tenant or
whether the current user has permission to decrypt the file.

## Requirements

- Windows 10/11 x64
- Visual Studio 2022 Build Tools
  - Desktop development with C++
  - CMake tools for Windows
- .NET 8 SDK
- PowerShell 5.1 or later
- Microsoft Win32 Content Prep Tool when creating an Intune package
- Microsoft Visual C++ Redistributable 2022 x64 14.3 or later on target devices

The Microsoft Purview Information Protection client is not required.

## Build

Run the following commands in a non-elevated PowerShell session:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
cd C:\source\mip-protection-overlay-windows
.\scripts\Build.ps1 -Clean
.\scripts\Validate-Package.ps1 -RequireBuildArtifacts
```

Build output:

```text
artifacts\PurviewProtectionOverlay.dll
artifacts\Protected.ico
artifacts\Agent\PurviewProtectionAgent.exe
```

See the [build guide](docs/BUILD.md) for details.

## Local installation

First, create the Intune staging directory:

```powershell
.\packaging\intune\Build-IntunePackage.ps1 -SkipIntuneWin
```

Then install it from an elevated PowerShell session:

```powershell
cd .\artifacts\IntuneStage
.\Install.ps1 -RestartExplorer
```

For normal deployments, do not forcibly restart Explorer. Allow the installer
to return `3010`; the DLL will be loaded after the user signs out or Windows is
restarted.

## Test protection status

```powershell
.\scripts\Test-ProtectionStatus.ps1 -Path 'C:\Documents\protected.xlsx'
```

Example output:

```json
{
  "path": "C:\\Documents\\protected.xlsx",
  "isProtected": true,
  "isLabeled": true,
  "containsProtectedObjects": false,
  "outcome": "Inspected"
}
```

## Create an Intune package

```powershell
.\packaging\intune\Build-IntunePackage.ps1 `
  -IntuneWinAppUtilPath 'C:\Tools\IntuneWinAppUtil.exe' `
  -VCRedistPath 'C:\Tools\VC_redist.x64.exe'
```

If `-VCRedistPath` is omitted, deploy the Visual C++ Runtime as a separate
Intune dependency before installing this application.

Generated package:

```text
artifacts\IntunePackage\Install.intunewin
```

See the [Intune deployment guide](docs/INTUNE-DEPLOYMENT.md) for app settings
and detection rules.

## Configuration

Configuration file after installation:

```text
%ProgramData%\PurviewProtectionOverlay\config.json
```

You can change file extensions, watch roots, exclusion paths, and the
reconciliation interval. Restart the agent after modifying the configuration.
See the [configuration guide](docs/CONFIGURATION.md) for details.

## Troubleshooting

Agent log:

```text
%LOCALAPPDATA%\PurviewProtectionOverlay\Logs\Agent.log
```

Both of the following conditions must be true for the icon to appear:

1. The agent inspection result must be `isProtected: true`.
2. The file path must exist in `protected-files.txt`, and Explorer must have
   loaded the overlay DLL.

If the icon does not appear, see the
[troubleshooting guide](docs/TROUBLESHOOTING.md).

## Security and privacy

- No Tenant ID, Client ID, Client Secret, or certificate is required.
- File contents and paths are not sent to an external service.
- Explorer does not open documents; it reads only the local cache.
- Preview binaries may be unsigned.
- For enterprise deployment, sign binaries with a code-signing certificate
  trusted by your organization.

## License

The project source code is available under the [MIT License](LICENSE).
Microsoft MIP SDK and other dependencies remain subject to their respective
licenses. Review the [third-party notices](THIRD-PARTY-NOTICES.md) before
redistribution.

## Official references

- [Get file status with the MIP SDK](https://learn.microsoft.com/information-protection/develop/concept-handler-file-status-cpp)
- [Set up the MIP SDK](https://learn.microsoft.com/information-protection/develop/setup-configure-mip)
- [Prepare an Intune Win32 app](https://learn.microsoft.com/intune/intune-service/apps/apps-win32-prepare)
- [Add an Intune Win32 app](https://learn.microsoft.com/intune/app-management/deployment/add-win32)
