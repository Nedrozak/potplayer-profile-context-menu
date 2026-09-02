# Security Policy

## Supported version

The current supported public release is **1.0**.

## Reporting a security issue

If you find behavior that could cause unintended registry deletion, command execution, privilege misuse, or unsafe handling of profile/path data, please report it privately to the repository maintainer instead of posting exploit details in a public issue.

Until a private contact method is configured on the repository, use GitHub's private vulnerability reporting feature if enabled under **Security → Advisories → Report a vulnerability**.

## Scope and privileges

The utility requests Administrator rights because PotPlayer Explorer registrations are managed under `HKLM\Software\Classes`.

The project is designed to:

- Modify only recognized PotPlayer profile context-menu registrations.
- Create registry backups before changes.
- Avoid silently deleting unrelated Explorer entries.
- Avoid network access.

## Logs and privacy

PowerShell transcript logs can contain Windows usernames, machine names, and local filesystem paths. Diagnostics can also contain the PotPlayer executable path and registry paths. Review/redact files before posting them publicly.
