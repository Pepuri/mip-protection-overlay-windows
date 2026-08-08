# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [1.0.0-preview.1] - 2026-08-08

### Added

- Native x64 `IShellIconOverlayIdentifier` implementation.
- Red multi-resolution `MIP` overlay icon generated during the build.
- Offline MIP SDK `FileHandler.GetFileStatus()` protection detection.
- Per-user atomic protection cache.
- Exclusion-aware file watchers and periodic reconciliation scans.
- Default system-directory and OneDrive exclusions.
- Silent install, uninstall, Intune detection, and package staging scripts.
- GitHub build workflow and deployment documentation.

### Known limitations

- OneDrive Files On-Demand is not supported.
- Classic Windows overlay slot availability is not guaranteed.
- ARM64 and network drives have not been validated.
- Preview binaries may be unsigned.

