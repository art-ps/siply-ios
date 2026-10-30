import SwiftUI

/// Пустая папка: ни подпапок, ни треков.
struct EmptyFolderView: View {
    let text: String

    var body: some View {
        ContentUnavailableView(text, systemImage: "music.note")
    }
}
