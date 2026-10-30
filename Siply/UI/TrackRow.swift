import SwiftUI

/// Строка трека: обложка, название, артист, длительность; не скачанный — серый с облаком.
struct TrackRow: View {
    let track: Track
    let isCurrent: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ArtworkView(data: track.artwork, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .foregroundStyle(isCurrent ? Color.accentColor : (track.download == .remote ? Color.secondary : Color.primary))
                    .lineLimit(1)
                if !track.artist.isEmpty {
                    Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            switch track.download {
            case .remote: Image(systemName: "icloud.and.arrow.down")
            case .downloading: ProgressView().controlSize(.small)
            case .local, .onDemand: EmptyView()
            }
            if track.duration > 0 {
                Text(track.duration.mmss).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .foregroundStyle(track.download == .remote ? .secondary : .primary)   // облако и прочее в строке
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityAddTraits(.isButton)
    }
}
