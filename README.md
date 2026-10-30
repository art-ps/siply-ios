# Siply для iOS

Плеер музыки по папкам для iPhone: SwiftUI + AVFoundation, без зависимостей. Версия для Мака: https://github.com/art-ps/siply

Требования: iOS 26.1+, iPhone.

## Сборка

    brew install xcodegen
    xcodegen generate
    xcodebuild -scheme Siply -destination 'generic/platform=iOS' build

## Тесты

    xcodebuild test -scheme Siply -destination 'platform=iOS Simulator,name=iPhone 17'

Ручная проверка на устройстве: [docs/checklist.md](docs/checklist.md).

Лицензия: MIT.
