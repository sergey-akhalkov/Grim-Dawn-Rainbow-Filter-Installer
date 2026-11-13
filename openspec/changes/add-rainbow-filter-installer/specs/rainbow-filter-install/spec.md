# Spec Delta

## Purpose

Installs the Grim Raynbow Rainbow Filter text overlay into a Grim Dawn installation with one command,
using the game's own language and DLC version, and removes it safely.

## ADDED Requirements

### Requirement: One-command install

The installer SHALL install the current Grim Raynbow filter for the detected game language and
version from a single command, reporting the installed path and the required game restart. On
failure it MUST exit non-zero; a successful rollback leaves no partial install, while a failed
rollback keeps the recovery manifest and backup.

#### Scenario: Successful one-command install

- **WHEN** the user runs the one-liner on Windows with Grim Dawn installed and a supported language
- **THEN** the filter file is downloaded, written to the settings path, and the installed path is printed before a success exit

#### Scenario: Failed install leaves nothing behind

- **WHEN** any install step fails and rollback succeeds
- **THEN** no filter file or manifest from that run remains and the exit is non-zero

### Requirement: Game language detection

The installer MUST take the filter language from the game's own
`Documents\My Games\Grim Dawn\Settings\options.txt`. When that value is missing or unsupported it
MUST fall back to the OS UI culture, and only then to English. It MUST NOT choose English while the
game names a supported language.

#### Scenario: Russian game language

- **WHEN** `options.txt` contains `language = "Russian"`
- **THEN** the filter is downloaded for `ru`

#### Scenario: Community translation

- **WHEN** `options.txt` names a value containing "Russian" such as "Community Russian"
- **THEN** the filter is downloaded for `ru`

#### Scenario: No game language value

- **WHEN** `options.txt` is missing or has no recognisable language
- **THEN** the language is derived from the OS UI culture

#### Scenario: Nothing detectable

- **WHEN** neither the game nor the OS identifies a supported language
- **THEN** English is used

#### Scenario: Explicit language override

- **WHEN** the user passes `-Language en` while the game is Russian
- **THEN** the English filter is installed and the choice is reported

### Requirement: Game version detection

The installer MUST map the `gdx3`, `gdx2` and `gdx1` directories in the game root to Fangs of
Asterkarn, Forgotten Gods and Ashes of Malmouth, and a root without them to the base game. When no
game root is detected it MUST use the current Fangs of Asterkarn file; `-GameVersion` always
overrides detection.

#### Scenario: Fangs of Asterkarn detected

- **WHEN** the game root contains `gdx3`
- **THEN** the Fangs of Asterkarn filter is requested

#### Scenario: Forgotten Gods detected

- **WHEN** the game root contains `gdx2` but not `gdx3`
- **THEN** the Forgotten Gods filter is requested

#### Scenario: No game root detected

- **WHEN** no game root is found and `-GameVersion` is not passed
- **THEN** the current Fangs of Asterkarn filter is requested

#### Scenario: Version override

- **WHEN** the user passes `-GameVersion base` on a Fangs of Asterkarn install
- **THEN** the base-game filter is installed

### Requirement: Destination from the file header

The installer MUST take the destination path below `settings\` from the downloaded file's own
instruction header, normalising separators. It MUST refuse to install when the response has no
parsable header.

#### Scenario: Header path is used

- **WHEN** the file header names `settings\text_ru\aom\tagsgdx1_achievements.txt`
- **THEN** the file is installed at exactly that path below the chosen root

#### Scenario: Invalid response refused

- **WHEN** the download is not a Raynbow text file or has no `settings\` path
- **THEN** the run stops before writing anything and reports an invalid download

### Requirement: Install location selection

The installer MUST install into the game directory when it is found and writable, otherwise into
`Documents\My Games\Grim Dawn` when that user-data root exists. When neither root exists it MUST
fail. `-Location game|documents` MUST force the choice, and after a successful install exactly one
managed copy MUST remain across both roots.

#### Scenario: Writable game directory

- **WHEN** the game root is found and writable
- **THEN** the filter is installed there

#### Scenario: Game directory not writable

- **WHEN** the game root is found but cannot be written
- **THEN** the filter is installed under `Documents\My Games\Grim Dawn` and the fallback is reported

#### Scenario: No game root but a user-data root

- **WHEN** no game root is detected but `Documents\My Games\Grim Dawn` exists
- **THEN** the filter is installed under that root with the current Fangs of Asterkarn file and the limited detection is reported

#### Scenario: No location at all

- **WHEN** neither a game root nor `Documents\My Games\Grim Dawn` exists
- **THEN** the run fails with an instruction to pass `-GamePath`

#### Scenario: Forced Documents install

- **WHEN** the user passes `-Location documents`
- **THEN** the filter is installed under the Documents settings root

#### Scenario: Stale copy in the other location

- **WHEN** a previous installer copy exists in the other known location
- **THEN** that copy is removed through the manifest before the new install completes

### Requirement: Legacy file backup

The installer MUST move only the legacy allowlist enumerated in design.md (Legacy cleanup) into a
timestamped backup under the chosen settings root, scanning `settings\` and its `text_*`
subdirectories. It MUST skip the current target path and the manifest-recorded file, and MUST NOT
delete or move anything outside that allowlist.

#### Scenario: Allowlisted legacy files moved

- **WHEN** files named in the legacy allowlist exist in a scanned settings location
- **THEN** they are moved into the timestamped backup and listed in the output

#### Scenario: Unrelated file untouched

- **WHEN** a file outside the allowlist exists in the settings tree
- **THEN** it stays in place unchanged

#### Scenario: The current target is not treated as legacy

- **WHEN** the new target file already exists under an allowlisted basename
- **THEN** it is backed up as the displaced target rather than moved as a legacy file

### Requirement: Install commit and rollback

The installer MUST write its manifest in state `installing` before any mutation, mark it `installed`
only after a verified filter write, and on a detected failure remove a published filter before
restoring displaced and moved files, then restore the previous manifest when one existed. A leftover
`installing` manifest MUST be reconciled by a later run or uninstall.

#### Scenario: Detected failure restores the previous tree

- **WHEN** a failure is detected after legacy files or a displaced target were moved
- **THEN** the published filter is removed first, the moved files are restored, the previous manifest is restored when it existed, and the failure is reported

#### Scenario: Same-path update preserves the original bytes

- **WHEN** a failure occurs after a new filter replaced a displaced file at the same path
- **THEN** the new file is removed before the displaced original is restored, and the original bytes are intact

#### Scenario: Verification failure after the move

- **WHEN** verification of a first install fails after the new filter was moved into place
- **THEN** rollback removes the published filter and the transaction manifest, and the exit is non-zero

#### Scenario: Failed reinstall keeps its uninstall record

- **WHEN** a reinstall fails after the previous manifest was replaced
- **THEN** the previous manifest is restored, so a later uninstall still finds and removes the restored filter

#### Scenario: Rollback itself fails

- **WHEN** restoring a moved file fails during rollback
- **THEN** the `installing` manifest and the backup folder are kept, the exit is non-zero, and the message names the recovery action

#### Scenario: Manifest cannot be written

- **WHEN** the manifest write fails before any file mutation
- **THEN** nothing is modified and the run exits non-zero

#### Scenario: Crash state is reconciled

- **WHEN** an `installing` manifest from an interrupted run is found by a later run
- **THEN** the recorded filter is removed to the backup and the install proceeds from that clean state

### Requirement: Managed destination reconciliation

On reinstall, when the previous manifest records a destination different from the new header path,
the installer MUST move the previous managed file to the backup before writing the new one. After the
reinstall exactly one managed copy MUST remain.

#### Scenario: Language change in the same root

- **WHEN** an English install is replaced by a Russian install under the same root
- **THEN** the previous `text_en` file is moved to the backup and only the new `text_ru` file remains managed

#### Scenario: Uninstall after a destination change

- **WHEN** the user runs `-Uninstall` after such a reinstall
- **THEN** neither the previous nor the new managed file remains

### Requirement: Uninstall

The installer MUST provide `-Uninstall`, which removes the file recorded in its manifest (state
`installing` or `installed`) and reports the kept backup folder. With no manifest it MUST report that
nothing was installed and MUST not delete any file.

#### Scenario: Uninstall removes the installed filter

- **WHEN** the user runs `-Uninstall` after an install
- **THEN** the recorded filter file is removed, backups remain, and the exit is zero

#### Scenario: Uninstall without an install

- **WHEN** the user runs `-Uninstall` with no manifest
- **THEN** nothing is deleted and the message says no install was recorded

### Requirement: Dry run and local file

`-DryRun` MUST make no filesystem changes and MUST NOT download to a file: it reads the header in
memory or from `-FilePath`. `-FilePath` MUST install from a local file without any network request.

#### Scenario: Dry run changes nothing

- **WHEN** `-DryRun` is passed, including with a read-only settings fixture
- **THEN** the plan is printed and no file, backup, or manifest is created or modified

#### Scenario: Local file install

- **WHEN** `-FilePath` names a saved Raynbow file and no network is available
- **THEN** the file is installed and the result matches a downloaded install

### Requirement: Failure reporting

Every failure MUST name the cause and the next action and exit non-zero. When rollback succeeds, no
filter or manifest from the failed run remains; when rollback itself fails, the `installing` manifest
and backup are kept and the message names the recovery action. A missing game, a missing user-data
root, no writable location, a download error, and an invalid response MUST be reported distinctly.

#### Scenario: Game not found

- **WHEN** neither a game root nor `Documents\My Games\Grim Dawn` exists and `-GamePath` is absent
- **THEN** the message names `-GamePath` as the next action and the exit is non-zero

#### Scenario: Download error

- **WHEN** the download endpoint returns a non-success status or times out
- **THEN** the message names the endpoint and the `-FilePath` alternative

### Requirement: Bilingual documentation and console language

The repository MUST ship `README.md` in English and `README.ru.md` in Russian with the same coverage
and a link to each other. Console messages MUST use the filter language.

#### Scenario: Language switcher

- **WHEN** a reader opens either README
- **THEN** a link to the other language version is visible near the top

#### Scenario: Russian console output

- **WHEN** the filter language is `ru`
- **THEN** progress and result messages are printed in Russian
