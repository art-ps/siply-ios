import Foundation

/// Что можно сделать с iCloud-файлом или папкой: скачать или убрать с устройства.
enum FileAction: Hashable {
    case download, evict

    static func available(isUbiquitous: Bool, state: DownloadState) -> Set<FileAction> {
        guard isUbiquitous else { return [] }
        switch state {
        case .remote: return [.download]
        case .local: return [.evict]
        case .downloading, .onDemand: return []
        }
    }

    /// Нескачанная папка целиком — только «Скачать»: внутрь не заходим.
    static func available(isUbiquitous: Bool, folderState: DownloadState, fileStates: [DownloadState]) -> Set<FileAction> {
        guard isUbiquitous else { return [] }
        if folderState == .remote { return [.download] }
        var result: Set<FileAction> = []
        if fileStates.contains(.remote) { result.insert(.download) }
        if fileStates.contains(.local) { result.insert(.evict) }
        return result
    }
}
