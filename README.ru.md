# Grim Dawn Rainbow Filter — установка одной командой

[English](README.md) | **Русский**

[![validate](https://github.com/sergey-akhalkov/Grim-Dawn-Rainbow-Filter-Installer/actions/workflows/validate.yml/badge.svg)](https://github.com/sergey-akhalkov/Grim-Dawn-Rainbow-Filter-Installer/actions/workflows/validate.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-blue)

Ставит актуальный [Grim Raynbow](https://grimraynbow.com) (Rainbow Filter) в Grim Dawn одной
командой. Это клиентский `.txt`-файл: без папки mods, без правки данных игры и сохранений. Удаление
файла возвращает стандартные цвета.

## Установка

```powershell
irm https://raw.githubusercontent.com/sergey-akhalkov/Grim-Dawn-Rainbow-Filter-Installer/main/install.ps1 | iex
```

Игру можно не закрывать; после установки перезапусти Grim Dawn, чтобы он прочитал новый файл.

Что делает установщик:

- берёт язык **из самой игры** (`Documents\My Games\Grim Dawn\Settings\options.txt`); английский —
  только если ни игра, ни Windows не дали распознаваемого языка;
- определяет набор DLC по папкам `gdx1`/`gdx2`/`gdx3` и качает файл под эту версию;
- читает путь установки из шапки скачанного файла;
- ставит в папку игры, а если она недоступна для записи — в Документы;
- убирает известные старые файлы Rainbow в `settings\.rainbow-backup\<дата>`;
- пишет манифест, чтобы `-Uninstall` удалил ровно то, что было установлено.

Повторный запуск той же команды обновляет файл после обновления игры или Raynbow.

## Параметры

Скачай скрипт один раз, чтобы использовать флаги:

```powershell
Invoke-WebRequest https://raw.githubusercontent.com/sergey-akhalkov/Grim-Dawn-Rainbow-Filter-Installer/main/install.ps1 -OutFile install.ps1
.\install.ps1 -DryRun
```

| Параметр | Значения | По умолчанию |
| --- | --- | --- |
| `-Language` | `auto en ru de fr es it cs pl ja ko pt vi zh` | язык игры, затем Windows, затем `en` |
| `-Preset` | `full`, `basic`, `diablo` | `full` |
| `-GameVersion` | `auto foa fg aom base` | по папке игры |
| `-Location` | `auto`, `game`, `documents` | `auto` |
| `-GamePath` | папка игры | автопоиск (Steam/GOG) |
| `-FilePath` | сохранённый `.txt` Raynbow | скачать с grimraynbow.com |
| `-DryRun` | переключатель | показать план, ничего не менять |
| `-Uninstall` | переключатель | удалить установленный файл, бэкапы оставить |

Примеры:

```powershell
.\install.ps1 -Language en                 # играешь в Grim Dawn на английском
.\install.ps1 -Preset basic                # Basic Highlighting вместо Full Rainbow
.\install.ps1 -Location documents          # принудительно поставить в Документы
.\install.ps1 -Uninstall                   # удалить установленный файл
```

## Если цвета не появились

**После перезапуска цветов нет.** Файл установлен, но игра не читает это место. Попробуй другой
корень: `.\install.ps1 -Location documents` (или `-Location game`). На Windows 11 иногда работает
только один из двух.

**Цветов нет, место правильное.** Фильтр привязан к языку: файл должен совпадать с языком,
выбранным в Grim Dawn. Установщик берёт его из настроек игры; если язык менялся после установки —
запусти установщик снова. Можно указать явно: `-Language en`.

**«Tag not found» или сломанные названия.** Игра обновилась. Запусти установщик снова — он скачает
файл под текущую версию.

**Скрипт не находит игру.** Укажи папку с `Grim Dawn.exe`:
`-GamePath "D:\SteamLibrary\steamapps\common\Grim Dawn"`.

**Нет интернета или сайт недоступен.** Скачай файл с [grimraynbow.com](https://grimraynbow.com) в
браузере и запусти `.\install.ps1 -FilePath .\tagsgdx1_achievements.txt`.

**PowerShell не даёт запустить сохранённый скрипт.** Открой PowerShell 7 (`pwsh`) или запусти
`powershell -ExecutionPolicy Bypass -File .\install.ps1`.

## Удаление

```powershell
.\install.ps1 -Uninstall
```

Удаляет только файл, записанный установщиком. Бэкапы остаются в
`<папка игры или Документы>\settings\.rainbow-backup\`; удали эту папку, если старые файлы больше не
нужны.

## Ручная установка

Можно обойтись без скрипта: открой [grimraynbow.com](https://grimraynbow.com), выбери язык, пресет и
версию игры, скачай сгенерированный файл и положи его по пути из шапки файла (например,
`settings\text_ru\aom\tagsgdx1_achievements.txt`) в папку игры или в `Documents\My Games\Grim Dawn`.
После этого перезапусти Grim Dawn.

## Как это работает

Установщик скачивает один сгенерированный файл с grimraynbow.com. В шапке файла уже указан точный
путь (`settings\text_ru\aom\...` или `settings\text_en\...`) для выбранных языка и версии игры.
Установщик кладёт файл в папку игры или в Документы — туда, откуда игра его читает, — и ничего
больше не трогает.

Требования: Windows, PowerShell 5.1 или новее, интернет для скачивания. Для установки в Документы
права администратора не нужны.

## Благодарности

Rainbow Filter / [Grim Raynbow](https://grimraynbow.com) — **WareBare** и сообщество в
[теме на форуме Grim Dawn](https://forums.crateentertainment.com/t/tool-grim-raynbow-aka-rainbow-filter/42765).
Установщик неофициальный и не связан с Crate Entertainment или автором фильтра.

## Лицензия

[MIT](LICENSE), copyright (c) 2026 Sergey Akhalkov. Лицензия покрывает установщик, а не файлы
Rainbow Filter: они скачиваются с сайта автора и остаются его работой.
