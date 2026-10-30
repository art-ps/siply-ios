import SwiftUI

/// Полноэкранный «Сейчас играет»: обложка, прогресс, транспорт, вывод звука.
struct NowPlayingSheet: View {
    @Environment(PlayerModel.self) private var player
    @State private var position: TimeInterval = 0
    @State private var isScrubbing = false

    var body: some View {
        VStack(spacing: 24) {
            if let track = player.currentTrack {
                ArtworkView(data: track.artwork, size: 300)
                    .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
                VStack(spacing: 4) {
                    Text(track.title).font(.title2.bold()).lineLimit(1)
                    Text(track.artist).font(.title3).lineLimit(1)
                    Text(track.album).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                .multilineTextAlignment(.center)
            }
            VStack(spacing: 4) {
                // seek только на отпускание, иначе таймер плеера дёргает ползунок
                Slider(value: $position, in: 0...max(player.duration, 1)) { editing in
                    isScrubbing = editing
                    if !editing { player.seek(to: position) }
                }
                HStack {
                    Text(position.mmss)
                    Spacer()
                    Text("-" + (player.duration - position).mmss)
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            HStack(spacing: 48) {
                Button { player.previous() } label: {
                    Image(systemName: "backward.fill").font(.title)
                }
                .accessibilityLabel("Предыдущий")
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 44))
                }
                .accessibilityLabel(player.isPlaying ? "Пауза" : "Воспроизвести")
                Button { player.next() } label: {
                    Image(systemName: "forward.fill").font(.title)
                }
                .accessibilityLabel("Следующий")
            }
            .buttonStyle(.plain)
            HStack {
                RoutePicker().frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 32)
        .onAppear { position = player.currentTime }
        .onChange(of: player.currentTime) { _, time in
            if !isScrubbing { position = time }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
