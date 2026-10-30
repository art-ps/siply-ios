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
                Button(rateLabel) { player.cycleRate() }
                    .buttonStyle(.bordered)
                    .font(.callout.monospacedDigit())
                    .accessibilityLabel("Скорость")
                    .frame(maxWidth: .infinity, alignment: .leading)
                RoutePicker().frame(width: 44, height: 44)
                sleepMenu.frame(maxWidth: .infinity, alignment: .trailing)
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

    private var sleepMenu: some View {
        Menu {
            Picker("Таймер сна", selection: Binding(get: { player.sleep }, set: { player.sleep = $0 })) {
                Text("Выкл").tag(SleepOption.off)
                Text("15 мин").tag(SleepOption.minutes(15))
                Text("30 мин").tag(SleepOption.minutes(30))
                Text("60 мин").tag(SleepOption.minutes(60))
                Text("До конца трека").tag(SleepOption.endOfTrack)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "moon.zzz")
                // Раз в секунду пересчитываем остаток до паузы.
                if let deadline = player.sleepDeadline {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let left = max(0, Int(deadline.timeIntervalSince(ctx.date).rounded(.up)))
                        Text(String(format: "%d:%02d", left / 60, left % 60)).monospacedDigit()
                    }
                }
            }
            .font(.callout)
            .foregroundStyle(player.sleep == .off ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
        }
        .accessibilityLabel("Таймер сна")
    }

    /// «1,25×»: запятая по-русски, без хвостовых нулей.
    private var rateLabel: String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return (f.string(from: NSNumber(value: player.rate)) ?? "1") + "×"
    }
}
