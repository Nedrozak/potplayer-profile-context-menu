# PotPlayer Profile Context Menu

**Version 1.0**

Add your existing PotPlayer configuration profiles directly to the Windows Explorer right-click menu.

The utility automatically detects saved PotPlayer profiles, creates an Explorer entry for each profile, and verifies the **complete registered command** rather than checking profile names alone.

For example:

```text
"C:\Program Files\DAUM\PotPlayer\PotPlayerMini64.exe" "%1" config="MadVR"
```

## Features

- Automatically detects PotPlayer configuration profiles.
- Supports PotPlayer settings stored in the registry or `PotPlayerMini64.ini`.
- Adds profile-specific Explorer context-menu entries such as `Open with (MadVR)`.
- Validates the entire Explorer registration, including the executable path, menu text, profile metadata, position, and full command string.
- Detects moved/reinstalled PotPlayer executables and offers repair.
- Repairs only missing or incorrect entries instead of rewriting healthy ones.
- Creates a timestamped registry backup before registry changes.
- Includes dry-run preview and detailed diagnostics.
- Keeps logs and backups next to the launcher scripts.
- Supports one optional profile with Explorer `Position=Top`.
- Includes clean removal of entries managed by this utility.
- Requires Windows PowerShell 5.1 or newer.
- No installer framework, external modules, or network access required.

## Requirements

- Windows 10 or Windows 11.
- PotPlayer 64-bit (`PotPlayerMini64.exe`).
- Windows PowerShell 5.1 or newer.
- Administrator rights when modifying Explorer registrations under `HKLM`.

## Installation

1. Download the latest release ZIP from GitHub Releases.
2. Extract it to a normal writable folder.
3. Run `1.Setup_PotPlayer_Profiles.cmd`.
4. Approve the UAC prompt.
5. Press **Enter** when the utility offers to synchronize Explorer with PotPlayer.

Normal use is intentionally compact:

```text
PotPlayer Profile Context Menu v1.0
----------------------------------
PotPlayer profiles: MadVR, Native
Explorer status: Up to date

[Enter] Exit
A       Advanced
```

When repair is needed:

```text
PotPlayer profiles: MadVR, Native
Explorer status: Needs sync (2 to repair)

[Enter] Sync
A       Advanced
Q       Quit
```

## Advanced options

The Advanced menu keeps troubleshooting and maintenance features out of the normal workflow:

- `P` — detailed dry-run preview.
- `D` — diagnostics and save a report under `Logs`.
- `N` — add/repair only; never removes entries.
- `R` — rebuild only entries managed by this utility.
- `O` — choose or clear the profile placed at the top of Explorer's menu.
- `M` — add a profile manually.
- `U` — manage/remove Explorer profiles.
- `F` — refresh profile detection.

## Removal

Run:

```text
2.Remove_PotPlayer_Profiles.cmd
```

The removal utility backs up affected registry keys first and removes only entries recognized as belonging to this project. Native PotPlayer verbs and unrelated Explorer commands are left intact.

## Profile detection

Version 1.0 can discover profiles from:

- `HKCU\Software\Daum\PotPlayerMini64\OptionList`
- `%APPDATA%\PotPlayerMini64\PotPlayerMini64.ini`
- `PotPlayerMini64.ini` beside the PotPlayer executable

Profile-name matching is case-insensitive to avoid duplicate menu entries. The registered command itself is validated exactly.

## What the utility changes

The utility manages profile verbs below PotPlayer video ProgID shell keys such as:

```text
HKLM\Software\Classes\PotPlayerMini64.MKV\shell
HKLM\Software\Classes\PotPlayerMini64.MP4\shell
```

Each managed profile verb contains metadata including:

```text
ManagedBy     = PotPlayerProfileContextMenu
SchemaVersion = 1.0
PotPlayerConfig = <profile name>
```

The command is stored below the verb's `command` subkey.

For more implementation details, see [`docs/TECHNICAL.md`](docs/TECHNICAL.md).

## Logs, backups, and privacy

Runtime files are created beside the launcher scripts:

```text
Logs\
Backups\
PotPlayer_Profile_Context_Menu.settings.json
```

Typical files include:

```text
Logs\setup_YYYYMMDD_HHMMSS.log
Logs\setup_YYYYMMDD_HHMMSS_events.log
Logs\remove_YYYYMMDD_HHMMSS.log
Logs\diagnostics_YYYYMMDD_HHMMSS.txt
Backups\backup_YYYYMMDD_HHMMSS\*.reg
Backups\remove_backup_YYYYMMDD_HHMMSS\*.reg
```

PowerShell transcript logs can contain your Windows username, computer name, and local filesystem paths. **Review logs before attaching them to a public GitHub issue.**

## Troubleshooting

See [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md).

When reporting a problem, the most useful information is usually:

- Windows version.
- PowerShell version (`$PSVersionTable.PSVersion`).
- PotPlayer installation path.
- The diagnostics report generated with **Advanced → D**.
- Whether PotPlayer uses registry settings or INI mode.

Please review diagnostic/log files for private local paths before posting them publicly.


## Repository layout

The end-user runtime files live under `app/` so the repository root stays clean:

```text
potplayer-profile-context-menu/
├── app/
│   ├── 1.Setup_PotPlayer_Profiles.cmd
│   ├── 2.Remove_PotPlayer_Profiles.cmd
│   ├── PotPlayer_Profiles_Setup.ps1
│   └── PotPlayer_Profiles_Remove.ps1
├── docs/
├── scripts/
│   └── Build-Release.ps1
├── .github/
├── README.md
├── LICENSE
├── CHANGELOG.md
└── VERSION
```

Users normally should not download the source tree. GitHub Releases contains the built ZIP.

## Building a release locally

Run from PowerShell:

```powershell
.\scripts\Build-Release.ps1
```

The script creates:

```text
dist\PotPlayer-Profile-Context-Menu-v1.0.zip
dist\SHA256SUMS.txt
```

The ZIP contains a single top-level `PotPlayer-Profile-Context-Menu-v1.0` folder, so extracting it never dumps loose files into the destination folder.

The end-user archive is intentionally minimal and contains only:

```text
1.Setup_PotPlayer_Profiles.cmd
2.Remove_PotPlayer_Profiles.cmd
PotPlayer_Profiles_Setup.ps1
PotPlayer_Profiles_Remove.ps1
README.txt
LICENSE
```

Repository-only files such as `README.md`, `CHANGELOG.md`, `VERSION`, docs, workflows, and build scripts are not shipped in the release ZIP.

## GitHub repository setup

If you are publishing/forking this project, see [`docs/GITHUB_SETUP.md`](docs/GITHUB_SETUP.md).

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Security

See [`SECURITY.md`](SECURITY.md).

## License

MIT. See [`LICENSE`](LICENSE).

## Disclaimer

This is an independent community project. It is not affiliated with, endorsed by, or maintained by Kakao or the PotPlayer developers. PotPlayer and related names belong to their respective owners.
