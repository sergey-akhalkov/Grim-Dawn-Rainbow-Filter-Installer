param([switch]$Live)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$installer = Join-Path (Split-Path -Parent $here) 'install.ps1'
. $installer

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('rainbow-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$script:failures = 0

# Seams from install.ps1: keep the suite away from the real Documents tree and the real game.
$missingDocuments = Join-Path $testRoot 'missing-documents'
$missingGame = Join-Path $testRoot 'missing-game'
$env:DSH_RAINBOW_DOCUMENTS_ROOT = $missingDocuments
$env:DSH_RAINBOW_GAME_ROOT = $missingGame
$env:DSH_RAINBOW_FAULT = $null

function Ok([string]$Message) { Write-Host "ok   $Message" -ForegroundColor Green }
function Fail([string]$Message) { $script:failures++; Write-Host "FAIL $Message" -ForegroundColor Red }
function Assert([bool]$Condition, [string]$Message) {
    if ($Condition) { Ok $Message } else { Fail $Message }
}

function New-FilterFile([string]$Path, [string]$Relative, [string]$Fill = 'x') {
    $header = @(
        '# ############################## #'
        '# ### Grim Dawn:    v1.3.1.1 ### #'
        '# ### Grim Raynbow: v0.0.3.5 ### #'
        '# ############################## #'
        ('# \Grim Dawn\settings\' + $Relative)
        ('# C:\Users\[UserName]\Documents\My Games\Grim Dawn\Settings\' + $Relative)
    ) -join "`n"
    Set-Content -LiteralPath $Path -Value ($header + "`n" + ($Fill * 60000)) -Encoding UTF8
}

function New-Game([string]$Path, [string[]]$Dlc) {
    New-Item -ItemType Directory -Path (Join-Path $Path 'database') -Force | Out-Null
    foreach ($entry in $Dlc) { New-Item -ItemType Directory -Path (Join-Path $Path $entry) -Force | Out-Null }
}

function Get-TreeHash([string]$Path) {
    $files = Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue | Sort-Object FullName
    $directories = Get-ChildItem -LiteralPath $Path -Recurse -Directory -ErrorAction SilentlyContinue | Sort-Object FullName
    $fileHash = ($files | ForEach-Object { (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash + ':' + $_.FullName.Substring($Path.Length) }) -join '|'
    $directoryHash = ($directories | ForEach-Object { 'DIR:' + $_.FullName.Substring($Path.Length) }) -join '|'
    return ($fileHash + '|' + $directoryHash)
}

function Invoke-Installer([hashtable]$Arguments) {
    try {
        & $installer @Arguments *> $null
        return $true
    } catch {
        return $false
    }
}

function Invoke-InstallerOutput([hashtable]$Arguments) {
    $result = @{ Ok = $true; Output = '' }
    try {
        $result.Output = (& $installer @Arguments 6>&1 2>&1 3>&1 4>&1 5>&1 | Out-String)
    } catch {
        $result.Ok = $false
        $result.Output = $_.Exception.Message
    }
    return $result
}

function Get-ChildInstallerExit([string[]]$Arguments) {
    $exeName = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
    $exe = Join-Path $PSHOME $exeName
    # Windows PowerShell treats native stderr as a terminating error under Stop.
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $exe -NoProfile -ExecutionPolicy Bypass -File $installer @Arguments 2>$null | Out-Null
        return $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $saved
    }
}

function Add-DenyWrite([string]$Path, [switch]$Inherit) {
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    if ($Inherit) {
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($sid, 'CreateFiles,CreateDirectories,Write', 'ContainerInherit,ObjectInherit', 'None', 'Deny')
    } else {
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($sid, 'CreateFiles,CreateDirectories,Write', 'Deny')
    }
    $acl = Get-Acl -LiteralPath $Path
    $acl.AddAccessRule($rule)
    Set-Acl -Path $Path -AclObject $acl
    return $rule
}

function Remove-DenyWrite([string]$Path, $Rule) {
    $acl = Get-Acl -LiteralPath $Path
    $acl.RemoveAccessRule($Rule) | Out-Null
    Set-Acl -Path $Path -AclObject $acl
}

function Invoke-WebRequest {
    [CmdletBinding()]
    param($Uri, $OutFile, [switch]$UseBasicParsing, $TimeoutSec)
    $script:webCalls++
    $script:webUri = $Uri
    if (-not $script:webFixture) { return }
    if ($OutFile) {
        $script:webOutFile = $OutFile
        Copy-Item -LiteralPath $script:webFixture -Destination $OutFile -Force
        return
    }
    return [pscustomobject]@{ Content = (Get-Content -LiteralPath $script:webFixture -Raw) }
}
$script:webCalls = 0
$script:webFixture = $null
$script:webOutFile = $null
$script:webUri = $null

# --- header parsing ---------------------------------------------------------
$headers = (New-Item -ItemType Directory -Path (Join-Path $testRoot 'headers') -Force).FullName
$enFile = Join-Path $headers 'en.txt'
New-FilterFile $enFile 'text_en\tagsgdx3_uimain.txt'
$enHeader = Get-HeaderInfo (Get-HeaderText $enFile)
Assert ($enHeader.Relative -eq 'text_en\tagsgdx3_uimain.txt') 'EN header path parsed'
Assert ($enHeader.RaynowVersion -eq '0.0.3.5') 'Raynbow version parsed'

$ruFile = Join-Path $headers 'ru.txt'
New-FilterFile $ruFile 'text_ru\\aom\tagsgdx1_achievements.txt'
$ruHeader = Get-HeaderInfo (Get-HeaderText $ruFile)
Assert ($ruHeader.Relative -eq 'text_ru\aom\tagsgdx1_achievements.txt') 'RU header path normalised'

$enFile2 = Join-Path $headers 'en2.txt'
New-FilterFile $enFile2 'text_en\tagsgdx3_uimain.txt' 'y'

$badFile = Join-Path $headers 'bad.txt'
Set-Content -LiteralPath $badFile -Value 'not a rainbow file' -Encoding UTF8
$badRejected = $false
try { $null = Get-HeaderInfo (Get-HeaderText $badFile) } catch { $badRejected = $true }
Assert $badRejected 'malformed header rejected'

# --- language ---------------------------------------------------------------
$userData = Join-Path $testRoot 'userdata'
New-Item -ItemType Directory -Path (Join-Path $userData 'Settings') -Force | Out-Null
$options = Join-Path $userData 'Settings\options.txt'
Set-Content -LiteralPath $options -Value 'language = "Russian"' -Encoding UTF8
Assert ((Get-GameLanguage $userData) -eq 'ru') 'language Russian resolved'
Assert ((Resolve-Language $null $userData) -eq 'ru') 'language resolution prefers the game'
Assert ((Resolve-Language 'en' $userData) -eq 'en') 'explicit language wins'
Assert ((Resolve-Language 'auto' $userData) -eq 'ru') 'auto language defers to the game'
Set-Content -LiteralPath $options -Value 'language = "Community Russian"' -Encoding UTF8
Assert ((Get-GameLanguage $userData) -eq 'ru') 'Community Russian resolved'
Set-Content -LiteralPath $options -Value 'language = "English"' -Encoding UTF8
Assert ((Get-GameLanguage $userData) -eq 'en') 'English resolved'
Set-Content -LiteralPath $options -Value 'language = ""' -Encoding UTF8
Assert ($null -eq (Get-GameLanguage $userData)) 'empty language is not resolved from the game'
Assert ((Resolve-Language $null $userData) -eq (Get-OsLanguage)) 'missing language falls back to the OS culture'
Set-Content -LiteralPath $options -Value 'language = "Klingon"' -Encoding UTF8
Assert ($null -eq (Get-GameLanguage $userData)) 'unknown language is not resolved from the game'

function Get-UICulture { [pscustomobject]@{ Name = 'ru-RU' } }
try { Assert ((Get-OsLanguage) -eq 'ru') 'supported OS culture maps to its language' } finally { Remove-Item Function:\Get-UICulture -ErrorAction SilentlyContinue }
function Get-UICulture { [pscustomobject]@{ Name = 'xx-XX' } }
try { Assert ((Get-OsLanguage) -eq 'en') 'unsupported OS culture falls back to English' } finally { Remove-Item Function:\Get-UICulture -ErrorAction SilentlyContinue }

# --- version ----------------------------------------------------------------
$foaGame = Join-Path $testRoot 'foa-game'; New-Game $foaGame @('gdx1', 'gdx2', 'gdx3')
$fgGame = Join-Path $testRoot 'fg-game'; New-Game $fgGame @('gdx1', 'gdx2')
$aomGame = Join-Path $testRoot 'aom-game'; New-Game $aomGame @('gdx1')
$baseGame = Join-Path $testRoot 'base-game'; New-Game $baseGame @()
Assert ((Get-GameVersion $foaGame $null) -eq 'foa') 'gdx3 maps to FoA'
Assert ((Get-GameVersion $fgGame $null) -eq 'fg') 'gdx2 maps to FG'
Assert ((Get-GameVersion $aomGame $null) -eq 'aom') 'gdx1 maps to AoM'
Assert ((Get-GameVersion $baseGame $null) -eq 'base') 'no DLC maps to base'
Assert ((Get-GameVersion $null $null) -eq 'foa') 'missing root defaults to FoA'
Assert ((Get-GameVersion $foaGame 'base') -eq 'base') 'explicit version wins'
Assert ((Get-GameVersion $foaGame 'auto') -eq 'foa') 'auto version uses detection'
Assert ((Get-DownloadUrl 'ru' 'full' 'foa') -eq 'https://grimraynbow.com/ru/GD/Filter/Download?preset_id=1') 'URL for full FoA'
Assert ((Get-DownloadUrl 'ru' 'basic' 'fg') -eq 'https://grimraynbow.com/ru/GD/Filter/Download?preset_id=2-3') 'URL for basic FG'
Assert ((Get-DownloadUrl 'ru' 'diablo' 'base') -eq 'https://grimraynbow.com/ru/GD/Filter/Download?preset_id=3-1') 'URL for diablo base'

$gogGame = Join-Path $testRoot 'gog-game'
New-Game $gogGame @('gdx3')
$env:DSH_RAINBOW_GAME_ROOT = $null
function Get-ItemProperty {
    [CmdletBinding()]
    param($Path)
    if ($Path -like '*GOG.com\Games\1449651388*') { return [pscustomobject]@{ path = $gogGame } }
    return $null
}
try {
    $gogFound = Find-GameRoot
} finally {
    Remove-Item Function:\Get-ItemProperty -ErrorAction SilentlyContinue
    $env:DSH_RAINBOW_GAME_ROOT = $missingGame
}
Assert ($gogFound -eq (Resolve-Path -LiteralPath $gogGame).Path) 'GOG registry discovery resolves the game root'

# --- script surface ---------------------------------------------------------
Assert ($null -ne (Get-Command -Name $installer -ErrorAction SilentlyContinue)) 'install.ps1 resolves as a command'
Assert ((Get-ChildInstallerExit @('-DryRun', '-Language', 'xx')) -ne 0) 'invalid language exits non-zero before any download'
Assert ((Get-ChildInstallerExit @('-DryRun', '-Language', 'en', '-FilePath', $enFile, '-GamePath', $foaGame, '-Location', 'game')) -eq 0) 'dry run exits zero in a child process'
$head = ((Get-Content -LiteralPath $installer -Raw -Encoding UTF8) -split [regex]::Escape('$script:SiteBase'))[0]
$iexBound = $true
try { & { $null = Invoke-Expression ($head + "`n'PARAM-OK'") } } catch { $iexBound = $false }
Assert $iexBound 'parameter block works when invoked via iex'

# --- install location -------------------------------------------------------
$docsFixture = Join-Path $testRoot 'documents'; New-Item -ItemType Directory -Path $docsFixture -Force | Out-Null
Assert ((Resolve-InstallRoot -GameRoot $foaGame -UserDataRoot $docsFixture -Location auto -DryRun $true) -eq $foaGame) 'auto picks the game root'
Assert ((Resolve-InstallRoot -GameRoot $null -UserDataRoot $docsFixture -Location auto -DryRun $true) -eq $docsFixture) 'auto falls back to Documents'
Assert ((Resolve-InstallRoot -GameRoot $foaGame -UserDataRoot $docsFixture -Location documents -DryRun $true) -eq $docsFixture) 'forced documents picks Documents'
$noRootRejected = $false
try { $null = Resolve-InstallRoot -GameRoot $null -UserDataRoot (Join-Path $testRoot 'missing') -Location auto -DryRun $true } catch { $noRootRejected = $true }
Assert $noRootRejected 'no root at all fails'
$forcedRejected = $false
try { $null = Resolve-InstallRoot -GameRoot $null -UserDataRoot $docsFixture -Location game -DryRun $true } catch { $forcedRejected = $true }
Assert $forcedRejected 'forced game location without a root fails'

# --- install, legacy backup, displaced target, uninstall --------------------
$case1 = Join-Path $testRoot 'case1'
New-Game $case1 @('gdx2')
New-Item -ItemType Directory -Path (Join-Path $case1 'settings\text_en') -Force | Out-Null
$legacyNames = @(
    'tags_items.txt', 'tags_ui.txt', 'tagsgdx1_items.txt', 'tagsgdx1_storyelements.txt',
    'tagsgdx2_endlessdungeon.txt', 'tagsgdx2_items.txt', 'tagsgdx3_uimain.txt',
    'tagsgdx1_achievements.txt', 'tags_achievements.txt', 'tagsgdx1_ui.txt', 'tagsgdx2_ui.txt'
)
foreach ($name in $legacyNames) { Set-Content -LiteralPath (Join-Path $case1 ('settings\text_en\' + $name)) -Value 'legacy' -Encoding UTF8 }
Set-Content -LiteralPath (Join-Path $case1 'settings\tags_ui.txt') -Value 'legacy root' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $case1 'settings\text_en\custom.txt') -Value 'keep' -Encoding UTF8
$target1 = Join-Path $case1 'settings\text_en\tagsgdx3_uimain.txt'
Set-Content -LiteralPath $target1 -Value 'old target' -Encoding UTF8
$ok = Invoke-Installer @{ FilePath = $enFile; GamePath = $case1; Language = 'en'; GameVersion = 'fg'; Location = 'game' }
Assert $ok 'EN install succeeds'
Assert (Test-Path -LiteralPath $target1) 'EN target installed'
Assert (-not (Test-Path -LiteralPath (Join-Path $case1 'settings\text_en\tags_items.txt'))) 'legacy file moved away'
$backup1 = Join-Path $case1 'settings\.rainbow-backup'
Assert (@(Get-ChildItem -LiteralPath $backup1 -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'tags_items.txt' }).Count -eq 1) 'legacy file is in the backup'
Assert (@(Get-ChildItem -LiteralPath $backup1 -Recurse -File -ErrorAction SilentlyContinue).Count -eq 12) 'all allowlisted legacy files moved'
$displaced = @(Get-ChildItem -LiteralPath $backup1 -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'tagsgdx3_uimain.txt' })
Assert ($displaced.Count -eq 1 -and (Get-Content -LiteralPath $displaced[0].FullName -Raw) -match 'old target') 'current target backed up as displaced'
Assert (Test-Path -LiteralPath (Join-Path $case1 'settings\text_en\custom.txt')) 'unrelated file preserved'
$manifest = Read-Manifest $case1
Assert ($null -ne $manifest -and (Get-Prop $manifest 'state') -eq 'installed') 'manifest installed state'
$ok = Invoke-Installer @{ Uninstall = $true; GamePath = $case1; Language = 'en' }
Assert ($ok -and -not (Test-Path -LiteralPath $target1)) 'uninstall removes the target'
Assert (-not (Test-Path -LiteralPath (Get-ManifestPath $case1))) 'uninstall removes the manifest'
Assert (Test-Path -LiteralPath $backup1) 'uninstall keeps the backup'
Assert (Test-Path -LiteralPath (Join-Path $case1 'settings\text_en\custom.txt')) 'uninstall keeps unrelated files'

# --- reinstall with a different destination --------------------------------
$case2 = Join-Path $testRoot 'case2'
New-Game $case2 @('gdx3')
$ok = Invoke-Installer @{ FilePath = $enFile; GamePath = $case2; Language = 'en'; Location = 'game' }
$targetEn = Join-Path $case2 'settings\text_en\tagsgdx3_uimain.txt'
Assert ($ok -and (Test-Path -LiteralPath $targetEn)) 'EN install for reinstall'
$ok = Invoke-Installer @{ FilePath = $ruFile; GamePath = $case2; Language = 'ru'; Location = 'game' }
$targetRu = Join-Path $case2 'settings\text_ru\aom\tagsgdx1_achievements.txt'
Assert ($ok -and (Test-Path -LiteralPath $targetRu)) 'RU reinstall succeeds'
Assert (-not (Test-Path -LiteralPath $targetEn)) 'previous EN file no longer active'
Assert (@(Get-ChildItem -LiteralPath (Join-Path $case2 'settings\.rainbow-backup') -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'tagsgdx3_uimain.txt' }).Count -eq 1) 'previous EN file is in the backup'
$ok = Invoke-Installer @{ Uninstall = $true; GamePath = $case2; Language = 'en' }
Assert ($ok -and -not (Test-Path -LiteralPath $targetRu) -and -not (Test-Path -LiteralPath $targetEn)) 'uninstall after reinstall leaves no managed file'

# --- dry run makes no changes, console follows the language -----------------
$case3 = Join-Path $testRoot 'case3'
New-Game $case3 @('gdx3')
New-Item -ItemType Directory -Path (Join-Path $case3 'settings\text_en') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $case3 'settings\text_en\tags_items.txt') -Value 'legacy' -Encoding UTF8
$before = Get-TreeHash $case3
$enRun = Invoke-InstallerOutput @{ FilePath = $enFile; GamePath = $case3; Language = 'en'; Location = 'game'; DryRun = $true }
$after = Get-TreeHash $case3
Assert $enRun.Ok 'dry run succeeds'
Assert ($enRun.Output -match 'Dry run' -and $enRun.Output -match 'Language: en') 'dry run prints English messages'
Assert ($before -eq $after) 'dry run leaves the tree unchanged'
Assert (-not (Test-Path -LiteralPath (Get-ManifestPath $case3))) 'dry run writes no manifest'
$ruRun = Invoke-InstallerOutput @{ FilePath = $enFile; GamePath = $case3; Language = 'ru'; Location = 'game'; DryRun = $true }
Assert ($ruRun.Ok -and $ruRun.Output -match 'Пробный запуск' -and $ruRun.Output -match 'Язык: ru') 'dry run prints Russian messages'

# --- dry run against a read-only tree does not probe with a write -----------
$roDry = Join-Path $testRoot 'ro-dry'
New-Game $roDry @('gdx3')
New-Item -ItemType Directory -Path (Join-Path $roDry 'settings\text_en') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $roDry 'settings\text_en\tags_items.txt') -Value 'legacy' -Encoding UTF8
$roRule = Add-DenyWrite $roDry -Inherit
$writeDenied = $false
try { [IO.File]::WriteAllText((Join-Path $roDry 'settings\probe.txt'), 'probe') } catch { $writeDenied = $true }
$before = Get-TreeHash $roDry
$roRun = Invoke-InstallerOutput @{ FilePath = $enFile; GamePath = $roDry; Language = 'en'; Location = 'game'; DryRun = $true }
$after = Get-TreeHash $roDry
Remove-DenyWrite $roDry $roRule
Assert $writeDenied 'read-only settings fixture denies writes'
Assert ($roRun.Ok -and $before -eq $after) 'dry run on a read-only tree changes nothing'
Assert (-not (Test-Path -LiteralPath (Join-Path $roDry 'settings\.rainbow-backup'))) 'dry run creates no backup directory'
Assert (-not (Test-Path -LiteralPath (Get-ManifestPath $roDry))) 'dry run on a read-only tree writes no manifest'

# --- Documents-only install with the FoA default and a warning --------------
$docsOnly = Join-Path $testRoot 'documents-only'
New-Item -ItemType Directory -Path $docsOnly -Force | Out-Null
$env:DSH_RAINBOW_DOCUMENTS_ROOT = $docsOnly
$docsRun = Invoke-InstallerOutput @{ FilePath = $enFile; Language = 'en'; Location = 'auto' }
$docsTarget = Join-Path $docsOnly 'settings\text_en\tagsgdx3_uimain.txt'
Assert ($docsRun.Ok -and (Test-Path -LiteralPath $docsTarget)) 'Documents-only install works'
Assert ($docsRun.Output -match 'game folder was not found') 'Documents-only install warns about limited detection'
$docsManifest = Read-Manifest $docsOnly
Assert ($null -ne $docsManifest -and (Get-Prop $docsManifest 'gameVersion') -eq 'foa') 'Documents-only install uses the FoA default'
$ok = Invoke-Installer @{ Uninstall = $true; Language = 'en' }
Assert ($ok -and -not (Test-Path -LiteralPath $docsTarget)) 'Documents-only uninstall removes the target'
$env:DSH_RAINBOW_DOCUMENTS_ROOT = $missingDocuments

# --- forced Documents install reports limited detection --------------------
$forcedDocs = Join-Path $testRoot 'forced-documents'
New-Item -ItemType Directory -Path $forcedDocs -Force | Out-Null
$env:DSH_RAINBOW_DOCUMENTS_ROOT = $forcedDocs
$forcedRun = Invoke-InstallerOutput @{ FilePath = $enFile; Language = 'en'; Location = 'documents' }
$forcedTarget = Join-Path $forcedDocs 'settings\text_en\tagsgdx3_uimain.txt'
Assert ($forcedRun.Ok -and (Test-Path -LiteralPath $forcedTarget)) 'forced Documents install works without a game root'
Assert ($forcedRun.Output -match 'game folder was not found') 'forced Documents install reports limited detection'
$forcedManifest = Read-Manifest $forcedDocs
Assert ($null -ne $forcedManifest -and (Get-Prop $forcedManifest 'gameVersion') -eq 'foa') 'forced Documents install uses the FoA default'
$ok = Invoke-Installer @{ Uninstall = $true; Language = 'en' }
Assert ($ok -and -not (Test-Path -LiteralPath $forcedTarget)) 'forced Documents uninstall removes the target'
$env:DSH_RAINBOW_DOCUMENTS_ROOT = $missingDocuments

# --- no game and no Documents root fails naming -GamePath -------------------
$env:DSH_RAINBOW_DOCUMENTS_ROOT = Join-Path $testRoot 'no-documents-either'
$noRootRun = Invoke-InstallerOutput @{ FilePath = $enFile; Language = 'en'; Location = 'auto' }
$env:DSH_RAINBOW_DOCUMENTS_ROOT = $missingDocuments
Assert (-not $noRootRun.Ok) 'no root at all fails'
Assert ($noRootRun.Output -match '-GamePath') 'no root failure names -GamePath'

# --- read-only game root falls back to Documents ---------------------------
$roGame = Join-Path $testRoot 'ro-game'
New-Game $roGame @('gdx3')
$fallbackDocs = Join-Path $testRoot 'fallback-documents'
New-Item -ItemType Directory -Path $fallbackDocs -Force | Out-Null
$env:DSH_RAINBOW_DOCUMENTS_ROOT = $fallbackDocs
$roRule = Add-DenyWrite $roGame
$fallbackRun = Invoke-InstallerOutput @{ FilePath = $enFile; GamePath = $roGame; Language = 'en'; Location = 'auto' }
Remove-DenyWrite $roGame $roRule
$fallbackTarget = Join-Path $fallbackDocs 'settings\text_en\tagsgdx3_uimain.txt'
Assert ($fallbackRun.Ok -and (Test-Path -LiteralPath $fallbackTarget)) 'read-only game root falls back to Documents'
Assert ($fallbackRun.Output -match 'not writable') 'fallback to Documents is reported'
Assert (-not (Test-Path -LiteralPath (Join-Path $roGame 'settings\.rainbow-filter.json'))) 'fallback writes no manifest into the game root'
$ok = Invoke-Installer @{ Uninstall = $true; GamePath = $roGame; Language = 'en' }
Assert ($ok -and -not (Test-Path -LiteralPath $fallbackTarget)) 'fallback install can be uninstalled'
$env:DSH_RAINBOW_DOCUMENTS_ROOT = $missingDocuments

# --- forced Documents install removes the stale copy in the game root ------
$singleGame = Join-Path $testRoot 'single-game'
New-Game $singleGame @('gdx3')
$singleDocs = Join-Path $testRoot 'single-documents'
New-Item -ItemType Directory -Path $singleDocs -Force | Out-Null
$env:DSH_RAINBOW_DOCUMENTS_ROOT = $singleDocs
$ok = Invoke-Installer @{ FilePath = $enFile; GamePath = $singleGame; Language = 'en'; Location = 'game' }
$gameTarget = Join-Path $singleGame 'settings\text_en\tagsgdx3_uimain.txt'
Assert ($ok -and (Test-Path -LiteralPath $gameTarget)) 'first install for the single-copy rule'
$ok = Invoke-Installer @{ FilePath = $enFile; GamePath = $singleGame; Language = 'en'; Location = 'documents' }
$docsTarget = Join-Path $singleDocs 'settings\text_en\tagsgdx3_uimain.txt'
Assert ($ok -and (Test-Path -LiteralPath $docsTarget)) 'forced Documents install succeeds'
Assert (-not (Test-Path -LiteralPath $gameTarget)) 'stale copy in the game root is removed'
Assert (-not (Test-Path -LiteralPath (Get-ManifestPath $singleGame))) 'stale game-root manifest is removed'
$ok = Invoke-Installer @{ Uninstall = $true; GamePath = $singleGame; Language = 'en' }
Assert ($ok -and -not (Test-Path -LiteralPath $docsTarget) -and -not (Test-Path -LiteralPath $gameTarget)) 'uninstall leaves no managed copy'
$env:DSH_RAINBOW_DOCUMENTS_ROOT = $missingDocuments

# --- verification failure rolls back ---------------------------------------
$case4 = Join-Path $testRoot 'case4'
New-Game $case4 @('gdx3')
New-Item -ItemType Directory -Path (Join-Path $case4 'settings\text_en') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $case4 'settings\text_en\tags_items.txt') -Value 'legacy' -Encoding UTF8
$env:DSH_RAINBOW_FAULT = 'verify'
$ok = Invoke-Installer @{ FilePath = $enFile; GamePath = $case4; Language = 'en'; Location = 'game' }
$env:DSH_RAINBOW_FAULT = $null
$target4 = Join-Path $case4 'settings\text_en\tagsgdx3_uimain.txt'
Assert (-not $ok) 'verification failure exits non-zero'
Assert (-not (Test-Path -LiteralPath $target4)) 'failed install leaves no target'
Assert (-not (Test-Path -LiteralPath (Get-ManifestPath $case4))) 'failed install leaves no manifest'
Assert (Test-Path -LiteralPath (Join-Path $case4 'settings\text_en\tags_items.txt')) 'failed install restores the legacy file'

# --- failure after the legacy move restores the moved files ----------------
$case4b = Join-Path $testRoot 'case4b'
New-Game $case4b @('gdx3')
New-Item -ItemType Directory -Path (Join-Path $case4b 'settings\text_en') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $case4b 'settings\text_en\tags_items.txt') -Value 'legacy' -Encoding UTF8
$env:DSH_RAINBOW_FAULT = 'legacy'
$ok = Invoke-Installer @{ FilePath = $enFile; GamePath = $case4b; Language = 'en'; Location = 'game' }
$env:DSH_RAINBOW_FAULT = $null
Assert (-not $ok) 'failure after the legacy move exits non-zero'
Assert (Test-Path -LiteralPath (Join-Path $case4b 'settings\text_en\tags_items.txt')) 'legacy move failure restores the legacy file'
Assert (-not (Test-Path -LiteralPath (Join-Path $case4b 'settings\text_en\tagsgdx3_uimain.txt'))) 'legacy move failure publishes nothing'
Assert (-not (Test-Path -LiteralPath (Get-ManifestPath $case4b))) 'legacy move failure leaves no manifest'

# --- failed reinstall keeps the original bytes and the previous manifest ---
$case5 = Join-Path $testRoot 'case5'
New-Game $case5 @('gdx3')
$ok = Invoke-Installer @{ FilePath = $enFile; GamePath = $case5; Language = 'en'; Location = 'game' }
$target5 = Join-Path $case5 'settings\text_en\tagsgdx3_uimain.txt'
$hashBefore = (Get-FileHash -LiteralPath $target5 -Algorithm SHA256).Hash
$env:DSH_RAINBOW_FAULT = 'published'
$ok = Invoke-Installer @{ FilePath = $enFile2; GamePath = $case5; Language = 'en'; Location = 'game' }
$env:DSH_RAINBOW_FAULT = $null
$manifest5 = Read-Manifest $case5
Assert (-not $ok) 'failed reinstall exits non-zero'
Assert ((Test-Path -LiteralPath $target5) -and (Get-FileHash -LiteralPath $target5 -Algorithm SHA256).Hash -eq $hashBefore) 'failed reinstall preserves the original bytes'
Assert ($null -ne $manifest5 -and (Get-Prop $manifest5 'state') -eq 'installed') 'failed reinstall restores the previous manifest'
$ok = Invoke-Installer @{ Uninstall = $true; GamePath = $case5; Language = 'en' }
Assert ($ok -and -not (Test-Path -LiteralPath $target5)) 'uninstall still works after a failed reinstall'

# --- rollback failure keeps the recovery record ----------------------------
$case6 = Join-Path $testRoot 'case6'
New-Game $case6 @('gdx3')
$ok = Invoke-Installer @{ FilePath = $enFile; GamePath = $case6; Language = 'en'; Location = 'game' }
$target6 = Join-Path $case6 'settings\text_en\tagsgdx3_uimain.txt'
$env:DSH_RAINBOW_FAULT = 'verify,restore'
$errorText = $null
try { & $installer -FilePath $enFile2 -GamePath $case6 -Language en -Location game 2>$null | Out-Null } catch { $errorText = $_.Exception.Message }
$env:DSH_RAINBOW_FAULT = $null
$manifest6 = Read-Manifest $case6
Assert ($null -ne $errorText) 'rollback failure exits non-zero'
Assert ($null -ne $manifest6 -and (Get-Prop $manifest6 'state') -eq 'installing') 'rollback failure keeps the installing manifest'
Assert (Test-Path -LiteralPath (Get-Prop $manifest6 'backupDir')) 'rollback failure keeps the backup folder'
Assert ($errorText -match 'recovery manifest') 'rollback failure names the recovery manifest'

# --- manifest write failure changes nothing --------------------------------
$case6b = Join-Path $testRoot 'case6b'
New-Game $case6b @('gdx3')
Set-Content -LiteralPath (Join-Path $case6b 'settings') -Value 'blocker' -Encoding UTF8
$before = Get-TreeHash $case6b
$blockedRun = Invoke-InstallerOutput @{ FilePath = $enFile; GamePath = $case6b; Language = 'en'; Location = 'game' }
$after = Get-TreeHash $case6b
Assert (-not $blockedRun.Ok) 'manifest write failure exits non-zero'
Assert ($blockedRun.Output -match 'manifest') 'manifest write failure names the manifest'
Assert ($before -eq $after) 'manifest write failure changes nothing'

# --- crash-left installing manifest is reconciled --------------------------
$case7 = Join-Path $testRoot 'case7'
New-Game $case7 @('gdx3')
$target7 = Join-Path $case7 'settings\text_en\tagsgdx3_uimain.txt'
New-Item -ItemType Directory -Path (Split-Path -Parent $target7) -Force | Out-Null
Set-Content -LiteralPath $target7 -Value 'crashed filter' -Encoding UTF8
$crashedManifest = [ordered]@{
    state = 'installing'; root = $case7; relative = 'settings\text_en\tagsgdx3_uimain.txt'
    target = $target7; source = 'crash'; backupDir = $null; moved = @()
}
Write-TextAtomic (Get-ManifestPath $case7) (($crashedManifest | ConvertTo-Json -Depth 6) + "`n")
$ok = Invoke-Installer @{ FilePath = $enFile; GamePath = $case7; Language = 'en'; Location = 'game' }
$manifest7 = Read-Manifest $case7
Assert ($ok -and (Get-Prop $manifest7 'state') -eq 'installed') 'crash-left install reconciles'
Assert (@(Get-ChildItem -LiteralPath (Join-Path $case7 'settings\.rainbow-backup') -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'tagsgdx3_uimain.txt' }).Count -eq 1) 'crash-left target is backed up'

# --- uninstall reconciles a leftover installing manifest -------------------
$case8 = Join-Path $testRoot 'case8'
New-Game $case8 @('gdx3')
$target8 = Join-Path $case8 'settings\text_en\tagsgdx3_uimain.txt'
New-Item -ItemType Directory -Path (Split-Path -Parent $target8) -Force | Out-Null
Set-Content -LiteralPath $target8 -Value 'original before crash' -Encoding UTF8
$crashedManifest = [ordered]@{
    state = 'installing'; root = $case8; relative = 'settings\text_en\tagsgdx3_uimain.txt'
    target = $target8; source = 'crash'; backupDir = $null; moved = @()
}
Write-TextAtomic (Get-ManifestPath $case8) (($crashedManifest | ConvertTo-Json -Depth 6) + "`n")
$ok = Invoke-Installer @{ Uninstall = $true; GamePath = $case8; Language = 'en' }
Assert ($ok -and -not (Test-Path -LiteralPath $target8)) 'uninstall removes a leftover installing target'
Assert (-not (Test-Path -LiteralPath (Get-ManifestPath $case8))) 'uninstall removes a leftover installing manifest'
$crashBackup = @(Get-ChildItem -LiteralPath (Join-Path $case8 'settings\.rainbow-backup') -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'tagsgdx3_uimain.txt' -and (Get-Content -LiteralPath $_.FullName -Raw) -match 'original before crash' })
Assert ($crashBackup.Count -eq 1) 'uninstall backs up a crash-left target instead of deleting it'

# --- uninstall without an install deletes nothing --------------------------
$case9 = Join-Path $testRoot 'case9'
New-Game $case9 @('gdx3')
New-Item -ItemType Directory -Path (Join-Path $case9 'settings') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $case9 'settings\keep.txt') -Value 'keep' -Encoding UTF8
$uninstallRun = Invoke-InstallerOutput @{ Uninstall = $true; GamePath = $case9; Language = 'en' }
Assert ($uninstallRun.Ok) 'uninstall without an install succeeds'
Assert ($uninstallRun.Output -match 'No Rainbow Filter installation was recorded') 'uninstall without an install says nothing was recorded'
Assert (Test-Path -LiteralPath (Join-Path $case9 'settings\keep.txt')) 'uninstall without an install deletes nothing'

# --- forward slashes in the header are normalised --------------------------
$fwFile = Join-Path $headers 'fw.txt'
New-FilterFile $fwFile 'text_en/tagsgdx3_uimain.txt'
$fwHeader = Get-HeaderInfo (Get-HeaderText $fwFile)
Assert ($fwHeader.Relative -eq 'text_en\tagsgdx3_uimain.txt') 'forward slashes in the header normalised'

# --- dry-run uninstall changes nothing -------------------------------------
$case10 = Join-Path $testRoot 'case10'
New-Game $case10 @('gdx3')
$ok = Invoke-Installer @{ FilePath = $enFile; GamePath = $case10; Language = 'en'; Location = 'game' }
$target10 = Join-Path $case10 'settings\text_en\tagsgdx3_uimain.txt'
$before = Get-TreeHash $case10
$dryUninstall = Invoke-InstallerOutput @{ Uninstall = $true; GamePath = $case10; Language = 'en'; DryRun = $true }
Assert ($dryUninstall.Ok -and $dryUninstall.Output -match 'Would remove') 'dry-run uninstall prints the plan'
Assert ($before -eq (Get-TreeHash $case10)) 'dry-run uninstall changes nothing'
Assert ((Test-Path -LiteralPath $target10) -and (Test-Path -LiteralPath (Get-ManifestPath $case10))) 'dry-run uninstall keeps the filter and manifest'
$ok = Invoke-Installer @{ Uninstall = $true; GamePath = $case10; Language = 'en' }
Assert ($ok -and -not (Test-Path -LiteralPath $target10)) 'uninstall after a dry run still works'

# --- a manifest outside the settings root is ignored -----------------------
$case11 = Join-Path $testRoot 'case11'
New-Game $case11 @('gdx3')
New-Item -ItemType Directory -Path (Join-Path $case11 'settings') -Force | Out-Null
$outside = Join-Path $testRoot 'outside.txt'
Set-Content -LiteralPath $outside -Value 'do not touch' -Encoding UTF8
$poisoned = [ordered]@{
    state = 'installed'; root = $case11; relative = 'settings\text_en\tagsgdx3_uimain.txt'
    target = $outside; source = 'test'; backupDir = $null; moved = @()
}
Write-TextAtomic (Get-ManifestPath $case11) (($poisoned | ConvertTo-Json -Depth 6) + "`n")
$ok = Invoke-Installer @{ Uninstall = $true; GamePath = $case11; Language = 'en' }
Assert ($ok -and (Test-Path -LiteralPath $outside)) 'uninstall ignores a target outside the settings root'
Assert (-not (Test-Path -LiteralPath (Get-ManifestPath $case11))) 'uninstall removes the poisoned manifest'

# --- install ignores a previous target outside the settings root -----------
$case12 = Join-Path $testRoot 'case12'
New-Game $case12 @('gdx3')
New-Item -ItemType Directory -Path (Join-Path $case12 'settings') -Force | Out-Null
$poisoned = [ordered]@{
    state = 'installed'; root = $case12; relative = 'settings\text_en\tagsgdx3_uimain.txt'
    target = $outside; source = 'test'; backupDir = $null; moved = @()
}
Write-TextAtomic (Get-ManifestPath $case12) (($poisoned | ConvertTo-Json -Depth 6) + "`n")
$ok = Invoke-Installer @{ FilePath = $enFile; GamePath = $case12; Language = 'en'; Location = 'game' }
$manifest12 = Read-Manifest $case12
Assert ($ok -and (Test-Path -LiteralPath $outside) -and (Get-Prop $manifest12 'state') -eq 'installed') 'install ignores a previous target outside the settings root'

# --- a manifest target inside the root but outside settings is ignored -----
$case15 = Join-Path $testRoot 'case15'
New-Game $case15 @('gdx3')
New-Item -ItemType Directory -Path (Join-Path $case15 'settings') -Force | Out-Null
$saveDir = Join-Path $case15 'save\main\_Hero'
New-Item -ItemType Directory -Path $saveDir -Force | Out-Null
$saveFile = Join-Path $saveDir 'player.gdc'
Set-Content -LiteralPath $saveFile -Value 'save data' -Encoding UTF8
$poisoned = [ordered]@{
    state = 'installed'; root = $case15; relative = 'settings\text_en\tagsgdx3_uimain.txt'
    target = $saveFile; source = 'test'; backupDir = $null; moved = @()
}
Write-TextAtomic (Get-ManifestPath $case15) (($poisoned | ConvertTo-Json -Depth 6) + "`n")
$ok = Invoke-Installer @{ Uninstall = $true; GamePath = $case15; Language = 'en' }
Assert ($ok -and (Test-Path -LiteralPath $saveFile)) 'uninstall ignores a target outside settings'
Assert (-not (Test-Path -LiteralPath (Get-ManifestPath $case15))) 'uninstall removes the save-targeting manifest'

$case16 = Join-Path $testRoot 'case16'
New-Game $case16 @('gdx3')
New-Item -ItemType Directory -Path (Join-Path $case16 'settings') -Force | Out-Null
$saveDir = Join-Path $case16 'save\main\_Hero'
New-Item -ItemType Directory -Path $saveDir -Force | Out-Null
$saveFile = Join-Path $saveDir 'player.gdc'
Set-Content -LiteralPath $saveFile -Value 'save data' -Encoding UTF8
$poisoned = [ordered]@{
    state = 'installed'; root = $case16; relative = 'settings\text_en\tagsgdx3_uimain.txt'
    target = $saveFile; source = 'test'; backupDir = $null; moved = @()
}
Write-TextAtomic (Get-ManifestPath $case16) (($poisoned | ConvertTo-Json -Depth 6) + "`n")
$ok = Invoke-Installer @{ FilePath = $enFile; GamePath = $case16; Language = 'en'; Location = 'game' }
Assert ($ok -and (Test-Path -LiteralPath $saveFile)) 'install ignores a previous target outside settings'

# --- malformed sources are rejected before any install write ---------------
$noVersionFile = Join-Path $headers 'noversion.txt'
$noVersionHeader = @(
    '# ############################## #'
    '# \Grim Dawn\settings\text_en\tagsgdx3_uimain.txt'
) -join "`n"
Set-Content -LiteralPath $noVersionFile -Value ($noVersionHeader + "`n" + ('x' * 60000)) -Encoding UTF8
$noVersionRejected = $false
try { $null = Get-HeaderInfo (Get-HeaderText $noVersionFile) } catch { $noVersionRejected = $true }
Assert $noVersionRejected 'missing Raynbow version header rejected'

$tinyFile = Join-Path $headers 'tiny.txt'
$tinyHeader = @(
    '# ### Grim Dawn:    v1.3.1.1 ### #'
    '# ### Grim Raynbow: v0.0.3.5 ### #'
    '# \Grim Dawn\settings\text_en\tagsgdx3_uimain.txt'
) -join "`n"
Set-Content -LiteralPath $tinyFile -Value ($tinyHeader + "`n" + ('x' * 10)) -Encoding UTF8
$tinyRun = Invoke-InstallerOutput @{ FilePath = $tinyFile; GamePath = $foaGame; Language = 'en'; Location = 'game' }
Assert (-not $tinyRun.Ok -and $tinyRun.Output -match 'not a valid Raynbow filter') 'tiny local file refused before install'
Assert (-not (Test-Path -LiteralPath (Get-ManifestPath $foaGame))) 'tiny local file writes no manifest'

$badGame = Join-Path $testRoot 'bad-source-game'
New-Game $badGame @('gdx3')
$badRule = Add-DenyWrite $badGame
$before = Get-TreeHash $badGame
$badRun = Invoke-InstallerOutput @{ FilePath = $noVersionFile; GamePath = $badGame; Language = 'en'; Location = 'game' }
$after = Get-TreeHash $badGame
Remove-DenyWrite $badGame $badRule
Assert (-not $badRun.Ok) 'malformed source with a read-only root fails'
Assert ($badRun.Output -match 'Raynbow version header') 'malformed source reports the missing version header'
Assert ($before -eq $after) 'malformed source changes nothing'

# --- help, early-language failures and network-free rejection --------------
$help = Get-Help $installer -Full
Assert ($help.Synopsis -match 'Install or update the Grim Raynbow') 'comment-based help synopsis exposed'

$notGame = Join-Path $testRoot 'not-a-game'
New-Item -ItemType Directory -Path $notGame -Force | Out-Null
$ruEarly = Invoke-InstallerOutput @{ DryRun = $true; Language = 'ru'; GamePath = $notGame }
Assert (-not $ruEarly.Ok -and $ruEarly.Output -match 'Это не папка Grim Dawn') 'early install failure uses the selected language'
$ruEarlyUninstall = Invoke-InstallerOutput @{ Uninstall = $true; Language = 'ru'; GamePath = $notGame }
Assert (-not $ruEarlyUninstall.Ok -and $ruEarlyUninstall.Output -match 'Это не папка Grim Dawn') 'early uninstall failure uses the selected language'

$script:webFixture = $enFile
$script:webCalls = 0
$null = Invoke-WebRequest -Uri 'https://example.invalid' -ErrorAction Stop
Assert ($script:webCalls -eq 1) 'network spy intercepts Invoke-WebRequest'
$script:webCalls = 0
$bindingError = $null
try { & $installer -DryRun -Language xx } catch { $bindingError = $_.Exception.Message }
Assert ($script:webCalls -eq 0) 'invalid language performs no network call'
Assert ($null -ne $bindingError -and $bindingError -match 'Cannot validate argument') 'invalid language fails parameter validation'

# --- download and in-memory paths (mocked network, direct call) ------------
$savedTmp = $env:TMP
$savedTemp = $env:TEMP
$mockTemp = Join-Path $testRoot 'mock-temp'
New-Item -ItemType Directory -Path $mockTemp -Force | Out-Null
$env:TMP = $mockTemp
$env:TEMP = $mockTemp
$script:webFixture = $enFile
$script:webCalls = 0
$dlGame = Join-Path $testRoot 'download-game'
New-Game $dlGame @('gdx3')
$dlOk = $false
$FilePath = $null
$GamePath = $dlGame
$Language = 'en'
$Location = 'game'
$DryRun = $false
$GameVersion = 'foa'
$Preset = 'full'
try { Invoke-Install; $dlOk = $true } catch { $dlOk = $false }
$env:TMP = $savedTmp
$env:TEMP = $savedTemp
$dlTarget = Join-Path $dlGame 'settings\text_en\tagsgdx3_uimain.txt'
Assert ($dlOk -and (Test-Path -LiteralPath $dlTarget)) 'download-to-temp install works'
Assert ($script:webCalls -eq 1) 'download path makes one request'
Assert ($script:webOutFile -like ($mockTemp + '*')) 'download is staged in the temp directory'
Assert (-not (Test-Path -LiteralPath $script:webOutFile)) 'download temp file is cleaned up'

$env:TMP = $mockTemp
$env:TEMP = $mockTemp
$script:webCalls = 0
$script:webOutFile = $null
$memGame = Join-Path $testRoot 'memory-game'
New-Game $memGame @('gdx3')
$memOk = $false
$FilePath = $null
$GamePath = $memGame
$DryRun = $true
try { Invoke-Install; $memOk = $true } catch { $memOk = $false }
$env:TMP = $savedTmp
$env:TEMP = $savedTemp
$DryRun = $false
Assert ($memOk) 'in-memory dry run works'
Assert ($script:webCalls -eq 1) 'in-memory dry run makes one request'
Assert ($null -eq $script:webOutFile) 'in-memory dry run requests no output file'
Assert (@(Get-ChildItem -LiteralPath $mockTemp -Force -ErrorAction SilentlyContinue).Count -eq 0) 'in-memory dry run writes no temp entries'
Assert (-not (Test-Path -LiteralPath (Get-ManifestPath $memGame))) 'in-memory dry run writes no manifest'

$script:webFixture = $enFile
$FilePath = $null
$GamePath = $memGame
$DryRun = $true
foreach ($product in @(@('full', 'preset_id=1'), @('basic', 'preset_id=2'), @('diablo', 'preset_id=3'))) {
    $Preset = $product[0]
    Invoke-Install
    Assert ($script:webUri -match $product[1]) ('preset ' + $product[0] + ' reaches the request')
}
$DryRun = $false
$Preset = 'full'

$env:DSH_RAINBOW_DOCUMENTS_ROOT = Join-Path $testRoot 'no-docs-download'
$script:webCalls = 0
$noRootDownload = Invoke-InstallerOutput @{ Language = 'en'; Location = 'auto' }
$env:DSH_RAINBOW_DOCUMENTS_ROOT = $missingDocuments
Assert (-not $noRootDownload.Ok -and $noRootDownload.Output -match '-GamePath') 'no-root failure is reported before the download'
Assert ($script:webCalls -eq 0) 'no-root failure makes no request'

# --- repeated installs keep every backup generation ------------------------
$case13 = Join-Path $testRoot 'case13'
New-Game $case13 @('gdx3')
$target13 = Join-Path $case13 'settings\text_en\tagsgdx3_uimain.txt'
New-Item -ItemType Directory -Path (Split-Path -Parent $target13) -Force | Out-Null
Set-Content -LiteralPath $target13 -Value 'original bytes' -Encoding UTF8
$ok = Invoke-Installer @{ FilePath = $enFile; GamePath = $case13; Language = 'en'; Location = 'game' }
$ok2 = Invoke-Installer @{ FilePath = $enFile2; GamePath = $case13; Language = 'en'; Location = 'game' }
$backupDirs = @(Get-ChildItem -LiteralPath (Join-Path $case13 'settings\.rainbow-backup') -Directory -ErrorAction SilentlyContinue)
Assert ($ok -and $ok2 -and $backupDirs.Count -ge 2) 'repeated installs use distinct backup folders'
$original = @(Get-ChildItem -LiteralPath (Join-Path $case13 'settings\.rainbow-backup') -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'tagsgdx3_uimain.txt' -and (Get-Content -LiteralPath $_.FullName -Raw) -match 'original bytes' })
Assert ($original.Count -eq 1) 'the original user file survives repeated installs'

# --- failed cross-root cleanup rolls the new install back ------------------
$case14 = Join-Path $testRoot 'case14'
New-Game $case14 @('gdx3')
$case14Docs = Join-Path $testRoot 'case14-docs'
New-Item -ItemType Directory -Path $case14Docs -Force | Out-Null
$env:DSH_RAINBOW_DOCUMENTS_ROOT = $case14Docs
$ok = Invoke-Installer @{ FilePath = $enFile; GamePath = $case14; Language = 'en'; Location = 'game' }
$gameTarget14 = Join-Path $case14 'settings\text_en\tagsgdx3_uimain.txt'
New-Item -ItemType Directory -Path (Join-Path $case14Docs 'settings\.rainbow-backup') -Force | Out-Null
$backupRule = Add-DenyWrite (Join-Path $case14Docs 'settings\.rainbow-backup')
try {
    $cleanupRun = Invoke-InstallerOutput @{ FilePath = $enFile2; GamePath = $case14; Language = 'en'; Location = 'documents' }
} finally {
    Remove-DenyWrite (Join-Path $case14Docs 'settings\.rainbow-backup') $backupRule
}
Assert (-not $cleanupRun.Ok) 'failed cross-root cleanup exits non-zero'
Assert (Test-Path -LiteralPath $gameTarget14) 'failed cross-root cleanup keeps the existing copy'
Assert (-not (Test-Path -LiteralPath (Join-Path $case14Docs 'settings\text_en\tagsgdx3_uimain.txt'))) 'failed cross-root cleanup publishes nothing'
Assert ($null -eq (Read-Manifest $case14Docs)) 'failed cross-root cleanup leaves no manifest'
$env:DSH_RAINBOW_DOCUMENTS_ROOT = $missingDocuments

Remove-Item Function:\Invoke-WebRequest -ErrorAction SilentlyContinue
if ($Live) {
    $liveFile = Join-Path $testRoot 'live-ru.txt'
    Invoke-WebRequest -Uri 'https://grimraynbow.com/ru/GD/Filter/Download?preset_id=1' -OutFile $liveFile -UseBasicParsing -TimeoutSec 120
    $liveSize = (Get-Item -LiteralPath $liveFile).Length
    $liveHeader = Get-HeaderInfo (Get-HeaderText $liveFile)
    Assert ($liveSize -gt 200000) 'live RU download is larger than 200 KB'
    Assert ($null -ne $liveHeader.RaynowVersion) 'live RU download carries a Raynbow version'
    Assert ($liveHeader.Relative -eq 'text_ru\aom\tagsgdx1_achievements.txt') 'live RU header path'
    $hashes = @{}
    foreach ($product in @(@('full', 'Full Rainbow'), @('basic', 'Basic Highlighting'), @('diablo', 'Diablo'))) {
        $file = Join-Path $testRoot ('live-' + $product[0] + '.txt')
        Invoke-WebRequest -Uri (Get-DownloadUrl 'ru' $product[0] 'foa') -OutFile $file -UseBasicParsing -TimeoutSec 120
        $hashes[$product[0]] = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
        $line = Get-Content -LiteralPath $file -TotalCount 12 -Encoding UTF8 | Where-Object { $_ -match 'Preset:' } | Select-Object -First 1
        Assert ($line -match $product[1]) ('live preset ' + $product[0] + ' carries its name')
    }
    Assert (($hashes.Values | Select-Object -Unique).Count -eq 3) 'live presets differ'
}

# --- failed published removal preserves every backup -----------------------
$case17 = Join-Path $testRoot 'case17'
New-Game $case17 @('gdx3')
$target17 = Join-Path $case17 'settings\text_en\tagsgdx3_uimain.txt'
New-Item -ItemType Directory -Path (Split-Path -Parent $target17) -Force | Out-Null
Set-Content -LiteralPath $target17 -Value 'original bytes' -Encoding UTF8
$ok = Invoke-Installer @{ FilePath = $enFile; GamePath = $case17; Language = 'en'; Location = 'game' }
$hashFilter = (Get-FileHash -LiteralPath $enFile -Algorithm SHA256).Hash
$env:DSH_RAINBOW_FAULT = 'verify,remove-published'
$errorText = $null
try { & $installer -FilePath $enFile2 -GamePath $case17 -Language en -Location game 2>$null | Out-Null } catch { $errorText = $_.Exception.Message }
$env:DSH_RAINBOW_FAULT = $null
$manifest17 = Read-Manifest $case17
Assert ($null -ne $errorText) 'published removal failure exits non-zero'
Assert ($null -ne $manifest17 -and (Get-Prop $manifest17 'state') -eq 'installing') 'published removal failure keeps the installing manifest'
Assert ($errorText -match 'recovery manifest') 'published removal failure names the recovery action'
$backupFiles = @(Get-ChildItem -LiteralPath (Join-Path $case17 'settings\.rainbow-backup') -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'tagsgdx3_uimain.txt' })
$originals = @($backupFiles | Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match 'original bytes' })
$firstFilters = @($backupFiles | Where-Object { (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash -eq $hashFilter })
Assert ($originals.Count -eq 1) 'published removal failure keeps the original user backup'
Assert ($firstFilters.Count -ge 1) 'published removal failure keeps the displaced filter backup'

# --- legacy cleanup skips directories with allowlisted names ---------------
$case18 = Join-Path $testRoot 'case18'
New-Game $case18 @('gdx3')
$legacyDir = Join-Path $case18 'settings\text_en\tags_items.txt'
New-Item -ItemType Directory -Path $legacyDir -Force | Out-Null
Set-Content -LiteralPath (Join-Path $legacyDir 'custom.txt') -Value 'keep' -Encoding UTF8
$ok = Invoke-Installer @{ FilePath = $enFile; GamePath = $case18; Language = 'en'; Location = 'game' }
Assert ($ok -and (Test-Path -LiteralPath (Join-Path $legacyDir 'custom.txt'))) 'legacy cleanup ignores a directory with an allowlisted name'

# --- real auto install chooses a writable game root -----------------------
$autoGame = Join-Path $testRoot 'auto-game'
New-Game $autoGame @('gdx3')
$autoDocs = Join-Path $testRoot 'auto-docs'
New-Item -ItemType Directory -Path $autoDocs -Force | Out-Null
$env:DSH_RAINBOW_DOCUMENTS_ROOT = $autoDocs
$autoRun = Invoke-InstallerOutput @{ FilePath = $enFile; GamePath = $autoGame; Language = 'en' }
$autoTarget = Join-Path $autoGame 'settings\text_en\tagsgdx3_uimain.txt'
Assert ($autoRun.Ok -and (Test-Path -LiteralPath $autoTarget)) 'auto install uses a writable game root'
Assert (Test-Path -LiteralPath (Get-ManifestPath $autoGame)) 'auto install writes the game-root manifest'
Assert (-not (Test-Path -LiteralPath (Join-Path $autoDocs 'settings\text_en\tagsgdx3_uimain.txt'))) 'auto install writes no Documents copy'
$ok = Invoke-Installer @{ Uninstall = $true; GamePath = $autoGame; Language = 'en' }
$env:DSH_RAINBOW_DOCUMENTS_ROOT = $missingDocuments

# --- legacy cleanup scans text_<lang>\aom ----------------------------------
$case19 = Join-Path $testRoot 'case19'
New-Game $case19 @('gdx3')
$aomDir = Join-Path $case19 'settings\text_ru\aom'
New-Item -ItemType Directory -Path $aomDir -Force | Out-Null
Set-Content -LiteralPath (Join-Path $aomDir 'tagsgdx1_ui.txt') -Value 'legacy aom' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $aomDir 'custom.txt') -Value 'keep aom' -Encoding UTF8
$ok = Invoke-Installer @{ FilePath = $ruFile; GamePath = $case19; Language = 'ru'; Location = 'game' }
$aomLegacy = @(Get-ChildItem -LiteralPath (Join-Path $case19 'settings\.rainbow-backup') -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'tagsgdx1_ui.txt' -and (Get-Content -LiteralPath $_.FullName -Raw) -match 'legacy aom' })
Assert ($ok -and $aomLegacy.Count -eq 1) 'legacy file under text_ru\aom moves into the backup'
Assert (-not (Test-Path -LiteralPath (Join-Path $aomDir 'tagsgdx1_ui.txt'))) 'legacy file under aom is no longer active'
Assert (Test-Path -LiteralPath (Join-Path $aomDir 'custom.txt')) 'unrelated file under aom is preserved'

# --- the installing manifest exists before the first backup move -----------
$journalGame = Join-Path $testRoot 'journal-game'
New-Game $journalGame @('gdx3')
New-Item -ItemType Directory -Path (Join-Path $journalGame 'settings\text_en') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $journalGame 'settings\text_en\tags_items.txt') -Value 'legacy' -Encoding UTF8
$script:journalGame = $journalGame
$script:journalSeen = $false
$script:journalState = $null
function Move-Item {
    [CmdletBinding()]
    param($LiteralPath, $Destination, [switch]$Force)
    if ($Destination -like '*\.rainbow-backup\*') {
        $script:journalSeen = Test-Path -LiteralPath (Get-ManifestPath $script:journalGame)
        if ($script:journalSeen) { $script:journalState = [string](Get-Prop (Read-Manifest $script:journalGame) 'state') }
        throw 'stop-after-journal'
    }
    Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force
}
$FilePath = $enFile
$GamePath = $journalGame
$Language = 'en'
$Location = 'game'
$DryRun = $false
$GameVersion = 'foa'
$Preset = 'full'
try { Invoke-Install } catch { }
Remove-Item Function:\Move-Item -ErrorAction SilentlyContinue
Assert ($script:journalSeen -and $script:journalState -eq 'installing') 'installing manifest is journaled before the first backup move'
Assert (-not (Test-Path -LiteralPath (Get-ManifestPath $journalGame))) 'failed journaled install rolls back the manifest'
Assert (Test-Path -LiteralPath (Join-Path $journalGame 'settings\text_en\tags_items.txt')) 'failed journaled install leaves the legacy file in place'

# --- failed previous-manifest restoration keeps the journal ----------------
$case20 = Join-Path $testRoot 'case20'
New-Game $case20 @('gdx3')
$ok = Invoke-Installer @{ FilePath = $enFile; GamePath = $case20; Language = 'en'; Location = 'game' }
$target20 = Join-Path $case20 'settings\text_en\tagsgdx3_uimain.txt'
$hashFilter20 = (Get-FileHash -LiteralPath $enFile -Algorithm SHA256).Hash
$env:DSH_RAINBOW_FAULT = 'verify,restore-manifest'
$errorText = $null
try { & $installer -FilePath $enFile2 -GamePath $case20 -Language en -Location game 2>$null | Out-Null } catch { $errorText = $_.Exception.Message }
$env:DSH_RAINBOW_FAULT = $null
$manifest20 = Read-Manifest $case20
Assert ($null -ne $errorText) 'manifest restore failure exits non-zero'
Assert ($null -ne $manifest20 -and (Get-Prop $manifest20 'state') -eq 'installing') 'manifest restore failure keeps the installing journal'
Assert ($errorText -match 'recovery manifest') 'manifest restore failure names the recovery action'
Assert ((Test-Path -LiteralPath $target20) -and (Get-FileHash -LiteralPath $target20 -Algorithm SHA256).Hash -eq $hashFilter20) 'manifest restore failure restores the displaced filter'

# --- result -----------------------------------------------------------------
Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
if ($script:failures -gt 0) {
    Write-Host "$($script:failures) check(s) failed" -ForegroundColor Red
    exit 1
}
Write-Host 'all installer checks passed' -ForegroundColor Green
exit 0
