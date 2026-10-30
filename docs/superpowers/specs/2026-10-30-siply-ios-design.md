# Siply для iPhone

## Зачем

Тот же Siply, что на Маке: папки с музыкой — это и есть библиотека, без импорта и медиатеки. На iPhone музыка лежит в iCloud Drive, на флешке, в облачных провайдерах Files или в папке самого приложения; Siply показывает эти папки и играет их.

Пользователь — тот же, что у macOS-версии: коллекция файлами (FLAC, MP3, старые ID3 в Windows-1251), раздражение от Apple Music с импортом.

## Решено с пользователем

- Отдельный репозиторий `~/projects/siply-ios` рядом с `siply`. Общий код (`PlayerModel`, `Track`, `FolderNode`, `LibraryScanner`, `FileOpener`, `AudioEngine`, тесты) **копируется**, не выносится в пакет. Две копии живут независимо.
- Два вида источников: своя папка приложения («На iPhone / Siply», видна в Files и в Finder на Маке) и любые папки через системный picker — iCloud Drive, USB-флешка, SMB, облачные File Provider'ы.
- Первый экран — список источников. Каждый помнится bookmark'ом, пока его не удалят.
- Нескачанные файлы и папки (iCloud и другие провайдеры) показываются серыми. Тап по треку — скачивание, трек белеет и играет. Тап по папке — скачивается её содержимое.
- Структура экрана — вариант B из макетов: `TabView` с табами «Папки» и «Поиск», мини-плеер над таб-баром через `tabViewBottomAccessory` (iOS 26). Макет: `siply/.superpowers/brainstorm/16301-1793352306/content/structure.html`.
- Поиск — по всем источникам, по именам файлов и папок. Без тегов.
- На bookmark-источниках вне iCloud (SMB, Яндекс.Диск и другие File Provider'ы) теги и обложки **не читаем при открытии папки** — чтение метаданных там равно скачиванию файла целиком. Показываем имена файлов; теги и обложка появляются после того, как трек скачан для проигрывания. В своей папке и на iCloud (где `.local` означает «файл на диске») — теги как на Маке.
- Только iPhone. iPad — не в v1.
- Платный Apple Developer аккаунт есть: цель — TestFlight, затем App Store.

## Цели

- Открыл папку — слушаешь. Ноль импорта, ноль базы.
- Ощущение Apple Music: шапка альбома с Play/Shuffle, список треков, мини-плеер над табами, Liquid Glass.
- Фоновое воспроизведение, локскрин, Control Center, наушники и AirPlay — как у любого нормального плеера.
- Теги и обложки из файлов, починка кириллицы 1251 — как на Маке.

## Не делаем

- Плейлисты, очередь с ручным порядком, «следующий трек по выбору».
- Поиск по тегам, фоновую индексацию.
- Выбор устройства вывода per-app — iOS не позволяет; есть только системный `AVRoutePickerView`.
- iPad-раскладку, Mac Catalyst, виджеты, CarPlay, Shortcuts.
- Редактирование тегов, удаление и перемещение файлов.
- Эквалайзер, кроссфейд, gapless.

## Анти-цели

- Приложение, которое «импортирует» или копирует музыку куда-то к себе. Своя папка — просто ещё одна папка в Files, пользователь кладёт туда файлы сам.
- Звук, который умирает при блокировке экрана или смене трека в фоне.
- Серые треки, которые нельзя оживить тапом.

## Ограничения

- iOS 26.1+ (`tabViewBottomAccessory(isEnabled:)` появился в 26.1, `glassEffect`). Xcode 27, Swift 5.x, SwiftUI, AVFoundation, MediaPlayer. Ноль сторонних зависимостей, как на Маке.
- XcodeGen (`project.yml`), как в macOS-репо. Bundle id `info.pisarev.siply-ios`, `DEVELOPMENT_TEAM: 2C2N587UW8` — команда платного аккаунта (у неё Developer ID, которым подписан macOS-релиз). *Решение моё.*
- Объём этого плана: сборка, которая ставится на iPhone пользователя через Xcode, тесты и чеклист. Archive → App Store Connect → TestFlight — следующий шаг, не здесь. *Решение моё.*
- Репо: GitHub `art-ps/siply-ios`, как у macOS-версии. Pull request'ы не создаём; чеклист ручной проверки — файл `docs/checklist.md`. *Решение моё.*
- Форматы — что играет `AVAudioPlayer` на iOS: MP3, AAC/M4A/ALAC, FLAC, WAV, AIFF, CAF. Тот же `LibraryScanner.audioExtensions`.
- Новый репо → `git config --local user.name "Artem Pisarev"` / `user.email "artem@pisarev.in"` до первого коммита.

## Как устроено

### Источники

`Source` — `{ id: UUID, name: String, kind: .appFolder | .bookmark(Data) }`. Список хранится в `UserDefaults` (JSON). `SourceStore` (`@Observable`) — добавить, удалить, восстановить, отдать URL.

- `.appFolder` — `Documents` приложения. В `Info.plist`: `UIFileSharingEnabled = YES`, `LSSupportsOpeningDocumentsInPlace = YES`. Всегда присутствует, первая строка, не удаляется. Имя — «Siply».
- `.bookmark` — результат `.fileImporter(allowedContentTypes: [.folder])`. При добавлении: `startAccessingSecurityScopedResource()`, затем `url.bookmarkData()` (без `.withSecurityScope` — его нет на iOS). При восстановлении: `URL(resolvingBookmarkData:bookmarkDataIsStale:)`, снова `startAccessing…`, доступ держится всё время жизни приложения — дочерние URL работают, пока открыт родитель. Stale bookmark → пересохранить. Не резолвится или папки нет (флешка вытащена) → источник в списке серый, тап ничего не делает, подпись «Не подключена».
- Имя источника — `lastPathComponent` папки, для флешки — имя тома из `volumeNameKey`, если есть. *Решение моё.*

### Папка

Экран папки = `FolderNode` + `LibraryScanner.tracks(in:)` из macOS-кода. Шапка (обложка, имя, «N треков · M мин», Play, Shuffle), секция «Папки» (подпапки), секция «Треки». Play играет только треки этой папки, как на Маке. Навигация — `NavigationStack` внутри таба «Папки»: Источники → Папка → Подпапка → …

### Нескачанное

`DownloadState` для URL: `.local | .remote | .downloading`.

- iCloud: `URLResourceValues.ubiquitousItemDownloadingStatus` (`.current`/`.downloaded` → local, `.notDownloaded` → remote). Скачивание — `FileManager.startDownloadingUbiquitousItem(at:)`, прогресс и завершение — `NSMetadataQuery` на этот URL или поллинг статуса раз в 0.5 с. *Поллинг — решение моё, проще; `NSMetadataQuery` — если будет дёргаться.*
- Другие File Provider'ы (SMB, Яндекс.Диск и т.п.): `ubiquitousItemDownloadingStatus` отсутствует, заранее «скачан/нет» не узнать. Источник помечается `tagsOnDemand` (bookmark-источник, у которого папка не `isUbiquitousItem`): все треки показываются по имени файла, без тегов и обложек, белые. При play — чтение через `NSFileCoordinator.coordinate(readingItemAt:)` в фоне дотягивает файл, строка на это время `.downloading`; после — теги и обложка читаются и строка перерисовывается. Если провайдер не отдал файл — ошибка, трек остаётся без тегов, короткий тост.
- Папка серая, если среди её прямых аудиофайлов есть `.remote`. Тап по серой папке — `startDownloadingUbiquitousItem` на каждый такой файл, папка открывается сразу, треки белеют по мере скачивания.
- Очередь: пока играет трек, следующий в очереди, если он `.remote`, скачивается заранее (только один, не вся папка) — иначе iOS усыпит приложение между треками, когда звука нет, и скачивание оборвётся. `PlayerModel.next()` на ещё не скачанный трек → `beginBackgroundTask`, скачать, играть; мини-плеер показывает индикатор. Нескачанный трек не пропускается. *Префетч одного трека — решение моё.*
- Теги и обложки у `.remote` треков не читаем — показываем имя файла без расширения, обложку-заглушку. После скачивания строка перечитывается. `LibraryScanner.tracks(in:)` получает ветку для `.remote`: сейчас `isPlayable` выкинул бы нескачанный файл из списка совсем.

### Плеер

`PlayerModel` и `AVAudioPlayerEngine` копируются; из протокола `AudioEngine` уходит `outputDeviceUID`, из `OutputDevice.swift` — всё (CoreAudio на iOS нет). Добавляется:

- `AVAudioSession.sharedInstance().setCategory(.playback)` при старте, `setActive(true)` перед первым `play()`.
- `Info.plist`: `UIBackgroundModes = [audio]`.
- `AVAudioSession.routeChangeNotification` с `.oldDeviceUnavailable` → пауза. `interruptionNotification` → пауза, после `.shouldResume` — продолжить.
- `NowPlaying` копируется, `NSImage` → `UIImage`.

### Мини-плеер и «Сейчас играет»

`tabViewBottomAccessory`: обложка, название, исполнитель, Play/Pause, Next. В `.inline`-размещении (таб-бар свёрнут при скролле) — только обложка, название, Play/Pause. `.tabBarMinimizeBehavior(.onScrollDown)`. Нет текущего трека → accessory выключен (`isEnabled: false`, iOS 26.1+), пустой полоски быть не должно.

Тап по мини-плееру → `.sheet` на весь экран: большая обложка, название/исполнитель/альбом, прогресс со скраббингом, ◀︎◀︎ ▶︎/⏸ ▶︎▶︎, кнопка `AVRoutePickerView` (AirPlay/Bluetooth). Громкость — кнопками телефона; слайдера нет. *Решение моё.*

### Поиск

Таб «Поиск»: поле сверху, результаты сгруппированы по источникам. Дерево путей каждого доступного источника обходится **один раз за сессию** при первом поиске (`FileManager.enumerator` с `.skipsHiddenFiles`, только имена и флаг «папка», без тегов) и держится в памяти; pull-to-refresh на экране поиска или перезапуск сбрасывают. Это не фоновый индекс: обход только по запросу, на диск не пишется. *Решение моё: по SMB/iCloud обход на каждую букву — десятки секунд.* Совпадение — подстрока без регистра (`localizedCaseInsensitiveContains`) в имени файла (без расширения) или имени папки. Папки в результатах — строки с `›`, ведут на экран папки. Треки — играют одиночно (очередь = результаты поиска в этом источнике). *Очередь из результатов — решение моё.* Поиск запускается с задержкой 300 мс после ввода, результаты ограничены 200 строками. Недоступные источники (флешка не подключена) пропускаются.

### Открытие файла из Files / «Поделиться»

`CFBundleDocumentTypes` те же, что на Маке, + `LSSupportsOpeningDocumentsInPlace`. `.onOpenURL` → если файл лежит внутри известного источника — как на Маке: папка открывается, файл играет, остальная папка следом (`FileOpener`). Если нет — играет только этот файл (на iOS доступа к соседям нет), экран не меняется. *Решение моё.*

### Что переносится без правок

`Track`, `FolderNode`, `LibraryScanner.repairTag`, `AudioEngine`-протокол, `FakeAudioEngine`, `TempDir`, `AudioFixtures` и их тесты.

С правками: `PlayerModel` (убрать `availableOutputs`/`applyOutput`, добавить `Downloader` с инъекцией для теста №5), `LibraryScanner.tracks(in:)` (ветка `.remote` и `tagsOnDemand`), `FileOpener` (завязан на `Library` — переписать под `SourceStore`, тесты тоже), `NowPlaying` (`NSImage` → `UIImage`, `playbackState` убрать — macOS-only). `Library` (один корень) не переносится — его место занимает `SourceStore`.

## Критерии приёмки (тесты)

Unit (`xcodebuild test -scheme Siply -destination 'platform=iOS Simulator,name=<любой iPhone из xcrun simctl list>'`):

1. Скопированные тесты `TrackTests`, `FolderNodeTests`, `LibraryScannerTests`, `TagTextTests`, `PlayerModelTests`, `FileOpenerTests` (переписан под `SourceStore`), `AVAudioPlayerEngineTests` зелёные на симуляторе.
2. `SourceStore`: `.appFolder` всегда первый и единственный; добавление bookmark-источника сохраняется в `UserDefaults` и восстанавливается после пересоздания store; удаление убирает из списка и из defaults; битый bookmark → источник `unavailable`, не падение.
3. `DownloadState(status:)` принимает значение `URLUbiquitousItemDownloadingStatus?` (на симуляторе iCloud не подделать): `.notDownloaded` → `.remote`; `.current`/`.downloaded` → `.local`; `nil` → `.local`.
4. Папка с хотя бы одним `.remote` треком → `FolderRow.isDimmed == true`; без них → `false`.
5. `PlayerModel` с фейковым `Downloader`: при `play` трека N, если N+1 `.remote`, вызван `download(N+1)`; `next()` на ещё не скачанный трек не вызывает `engine.load` до завершения; после завершения — `load` и `play`.
6. `LibraryScanner.tracks(in:)` для источника `tagsOnDemand` отдаёт треки с `title == имя файла без расширения`, `artwork == nil`, не открывая `AVURLAsset` (проверка через счётчик/фейк).
7. Поиск: «кино» находит папку `Кино/` и файл `Кино 2.mp3`; `Курю.mp3` внутри `Кино/` и `01.mp3` с тегом «Кино» — не находит (файл только по своему имени, папка — отдельный хит); регистр не важен; `.hidden`-папки пропущены; недоступный источник пропущен без ошибки; второй запрос не вызывает повторный обход.
8. `.onOpenURL` с файлом внутри источника → очередь = треки папки, старт с него; с файлом вне источников → очередь из одного трека.

Руками на устройстве (`docs/checklist.md`):

9. Заблокировал экран — играет; локскрин показывает обложку и кнопки; AirPods вытащил — пауза.
10. Папка iCloud с нескачанными треками: серые с ☁︎, тап — скачал и заиграл; следующий серый в очереди докачался сам.
11. Флешка вытащена → источник серый «Не подключена»; вставил → снова рабочий без перезапуска.
12. Finder на Маке → iPhone → Files → Siply: скопированная папка появляется в источнике «Siply» после pull-to-refresh или повторного входа.
13. Мини-плеер над табами, сворачивается при скролле, без пустой полоски когда ничего не играет.

## На усмотрение исполнителя

- Структура папок проекта (`Siply/Shared`, `Siply/iOS` или плоско).
- Кэш обложек в списке (на Маке — `NSImage(data:)` на каждый рендер; на iPhone список длинный — скорее всего нужен кэш по URL).
- Pull-to-refresh vs автоматический rescan при возврате на экран.
- Как именно слушать завершение скачивания iCloud (поллинг или `NSMetadataQuery`).
- Иконка: та же, что на Маке, подогнанная под iOS-формат.
