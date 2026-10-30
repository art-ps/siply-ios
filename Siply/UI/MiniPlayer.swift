import SwiftUI

/// Мини-плеер в аксессуаре над таб-баром; тап открывает «Сейчас играет».
struct MiniPlayer: View {
    @Environment(PlayerModel.self) private var player
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @State private var showSheet = false

    var body: some View {
        if let track = player.currentTrack {
            HStack(spacing: 10) {
                ArtworkView(data: track.artwork, size: 36)
                VStack(alignment: .leading) {
                    Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if placement != .inline, !track.artist.isEmpty {
                        Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                if player.isDownloading {
                    ProgressView().controlSize(.small)
                } else {
                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(player.isPlaying ? "Пауза" : "Воспроизвести")
                }
                if placement != .inline {   // в свёрнутом таб-баре места нет
                    Button { player.next() } label: {
                        Image(systemName: "forward.fill").font(.title3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Следующий")
                }
            }
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .onTapGesture { showSheet = true }
            .sheet(isPresented: $showSheet) { NowPlayingSheet() }
        } else {
            EmptyView()
        }
    }
}
