# Troubleshooting

## A video opens normally but not with a profile

The required PotPlayer argument order is:

```text
"PotPlayerMini64.exe" "%1" config="ProfileName"
```

The setup utility validates this complete command. Run setup and press Enter to repair if `Explorer status` reports that synchronization is needed.

## Setup repeatedly says a profile needs repair

Use **Advanced → D** to generate diagnostics. Compare the `Expected command` and `Actual command` lines and check the listed reason.

Common causes include:

- PotPlayer was moved or reinstalled.
- One or more PotPlayer video ProgIDs contain a mismatched registration.

## PotPlayer profiles are not detected

Check whether the profiles exist in PotPlayer's configuration list. Version 1.0 looks at:

```text
HKCU\Software\Daum\PotPlayerMini64\OptionList
%APPDATA%\PotPlayerMini64\PotPlayerMini64.ini
<PotPlayer folder>\PotPlayerMini64.ini
```

If automatic detection returns zero profiles, destructive automatic sync is disabled. You can use **Advanced → M** for manual profile entry while investigating detection.

## PotPlayer executable is not found

The utility checks Windows App Paths, existing managed registrations, Program Files, and PATH. If none work, it prompts for the full path to `PotPlayerMini64.exe`.

## Windows PowerShell requirements

The project targets Windows PowerShell 5.1. If a PowerShell error occurs, attach the diagnostics/log information after reviewing it for private local data.

You can check your version with:

```powershell
$PSVersionTable.PSVersion
```

## Logs say the log file is already in use

Version 1.0 uses separate files for the PowerShell transcript and internal event logging:

```text
setup_YYYYMMDD_HHMMSS.log
setup_YYYYMMDD_HHMMSS_events.log
```

If you see a file-lock problem, make sure all files in the extracted package come from the same release ZIP.

## Recovering from a bad registry change

Before registry modifications, the utility exports affected PotPlayer shell keys to a timestamped directory under `Backups`.

Review the backup's `README.txt` and `.reg` files before importing anything. Importing a `.reg` backup changes the registry and should only be done when you understand which key it restores.
