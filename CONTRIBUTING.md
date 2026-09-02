# Contributing

Contributions to PotPlayer Profile Context Menu are welcome.

## Development environment

The project targets Windows PowerShell 5.1 first. Please avoid syntax or APIs that require PowerShell 7 unless an equivalent Windows PowerShell 5.1 implementation is included.

Useful test environments:

- Windows 10 + Windows PowerShell 5.1
- Windows 11 + Windows PowerShell 5.1
- PotPlayer 64-bit with registry-based settings
- PotPlayer 64-bit with INI-based settings

## Before opening a pull request

1. Run the setup script on a test machine or VM.
2. Verify profile discovery.
3. Verify a media file opens with the expected profile.
4. Re-run setup and confirm it reports `Explorer status: Up to date`.
5. Run the removal utility and verify native PotPlayer entries remain intact.
6. Confirm no personal logs, `.reg` backups, or local settings files are committed.
7. Keep public version references at `1.0` unless the change is intentionally preparing a new release.

The GitHub validation workflow performs PowerShell parser checks against `app/`, validates the 1.0 metadata, builds the release ZIP, and verifies its top-level package structure.

## Registry safety

Changes involving registry discovery/removal should be conservative:

- Never silently remove unrelated Explorer verbs.
- Preserve native PotPlayer entries.
- Back up affected shell keys before destructive changes.
- Treat malformed registry values as data to ignore/report, not as a reason to crash.
- Keep ownership metadata explicit.

## Pull requests

Please explain:

- What behavior changes.
- Why the change is needed.
- Which Windows/PowerShell versions were tested.
- Whether registry schema or ownership behavior changes.

Do not include private diagnostic logs without reviewing/redacting usernames, computer names, and filesystem paths.
