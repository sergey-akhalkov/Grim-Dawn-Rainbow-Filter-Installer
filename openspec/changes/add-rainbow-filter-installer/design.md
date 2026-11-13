# Design

## Context

See `proposal.md` for motivation. The repository is empty apart from a placeholder README and the
MIT licence. Verified facts that shape the approach:

- The current Rainbow Filter is Grim Raynbow: the site generates one text file per
  language/version/preset and serves it with a plain `GET` to
  `/GD/Filter/Download?preset_id=<preset>[-<version>]` (preset `1`/`2`/`3`; version suffix
  `-1` base, `-2` AoM, `-3` FG, none/`-0` FoA). The file's first lines name its exact destination
  under `settings\` (EN: `text_en\tagsgdx3_uimain.txt`; RU: `text_ru\aom\tagsgdx1_achievements.txt`)
  and both possible roots (game directory, `Documents\My Games\Grim Dawn`).
- Grim Dawn stores `language = "Russian"` in `Documents\My Games\Grim Dawn\Settings\options.txt`.
- DLC are `gdx1` (AoM), `gdx2` (FG), `gdx3` (FoA) directories in the game root. The executable's
  file version is `0.3.0.0` on a current install, so it cannot identify the game version.
- The game reads the text files at startup; no process handling is needed.
- The destination file name changes with language and game version, so a reinstall can target a
  completely different path inside the same root.

## Goals / Non-Goals

**Goals:**

- One command with no manual path work, correct language and DLC version by default, safe on repeat
  runs, and reversible.
- A deterministic, network-free test path (fixtures + `-FilePath`) and a small CI surface.

**Non-Goals:**

- Custom colour generation, other Raynbow site features, non-Windows platforms, the legacy six-file
  Wanez distribution, or a GUI. These are stated in the proposal's scope.

## Decisions

### Destination comes from the file's own header

Parse the relative path after `...\settings\` from the downloaded file instead of hardcoding names.
Alternatives: hardcode today's names (breaks on renames/version changes); scrape the site HTML
(more code, same undocumented source). Trade-off: tied to the header format; an unparsable response
stops with a clear error instead of guessing.

### Download at install time, never bundle

The site is the current authoritative artefact; bundling redistributes WareBare's text, goes stale
with every game update, and adds licensing questions. `-FilePath` covers offline installs and gives
tests a network-free seam. Alternatives considered: mirror in the repo, GitHub Releases proxy,
regenerate files locally.

### Language from the game, not the OS

`options.txt` is what the game actually loads; OS locale frequently disagrees (Russian Windows,
English game). Order: `-Language` → `options.txt` (substring match, so "Community Russian" works) →
OS UI culture → `en`. English is explicitly the last resort, never chosen while the game names a
supported language. Alternatives: OS only (wrong often), always `en` (fails the primary audience),
interactive prompt (breaks one-command).

### Version from DLC directories; missing root is not fatal by itself

`gdx3`/`gdx2`/`gdx1` presence maps to FoA/FG/AoM; no directory means base game; a missing game root
means the current FoA file. `-GameVersion` always overrides. A game root is not required when the
user-data root `Documents\My Games\Grim Dawn` exists: the Documents install is then valid with the
FoA default (and a warning). Only when neither root exists does discovery fail, because there is
nowhere safe to install. Alternatives: always fail without a game root (rejects valid GOG/Steam
locations that are not discoverable); always guess Documents (can create a bogus tree on a machine
without the game).

### Location: game directory, else Documents, with a force flag

The author lists both roots and the working one varies by setup; Windows 11 often needs Documents.
The installer picks the writable game root, falls back to Documents, and `-Location` settles
disputes. It removes its own previous copy in the other root so exactly one remains. Alternatives:
Documents only (smallest script, fails on game-root setups), game only (permissions), write both
(known stale-colour bug).

### Reconcile the previous managed file on every reinstall

The destination path depends on language and version, so an EN→RU reinstall in the same root writes
a different file. The installer reads the previous manifest first and, when the recorded path differs
from the new header path, moves that previous file into the backup before writing. This keeps
"exactly one managed copy" true within a root, not just across roots. Without it the old file would
stay active and the manifest would lose its uninstall record.

### Commit order and rollback

Mutations are planned before they start, then journaled:

1. Read the previous manifest; scan the legacy allowlist; compute the target and the backup folder.
2. Write the manifest with state `installing` (target, root, backup folder, moved and displaced
   files), keeping the previous manifest bytes in memory and a publication flag for the filter. This
   is the first write, so a failure before the filter write always leaves a record.
3. Move legacy files and a displaced target into the backup; place the new filter (temp file, then
   move), set the publication flag immediately after the successful move, and only then verify the
   placed file.
4. Rewrite the manifest with state `installed`.
5. On a detected exception after step 3 started: if the publication flag is set, delete the newly
   published filter first; then move every displaced and moved file back from the backup; then restore
   the previous manifest bytes if one existed (delete the transaction manifest only when none did).
   Report the failure. If restoring itself fails, keep the `installing` manifest and the backup
   folder, exit non-zero, and name the recovery action.
6. A later run or `-Uninstall` that finds an `installing` manifest removes its recorded target into
   the backup before proceeding, so a crash between the two manifests cannot leave an unowned file.

Trade-off: one extra small write per install. Alternatives: write the manifest last (a crash leaves
an unidentifiable filter); no rollback (the review's P1 finding).

### Legacy cleanup: an explicit allowlist

The allowlist is exactly these basenames:

```
tags_items.txt
tags_ui.txt
tagsgdx1_items.txt
tagsgdx1_storyelements.txt
tagsgdx2_endlessdungeon.txt
tagsgdx2_items.txt
tagsgdx3_uimain.txt
tagsgdx1_achievements.txt
tags_achievements.txt
tagsgdx1_ui.txt
tagsgdx2_ui.txt
```

They are scanned in `<settings>\`, `<settings>\text_<lang>\`, and
`<settings>\text_<lang>\aom\` for every `text_*` directory, and moved to
`<settings>\.rainbow-backup\<timestamp>\` preserving their relative paths. The current target path is
excluded (it is backed up as the displaced target), and so is the path recorded by the previous
manifest (reconciled by the rule above). Note that the RU target basename
`tagsgdx1_achievements.txt` is also in the allowlist, which is exactly why the target must be
excluded from the legacy move.

### Manifest for uninstall

`settings\.rainbow-filter.json` records: state (`installing` or `installed`), root, relative path,
source URL, game/filter version, backup folder, moved files and the displaced target. `-Uninstall`
removes the recorded file for either state. Alternatives: recompute from the header (needs network),
delete known names (could delete a user file).

### No self-elevation

Try the game root, otherwise Documents; no `RunAs` re-launch, which breaks `irm | iex` and surprises
the user with UAC. Failures point to `-Location` or `-GamePath`.

### Dry run performs no disk writes

`-DryRun` reads the header without a temp file: when downloading, the response body is read in
memory and only its ASCII header is parsed; with `-FilePath` the local file is read. No directory is
created, no backup, no manifest, no writability probe that writes. The download-to-file path is used
only for a real install. Trade-off: the dry run holds the response body (~0.3 MB) in memory; the
header itself is ASCII, so PowerShell 5.1 decoding cannot corrupt it. A real install still downloads
to a file to keep the Cyrillic payload byte-exact.

### Offline tests with fixtures; no live site in CI

`tests/check.ps1` builds fake game roots and a fixture filter file, then exercises the installer
(`-FilePath`, `-GamePath`, `-DryRun`, real fixture install/uninstall, an injected failure, and a
crash-state `installing` manifest). CI runs on `windows-latest`. Alternatives: Pester (extra
convention for no gain here), live download in CI (flaky).

### Two READMEs, not a docs tree

`README.md` and `README.ru.md` link to each other and carry the same sections; fewer files to keep in
sync for one utility. Console messages follow the filter language.

## Risks / Trade-offs

- **Undocumented site endpoint** → validate status, size, header and path before writing; fail with
  the cause and the `-FilePath` alternative.
- **Crash between mutations** → manifest-first journal plus next-run reconciliation; a damaged install
  still has its backup folder and an `installing` record.
- **Location ambiguity remains for some setups** → `-Location` and troubleshooting docs name both
  roots and the restart requirement.
- **Docs drift between languages** → same section order in both READMEs and a link at the top.
- **PowerShell 5.1 encoding** → download to a temp file (binary) and copy; never round-trip the
  Cyrillic payload through a string.
- **Windows path quirks** → normalise doubled separators from the header, use
  `[Environment]::GetFolderPath('MyDocuments')` for redirected/OneDrive Documents.

## Migration Plan

New repository capability; no migration. Rollout is a normal push to `main`; rollback is deleting
`install.ps1` and the docs, which leaves no trace on users' machines beyond files the installer
already wrote (removable with `-Uninstall`).

## Open Questions

None that change the specs or task breakdown. The site's endpoint stability is handled as a runtime
risk, not an open design question.
