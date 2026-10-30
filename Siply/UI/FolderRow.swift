import SwiftUI

enum FolderRowState {
    /// Серая строка папки: хоть один трек не скачан.
    static func isDimmed(tracks: [Track]) -> Bool {
        tracks.contains { $0.download == .remote }
    }
}

/// Строка подпапки; серая с облаком, если в ней есть не скачанные треки.
struct FolderRow: View {
    let url: URL
    let dimmed: Bool

    var body: some View {
        HStack {
            Label(url.lastPathComponent, systemImage: "folder")
            if dimmed {
                Spacer()
                Image(systemName: "icloud.and.arrow.down")
            }
        }
        .foregroundStyle(dimmed ? .secondary : .primary)
    }
}
