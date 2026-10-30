import SwiftUI

/// Шапка папки: обложка, имя, «N треков · M мин», кнопки воспроизведения.
struct FolderHeader: View {
    let artwork: Data?
    let name: String
    let tracks: [Track]
    let play: () -> Void
    let shuffle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ArtworkView(data: artwork, size: 84)
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.title2.bold()).lineLimit(2)
                    Text(summary).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            HStack {
                // В одну строку и поровну по ширине: «Воспроизвести» иначе переносится и теряет иконку
                Button(action: play) {
                    buttonLabel("Воспроизвести", icon: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                Button(action: shuffle) {
                    buttonLabel("Перемешать", icon: "shuffle")
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
            .disabled(tracks.isEmpty)
        }
    }

    /// Иконка и текст явно: Label при сжатии теряет иконку
    private func buttonLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    /// Длительность неизвестна (теги по запросу) — только число треков.
    private var summary: String {
        let minutes = Int((tracks.reduce(0) { $0 + $1.duration } / 60).rounded())
        let count = Track.countLabel(tracks.count)
        return minutes > 0 ? "\(count) · \(minutes) мин" : count
    }
}
