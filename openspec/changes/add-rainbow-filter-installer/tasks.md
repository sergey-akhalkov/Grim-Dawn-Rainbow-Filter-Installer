# Tasks

All groups except documentation and CI edit the same `install.ps1`, so this change is one work lane
owned by the lead; there are no parallel workers and no per-group path split.

## 1. Script scaffold and parameters (`install.ps1`)

- [x] 1.1 Create `install.ps1` with comment-based help (`#Requires -Version 5.1`, strict mode) and the full parameter set; verify `pwsh -NoProfile -Command "Get-Command ./install.ps1"` resolves and `-DryRun -Language xx` exits non-zero before any network call.
- [x] 1.2 Add the RU/EN console message helper keyed off the filter language; verify `-DryRun -Language en` prints English and `-DryRun -Language ru` prints Russian.

## 2. Detection (`install.ps1`)

- [x] 2.1 Implement game-language resolution (`-Language` → `options.txt` → OS UI culture → `en`, substring match); verify fixture `options.txt` values `Russian`, `Community Russian`, and a missing value each resolve correctly.
- [x] 2.2 Implement version resolution from `gdx3`/`gdx2`/`gdx1` plus the `-GameVersion` override; verify fixture game roots map to `foa`, `fg`, `aom`, and `base`.
- [x] 2.3 Implement the game-root locator (Steam registry + `libraryfolders.vdf`, GOG registry, `-GamePath`) and the Documents-only rule; verify the real install is found, a fixture with no game root but a user-data root installs to Documents with FoA and a warning, and a fixture with neither fails naming `-GamePath`.

## 3. Source and header (`install.ps1`)

- [x] 3.1 Implement the download-to-temp path for real installs and the in-memory header read for `-DryRun` (pointing `TMP`/`TEMP` at a fixture dir); verify a live RU download is > 200 KB with the expected version header and that dry-run leaves that fixture dir empty.
- [x] 3.2 Implement header parsing (relative path below `settings\`, separator normalisation) and response sanity checks; verify EN and RU fixture headers resolve to the expected paths and a malformed file is refused with no write.
- [x] 3.3 Wire `-Preset full|basic|diablo` into the request; verify the three preset responses differ and each carries its preset name.

## 4. Install, backup, uninstall (`install.ps1`)

- [x] 4.1 Implement location selection (`auto`, `game`, `documents`), the single-copy rule, and the manifest-first `installing`/`installed` commit; verify fixture cases: writable game root, read-only game root falling back to Documents, and a forced `-Location`.
- [x] 4.2 Implement the legacy allowlist exactly as enumerated in `design.md` (Legacy cleanup); verify every allowlisted entry moves to the timestamped backup, an unrelated file stays, and the current target is backed up as displaced rather than moved as legacy.
- [x] 4.3 Implement rollback and crash reconciliation; inject failures after the legacy move, after a same-path publication over a displaced target, during verification after a first-install move, and during restoration, then verify the new file is removed before the original is restored with its bytes intact, a first-install verification failure removes both the published filter and the transaction manifest, a failed reinstall restores the previous manifest so uninstall still removes the restored filter, and a failed restore keeps the `installing` manifest and backup with a non-zero exit and the recovery action; then simulate a crash-left `installing` manifest and verify the next run removes that target to the backup.
- [x] 4.4 Verify an EN→RU reinstall in the same root: the previous `text_en` file moves to the backup, only the new managed file remains, and a later `-Uninstall` leaves neither.
- [x] 4.5 Verify the install→uninstall round trip removes only the recorded file and keeps the backup.
- [x] 4.6 Verify `-DryRun` against a read-only settings fixture changes no file, creates no backup and writes no manifest.

## 5. Documentation (`README.md`, `README.ru.md`)

- [x] 5.1 Write `README.md` covering what it is, one-command install, what the installer does, update, options, troubleshooting, uninstall, manual install, credits and licence; verify every internal link and the exact one-liner.
- [x] 5.2 Write `README.ru.md` with the same structure and coverage; verify the language switchers point at each other and both list the same options.

## 6. Verification and CI (`tests/check.ps1`, `.github/workflows/validate.yml`)

- [x] 6.1 Add `tests/check.ps1` and fixtures (header samples, fake game roots, `options.txt`, read-only trees) covering language, version, location including the Documents-only case, the legacy allowlist, rollback, crash reconciliation, uninstall and dry-run; verify it exits 0.
- [x] 6.2 Add `.github/workflows/validate.yml` running the same checks on `windows-latest`; verify the command exits 0 locally.
- [ ] 6.3 Live verification on the owner's machine: run the one-liner, verify the RU file lands at the printed path, restart Grim Dawn and confirm colours, then verify `-Uninstall` removes it.
- [x] 6.4 Run `openspec validate add-rainbow-filter-installer --strict` and verify it exits 0.

## Workflow follow-up

- Archive the change after the spec review and live verification are complete.
- Set the public GitHub description/topics and confirm the repository is public so `irm` works.
