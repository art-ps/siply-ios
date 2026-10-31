# Живой фон плеера — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Фон полноэкранного плеера — mesh-градиент из цветов обложки, медленно дрейфует и пульсирует по громкости.

**Architecture:** Чистая функция `ArtworkPalette` даёт 9 цветов; `AudioEngine` отдаёт громкость `level`; вид `PlayerBackground` рисует `MeshGradient` в `TimelineView` и подставляется как `presentationBackground` в `NowPlayingSheet`, содержимое листа — в тёмной схеме.

**Tech Stack:** SwiftUI (`MeshGradient`, `TimelineView`), CoreGraphics (даунсэмпл), AVFoundation (`AVAudioPlayer` metering), XCTest.

**Spec:** `docs/superpowers/specs/2026-10-31-siply-ios-player-background-design.md`

## Global Constraints

- iOS 26.1+, ноль сторонних зависимостей, XcodeGen (`project.yml`; новые файлы в `Siply/` и `SiplyTests/` подхватываются автоматически, после добавления файлов — `xcodegen generate`).
- Без Vision и CoreImage.
- Тесты: `xcodebuild test -scheme Siply -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath <scratch>/dd-sim 2>&1 | grep -E 'Executed|error:|TEST'` — ожидаем `** TEST SUCCEEDED **`.
- Строки интерфейса — по-русски. Коммиты — по-русски, без Co-Authored-By.
- Трогаем только: `Siply/UI/NowPlayingSheet.swift`, `Siply/Player/AudioEngine.swift`, `Siply/Player/PlayerModel.swift`, `SiplyTests/FakeAudioEngine.swift`, новые файлы ниже, `docs/checklist.md`. Мини-плеер, списки, поиск — нет.

## Review Focus

1. Обложка 1×1 или меньше 3×3 — палитра всё равно 9 цветов, без краша (тест в Task 1).
2. `level` у движка без загруженного трека — `0`, не `-160` и не NaN (тест в Task 2).
3. «Уменьшение движения» — градиент стоит, `TimelineView` на паузе, пульс не применяется (ручная проверка в Task 4).
4. Трек без обложки после трека с обложкой — палитра сбрасывается на акцентную, не остаётся старой (тест в Task 1: `nil` → акцент; проверка `.task(id:)` в Task 4).
5. Светлая тема системы — текст плеера белый на тёмном градиенте (ручная проверка в Task 4).

---

### Task 1: ArtworkPalette

**Files:**
- Create: `Siply/UI/ArtworkPalette.swift`
- Test: `SiplyTests/ArtworkPaletteTests.swift`

**Interfaces:**
- Produces: `enum ArtworkPalette { static func colors(from data: Data?) -> [Color] }` — ровно 9 `Color`, построчно для сетки 3×3; `static let accent = Color(red: 0x6B/255, green: 0x85/255, blue: 0xA3/255)`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
import SwiftUI
@testable import Siply

final class ArtworkPaletteTests: XCTestCase {
    private func png(_ color: UIColor, size: CGFloat = 8) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).pngData { ctx in
            color.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        }
    }
    private func hsb(_ c: Color) -> (h: CGFloat, s: CGFloat, b: CGFloat) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0
        UIColor(c).getHue(&h, saturation: &s, brightness: &b, alpha: nil)
        return (h, s, b)
    }
    private let accentHue: CGFloat = {
        var h: CGFloat = 0
        UIColor(ArtworkPalette.accent).getHue(&h, saturation: nil, brightness: nil, alpha: nil)
        return h
    }()

    func testSolidRedArtworkKeepsHueDarkensBrightness() {
        let colors = ArtworkPalette.colors(from: png(.red))
        XCTAssertEqual(colors.count, 9)
        for c in colors {
            let v = hsb(c)
            XCTAssertTrue(v.h < 0.02 || v.h > 0.98, "hue \(v.h)")
            XCTAssertGreaterThanOrEqual(v.s, 0.35)
            XCTAssertTrue((0.18...0.45).contains(v.b), "brightness \(v.b)")
        }
    }

    func testNilArtworkAccentPalette() {
        let colors = ArtworkPalette.colors(from: nil)
        XCTAssertEqual(colors.count, 9)
        for c in colors {
            let v = hsb(c)
            XCTAssertEqual(v.h, accentHue, accuracy: 0.041)
            XCTAssertTrue((0.2...0.4).contains(v.b), "brightness \(v.b)")
        }
    }

    func testGarbageDataSameAsNil() {
        XCTAssertEqual(ArtworkPalette.colors(from: Data([1, 2, 3])), ArtworkPalette.colors(from: nil))
    }

    func testTinyArtworkStillNineColors() {
        XCTAssertEqual(ArtworkPalette.colors(from: png(.blue, size: 1)).count, 9)
    }

    func testSameInputSameOutput() {
        let data = png(.green)
        XCTAssertEqual(ArtworkPalette.colors(from: data), ArtworkPalette.colors(from: data))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: compile error `cannot find 'ArtworkPalette'`.

- [ ] **Step 3: Implement `ArtworkPalette` in `Siply/UI/ArtworkPalette.swift`**

`colors(from:)`: `UIImage(data:)?.cgImage` → `nil` → `fallback`. Иначе `CGContext(data: &buf, width: 3, height: 3, bitsPerComponent: 8, bytesPerRow: 12, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)`, `interpolationQuality = .high`, `draw(cg, in: CGRect(0,0,3,3))`; 9 пикселей → `UIColor(red:green:blue:alpha:)` → HSB → `s = max(s, 0.35)`, `b = min(max(b, 0.18), 0.45)` → `Color(hue:saturation:brightness:)`. Контекст не создался → `fallback`.

`fallback`: HSB акцента; для `row, col in 0..<3`: `hue = h + (CGFloat(col) - 1) * 0.04` (по модулю 1), `brightness = 0.2 + CGFloat(row) * 0.1`, saturation акцента.

- [ ] **Step 4: Run tests to verify they pass**

- [ ] **Step 5: Commit**

```bash
git add Siply/UI/ArtworkPalette.swift SiplyTests/ArtworkPaletteTests.swift
git commit -m "feat: палитра фона плеера из обложки"
```

---

### Task 2: Громкость из движка

**Files:**
- Modify: `Siply/Player/AudioEngine.swift`
- Modify: `Siply/Player/PlayerModel.swift`
- Modify: `SiplyTests/FakeAudioEngine.swift`
- Create: `SiplyTests/AVAudioPlayerEngineTests.swift`
- Test: `SiplyTests/PlayerModelTests.swift`

**Interfaces:**
- Produces: `AudioEngine.level: Float { get }` (0…1); `AVAudioPlayerEngine.normalized(db: Float) -> Float` (static); `PlayerModel.level: Float` (вычисляемое, `isPlaying ? engine.level : 0`); `FakeAudioEngine.level: Float = 0`.

- [ ] **Step 1: Write the failing tests**

`SiplyTests/AVAudioPlayerEngineTests.swift`:

```swift
import XCTest
@testable import Siply

final class AVAudioPlayerEngineTests: XCTestCase {
    func testNormalizedDb() {
        XCTAssertEqual(AVAudioPlayerEngine.normalized(db: -60), 0)
        XCTAssertEqual(AVAudioPlayerEngine.normalized(db: 0), 1)
        XCTAssertEqual(AVAudioPlayerEngine.normalized(db: -30), 0.5, accuracy: 0.001)
        XCTAssertEqual(AVAudioPlayerEngine.normalized(db: -160), 0)
        XCTAssertEqual(AVAudioPlayerEngine.normalized(db: 10), 1)
    }

    @MainActor func testLevelZeroWithoutPlayer() {
        XCTAssertEqual(AVAudioPlayerEngine().level, 0)
    }
}
```

В `PlayerModelTests`:

```swift
    func testLevelZeroWhenPaused() {
        engine.level = 0.7
        player.play(queue: tracks, startingAt: 0)
        player.togglePlayPause()
        XCTAssertEqual(player.level, 0)
    }

    func testLevelPassesThroughWhenPlaying() {
        engine.level = 0.7
        player.play(queue: tracks, startingAt: 0)
        XCTAssertEqual(player.level, 0.7)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: compile errors `has no member 'level'` / `'normalized'`.

- [ ] **Step 3: Implement**

- Протокол: `/// Громкость сейчас, 0…1; 0 без трека или на паузе.` `var level: Float { get }`.
- `AVAudioPlayerEngine`: в `load` после `enableRate` — `p.isMeteringEnabled = true`. `var level: Float { guard let p = player, p.isPlaying else { return 0 }; p.updateMeters(); return Self.normalized(db: p.averagePower(forChannel: 0)) }`. `static func normalized(db: Float) -> Float { min(max((db + 60) / 60, 0), 1) }`.
- `FakeAudioEngine`: `var level: Float = 0`.
- `PlayerModel`: `var level: Float { isPlaying ? engine.level : 0 }` рядом с `duration`.

- [ ] **Step 4: Run tests to verify they pass**

- [ ] **Step 5: Commit**

```bash
git add Siply/Player/AudioEngine.swift Siply/Player/PlayerModel.swift SiplyTests/FakeAudioEngine.swift SiplyTests/AVAudioPlayerEngineTests.swift SiplyTests/PlayerModelTests.swift
git commit -m "feat: громкость трека из движка для пульса фона"
```

---

### Task 3: PlayerBackground

**Files:**
- Create: `Siply/UI/PlayerBackground.swift`
- Test: `SiplyTests/PlayerBackgroundTests.swift`

**Interfaces:**
- Consumes: ничего из Task 1–2 (цвета и уровень приходят параметрами).
- Produces: `struct PlayerBackground: View { init(colors: [Color], level: @escaping () -> Float) }`; `static func points(at t: Double, amplitude: Float) -> [SIMD2<Float>]` — 9 точек построчно.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Siply

final class PlayerBackgroundTests: XCTestCase {
    private let corners: [(Int, SIMD2<Float>)] = [(0, [0, 0]), (2, [1, 0]), (6, [0, 1]), (8, [1, 1])]

    func testCornersFixed() {
        for t in [0.0, 1.7, 9.3] {
            let p = PlayerBackground.points(at: t, amplitude: 0.14)
            XCTAssertEqual(p.count, 9)
            for (i, c) in corners { XCTAssertEqual(p[i], c, "t=\(t) i=\(i)") }
        }
    }

    func testEdgesStayOnEdges() {
        let p = PlayerBackground.points(at: 4.2, amplitude: 0.14)
        XCTAssertEqual(p[1].y, 0)   // верх
        XCTAssertEqual(p[7].y, 1)   // низ
        XCTAssertEqual(p[3].x, 0)   // лево
        XCTAssertEqual(p[5].x, 1)   // право
    }

    func testInUnitSquareAndMove() {
        let a = PlayerBackground.points(at: 0, amplitude: 0.14)
        let b = PlayerBackground.points(at: 3, amplitude: 0.14)
        for p in a + b {
            XCTAssertTrue((0...1).contains(p.x) && (0...1).contains(p.y), "\(p)")
        }
        XCTAssertNotEqual(a, b)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: compile error `cannot find 'PlayerBackground'`.

- [ ] **Step 3: Implement `PlayerBackground` in `Siply/UI/PlayerBackground.swift`**

`points(at:amplitude:)`: базовые точки `(col/2, row/2)`. Подвижные: индексы 1, 7 — только `x`; 3, 5 — только `y`; 4 — обе. Смещение `amplitude * sin(Float(t) * ω + φ)`, `ω` для пяти точек: `2π/8, 2π/10, 2π/12, 2π/14, 2π/9` (для центра две компоненты: `2π/11` по x, `2π/13` по y), `φ`: `0, 1.3, 2.6, 3.9, 5.2, 0.7`. Результат зажать в `0…1`.

`body`: `@Environment(\.accessibilityReduceMotion) reduceMotion`, `@State private var smoother = Smoother()` (`final class Smoother { var value: Float = 0; func push(_ level: Float) -> Float { value = value * 0.85 + level * 0.15; return value } }` — ссылочный тип, чтобы менять из body без `@State`-присваивания), `@State private let start = Date()`. `TimelineView(.animation(paused: reduceMotion)) { ctx in ... }`: `t = reduceMotion ? 0 : ctx.date.timeIntervalSince(start)`; `s = reduceMotion ? 0 : smoother.push(level())`. `MeshGradient(width: 3, height: 3, points: Self.points(at: t, amplitude: 0.08 + 0.06 * s), colors: colors)` `.overlay(Color.white.opacity(Double(0.12 * s)))` `.ignoresSafeArea()`.

- [ ] **Step 4: Run tests to verify they pass**

- [ ] **Step 5: Commit**

```bash
git add Siply/UI/PlayerBackground.swift SiplyTests/PlayerBackgroundTests.swift
git commit -m "feat: PlayerBackground — mesh-градиент с дрейфом и пульсом"
```

---

### Task 4: Встраивание в NowPlayingSheet

**Files:**
- Modify: `Siply/UI/NowPlayingSheet.swift`
- Modify: `docs/checklist.md`

**Interfaces:**
- Consumes: `ArtworkPalette.colors(from:)` (Task 1), `player.level` (Task 2), `PlayerBackground(colors:level:)` (Task 3).

- [ ] **Step 1: Встроить фон**

В `NowPlayingSheet`: `@State private var colors = ArtworkPalette.colors(from: nil)`. На корневой `VStack` добавить:

```swift
.environment(\.colorScheme, .dark)
.task(id: player.currentTrack?.artwork) {
    let data = player.currentTrack?.artwork
    colors = await Task.detached { ArtworkPalette.colors(from: data) }.value
}
.presentationBackground { PlayerBackground(colors: colors) { player.level } }
```

Кнопка скорости и `RoutePicker` на тёмном фоне — проверить в симуляторе (`xcrun simctl` скриншот не нужен; достаточно, что сборка проходит и `.bordered` на тёмной схеме читается — если сливается, добавить `.tint(.white)` на кнопку).

- [ ] **Step 2: Сборка и все тесты**

Команда из Global Constraints. Expected: `** TEST SUCCEEDED **`, все прежние тесты зелёные.

- [ ] **Step 3: Чеклист**

В `docs/checklist.md` добавить пункт 15 (после 14):

```
15. Открыл плеер на треке с цветной обложкой → фон в её цветах, медленно переливается; на громком месте чуть ярче; пауза → переливается, не пульсирует; трек без обложки → серо-голубой фон; «Уменьшение движения» в настройках iOS → фон стоит; светлая тема системы → текст в плеере белый, читается.
```

- [ ] **Step 4: Commit**

```bash
git add Siply/UI/NowPlayingSheet.swift docs/checklist.md
git commit -m "feat: живой фон в полноэкранном плеере"
```
