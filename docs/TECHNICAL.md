# Technical notes

## Public version and registry schema

```text
Application version: 1.0
Registry schema:      1.0
ManagedBy:            PotPlayerProfileContextMenu
```

## Explorer command

For profile `MadVR`, the expected command is:

```text
"C:\Program Files\DAUM\PotPlayer\PotPlayerMini64.exe" "%1" config="MadVR"
```

The file argument must precede the `config=` option.

## Managed registrations

The utility checks PotPlayer 64-bit video ProgIDs under:

```text
HKLM\Software\Classes\PotPlayerMini64.<EXT>\shell
```

Profile verbs use a deterministic SHA-256-derived key name:

```text
open_profile_<16 hex characters>
```

The hash is based on the lower-cased profile name, giving stable case-insensitive identity while preserving the profile's display spelling in metadata and command text.

A healthy profile verb contains:

- Default value: `Open with (ProfileName)`
- `Icon`: full path to `PotPlayerMini64.exe`
- `PotPlayerConfig`: profile name
- `ManagedBy`: `PotPlayerProfileContextMenu`
- `SchemaVersion`: `1.0`
- Optional `Position=Top`
- `command` subkey default value containing the exact expected command

## Synchronization definition

A profile is considered synchronized only if all managed PotPlayer video shell paths have the canonical verb and all expected values match. This means a correct profile name alone is insufficient.

The setup detects:

- Missing profile registrations.
- Incorrect menu text.
- Incorrect icon/executable path.
- Incorrect profile metadata.
- Incorrect ownership/schema metadata.
- Incorrect top-position metadata.
- Missing or mismatched complete commands.
- Duplicate managed entries.
- Explorer-only profiles.

## Profile discovery

Registry mode uses:

```text
HKCU\Software\Daum\PotPlayerMini64\OptionList
```

INI discovery checks the roaming AppData and PotPlayer-install locations for `PotPlayerMini64.ini`.

## Executable discovery

The setup checks, in broad order:

1. Windows App Paths.
2. Existing managed profile registrations.
3. Standard Program Files locations.
4. `PATH` / `Get-Command`.
5. Manual user input.

Candidate values are normalized so quoted paths, icon-style values, and full existing command lines can still yield a valid executable path. Malformed candidates are ignored and logged rather than causing `Test-Path` to terminate setup.

## Backups

Before the first registry write/removal in a session, affected PotPlayer `shell` keys are exported with `reg.exe export`.

If a required export fails, destructive work is cancelled rather than proceeding without a reliable backup.

## Logs

The setup uses two log streams:

- `setup_*.log`: PowerShell transcript.
- `setup_*_events.log`: internal operation/event log.

They are separate to avoid Windows PowerShell 5.1 file-lock conflicts.


## Repository and release layout

Runtime source files are kept in `app/`. The repository itself is not the end-user package.

`scripts/Build-Release.ps1` copies only the four runtime files plus `README.txt` and `LICENSE` into a versioned staging folder, then archives that folder. Repository-only documentation and metadata are deliberately excluded from the end-user artifact. For v1.0 the artifact is:

```text
dist\PotPlayer-Profile-Context-Menu-v1.0.zip
```

The archive contains one `PotPlayer-Profile-Context-Menu-v1.0/` directory. GitHub Releases are created from tags matching `VERSION`, currently `v1.0`.
