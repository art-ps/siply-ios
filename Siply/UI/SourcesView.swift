import SwiftUI

/// Корневой экран: список источников музыки.
struct SourcesView: View {
    @Environment(SourceStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [FolderRoute] = []
    @State private var showPicker = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                let _ = store.revision   // перерисовка после refresh(): доступность читается с диска
                ForEach(store.sources) { source in
                    row(for: source)
                        .deleteDisabled(source.kind == .appFolder)
                }
                .onDelete { offsets in
                    let removed = offsets.map { store.sources[$0] }
                    for source in removed { store.remove(source) }
                }
            }
            .navigationTitle("Источники")
            .refreshable { store.refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.refresh() }
            }
            .navigationDestination(for: FolderRoute.self) { route in
                FolderView(folder: route.folder, source: route.source, autoDownload: route.autoDownload)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showPicker = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Добавить папку")
                }
            }
            .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url): store.add(folder: url)
                case .failure(let error): NSLog("Siply: выбор папки не удался: \(error)")
                }
            }
            .onChange(of: store.pendingRoute, initial: true) { _, route in
                if let route {
                    path = [route]
                    store.pendingRoute = nil
                }
            }
        }
    }

    @ViewBuilder
    private func row(for source: Source) -> some View {
        let url = store.url(of: source)
        if store.isAvailable(source), let url {
            NavigationLink(value: FolderRoute(folder: url, source: source)) {
                label(for: source, icon: icon(for: source, url: url), subtitle: subtitle(for: source, url: url))
            }
        } else {
            label(for: source, icon: "externaldrive", subtitle: "Не подключена")   // отключённый диск
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
                .onTapGesture { store.refresh() }   // вставили флешку — тап проверяет снова
        }
    }

    private func label(for source: Source, icon: String, subtitle: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                if !subtitle.isEmpty, subtitle != source.name {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: icon)
        }
    }

    private func isUbiquitous(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true
    }

    private func icon(for source: Source, url: URL?) -> String {
        if source.kind == .appFolder { return "iphone" }
        guard let url else { return "externaldrive" }   // нет URL — скорее всего отключённый диск
        if isUbiquitous(url) { return "icloud" }
        let values = try? url.resourceValues(forKeys: [.volumeIsRemovableKey, .volumeIsInternalKey])
        if values?.volumeIsRemovable == true || values?.volumeIsInternal == false { return "externaldrive" }
        return "folder"
    }

    private func subtitle(for source: Source, url: URL) -> String {
        if source.kind == .appFolder { return "На iPhone" }
        if isUbiquitous(url) { return "iCloud Drive" }
        let parent = url.deletingLastPathComponent().lastPathComponent
        return UUID(uuidString: parent) == nil ? parent : ""   // корень провайдера лежит в UUID-контейнере
    }
}
