import SwiftUI

@main
struct SiplyApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model.store)
                .environment(model.player)
                .environment(model.search)
        }
    }
}

/// Табы с мини-плеером; отдельный View, чтобы читать плеер из окружения.
struct RootView: View {
    @Environment(SourceStore.self) private var store
    @Environment(PlayerModel.self) private var player

    var body: some View {
        TabView {
            Tab("Папки", systemImage: "folder") { SourcesView() }
            Tab("Поиск", systemImage: "magnifyingglass", role: .search) { Text("Поиск") }   // Task 11: SearchView
        }
        .tabViewBottomAccessory(isEnabled: player.currentTrack != nil) { MiniPlayer() }
        .tabBarMinimizeBehavior(.onScrollDown)
        .onOpenURL { url in
            // nil — экран не меняется
            Task { store.pendingRoute = await FileOpener.open(url, store: store, player: player) }
        }
    }
}
