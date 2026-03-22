import SwiftUI

// MARK: - UpdatesViewModel

@Observable final class UpdatesViewModel {

    var items: [Manga] = []
    var isRefreshing = false

    func loadFromDB() async {
        let loaded = await Task.detached(priority: .userInitiated) {
            (try? MangaQueries.fetchLibraryByLastUpdated()) ?? []
        }.value
        items = loaded
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true

        // 1. Cargar biblioteca actual
        let library = await Task.detached(priority: .userInitiated) {
            (try? MangaQueries.fetchLibrary()) ?? []
        }.value

        // 2. Para cada manga en biblioteca, obtener capítulos del plugin
        //    y comparar con los guardados en DB
        await withTaskGroup(of: Void.self) { group in
            for manga in library {
                group.addTask {
                    await self.checkUpdates(for: manga)
                }
            }
        }

        // 3. Recargar lista desde DB
        await loadFromDB()
        isRefreshing = false
    }

    private func checkUpdates(for manga: Manga) async {
        let sourceId  = manga.sourceId
        let mangaPath = manga.path
        let mangaId   = manga.id

        let allInstalled = await ExtensionManager.shared.installed
        let ext = allInstalled.first(where: { $0.id == sourceId })
        guard let ext else { return }

        let remoteChapters = await Task.detached(priority: .background) {
            let bridge = ExtensionManager.shared.bridge(for: ext)
            return bridge?.getChapterList(mangaPath: mangaPath, mangaId: mangaId) ?? []
        }.value

        guard !remoteChapters.isEmpty else { return }

        let localChapters = (try? ChapterQueries.fetchAll(mangaId: mangaId)) ?? []
        let localIds = Set(localChapters.map { $0.id })
        let hasNew = remoteChapters.contains(where: { !localIds.contains($0.id) })

        guard hasNew else { return }

        // Hay capítulos nuevos → actualizar lastUpdatedAt
        try? MangaQueries.touchLastUpdated(mangaId: mangaId)
    }
}

// MARK: - UpdatesView

struct UpdatesView: View {
    @State private var vm = UpdatesViewModel()

    var body: some View {
        List {
            if vm.items.isEmpty && !vm.isRefreshing {
                ContentUnavailableView(
                    "No updates yet",
                    systemImage: "bell.badge",
                    description: Text("Add manga to your library to track updates.")
                )
            } else {
                ForEach(vm.items) { manga in
                    NavigationLink {
                        MangaDetailView(manga: manga)
                    } label: {
                        UpdatesRow(manga: manga)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Updates")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if vm.isRefreshing {
                    ProgressView()
                } else {
                    Button {
                        Task { await vm.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .task { await vm.loadFromDB() }
    }
}

// MARK: - UpdatesRow

private struct UpdatesRow: View {
    let manga: Manga

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: manga.coverURL) { image in
                image.resizable().aspectRatio(2/3, contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .aspectRatio(2/3, contentMode: .fit)
            }
            .frame(width: 48)
            .cornerRadius(6)
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(manga.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                if let updated = manga.lastUpdatedAt {
                    Text(updated.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack { UpdatesView() }
}
