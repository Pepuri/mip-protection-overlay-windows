# MIP Protection Overlay v1.0.0-preview.1

First public preview for Windows 10/11 x64.

## Highlights

- Shows a red `MIP` overlay on MIP-protected Office, PDF, and PFILE files.
- Uses the offline MIP SDK status API; no Tenant ID or user authentication.
- Keeps MIP processing out of Explorer through a per-user local cache.
- Includes silent install/uninstall and Intune Win32 deployment scripts.
- Excludes Windows, application, profile data, recovery, and OneDrive paths by
  default.

## Important

This is preview software. Test on a non-production Windows device before wider
deployment. The preview binaries may be unsigned; enterprise administrators
should build and sign project-owned binaries with a trusted code-signing
certificate.

## Known limitations

- OneDrive Files On-Demand is not supported.
- Windows exposes a limited number of classic overlay slots.
- Network drives and ARM64 are not validated.
- A sign-out or Windows restart is normally required after install, upgrade, or
  uninstall.

