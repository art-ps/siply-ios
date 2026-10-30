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
                Button(action: play) {
                    Label("Воспроизвести", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button(action: shuffle) {
                    Label("Перемешать", systemImage: "shuffle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .disabled(tracks.isEmpty)
        }
    }

    /// Длительность неизвестна (теги по запросу) — только число треков.
    private var summary: String {
        let minutes = Int((tracks.reduce(0) { $0 + $1.duration } / 60).rounded())
        let count = Track.countLabel(tracks.count)
        return minutes > 0 ? "\(count) · \(minutes) мин" : count
    }
}
