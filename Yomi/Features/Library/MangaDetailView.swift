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

    // Feature 4 — Chapter selection
    @State private var isSelectingChapters = false
    @State private var selectedChapterIds: Set<String> = []

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
                        if isSelectingChapters {
                            // Selection mode row — no NavigationLink
                            ChapterRow(
                                chapter: chapter,
                                manga: manga,
                                bridge: bridge,
                                isSelecting: true,
                                isSelected: selectedChapterIds.contains(chapter.id),
                                onTap: {
                                    withAnimation(.spring(duration: 0.15)) {
                                        if selectedChapterIds.contains(chapter.id) {
                                            selectedChapterIds.remove(chapter.id)
                                        } else {
                                            selectedChapterIds.insert(chapter.id)
                                        }
                                    }
                                }
                            )
                        } else {
                            NavigationLink {
                                ChapterReaderView(
                                    manga: manga,
                                    bridge: bridge!,
                                    chapters: chapters,
                                    chapterIndex: chapters.firstIndex(where: { $0.id == chapter.id }) ?? 0
                                )
                            } label: {
                                ChapterRow(
                                    chapter: chapter,
                                    manga: manga,
                                    bridge: bridge,
                                    isSelecting: false,
                                    isSelected: false,
                                    onTap: nil
                                )
                            }
                            .disabled(bridge == nil)
                        }
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
                chapterSectionHeader
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(isSelectingChapters
            ? (selectedChapterIds.isEmpty ? "Select" : "\(selectedChapterIds.count) selected")
            : manga.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isSelectingChapters {
                // Selection mode toolbar
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        withAnimation(.spring(duration: 0.2)) {
                            isSelectingChapters = false
                            selectedChapterIds = []
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    let sortedChapters = chaptersDescending ? Array(chapters.reversed()) : chapters
                    let visibleIds = Set(sortedChapters.prefix(displayedChapterCount).map { $0.id })
                    Button(selectedChapterIds.count == visibleIds.count ? "Deselect All" : "Select All") {
                        withAnimation(.spring(duration: 0.15)) {
                            if selectedChapterIds.count == visibleIds.count {
                                selectedChapterIds = []
                            } else {
                                selectedChapterIds = visibleIds
                            }
                        }
                    }
                }
            } else {
                // Normal toolbar
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showCategorySheet = true
                        } label: {
                            Label("Edit categories", systemImage: "tag")
                        }
                        .disabled(!manga.inLibrary)

                        Button {
                            withAnimation(.spring(duration: 0.2)) {
                                isSelectingChapters = true
                                selectedChapterIds = []
                            }
                        } label: {
                            Label("Select chapters", systemImage: "checkmark.circle")
                        }
                        .disabled(chapters.isEmpty)

                        Divider()

                        Button(role: .destructive) {
                            Task { await toggleLibrary() }
                        } label: {
                            Label(manga.inLibrary ? "Remove from library" : "Add to library",
                                  systemImage: manga.inLibrary ? "heart.slash" : "heart")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
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
        }
        .safeAreaInset(edge: .bottom) {
            if isSelectingChapters {
                selectionActionBar
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

    // MARK: - Chapter Section Header

    private var chapterSectionHeader: some View {
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

            // Sort toggle
            Button {
                withAnimation(.spring(duration: 0.2)) { chaptersDescending.toggle() }
            } label: {
                Image(systemName: chaptersDescending ? "arrow.down" : "arrow.up")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)

            // Download menu
            if let b = bridge, !chapters.isEmpty {
                let unread = chapters.filter { !$0.isDownloaded && !$0.isRead }
                let undownloaded = chapters.filter { !$0.isDownloaded }
                Menu {
                    if !unread.isEmpty {
                        Button {
                            unread.prefix(1).forEach { DownloadManager.shared.enqueue($0, manga: manga, bridge: b) }
                        } label: {
                            Label("Next chapter", systemImage: "arrow.down.circle")
                        }
                        if unread.count >= 5 {
                            Button {
                                unread.prefix(5).forEach { DownloadManager.shared.enqueue($0, manga: manga, bridge: b) }
                            } label: {
                                Label("Next 5 chapters", systemImage: "arrow.down.circle")
                            }
                        }
                        if unread.count >= 10 {
                            Button {
                                unread.prefix(10).forEach { DownloadManager.shared.enqueue($0, manga: manga, bridge: b) }
                            } label: {
                                Label("Next 10 chapters", systemImage: "arrow.down.circle")
                            }
                        }
                        Button {
                            unread.forEach { DownloadManager.shared.enqueue($0, manga: manga, bridge: b) }
                        } label: {
                            Label("All unread (\(unread.count))", systemImage: "arrow.down.to.line")
                        }
                        Divider()
                    }
                    if !undownloaded.isEmpty {
                        Button {
                            undownloaded.forEach { DownloadManager.shared.enqueue($0, manga: manga, bridge: b) }
                        } label: {
                            Label("All chapters (\(undownloaded.count))", systemImage: "tray.and.arrow.down")
                        }
                    }
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .disabled(undownloaded.isEmpty)
                .opacity(undownloaded.isEmpty ? 0.3 : 1.0)
            }
        }
        .textCase(nil)
    }

    // MARK: - Selection Action Bar

    private var selectionActionBar: some View {
        HStack(spacing: 0) {
            // Mark read
            Button {
                Task { await markSelected(read: true) }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle")
                    Text("Read").font(.caption2)
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(selectedChapterIds.isEmpty)

            // Mark unread
            Button {
                Task { await markSelected(read: false) }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "circle")
                    Text("Unread").font(.caption2)
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(selectedChapterIds.isEmpty)

            // Download selected
            if let b = bridge {
                Button {
                    let toDownload = chapters.filter {
                        selectedChapterIds.contains($0.id) && !$0.isDownloaded
                    }
                    toDownload.forEach { DownloadManager.shared.enqueue($0, manga: manga, bridge: b) }
                    withAnimation(.spring(duration: 0.2)) {
                        isSelectingChapters = false
                        selectedChapterIds = []
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                        Text("Download").font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(selectedChapterIds.isEmpty)
            }

            // Delete selected downloads
            Button(role: .destructive) {
                let toDelete = chapters.filter {
                    selectedChapterIds.contains($0.id) && $0.isDownloaded
                }
                toDelete.forEach { DownloadManager.shared.deleteDownload(chapter: $0) }
                withAnimation(.spring(duration: 0.2)) {
                    isSelectingChapters = false
                    selectedChapterIds = []
                }
                Task { await loadChapters() }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "trash")
                    Text("Delete").font(.caption2)
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(.red)
            }
            .disabled(selectedChapterIds.isEmpty)
        }
        .padding(.vertical, 12)
        .background(.bar)
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
            merged.isDownloaded = persisted.isDownloaded
            return merged
        }

        isLoadingChapters = false
    }

    // MARK: - Mark Selected Read/Unread

    private func markSelected(read: Bool) async {
        let ids = selectedChapterIds
        await Task.detached(priority: .userInitiated) {
            for id in ids {
                try? ChapterQueries.setRead(chapterId: id, isRead: read)
            }
        }.value
        // Refresh chapters
        chapters = chapters.map { ch in
            if ids.contains(ch.id) {
                var updated = ch
                updated.isRead = read
                return updated
            }
            return ch
        }
        withAnimation(.spring(duration: 0.2)) {
            isSelectingChapters = false
            selectedChapterIds = []
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
    var isSelecting: Bool = false
    var isSelected: Bool = false
    var onTap: (() -> Void)? = nil

    private var dm: DownloadManager { DownloadManager.shared }

    var body: some View {
        HStack(spacing: 10) {
            // Selection circle
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .font(.title3)
            }

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

            Spacer()

            // Per-chapter download button (only in normal mode, not downloading already)
            if !isSelecting, let b = bridge, !chapter.isDownloaded,
               dm.activeChapterId != chapter.id,
               !dm.queue.contains(where: { $0.id == chapter.id }) {
                Button {
                    DownloadManager.shared.enqueue(chapter, manga: manga, bridge: b)
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting { onTap?() }
        }
        .swipeActions(edge: .leading) {
            if !isSelecting {
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
