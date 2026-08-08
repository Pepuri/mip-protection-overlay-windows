# Contributing

Contributions are welcome through GitHub issues and pull requests.

## Before opening a pull request

1. Do not include documents, user paths, tenant data, logs, credentials, or
   signing material.
2. Build on Windows x64.
3. Run:

   ```powershell
   .\scripts\Build.ps1 -Clean
   .\scripts\Validate-Package.ps1 -RequireBuildArtifacts
   ```

4. Test installation and removal on a disposable Windows VM.
5. Document new settings and limitations.

## Design constraints

- Explorer code must remain fast and must not open or inspect document content.
- Network calls and MIP SDK calls must remain outside Explorer.
- Cache writes must be atomic.
- System paths must remain excluded by default.
- Do not claim OneDrive support without a repeatable test across supported
  Windows and OneDrive versions.

