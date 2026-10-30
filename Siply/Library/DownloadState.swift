import Foundation

/// Лежит ли файл на устройстве. Для iCloud Drive и файловых провайдеров.
enum DownloadState: Equatable {
    case local, remote, downloading
    /// Файл на провайдере без iCloud-статуса: показываем как local, но перед play тянем через NSFileCoordinator.
    case onDemand

    /// nil (не iCloud) / .current / .downloaded → .local; .notDownloaded → .remote.
    init(status: URLUbiquitousItemDownloadingStatus?) {
        self = status == .notDownloaded ? .remote : .local
    }

    /// Любая ошибка чтения атрибута — считаем файл локальным.
    static func of(_ url: URL) -> DownloadState {
        let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus
        return DownloadState(status: status)
    }
}
