# Microsoft Intune deployment

## 1. Build and optionally sign

```powershell
.\scripts\Build.ps1 -Clean
.\scripts\Validate-Package.ps1 -RequireBuildArtifacts
```

For production, sign project-owned executables before packaging.

## 2. Build `.intunewin`

```powershell
.\packaging\intune\Build-IntunePackage.ps1 `
  -IntuneWinAppUtilPath 'C:\Tools\IntuneWinAppUtil.exe' `
  -VCRedistPath 'C:\Tools\VC_redist.x64.exe'
```

There are two supported prerequisite approaches:

1. Deploy Microsoft Visual C++ Redistributable 2022 x64 (14.3 or later) as an
   Intune dependency and omit `-VCRedistPath`.
2. Pass Microsoft's official `VC_redist.x64.exe` to include and silently install
   it when missing.

Upload:

```text
artifacts\IntunePackage\Install.intunewin
```

## 3. Intune application settings

| Setting | Value |
|---|---|
| App type | Windows app (Win32) |
| Name | MIP Protection Overlay |
| Publisher | Community / your organization |
| App version | 1.0.0 |
| Install behavior | System |
| Device restart behavior | Determine behavior based on return codes |

### Install command

```text
Install.cmd
```

### Uninstall command

The uninstall script is copied into the installed product folder so the command
does not depend on the original Intune staging directory:

```text
"C:\Program Files\PurviewProtectionOverlay\Uninstall.cmd"
```

The wrapper selects 64-bit Windows PowerShell. This also avoids relying on
environment-variable expansion in Intune's uninstall command field.

### Return codes

| Code | Intune type |
|---:|---|
| 0 | Success |
| 3010 | Soft reboot |
| 1 | Failed |

The installation normally returns `3010` because Explorer must unload/reload the
in-process DLL. Do not force-close Explorer during a production Intune install.

## 4. Requirements

- Operating system architecture: 64-bit
- Minimum operating system: organization-supported Windows 10/11 release
- Disk space: at least 500 MB

The .NET runtime and MIP SDK files are included in the self-contained Agent
payload. The supported Microsoft Visual C++ 2022 x64 Runtime must also be
installed, either as a dependency or from the optional packaged redistributable.

## 5. Detection rule

Choose **Use a custom detection script** and upload:

```text
packaging\intune\Detect.ps1
```

Settings:

- Run script as 32-bit process on 64-bit clients: **No**
- Enforce script signature check: according to organizational policy

Detection requires:

- `HKLM\SOFTWARE\PurviewProtectionOverlay\Version >= 1.0.0`
- native overlay DLL;
- overlay icon;
- Agent executable.

## 6. Assignment strategy

1. Assign as **Available** or **Required** to a small device pilot group.
2. Restart or sign out/in after installation.
3. Validate protected and unprotected files in an ordinary local NTFS folder.
4. Monitor Agent logs and CPU/disk activity for at least several days.
5. Expand to a broader ring only after the pilot succeeds.

## 7. Upgrade

Create a new Win32 app for the new version and configure Intune Supersedence.
The installer preserves `ProgramData\PurviewProtectionOverlay\config.json`.

The installer renames a previously loaded overlay DLL before installing the new
version. Files named `*.legacy.*.dll` can be deleted after Windows restarts.

## 8. Uninstall

Remove the Required install assignment before assigning the same group to
Uninstall. Restart or sign out/in after the uninstall so Explorer unloads the
extension.

By default, user cache and logs remain for troubleshooting. To remove caches from
all local profiles, run the installed uninstall script with `-RemoveUserCaches`.
