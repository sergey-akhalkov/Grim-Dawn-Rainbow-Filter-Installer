# Grim Dawn Rainbow Filter — one-command installer

**English** | [Русский](README.ru.md)

[![validate](https://github.com/sergey-akhalkov/Grim-Dawn-Rainbow-Filter-Installer/actions/workflows/validate.yml/badge.svg)](https://github.com/sergey-akhalkov/Grim-Dawn-Rainbow-Filter-Installer/actions/workflows/validate.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-blue)

Installs the current [Grim Raynbow](https://grimraynbow.com) (Rainbow Filter) text overlay into
Grim Dawn with one command. It is a client-side `.txt` file: no mods folder, no game data edits, no
save changes. Removing the file returns the game to its default colours.

## Install

```powershell
irm https://raw.githubusercontent.com/sergey-akhalkov/Grim-Dawn-Rainbow-Filter-Installer/main/install.ps1 | iex
```

The game may stay open; restart Grim Dawn afterwards so it loads the new file.

The installer:

- reads the language the **game** uses from `Documents\My Games\Grim Dawn\Settings\options.txt`
  (English is only the last resort when neither the game nor Windows identifies a language);
- detects your DLC set from the `gdx1`/`gdx2`/`gdx3` folders and downloads the matching filter;
- parses the destination path from the downloaded file's own header;
- installs into the game folder, or into Documents when the game folder is not writable;
- moves known old Rainbow files into `settings\.rainbow-backup\<timestamp>`;
- writes a manifest so `-Uninstall` removes exactly what it installed.

Rerun the same command to update after a game or Raynbow update.

## Options

Download the script once to use the flags:

```powershell
Invoke-WebRequest https://raw.githubusercontent.com/sergey-akhalkov/Grim-Dawn-Rainbow-Filter-Installer/main/install.ps1 -OutFile install.ps1
.\install.ps1 -DryRun
```

| Option | Values | Default |
| --- | --- | --- |
| `-Language` | `auto en ru de fr es it cs pl ja ko pt vi zh` | the game's language, then Windows, then `en` |
| `-Preset` | `full`, `basic`, `diablo` | `full` |
| `-GameVersion` | `auto foa fg aom base` | detected from the game folder |
| `-Location` | `auto`, `game`, `documents` | `auto` |
| `-GamePath` | game folder | auto (Steam/GOG) |
| `-FilePath` | a saved Raynbow `.txt` | download from grimraynbow.com |
| `-DryRun` | switch | print the plan, change nothing |
| `-Uninstall` | switch | remove the installed file, keep backups |

Examples:

```powershell
.\install.ps1 -Language en                 # play Grim Dawn in English
.\install.ps1 -Preset basic                # Basic Highlighting instead of Full Rainbow
.\install.ps1 -Location documents          # force the Documents location
.\install.ps1 -Uninstall                   # remove the installed file
```

## Troubleshooting

**No colours after the restart.** The file is installed but the game is not loading that location.
Try the other root: `.\install.ps1 -Location documents` (or `-Location game`). Windows 11 sometimes
loads only one of the two.

**No colours, location is right.** The filter is language-specific: the file must match the language
selected in Grim Dawn. The installer reads it from the game settings; if you changed the language
after installing, rerun the installer. You can also force it: `-Language en`.

**"Tag not found" or broken item names.** Grim Dawn was updated. Rerun the installer to get the file
for the current game version.

**The script cannot find the game.** Pass the folder that contains `Grim Dawn.exe`:
`-GamePath "D:\SteamLibrary\steamapps\common\Grim Dawn"`.

**No internet or the site is down.** Download the file from [grimraynbow.com](https://grimraynbow.com)
in a browser and run `.\install.ps1 -FilePath .\tagsgdx1_achievements.txt`.

**PowerShell refuses to run the saved script.** Start PowerShell 7 (`pwsh`) or run
`powershell -ExecutionPolicy Bypass -File .\install.ps1`.

## Uninstall

```powershell
.\install.ps1 -Uninstall
```

Removes only the file recorded by the installer. Backups stay in
`<game or Documents>\settings\.rainbow-backup\`; delete that folder if you no longer need the old
files.

## Manual install

You can skip the script: open [grimraynbow.com](https://grimraynbow.com), choose the language, preset
and game version, download the generated file, and copy it to the path named in the file's own
header (for example `settings\text_ru\aom\tagsgdx1_achievements.txt`) under your game folder or
under `Documents\My Games\Grim Dawn`. Restart Grim Dawn afterwards.

## How it works

The installer downloads one generated text file from grimraynbow.com. The file's own header names the
exact destination (`settings\text_ru\aom\...` or `settings\text_en\...`) for the language and game
version you selected. The installer places it under the game folder or Documents, whichever the game
uses, and leaves everything else alone.

Requirements: Windows, PowerShell 5.1 or newer, internet access for the download. No administrator
rights are required for the Documents location.

## Credits

Rainbow Filter / [Grim Raynbow](https://grimraynbow.com) by **WareBare**, with the community in the
[Grim Dawn forum thread](https://forums.crateentertainment.com/t/tool-grim-raynbow-aka-rainbow-filter/42765).
This installer is unofficial and is not affiliated with Crate Entertainment or the filter author.

## License

[MIT](LICENSE), copyright (c) 2026 Sergey Akhalkov. The licence covers this installer, not the
Rainbow Filter files, which are downloaded from the author's site and remain the author's work.
