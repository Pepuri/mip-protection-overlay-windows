# Blog and video publishing guide

## Recommended article title

> Display MIP-protected documents with an icon in Windows File Explorer

## Blog outline

1. The problem users experience
2. The completed result
3. The difference between protection and a label without protection
4. Why Explorer should not inspect files directly
5. The agent-to-cache-to-overlay architecture
6. Authentication-free MIP SDK `GetFileStatus()`
7. Building the source
8. Local installation and validation
9. Intune Win32 app packaging
10. Detection rules and restart behavior
11. Performance and system-path exclusions
12. Why OneDrive is not supported
13. Code-signing and production deployment considerations
14. GitHub collaboration and licensing

Avoid claims that this project is a Microsoft product, replaces a commercial
product, supports every MIP file, or is production-ready without validation.

## YouTube structure (about 12 minutes)

| Time | Section |
|---|---|
| 00:00 | Show the completed red MIP icon overlay on a protected file |
| 00:40 | Explain the problem and project goal |
| 01:30 | Review supported and unsupported scenarios |
| 02:20 | Explain the agent, cache, and overlay architecture |
| 04:00 | Introduce the GitHub repository and build process |
| 05:30 | Demonstrate local installation and the protection-status probe |
| 07:00 | Create an Intune `.intunewin` package |
| 08:30 | Configure Intune installation, removal, and detection |
| 10:20 | Review logs and troubleshooting steps |
| 11:10 | Explain OneDrive and code-signing limitations |
| 11:50 | Share the GitHub link and closing notes |

Show the result first. Use the GitHub README as the canonical instructions so
the blog and video do not become outdated when scripts change.
