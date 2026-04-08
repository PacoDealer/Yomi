import SwiftUI

struct MangaDetailView: View {

    // MARK: - State

    @State private var manga: Manga
    @State private var synopsisExpanded = false
    @State private var chapters: [Chapter] = []
    @State private var bridge: JSBridge? = nil
    @State private var isLoadingChapters = false
    @State private var downloadManager = DownloadManager.shared

    // Feature 1 — Category assignment
    @State private var allCategories: [Category] = []
    @State private var assignedCategoryIds: Set<String> = []
    @State private var showCategorySheet = false

    // Feature 2 — Chapter pagination
    @State private var displayedChapterCount: Int = 50
    @State private var chaptersDescending: Bool = true

    // Feature 3 — Storage size
    @State private var storageSizeLabel: String? = nil

    init(manga: Manga) {
        _manga = State(initialValue: manga)
    }

    // MARK: - Body

    var body: some View {
        List {
            // MARK: Header
            Section {
                HStack(alignment: .top, spacing: 12) {
                    AsyncImage(url: manga.coverURL) { image in
                        image
                            .resizable()
                            .aspectRatio(2 / 3, contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .aspectRatio(2 / 3, contentMode: .fit)
                    }
                    .frame(width: 120)
                    .cornerRadius(8)
                    .clipped()

                    VStack(alignment: .leading, spacing: 6) {
                        Text(manga.title)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)

                        if let author = manga.author {
                            Text(author)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        StatusBadge(status: manga.status)

                        if manga.inLibrary {
                            ReadingStatusMenu(readingStatus: manga.readingStatus) { newStatus in
                                Task { await updateReadingStatus(newStatus) }
                            }
                        }

                        if !manga.genres.isEmpty {
                            Text(manga.genres.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // MARK: Synopsis
            Section("Synopsis") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(manga.summary ?? "No synopsis available.")
                        .font(.subheadline)
                        .lineLimit(synopsisExpanded ? nil : 4)

                    Button(synopsisExpanded ? "Less" : "More") {
                        synopsisExpanded.toggle()
                    }
                    .font(.subheadline)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
            }

            // MARK: Chapters
            Section {
                if isLoadingChapters {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 4)
                } else if chapters.isEmpty {
                    Text(bridge == nil ? "No source available for this manga." : "No chapters found.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    let sorted = chaptersDescending ? Array(chapters.reversed()) : chapters
                    let visible = Array(sorted.prefix(displayedChapterCount).enumerated())
                    ForEach(visible, id: \.element.id) { _, chapter in
                        NavigationLink {
                            ChapterReaderView(
                                manga: manga,
                                bridge: bridge!,
                                chapters: chapters,
                                chapterIndex: chapters.firstIndex(where: { $0.id == chapter.id }) ?? 0
                            )
                        } label: {
                            ChapterRow(chapter: chapter, manga: manga, bridge: bridge)
                        }
                        .disabled(bridge == nil)
                    }
                    if chapters.count > displayedChapterCount {
                        Button("Load \(min(50, chapters.count - displayedChapterCount)) more") {
                            displayedChapterCount += 50
                        }
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                }
            } header: {
                HStack {
                    Text("Chapters")
                    if !chapters.isEmpty {
                        Text("(\(chapters.count))")
                            .foregroundStyle(.secondary)
                    }
                    if let size = storageSizeLabel {
                        Text("· \(size)")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        withAnimation(.spring(duration: 0.2)) { chaptersDescending.toggle() }
                    } label: {
                        Image(systemName: chaptersDescending ? "arrow.down" : "arrow.up")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)

                    if let b = bridge, !chapters.isEmpty {
                        let undownloaded = chapters.filter { !$0.isDownloaded && !$0.isRead }
                        if !undownloaded.isEmpty {
                            Button("Download next \(min(10, undownloaded.count))") {
                                undownloaded.prefix(10).forEach { ch in
                                    DownloadManager.shared.enqueue(ch, manga: manga, bridge: b)
                                }
                            }
                            .font(.caption)
                            .textCase(nil)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(manga.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCategorySheet = true
                } label: {
                    Image(systemName: "tag")
                }
                .disabled(!manga.inLibrary)
                .opacity(manga.inLibrary ? 1.0 : 0.4)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await toggleLibrary() }
                } label: {
                    Image(systemName: manga.inLibrary ? "heart.fill" : "heart")
                        .foregroundStyle(manga.inLibrary ? .red : .primary)
                }
            }
        }
        .task { await loadChapters() }
        .task { await touchLastRead() }
        .task { await loadCategories() }
        .task { computeStorageSize() }
        .sheet(isPresented: $showCategorySheet) {
            NavigationStack {
                List {
                    ForEach(allCategories) { cat in
                        Button {
                            Task { await toggleCategory(cat) }
                        } label: {
                            HStack {
                                Text(cat.name)
                                Spacer()
                                if assignedCategoryIds.contains(cat.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .navigationTitle("Categories")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showCategorySheet = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Toggle Library

    private func toggleLibrary() async {
        do {
            let snapshot = manga
            let updated = try await Task.detached {
                try MangaQueries.toggleLibrary(manga: snapshot)
            }.value
            manga = updated
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            // Request notification permission on first library save
            if manga.inLibrary && !AppSettings.shared.hasRequestedNotifications {
                AppSettings.shared.hasRequestedNotifications = true
                Task {
                    await NotificationManager.shared.requestPermission()
                }
            }
            // Clean up downloaded chapters when removing from library
            if !manga.inLibrary {
                let mangaId = manga.id
                Task.detached {
                    let dir = FileManager.default
                        .urls(for: .documentDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("Downloads/\(mangaId)")
                    try? FileManager.default.removeItem(at: dir)
                }
            }
        } catch {
            print("toggleLibrary error: \(error)")
        }
    }

    // MARK: - Touch Last Read

    private func touchLastRead() async {
        guard manga.inLibrary else { return }
        let mangaId = manga.id
        Task.detached {
            try? MangaQueries.touchLastRead(mangaId: mangaId)
        }
    }

    // MARK: - Load Chapters

    private func loadChapters() async {
        let sourceId = manga.sourceId
        let mangaPath = manga.path
        let mangaId = manga.id

        let ext = ExtensionManager.shared.installed.first(where: { $0.id == sourceId })
        guard let ext else { return }

        isLoadingChapters = true

        let loadedBridge = ExtensionManager.shared.bridge(for: ext)
        let loadedChapters = await Task.detached(priority: .userInitiated) {
            loadedBridge?.getChapterList(mangaPath: mangaPath, mangaId: mangaId) ?? []
        }.value

        bridge = loadedBridge

        // Merge persisted read/time state from DB
        let saved = (try? ChapterQueries.fetchAll(mangaId: mangaId)) ?? []
        let savedMap = Dictionary(uniqueKeysWithValues: saved.map { ($0.id, $0) })
        chapters = loadedChapters.map { ch in
            guard let persisted = savedMap[ch.id] else { return ch }
            var merged = ch
            merged.isRead = persisted.isRead
            merged.readingSeconds = persisted.readingSeconds
            return merged
        }

        isLoadingChapters = false
    }

    // MARK: - Storage size

    private func computeStorageSize() {
        let mangaDir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads/\(manga.id)", isDirectory: true)

        guard FileManager.default.fileExists(atPath: mangaDir.path) else { return }

        var totalBytes: Int64 = 0
        if let enumerator = FileManager.default.enumerator(
            at: mangaDir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                totalBytes += Int64(size)
            }
        }

        if totalBytes > 0 {
            storageSizeLabel = ByteCountFormatter.string(
                fromByteCount: totalBytes,
                countStyle: .file
            )
        }
    }

    // MARK: - Load Categories

    private func loadCategories() async {
        let mangaId = manga.id
        let (all, assigned) = await Task.detached(priority: .userInitiated) {
            let all = (try? CategoryQueries.fetchAll()) ?? []
            let assigned = (try? CategoryQueries.categoriesForManga(mangaId: mangaId)) ?? []
            return (all, Set(assigned.map { $0.id }))
        }.value
        allCategories = all
        assignedCategoryIds = assigned
    }

    // MARK: - Update Reading Status

    private func updateReadingStatus(_ status: ReadingStatus) async {
        let mangaId = manga.id
        await Task.detached(priority: .userInitiated) {
            try? MangaQueries.updateReadingStatus(mangaId: mangaId, status: status)
        }.value
        manga.readingStatus = status
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Toggle Category

    private func toggleCategory(_ category: Category) async {
        let mangaId = manga.id
        let catId = category.id
        let isAssigned = assignedCategoryIds.contains(catId)
        await Task.detached(priority: .userInitiated) {
            if isAssigned {
                try? CategoryQueries.unassign(mangaId: mangaId, categoryId: catId)
            } else {
                try? CategoryQueries.assign(mangaId: mangaId, categoryId: catId)
            }
        }.value
        if isAssigned {
            assignedCategoryIds.remove(catId)
        } else {
            assignedCategoryIds.insert(catId)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - ChapterRow

private struct ChapterRow: View {
    let chapter: Chapter
    let manga: Manga
    let bridge: JSBridge?

    private var dm: DownloadManager { DownloadManager.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(chapter.name)
                    .font(.subheadline)
                    .foregroundStyle(chapter.isRead ? .secondary : .primary)
                if chapter.isRead {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if chapter.isDownloaded {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tint)
                } else if dm.activeChapterId == chapter.id {
                    ProgressView(value: dm.progress[chapter.id] ?? 0)
                        .frame(width: 20)
                } else if dm.queue.contains(where: { $0.id == chapter.id }) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let number = chapter.chapterNumber {
                Text("Chapter \(number, specifier: "%.1f")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .leading) {
            if chapter.isDownloaded {
                Button(role: .destructive) {
                    DownloadManager.shared.deleteDownload(chapter: chapter)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } else {
                Button {
                    guard let b = bridge else { return }
                    DownloadManager.shared.enqueue(chapter, manga: manga, bridge: b)
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .tint(.blue)
            }
        }
    }
}

// MARK: - ReadingStatusMenu

private struct ReadingStatusMenu: View {
    let readingStatus: ReadingStatus
    let onSelect: (ReadingStatus) -> Void

    var body: some View {
        Menu {
            ForEach(ReadingStatus.allCases) { status in
                Button {
                    onSelect(status)
                } label: {
                    Label(status.label, systemImage: status.systemImage)
                    if readingStatus == status {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: readingStatus.systemImage)
                    .font(.caption)
                Text(readingStatus.label)
                    .font(.caption)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.12))
            .clipShape(Capsule())
            .foregroundStyle(readingStatus == .none ? Color.secondary : Color.accentColor)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - StatusBadge

private struct StatusBadge: View {
    let status: MangaStatus

    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch status {
        case .ongoing:   .green
        case .completed: .blue
        case .hiatus:    .orange
        case .cancelled: .red
        case .unknown:   .gray
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MangaDetailView(manga: Manga(
            id: "1", path: "/berserk", sourceId: "en.mangadex",
            title: "Berserk",
            coverURL: nil,
            summary: "Guts, a former mercenary now known as the 'Black Swordsman', is on a hunt for revenge. After a tumultuous childhood, he finally finds someone he respects and admires: Griffith, the leader of a mercenary band called the Band of the Hawk.",
            author: "Kentaro Miura", artist: "Kentaro Miura",
            status: .hiatus,
            genres: ["Action", "Dark Fantasy", "Adventure"],
            inLibrary: true, isLocal: false, lastReadAt: nil, lastUpdatedAt: nil, readingSeconds: 0
        ))
    }
}
