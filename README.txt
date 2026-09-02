PotPlayer Profile Context Menu v1.0
===================================

Adds your existing PotPlayer configuration profiles to the Windows Explorer
context menu and keeps the registered commands synchronized with PotPlayer.

Expected command format:

    "C:\Program Files\DAUM\PotPlayer\PotPlayerMini64.exe" "%1" config="ProfileName"

INSTALL / SYNC
--------------
1. Extract all files to a normal writable folder.
2. Run: 1.Setup_PotPlayer_Profiles.cmd
3. Approve the Administrator/UAC prompt.
4. Press Enter to sync when changes are needed.
5. Use Advanced only for preview, diagnostics, rebuild, manual profiles,
   top-profile selection, or profile removal.

REMOVE
------
Run: 2.Remove_PotPlayer_Profiles.cmd

The remover backs up affected registry keys and removes only entries recognized
as belonging to this utility.

RUNTIME FILES
-------------
Logs and backups are kept next to these launcher files:

    Logs\
    Backups\
    PotPlayer_Profile_Context_Menu.settings.json

PowerShell transcript logs can include the Windows username, computer name, and
local filesystem paths. Review logs before posting them publicly.

PROFILE DETECTION
-----------------
Profiles are detected from PotPlayer's registry OptionList and supported INI
locations. Profile-name matching is case-insensitive; the complete registered
command is checked exactly.

SAFETY
------
- Registry backup before changes.
- Dry-run preview and diagnostics.
- Selective repair of incorrect entries.
- Explorer-only/stale entries are not silently removed during normal sync.
- Clean removal preserves native PotPlayer and unrelated Explorer verbs.
- Requires Windows PowerShell 5.1 or newer.

Public release: 1.0
Registry schema: 1.0
License: MIT
