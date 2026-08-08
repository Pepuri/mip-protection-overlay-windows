# Build guide

## Prerequisites

Install the following components on an x64 Windows build machine:

1. Visual Studio 2022 Build Tools
2. Desktop development with C++
3. CMake tools for Windows
4. Windows 10/11 SDK
5. .NET 8 SDK
6. PowerShell 5.1 or later

Verify:

```powershell
cmake --version
dotnet --info
```

## Build all components

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
cd C:\source\mip-protection-overlay-windows
.\scripts\Build.ps1 -Clean
.\scripts\Validate-Package.ps1 -RequireBuildArtifacts
```

`Build.ps1` performs these operations:

1. Generates the deterministic red `MIP` multi-resolution ICO file.
2. Builds the native x64 in-process Explorer extension.
3. Restores the MIP SDK NuGet package.
4. Publishes the .NET 8 agent as a self-contained x64 application.
5. Copies release files to `artifacts`.

## Build output

```text
artifacts/
├─ PurviewProtectionOverlay.dll
├─ Protected.ico
└─ Agent/
   ├─ PurviewProtectionAgent.exe
   ├─ Microsoft.InformationProtection*.dll
   └─ MIP native dependencies
```

Do not commit the `artifacts`, `build`, `bin`, or `obj` directories.

## Code signing

Sign the native DLL, Agent executable, and other project-owned executable files
before building the Intune package. Do not sign Microsoft-supplied dependencies
with your certificate.

Example using SignTool:

```powershell
$timestamp = 'http://timestamp.digicert.com'
signtool sign /fd SHA256 /td SHA256 /tr $timestamp `
  /sha1 '<CODE-SIGNING-CERTIFICATE-THUMBPRINT>' `
  .\artifacts\PurviewProtectionOverlay.dll `
  .\artifacts\Agent\PurviewProtectionAgent.exe
```

Verify:

```powershell
signtool verify /pa /v .\artifacts\PurviewProtectionOverlay.dll
signtool verify /pa /v .\artifacts\Agent\PurviewProtectionAgent.exe
```

## Version updates

Before publishing a new version, update all of the following:

- `src/agent/ProtectionAgent.csproj` `<Version>`
- `src/agent/Program.cs` `Version`
- `packaging/intune/Install.ps1` default `Version`
- `packaging/intune/Detect.ps1` required version
- release notes and Git tag

