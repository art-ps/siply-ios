import AVFoundation
import Observation

/// Корень графа объектов приложения.
@MainActor @Observable
final class AppModel {
    let store: SourceStore
    let player: PlayerModel
    let search: SearchIndex
    private let nowPlaying: NowPlaying
    private let session: AudioSession

    init() {
        let store = SourceStore()
        let player = PlayerModel(engine: AVAudioPlayerEngine())
        self.store = store
        self.player = player
        search = SearchIndex(store: store)
        nowPlaying = NowPlaying(player: player)
        session = AudioSession(player: player)
    }
}
