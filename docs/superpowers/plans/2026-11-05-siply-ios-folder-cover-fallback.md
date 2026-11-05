# Обложка папки вместо ноты — план

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** трек без своей картинки получает обложку папки (`cover.jpg` / `cover.png` / `folder.jpg`) — в строках, мини-плеере, плеере, на экране блокировки, в живом фоне.

**Architecture:** правило живёт в `LibraryScanner`: `coverFile(in:)` + фолбэк в `loadTrack` и в заглушках `tracks(in:)`; `FileTrackLoader` даёт обложку своим заглушкам. UI не меняется — всё читает `track.artwork`.

**Tech Stack:** Swift, Foundation, AVFoundation, XCTest. XcodeGen (`*.xcodeproj` в .gitignore; новых файлов нет).

**Spec:** `docs/superpowers/specs/2026-11-05-siply-ios-folder-cover-fallback-design.md`

## Global Constraints

- Имена файлов обложки и порядок: `cover.jpg`, `cover.png`, `folder.jpg`. Не скачанный из iCloud файл (`DownloadState.of(file) != .local`) пропускается.
- Чтение: `Data(contentsOf: file, options: .mappedIfSafe)`.
- Своя картинка трека важнее обложки папки.
- Поиск (`SearchView`) не трогать.
- Без новых зависимостей. Комментарии в коде — по-русски, как в проекте.
- Тесты: `xcodebuild test -scheme Siply -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath <scratch>/dd-sim`; на диске только `TempDir`.
- Коммиты без `Co-Authored-By`.

## Review Focus

- Папка с картинками у части треков: трек со своей картинкой не должен получить `cover.jpg`.
- `cover.jpg` в iCloud не скачан: фолбэка нет, главный поток не ждёт загрузку.
- `tagsOnDemand` (SMB): заглушки получают обложку, но аудиофайлы по-прежнему не читаются.
- Шапка папки (`folderArtwork`) показывает то же, что раньше, в обычной папке с `cover.jpg`.
- Нет `cover.*` — `artwork == nil`, нота как раньше.

---

### Task 1: фолбэк на обложку папки

**Files:**
- Modify: `Siply/Library/LibraryScanner.swift` (`loadTrack`, `tracks(in:)`, `folderArtwork`, новый `coverFile(in:)`)
- Modify: `Siply/Player/PlaybackState.swift` (`FileTrackLoader.track(at:)` — заглушки `.onDemand` и `.remote`)
- Test: `SiplyTests/LibraryScannerTests.swift`, `SiplyTests/FileTrackLoaderTests.swift`
- Modify: `docs/checklist.md` (пункт 16)

**Interfaces:**
- Produces: `static func coverFile(in folder: URL) -> Data?` в `LibraryScanner`.
- `loadTrack(_ url: URL) async -> Track` — сигнатура прежняя; при `artwork == nil` после тегов — `coverFile(in: url.deletingLastPathComponent())`.
- `folderArtwork(for:tracks:)` — сигнатура и смысл прежние, цикл по именам заменяется вызовом `coverFile(in:)`.

- [ ] **Step 1: тесты (падают)**

В `LibraryScannerTests`:

```swift
func testLoadTrackWithoutArtUsesCoverFile() async throws {
    let tmp = TempDir()
    let wav = tmp.url.appendingPathComponent("01 A.wav")
    try AudioFixtures.writeWav(to: wav)
    tmp.file("cover.jpg", Data([1, 2, 3]))
    let t = await LibraryScanner.loadTrack(wav)
    XCTAssertEqual(t.artwork, Data([1, 2, 3]))
}

func testLoadTrackWithoutArtAndCoverIsNil() async throws {
    let tmp = TempDir()
    let wav = tmp.url.appendingPathComponent("01 A.wav")
    try AudioFixtures.writeWav(to: wav)
    let t = await LibraryScanner.loadTrack(wav)
    XCTAssertNil(t.artwork)
}

func testCoverFileOrder() {
    let tmp = TempDir()
    tmp.file("folder.jpg", Data([9]))
    tmp.file("cover.png", Data([2]))
    XCTAssertEqual(LibraryScanner.coverFile(in: tmp.url), Data([2]))
    XCTAssertNil(LibraryScanner.coverFile(in: TempDir().url))
}

func testOnDemandPlaceholdersGetCover() async throws {
    let tmp = TempDir()
    try AudioFixtures.writeWav(to: tmp.url.appendingPathComponent("01 A.wav"))
    try AudioFixtures.writeWav(to: tmp.url.appendingPathComponent("02 B.wav"))
    tmp.file("cover.jpg", Data([7, 7]))
    let tracks = await LibraryScanner.tracks(in: tmp.url, tagsOnDemand: true)
    XCTAssertEqual(tracks.count, 2)
    XCTAssertTrue(tracks.allSatisfy { $0.artwork == Data([7, 7]) && $0.duration == 0 })
}
```

В `FileTrackLoaderTests`:

```swift
func testOnDemandPlaceholderGetsCover() async {
    let app = TempDir(), other = TempDir()
    let file = other.file("03 Глава.mp3", Data("garbage".utf8))
    other.file("cover.jpg", Data([5]))
    let t = await FileTrackLoader(appFolder: app.url).track(at: file)
    XCTAssertEqual(t?.download, .onDemand)
    XCTAssertEqual(t?.artwork, Data([5]))
}
```

Существующие `testFolderArtworkPrefersTrackArtworkThenCoverFile` и `testTagsOnDemandSkipsMetadata` (там `cover.jpg` нет → `artwork == nil`) не менять — должны остаться зелёными.

- [ ] **Step 2: прогнать — новые падают** (`coverFile` не существует → ошибка компиляции, это ожидаемо).

- [ ] **Step 3: реализация**

`coverFile(in:)` — тело нынешнего цикла из `folderArtwork` с `.mappedIfSafe`; `folderArtwork` зовёт его. В `tracks(in:)` обложку читать один раз до `withTaskGroup` и присваивать заглушкам `.remote` и `.onDemand`. В `FileTrackLoader` обеим заглушкам — `LibraryScanner.coverFile(in: url.deletingLastPathComponent())`.

- [ ] **Step 4: весь набор тестов зелёный** (`** TEST SUCCEEDED **`, 0 failures).

- [ ] **Step 5: чеклист** — в `docs/checklist.md` пункт 16 дословно:

`16. Папка с cover.jpg и треками без картинок → в строках, мини-плеере, плеере и на экране блокировки обложка папки, фон плеера в её цветах; трек со своей картинкой — своя; папка без cover.jpg — ноты.`

- [ ] **Step 6: коммит**

```bash
git add Siply/Library/LibraryScanner.swift Siply/Player/PlaybackState.swift SiplyTests/LibraryScannerTests.swift SiplyTests/FileTrackLoaderTests.swift docs/checklist.md
git commit -m "feat: обложка папки для треков без своей картинки"
```
