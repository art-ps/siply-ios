import AVFoundation

/// .playback-сессия для фона и локскрина; прерывания (звонок, Siri) и вытащенные наушники → пауза.
/// Живёт с приложением, наблюдателей не снимаем.
@MainActor
final class AudioSession {
    private let player: PlayerModel
    private var wasPlaying = false
    private var tokens: [NSObjectProtocol] = []

    init(player: PlayerModel) {
        self.player = player
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
                                         object: session, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init) ?? []
            MainActor.assumeIsolated { self?.interruption(type, options) }
        })
        tokens.append(center.addObserver(forName: AVAudioSession.routeChangeNotification,
                                         object: session, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
            MainActor.assumeIsolated { self?.routeChange(reason) }
        })
    }

    private func interruption(_ type: AVAudioSession.InterruptionType?, _ options: AVAudioSession.InterruptionOptions) {
        switch type {
        case .began:
            wasPlaying = player.isPlaying
            if wasPlaying { player.togglePlayPause() }
        case .ended:
            if options.contains(.shouldResume), wasPlaying { player.togglePlayPause() }
            wasPlaying = false
        default: break
        }
    }

    /// Наушники/AirPlay пропали → пауза, без автовозобновления.
    private func routeChange(_ reason: AVAudioSession.RouteChangeReason?) {
        if reason == .oldDeviceUnavailable, player.isPlaying { player.togglePlayPause() }
    }
}
