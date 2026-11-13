#Requires -Version 5.1

<#
.SYNOPSIS
Install or update the Grim Raynbow (Rainbow Filter) text overlay for Grim Dawn.

.DESCRIPTION
Downloads the single generated filter file for the game's own language and DLC set, installs it
under the settings folder the game loads, moves known legacy Rainbow files to a timestamped backup,
and records a manifest for uninstall. The game may stay open; restart it to load the new colours.

.EXAMPLE
irm https://raw.githubusercontent.com/sergey-akhalkov/Grim-Dawn-Rainbow-Filter-Installer/main/install.ps1 | iex

.EXAMPLE
./install.ps1 -DryRun

.EXAMPLE
./install.ps1 -Language en -Preset basic

.EXAMPLE
./install.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [ValidateSet('auto', 'en', 'ru', 'de', 'fr', 'es', 'it', 'cs', 'pl', 'ja', 'ko', 'pt', 'vi', 'zh')]
    [string]$Language = 'auto',

    [ValidateSet('full', 'basic', 'diablo')]
    [string]$Preset = 'full',

    [ValidateSet('auto', 'foa', 'fg', 'aom', 'base')]
    [string]$GameVersion = 'auto',

    [ValidateSet('auto', 'game', 'documents')]
    [string]$Location = 'auto',

    [string]$GamePath,
    [string]$FilePath,

    [switch]$DryRun,
    [switch]$Uninstall
)

$script:SiteBase = 'https://grimraynbow.com'
$script:PresetIds = @{ full = '1'; basic = '2'; diablo = '3' }
$script:VersionSuffix = @{ foa = ''; base = '-1'; aom = '-2'; fg = '-3' }
$script:SupportedLanguages = @('en', 'ru', 'de', 'fr', 'es', 'it', 'cs', 'pl', 'ja', 'ko', 'pt', 'vi', 'zh')
$script:LanguageMap = [ordered]@{
    english = 'en'; russian = 'ru'; german = 'de'; french = 'fr'; spanish = 'es'; italian = 'it'
    czech = 'cs'; polish = 'pl'; japanese = 'ja'; korean = 'ko'; portuguese = 'pt'; chinese = 'zh'; vietnamese = 'vi'
}
$script:LegacyNames = @(
    'tags_items.txt', 'tags_ui.txt', 'tagsgdx1_items.txt', 'tagsgdx1_storyelements.txt',
    'tagsgdx2_endlessdungeon.txt', 'tagsgdx2_items.txt', 'tagsgdx3_uimain.txt',
    'tagsgdx1_achievements.txt', 'tags_achievements.txt', 'tagsgdx1_ui.txt', 'tagsgdx2_ui.txt'
)
$script:ManifestName = '.rainbow-filter.json'
$script:MessageLanguage = 'en'
$script:Messages = @{
    en = @{
        game = 'Grim Dawn: {0} ({1})'
        lang = 'Language: {0}, preset: {1}'
        source = 'Source: {0}'
        root = 'Install root: {0}'
        target = 'Target: {0}'
        backup = 'Backup: {0}'
        dry = 'Dry run: no changes were made.'
        installed = 'Installed: {0}'
        restart = 'Restart Grim Dawn to load the new colours.'
        uninstalled = 'Removed: {0}'
        wouldremove = 'Would remove: {0}'
        backupkept = 'Backup kept: {0}'
        noinstall = 'No Rainbow Filter installation was recorded.'
        'warn.docs' = 'Warning: the game folder is not writable; installing to Documents.'
        'warn.nogame' = 'Warning: the game folder was not found; using Documents and the current Fangs of Asterkarn file.'
        'warn.other' = 'Warning: could not remove the previous install record in the other location: {0}'
        'version.foa' = 'Fangs of Asterkarn'
        'version.fg' = 'Forgotten Gods'
        'version.aom' = 'Ashes of Malmouth'
        'version.base' = 'base game'
        'err.gamepath' = 'Not a Grim Dawn folder: {0}. Pass -GamePath with the folder that contains Grim Dawn.exe.'
        'err.nogame' = 'Grim Dawn was not found. Pass -GamePath <game folder> and run again.'
        'err.nodocs' = "Grim Dawn's Documents folder was not found: {0}. Run Grim Dawn once or pass -Location game."
        'err.notwritable' = 'Cannot write to {0}. Pass -Location documents.'
        'err.nowritable' = 'Cannot write to {0}, and {1} does not exist. Run Grim Dawn once or pass -GamePath <game folder>.'
        'err.download' = 'Cannot download {0}: {1}. Download the file from grimraynbow.com and pass -FilePath <file>.'
        'err.invalid' = 'The response is not a valid Raynbow filter (size {0}). Use -FilePath with a file downloaded from grimraynbow.com.'
        'err.header' = 'The file has no settings destination header. Use a file downloaded from grimraynbow.com.'
        'err.notraynow' = 'The file is not a Grim Raynbow filter (missing the Raynbow version header). Use a file downloaded from grimraynbow.com.'
        'err.filepath' = 'File not found: {0}. Pass -FilePath with a file downloaded from grimraynbow.com.'
        'err.manifest' = 'Cannot write the install manifest: {0}. Check that the settings folder is writable.'
        'err.verify' = 'The installed file failed verification: {0}. The install was rolled back; rerun or pass -FilePath with a freshly downloaded file.'
        'rollback.fail' = 'Rollback failed: {0}. The recovery manifest is kept at {1}; run -Uninstall or restore files from its backup folder.'
        failed = 'FAILED: {0}'
    }
    ru = @{
        game = 'Grim Dawn: {0} ({1})'
        lang = 'Язык: {0}, пресет: {1}'
        source = 'Источник: {0}'
        root = 'Папка установки: {0}'
        target = 'Файл: {0}'
        backup = 'Бэкап: {0}'
        dry = 'Пробный запуск: изменения не вносились.'
        installed = 'Установлено: {0}'
        restart = 'Перезапусти Grim Dawn, чтобы увидеть цвета.'
        uninstalled = 'Удалено: {0}'
        wouldremove = 'Будет удалено: {0}'
        backupkept = 'Бэкап сохранён: {0}'
        noinstall = 'Установка Rainbow Filter не найдена.'
        'warn.docs' = 'Внимание: папка игры недоступна для записи, ставлю в Документы.'
        'warn.nogame' = 'Внимание: папка игры не найдена, ставлю в Документы и беру текущий файл Fangs of Asterkarn.'
        'warn.other' = 'Внимание: не удалось удалить запись о предыдущей установке в другой папке: {0}'
        'version.foa' = 'Fangs of Asterkarn'
        'version.fg' = 'Forgotten Gods'
        'version.aom' = 'Ashes of Malmouth'
        'version.base' = 'базовая игра'
        'err.gamepath' = 'Это не папка Grim Dawn: {0}. Укажи -GamePath с папкой, где лежит Grim Dawn.exe.'
        'err.nogame' = 'Grim Dawn не найден. Укажи -GamePath <папка игры> и повтори.'
        'err.nodocs' = 'Папка Grim Dawn в Документах не найдена: {0}. Запусти Grim Dawn один раз или укажи -Location game.'
        'err.notwritable' = 'Нет прав на запись в {0}. Укажи -Location documents.'
        'err.nowritable' = 'Нет прав на запись в {0}, и папки {1} нет. Запусти Grim Dawn один раз или укажи -GamePath <папка игры>.'
        'err.download' = 'Не удалось скачать {0}: {1}. Скачай файл с grimraynbow.com и укажи -FilePath <файл>.'
        'err.invalid' = 'Ответ не похож на файл Raynbow (размер {0}). Используй -FilePath с файлом с grimraynbow.com.'
        'err.header' = 'В файле нет шапки с путём установки. Нужен файл с grimraynbow.com.'
        'err.notraynow' = 'Это не файл Grim Raynbow (нет заголовка версии Raynbow). Нужен файл с grimraynbow.com.'
        'err.filepath' = 'Файл не найден: {0}. Укажи -FilePath с файлом, скачанным с grimraynbow.com.'
        'err.manifest' = 'Не удалось записать манифест установки: {0}. Проверь права на запись в папку настроек.'
        'err.verify' = 'Установленный файл не прошёл проверку: {0}. Установка отменена; повтори или укажи -FilePath со свежим файлом.'
        'rollback.fail' = 'Откат не удался: {0}. Манифест восстановления сохранён в {1}; запусти -Uninstall или верни файлы из его папки бэкапа.'
        failed = 'ОШИБКА: {0}'
    }
}

function Get-Msg([string]$Key) {
    $table = $script:Messages[$script:MessageLanguage]
    if ($table.ContainsKey($Key)) { return $table[$Key] }
    return $Key
}

function Write-Step([string]$Key, [object[]]$FormatArgs) {
    $text = Get-Msg $Key
    if ($null -ne $FormatArgs -and $FormatArgs.Count -gt 0) { $text = $text -f $FormatArgs }
    Write-Host "==> $text"
}

function Write-Warn([string]$Key, [object[]]$FormatArgs) {
    $text = Get-Msg $Key
    if ($null -ne $FormatArgs -and $FormatArgs.Count -gt 0) { $text = $text -f $FormatArgs }
    Write-Host "    !! $text" -ForegroundColor Yellow
}

function Get-Prop($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $null
}

function Test-UnderRoot([string]$Path, [string]$Root) {
    if (-not $Path -or -not $Root) { return $false }
    try {
        $fullPath = [IO.Path]::GetFullPath($Path)
        $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
        return $fullPath.StartsWith($fullRoot, [StringComparison]::OrdinalIgnoreCase)
    } catch {
        return $false
    }
}

function Test-UnderSettings([string]$Path, [string]$Root) {
    return (Test-UnderRoot $Path (Join-Path $Root 'settings'))
}

function Get-UserDataRoot {
    # Test-only override: tests/check.ps1 keeps fixtures away from the real Documents tree.
    if ($env:DSH_RAINBOW_DOCUMENTS_ROOT) { return $env:DSH_RAINBOW_DOCUMENTS_ROOT }
    return Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'My Games\Grim Dawn'
}

function Get-GameLanguage([string]$UserDataRoot) {
    $options = Join-Path $UserDataRoot 'Settings\options.txt'
    if (-not (Test-Path -LiteralPath $options)) { return $null }
    $line = Get-Content -LiteralPath $options -TotalCount 200 -ErrorAction SilentlyContinue |
        Where-Object { $_ -match '^\s*language\s*=\s*"?([^"]+)"?' } | Select-Object -First 1
    if (-not $line) { return $null }
    if ($line -notmatch '^\s*language\s*=\s*"?([^"]+)"?') { return $null }
    $value = $Matches[1].Trim().ToLowerInvariant()
    if ($script:SupportedLanguages -contains $value) { return $value }
    foreach ($key in $script:LanguageMap.Keys) {
        if ($value.Contains($key)) { return $script:LanguageMap[$key] }
    }
    return $null
}

function Get-OsLanguage {
    try {
        $code = (Get-UICulture).Name.Split('-')[0].ToLowerInvariant()
        if ($script:SupportedLanguages -contains $code) { return $code }
    } catch { }
    return 'en'
}

function Resolve-Language([string]$Explicit, [string]$UserDataRoot) {
    if ($Explicit -and $Explicit -ne 'auto') { return $Explicit }
    $fromGame = Get-GameLanguage $UserDataRoot
    if ($fromGame) { return $fromGame }
    return (Get-OsLanguage)
}

function Test-GameRoot([string]$Path) {
    if (-not $Path) { return $false }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    if (Test-Path -LiteralPath (Join-Path $Path 'Grim Dawn.exe')) { return $true }
    return (Test-Path -LiteralPath (Join-Path $Path 'database') -PathType Container)
}

function Get-RegistryValue([string]$Key, [string]$Name) {
    $item = Get-ItemProperty -Path $Key -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $null }
    $property = $item.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-SteamLibraries {
    $libraries = New-Object System.Collections.Generic.List[string]
    $steam = Get-RegistryValue 'HKCU:\Software\Valve\Steam' 'SteamPath'
    if (-not $steam) {
        $steam = Get-RegistryValue 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' 'InstallPath'
    }
    if (-not $steam) { return $libraries }
    $libraries.Add($steam)
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
        $raw = Get-Content -LiteralPath $vdf -Raw -ErrorAction SilentlyContinue
        if ($raw) {
            foreach ($match in [regex]::Matches($raw, '(?m)"path"\s+"([^"]+)"')) {
                $libraries.Add($match.Groups[1].Value.Replace('\\', '\'))
            }
        }
    }
    return $libraries
}

function Find-GameRoot {
    # Test-only override: limits discovery to this path so fixtures never pick up a real install.
    if ($env:DSH_RAINBOW_GAME_ROOT) {
        if (Test-GameRoot $env:DSH_RAINBOW_GAME_ROOT) {
            return (Resolve-Path -LiteralPath $env:DSH_RAINBOW_GAME_ROOT).Path
        }
        return $null
    }
    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($library in (Get-SteamLibraries)) {
        $candidates.Add((Join-Path $library 'steamapps\common\Grim Dawn'))
    }
    foreach ($key in @('HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games\1449651388', 'HKLM:\SOFTWARE\GOG.com\Games\1449651388')) {
        $path = Get-RegistryValue $key 'path'
        if ($path) { $candidates.Add($path) }
    }
    $candidates.Add((Join-Path $env:ProgramFiles 'GOG Galaxy\Games\Grim Dawn'))
    $candidates.Add('C:\GOG Games\Grim Dawn')
    foreach ($candidate in $candidates) {
        if (Test-GameRoot $candidate) { return (Resolve-Path -LiteralPath $candidate).Path }
    }
    return $null
}

function Resolve-GameRoot([string]$Explicit) {
    if ($Explicit) {
        if (-not (Test-GameRoot $Explicit)) { throw ((Get-Msg 'err.gamepath') -f $Explicit) }
        return (Resolve-Path -LiteralPath $Explicit).Path
    }
    return (Find-GameRoot)
}

function Get-GameVersion([string]$GameRoot, [string]$Explicit) {
    if ($Explicit -and $Explicit -ne 'auto') { return $Explicit }
    if (-not $GameRoot) { return 'foa' }
    if (Test-Path -LiteralPath (Join-Path $GameRoot 'gdx3') -PathType Container) { return 'foa' }
    if (Test-Path -LiteralPath (Join-Path $GameRoot 'gdx2') -PathType Container) { return 'fg' }
    if (Test-Path -LiteralPath (Join-Path $GameRoot 'gdx1') -PathType Container) { return 'aom' }
    return 'base'
}

function Test-WritableDirectory([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    $probe = Join-Path $Path ('.rainbow-write-test-' + [guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText($probe, 'probe')
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        return $true
    } catch {
        if (Test-Path -LiteralPath $probe) { Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue }
        return $false
    }
}

function Resolve-InstallRoot {
    param(
        [string]$GameRoot,
        [string]$UserDataRoot,
        [string]$Location,
        [bool]$DryRun
    )
    $gameFound = [bool]($GameRoot -and (Test-Path -LiteralPath $GameRoot -PathType Container))
    $documentsFound = Test-Path -LiteralPath $UserDataRoot -PathType Container
    if ($Location -eq 'game') {
        if (-not $gameFound) { throw (Get-Msg 'err.nogame') }
        if (-not $DryRun -and -not (Test-WritableDirectory $GameRoot)) {
            if ($documentsFound) { throw ((Get-Msg 'err.notwritable') -f $GameRoot) }
            throw ((Get-Msg 'err.nowritable') -f $GameRoot, $UserDataRoot)
        }
        return $GameRoot
    }
    if ($Location -eq 'documents') {
        if (-not $documentsFound) { throw ((Get-Msg 'err.nodocs') -f $UserDataRoot) }
        if (-not $gameFound) { Write-Warn 'warn.nogame' }
        return $UserDataRoot
    }
    if ($gameFound) {
        if ($DryRun) { return $GameRoot }
        if (Test-WritableDirectory $GameRoot) { return $GameRoot }
        if ($documentsFound) {
            Write-Warn 'warn.docs'
            return $UserDataRoot
        }
        throw ((Get-Msg 'err.nowritable') -f $GameRoot, $UserDataRoot)
    }
    if ($documentsFound) {
        Write-Warn 'warn.nogame'
        return $UserDataRoot
    }
    throw (Get-Msg 'err.nogame')
}

function Get-DownloadUrl([string]$Lang, [string]$PresetName, [string]$Version) {
    $presetId = $script:PresetIds[$PresetName] + $script:VersionSuffix[$Version]
    return "$script:SiteBase/$Lang/GD/Filter/Download?preset_id=$presetId"
}

function Save-FilterDownload([string]$Url) {
    $temp = Join-Path ([IO.Path]::GetTempPath()) ('grimraynbow-' + [guid]::NewGuid().ToString('N') + '.txt')
    try {
        Invoke-WebRequest -Uri $Url -OutFile $temp -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop
        $size = (Get-Item -LiteralPath $temp).Length
        if ($size -lt 50000) { throw ((Get-Msg 'err.invalid') -f $size) }
        return $temp
    } catch {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
        if ($_.Exception.Message -like '*valid Raynbow*' -or $_.Exception.Message -like '*файл Raynbow*') { throw }
        throw ((Get-Msg 'err.download') -f $Url, $_.Exception.Message)
    }
}

function Read-FilterInMemory([string]$Url) {
    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop
        if ($response.Content -is [byte[]]) {
            $text = [Text.Encoding]::UTF8.GetString($response.Content)
        } else {
            $text = [string]$response.Content
        }
        if ($text.Length -lt 50000) { throw ((Get-Msg 'err.invalid') -f $text.Length) }
        return $text
    } catch {
        if ($_.Exception.Message -like '*valid Raynbow*' -or $_.Exception.Message -like '*файл Raynbow*') { throw }
        throw ((Get-Msg 'err.download') -f $Url, $_.Exception.Message)
    }
}

function Get-HeaderText([string]$Path) {
    return ((Get-Content -LiteralPath $Path -TotalCount 40 -Encoding UTF8) -join "`n")
}

function Get-HeaderInfo([string]$Text) {
    $relative = $null
    $gameFileVersion = $null
    $raynowVersion = $null
    foreach ($line in ($Text -split "`r?`n")) {
        if (-not $relative -and $line -match '(?i)^#\s*\\Grim Dawn\\settings\\(?<rel>.+?)\s*$') {
            $relative = $Matches['rel']
        }
        if ($line -match 'Grim Dawn:\s*v?([0-9.]+)') { $gameFileVersion = $Matches[1] }
        if ($line -match 'Grim Raynbow:\s*v?([0-9.]+)') { $raynowVersion = $Matches[1] }
    }
    if (-not $relative) { throw (Get-Msg 'err.header') }
    if (-not $raynowVersion) { throw (Get-Msg 'err.notraynow') }
    $relative = $relative.Replace('/', '\').Replace('\\', '\').TrimStart('\')
    if ($relative -match '(^|[\\/])\.\.([\\/]|$)') { throw (Get-Msg 'err.header') }
    return [pscustomobject]@{
        Relative       = $relative
        GameFileVersion = $gameFileVersion
        RaynowVersion  = $raynowVersion
    }
}

function Get-ManifestPath([string]$Root) {
    return Join-Path $Root ('settings\' + $script:ManifestName)
}

function Read-Manifest([string]$Root) {
    $path = Get-ManifestPath $Root
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Write-TextAtomic([string]$Path, [string]$Text) {
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $temp = "$Path.tmp-" + [guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText($temp, $Text, (New-Object Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $Path) {
        try { [IO.File]::Replace($temp, $Path, $null) } catch { Move-Item -LiteralPath $temp -Destination $Path -Force }
    } else {
        Move-Item -LiteralPath $temp -Destination $Path -Force
    }
}

function Get-LegacyFiles([string]$Root, [string]$TargetPath, [string]$PreviousTarget) {
    $settings = Join-Path $Root 'settings'
    if (-not (Test-Path -LiteralPath $settings)) { return @() }
    $directories = New-Object System.Collections.Generic.List[string]
    $directories.Add($settings)
    foreach ($dir in (Get-ChildItem -LiteralPath $settings -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'text_*' })) {
        $directories.Add($dir.FullName)
        $aom = Join-Path $dir.FullName 'aom'
        if (Test-Path -LiteralPath $aom -PathType Container) { $directories.Add($aom) }
    }
    $found = New-Object System.Collections.Generic.List[string]
    foreach ($directory in ($directories | Select-Object -Unique)) {
        foreach ($name in $script:LegacyNames) {
            $file = Join-Path $directory $name
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
            $full = (Get-Item -LiteralPath $file).FullName
            if ($full -eq $TargetPath) { continue }
            if ($PreviousTarget -and $full -eq $PreviousTarget) { continue }
            $found.Add($full)
        }
    }
    return $found
}

function Test-Fault([string]$Point) {
    # Test-only seam: the harness sets DSH_RAINBOW_FAULT to exercise rollback paths.
    if (-not $env:DSH_RAINBOW_FAULT) { return }
    if (($env:DSH_RAINBOW_FAULT -split ',') -contains $Point) { throw "injected fault: $Point" }
}

function Invoke-Rollback {
    param(
        [string]$ManifestPath,
        [string]$Target,
        $Moves,
        [bool]$Published,
        [string]$PreviousManifestText
    )
    $errors = New-Object System.Collections.Generic.List[string]
    if ($Published -and (Test-Path -LiteralPath $Target)) {
        try {
            Test-Fault 'remove-published'
            Remove-Item -LiteralPath $Target -Force
        } catch {
            # The new file still occupies the target; restoring over it could destroy the backup.
            $errors.Add($_.Exception.Message)
            return ,$errors
        }
    }
    $count = 0
    if ($null -ne $Moves) { $count = [int]$Moves.Count }
    for ($index = $count - 1; $index -ge 0; $index--) {
        $move = $Moves[$index]
        $from = [string](Get-Prop $move 'from')
        $to = [string](Get-Prop $move 'to')
        if (-not $to -or -not (Test-Path -LiteralPath $to)) { continue }
        # A failed cross-volume move can leave the source in place; keep it and drop the copy.
        if (Test-Path -LiteralPath $from) {
            Remove-Item -LiteralPath $to -Force -ErrorAction SilentlyContinue
            continue
        }
        try {
            Test-Fault 'restore'
            $parent = Split-Path -Parent $from
            if ($parent -and -not (Test-Path -LiteralPath $parent)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            Move-Item -LiteralPath $to -Destination $from -Force
        } catch {
            $errors.Add($_.Exception.Message)
        }
    }
    if ($errors.Count -eq 0) {
        if ($PreviousManifestText) {
            try {
                Test-Fault 'restore-manifest'
                Write-TextAtomic $ManifestPath $PreviousManifestText
            } catch {
                $errors.Add($_.Exception.Message)
            }
        } elseif (Test-Path -LiteralPath $ManifestPath) {
            try { Remove-Item -LiteralPath $ManifestPath -Force } catch { $errors.Add($_.Exception.Message) }
        }
    }
    return ,$errors
}

function Invoke-Uninstall([string]$GameRoot, [string]$UserDataRoot, [bool]$DryRun) {
    $roots = @($UserDataRoot, $GameRoot) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } | Select-Object -Unique
    $found = $false
    foreach ($root in $roots) {
        $manifest = Read-Manifest $root
        if (-not $manifest) { continue }
        $found = $true
        $target = [string](Get-Prop $manifest 'target')
        if (-not $target) {
            $relative = [string](Get-Prop $manifest 'relative')
            if ($relative) { $target = Join-Path $root $relative }
        }
        if ($target -and -not (Test-UnderSettings $target $root)) { $target = $null }
        if ($target -and (Test-Path -LiteralPath $target)) {
            if ($DryRun) {
                Write-Step 'wouldremove' $target
            } elseif ([string](Get-Prop $manifest 'state') -eq 'installing') {
                # A crash-left target may be the only copy; park it in the backup instead of deleting it.
                $backup = Join-Path $root ('settings\.rainbow-backup\' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
                $destination = Join-Path $backup $target.Substring($root.Length).TrimStart('\')
                New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
                Move-Item -LiteralPath $target -Destination $destination
                Write-Step 'backupkept' $backup
            } else {
                Remove-Item -LiteralPath $target -Force
                Write-Step 'uninstalled' $target
            }
        }
        $backup = [string](Get-Prop $manifest 'backupDir')
        if ($backup -and (Test-Path -LiteralPath $backup)) { Write-Step 'backupkept' $backup }
        if (-not $DryRun) {
            $manifestPath = Get-ManifestPath $root
            if (Test-Path -LiteralPath $manifestPath) { Remove-Item -LiteralPath $manifestPath -Force }
        }
    }
    if (-not $found) { Write-Host (Get-Msg 'noinstall') }
    if ($DryRun) { Write-Step 'dry' }
}

function Invoke-Install {
    $userDataRoot = Get-UserDataRoot
    $resolvedLanguage = Resolve-Language $Language $userDataRoot
    $script:MessageLanguage = if ($resolvedLanguage -eq 'ru') { 'ru' } else { 'en' }
    $gameRoot = Resolve-GameRoot $GamePath
    $version = Get-GameVersion $gameRoot $GameVersion
    $url = Get-DownloadUrl $resolvedLanguage $Preset $version
    $gameExists = [bool]($gameRoot -and (Test-Path -LiteralPath $gameRoot -PathType Container))
    $docsExists = [bool](Test-Path -LiteralPath $userDataRoot -PathType Container)
    if ($Location -eq 'game' -and -not $gameExists) { throw (Get-Msg 'err.nogame') }
    if ($Location -eq 'documents' -and -not $docsExists) { throw ((Get-Msg 'err.nodocs') -f $userDataRoot) }
    if ($Location -eq 'auto' -and -not $gameExists -and -not $docsExists) { throw (Get-Msg 'err.nogame') }

    $tempFile = $null
    try {
        if ($FilePath) {
            if (-not (Test-Path -LiteralPath $FilePath)) { throw ((Get-Msg 'err.filepath') -f $FilePath) }
            $source = (Resolve-Path -LiteralPath $FilePath).Path
            $sourceSize = (Get-Item -LiteralPath $source).Length
            if ($sourceSize -lt 50000) { throw ((Get-Msg 'err.invalid') -f $sourceSize) }
            $header = Get-HeaderInfo (Get-HeaderText $source)
            $sourceLabel = $source
        } elseif ($DryRun) {
            $header = Get-HeaderInfo (Read-FilterInMemory $url)
            $source = $null
            $sourceLabel = $url
        } else {
            $tempFile = Save-FilterDownload $url
            $header = Get-HeaderInfo (Get-HeaderText $tempFile)
            $source = $tempFile
            $sourceLabel = $url
        }

        $root = Resolve-InstallRoot -GameRoot $gameRoot -UserDataRoot $userDataRoot -Location $Location -DryRun ([bool]$DryRun)
        $relative = 'settings\' + $header.Relative
        $target = Join-Path $root $relative
        $manifestPath = Get-ManifestPath $root
        $previousManifestText = $null
        if (Test-Path -LiteralPath $manifestPath) { $previousManifestText = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 }
        $previous = Read-Manifest $root
        $previousTarget = $null
        if ($previous) {
            $previousTarget = [string](Get-Prop $previous 'target')
            if (-not $previousTarget) {
                $previousRelative = [string](Get-Prop $previous 'relative')
                if ($previousRelative) { $previousTarget = Join-Path $root $previousRelative }
            }
            if (-not (Test-UnderSettings $previousTarget $root)) { $previousTarget = $null }
        }

        $otherRoot = $null
        if ($gameRoot -and $root -ne $gameRoot) {
            $otherRoot = $gameRoot
        } elseif ($userDataRoot -and $root -ne $userDataRoot) {
            $otherRoot = $userDataRoot
        }
        $otherManifest = $null
        $otherTarget = $null
        if ($otherRoot -and (Test-Path -LiteralPath $otherRoot -PathType Container)) {
            $otherManifest = Read-Manifest $otherRoot
            if ($otherManifest) {
                $otherTarget = [string](Get-Prop $otherManifest 'target')
                if (-not $otherTarget) {
                    $otherRelative = [string](Get-Prop $otherManifest 'relative')
                    if ($otherRelative) { $otherTarget = Join-Path $otherRoot $otherRelative }
                }
                if (-not (Test-UnderSettings $otherTarget $otherRoot)) { $otherTarget = $null }
            }
        }

        $moves = New-Object System.Collections.Generic.List[object]
        if ($previousTarget -and $previousTarget -ne $target -and (Test-Path -LiteralPath $previousTarget)) {
            $moves.Add([pscustomobject]@{ from = $previousTarget; relative = $previousTarget.Substring($root.Length).TrimStart('\') })
        }
        foreach ($legacy in (Get-LegacyFiles $root $target $previousTarget)) {
            $moves.Add([pscustomobject]@{ from = $legacy; relative = $legacy.Substring($root.Length).TrimStart('\') })
        }
        if ((Test-Path -LiteralPath $target) -and -not ($moves | Where-Object { $_.from -eq $target })) {
            $moves.Add([pscustomobject]@{ from = $target; relative = $target.Substring($root.Length).TrimStart('\') })
        }
        if ($otherTarget -and (Test-Path -LiteralPath $otherTarget) -and -not ($moves | Where-Object { $_.from -eq $otherTarget })) {
            $moves.Add([pscustomobject]@{ from = $otherTarget; relative = 'other\' + $otherTarget.Substring($otherRoot.Length).TrimStart('\') })
        }

        $stamp = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        $backupDir = $null
        if ($moves.Count -gt 0) { $backupDir = Join-Path $root ('settings\.rainbow-backup\' + $stamp) }
        foreach ($move in $moves) {
            $move | Add-Member -NotePropertyName to -NotePropertyValue $(if ($backupDir) { Join-Path $backupDir $move.relative } else { $null })
        }

        Write-Step 'game' $root, (Get-Msg ('version.' + $version))
        Write-Step 'lang' $resolvedLanguage, $Preset
        Write-Step 'source' $sourceLabel
        Write-Step 'root' $root
        Write-Step 'target' $target
        if ($backupDir) { Write-Step 'backup' $backupDir }

        if ($DryRun) {
            Write-Step 'dry'
            return
        }

        $manifest = [ordered]@{
            state            = 'installing'
            root             = $root
            relative         = $relative
            target           = $target
            source           = $sourceLabel
            language         = $resolvedLanguage
            preset           = $Preset
            gameVersion      = $version
            gameFileVersion  = $header.GameFileVersion
            raynbowVersion   = $header.RaynowVersion
            backupDir        = $backupDir
            moved            = @($moves | ForEach-Object { [ordered]@{ from = $_.from; to = $_.to } })
            time             = (Get-Date).ToString('o')
        }
        $published = $false
        try {
            try {
                Write-TextAtomic $manifestPath (($manifest | ConvertTo-Json -Depth 8) + "`n")
            } catch {
                throw ((Get-Msg 'err.manifest') -f $_.Exception.Message)
            }
            if ($backupDir) {
                foreach ($move in $moves) {
                    $destinationParent = Split-Path -Parent $move.to
                    New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
                    Move-Item -LiteralPath $move.from -Destination $move.to
                }
            }
            Test-Fault 'legacy'
            $targetParent = Split-Path -Parent $target
            if (-not (Test-Path -LiteralPath $targetParent)) { New-Item -ItemType Directory -Path $targetParent -Force | Out-Null }
            # Stage next to the target, then rename, so a failed copy never leaves a partial filter.
            $staging = Join-Path $targetParent ('.rainbow-filter-' + [guid]::NewGuid().ToString('N') + '.tmp')
            try {
                Copy-Item -LiteralPath $source -Destination $staging -Force
                Move-Item -LiteralPath $staging -Destination $target -Force
                $published = $true
            } finally {
                if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Force -ErrorAction SilentlyContinue }
            }
            Test-Fault 'published'
            Test-Fault 'verify'
            $size = (Get-Item -LiteralPath $target).Length
            if ($size -lt 50000) { throw ((Get-Msg 'err.verify') -f "size $size") }
            $head = Get-HeaderText $target
            if ($head -notmatch 'Grim Raynbow:') { throw ((Get-Msg 'err.verify') -f 'missing version header') }
            $manifest.state = 'installed'
            $manifest.time = (Get-Date).ToString('o')
            try {
                Write-TextAtomic $manifestPath (($manifest | ConvertTo-Json -Depth 8) + "`n")
            } catch {
                throw ((Get-Msg 'err.manifest') -f $_.Exception.Message)
            }
        } catch {
            $failure = $_.Exception.Message
            $rollbackErrors = Invoke-Rollback -ManifestPath $manifestPath -Target $target -Moves $moves -Published $published -PreviousManifestText $previousManifestText
            if ($rollbackErrors.Count -gt 0) {
                throw ((Get-Msg 'rollback.fail') -f $failure, $manifestPath)
            }
            throw $failure
        }

        if ($otherManifest) {
            $otherManifestPath = Get-ManifestPath $otherRoot
            try {
                if (Test-Path -LiteralPath $otherManifestPath) { Remove-Item -LiteralPath $otherManifestPath -Force }
            } catch {
                Write-Warn 'warn.other' $_.Exception.Message
            }
        }

        Write-Step 'installed' $target
        Write-Step 'restart'
    } finally {
        if ($tempFile -and (Test-Path -LiteralPath $tempFile)) { Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue }
    }
}

function Invoke-Main {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
    $userDataRoot = Get-UserDataRoot
    if ($Uninstall) {
        $script:MessageLanguage = if ((Resolve-Language $Language $userDataRoot) -eq 'ru') { 'ru' } else { 'en' }
        $gameRoot = Resolve-GameRoot $GamePath
        Invoke-Uninstall $gameRoot $userDataRoot ([bool]$DryRun)
        return
    }
    Invoke-Install
}

if ($MyInvocation.InvocationName -eq '.') {
    # Dot-sourced by tests: expose the functions without running an install or leaking preferences.
    Set-StrictMode -Version Latest
} else {
    & {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'
        try {
            Invoke-Main
        } catch {
            Write-Host ''
            Write-Host ((Get-Msg 'failed') -f $_.Exception.Message) -ForegroundColor Red
            throw
        }
    }
}
