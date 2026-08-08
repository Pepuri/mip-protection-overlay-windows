# One-command local deployment

This workflow builds, validates, stages, and silently installs the x64 project
from an elevated Windows PowerShell session. It does not sign files, create an
Intune package, upload anything to Intune, or restart Explorer by default.

## Prerequisites already installed

```powershell
git clone https://github.com/Pepuri/mip-protection-overlay-windows.git
cd .\mip-protection-overlay-windows

powershell.exe -NoLogo -NoProfile -NonInteractive `
  -ExecutionPolicy Bypass `
  -File .\scripts\Invoke-LocalDeployment.ps1
```

The command must run as an administrator. It performs the following operations:

1. Builds the native x64 Explorer extension.
2. Restores and publishes the self-contained .NET 8 MIP status agent.
3. Validates the generated artifacts.
4. Downloads the official Microsoft Visual C++ Redistributable when it is not
   already installed.
5. Creates `artifacts\LocalStage`.
6. Runs the installer without UI or user interaction.
7. Returns `3010` when sign-out or restart is required.

## Install missing build prerequisites automatically

The following command uses `winget` and Visual Studio Installer to install the
.NET 8 SDK and the required Visual Studio 2022 C++/CMake components when they
are missing:

```powershell
powershell.exe -NoLogo -NoProfile -NonInteractive `
  -ExecutionPolicy Bypass `
  -File .\scripts\Invoke-LocalDeployment.ps1 `
  -InstallBuildPrerequisites
```

Installing or modifying Visual Studio Build Tools can require a Windows
restart. If prerequisite validation reports that components remain unavailable,
restart Windows and run the same command again.

## Offline Visual C++ Runtime

Provide a previously downloaded official installer when the build machine has
no internet access:

```powershell
powershell.exe -NoLogo -NoProfile -NonInteractive `
  -ExecutionPolicy Bypass `
  -File .\scripts\Invoke-LocalDeployment.ps1 `
  -VCRedistPath 'C:\Packages\VC_redist.x64.exe'
```

NuGet restore and automatic prerequisite installation still require access to
their respective package sources. Configure an internal NuGet source or install
the prerequisites in advance for fully offline builds.

## Test-only Explorer restart

Use `-RestartExplorer` only on a dedicated test device:

```powershell
.\scripts\Invoke-LocalDeployment.ps1 -RestartExplorer
```

For normal silent installation, omit the switch and sign out or restart Windows
after the script returns `3010`.
