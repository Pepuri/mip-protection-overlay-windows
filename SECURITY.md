# Security policy

## Supported versions

Only the latest GitHub release is supported for security fixes.

## Reporting a vulnerability

Do not open a public issue containing credentials, private documents, tenant
information, or exploit details. Use GitHub's private vulnerability reporting
feature when it is enabled for this repository.

Include:

- affected version;
- Windows version and architecture;
- reproduction steps using non-sensitive sample files;
- expected and actual behavior;
- relevant sanitized log entries.

## Security design

- Explorer loads only the native overlay DLL.
- The DLL reads a per-user local text cache and never opens protected documents.
- The background agent uses the offline MIP SDK `GetFileStatus()` API.
- No Tenant ID, Client Secret, user credential, or access token is required.
- No document content, file path, or status is transmitted by this project.
- Runtime logs and caches remain under the current user's Local AppData folder.

Compiled preview releases may be unsigned. Enterprise administrators should
build and sign binaries with a certificate trusted by their organization before
production deployment.

