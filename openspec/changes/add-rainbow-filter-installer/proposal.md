# Proposal

## Why

Installing the Rainbow Filter (Grim Raynbow) by hand means downloading one generated text file,
finding the right `settings\text_<lang>[\aom]\` folder (or the Documents copy), deleting old Rainbow
files, and restarting the game. Each step is a known failure point: the wrong location on Windows 11,
a file for the wrong game language or DLC, or leftover legacy files. The result is silently missing
colours or "Tag not found".

## What Changes

- Add `install.ps1`: the `irm ... | iex` one-command installer. It downloads the current Grim Raynbow
  file, detects the game's own language and DLC set, installs to the settings folder the game loads,
  backs up known legacy Rainbow files, and records a manifest for uninstall.
- Add overrides: `-Language`, `-Preset`, `-GameVersion`, `-Location`, `-GamePath`, `-FilePath`,
  `-DryRun`, `-Uninstall`.
- Add bilingual documentation: `README.md` (English) and `README.ru.md` (Russian).
- Add offline fixture tests and a CI workflow.
- **BREAKING**: none; the repository currently holds only a placeholder README and the MIT licence.

## Capabilities

### New Capabilities

- `rainbow-filter-install`: one-command installation, game-language and DLC detection, install-location
  selection, legacy-file backup, uninstall, dry-run/local-file modes, and failure reporting for the
  Grim Raynbow text overlay in Grim Dawn.

### Modified Capabilities

None.

## Impact

- New files: `install.ps1`, `README.md`, `README.ru.md`, `tests/check.ps1` with fixtures, and
  `.github/workflows/validate.yml`.
- External dependency: the public `grimraynbow.com` download endpoint (HTTPS GET, undocumented,
  validated at runtime). No Raynbow files are bundled or mirrored.
- No game data, saves, executables, or existing repository files are modified.
