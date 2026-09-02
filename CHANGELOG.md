# Changelog

All notable public changes to this project are documented here.

## 1.0 — 2026-09-02

Initial public release.

### Added

- Automatic discovery of existing PotPlayer configuration profiles.
- Registry and INI-mode profile discovery.
- Windows Explorer context-menu registration for detected profiles.
- Exact full-command validation using the verified `"PotPlayerMini64.exe" "%1" config="Profile"` argument order.
- Detection and repair of stale executable paths, metadata, menu text, position, and commands.
- Selective repair across managed PotPlayer video ProgIDs.
- Automatic registry backups before changes.
- Compact normal interface with advanced maintenance options.
- Dry-run preview and detailed diagnostics.
- Local logs and backups beside the launcher scripts.
- Optional top-profile placement.
- Clean tool-managed removal utility.
- Windows PowerShell 5.1 support.
