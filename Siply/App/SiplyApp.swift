import SwiftUI

@main
struct SiplyApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            Text("Siply")
                .environment(model.store)
                .environment(model.player)
                .environment(model.search)
        }
    }
}
