import SwiftUI

struct NovelDetailView: View {
    @State private var novel: Novel
    @State private var bridge: JSBridge?

    // MARK: - State

    @State private var synopsisExpanded = false
    @State private var chapters: [NovelChapter] = []
    @State private var isLoadingChapters = false
    @State private var isInLibrary: Bool
    @State private var chapterForNav: NovelChapter? = nil
    @State private var allCategories: [Category] = []
    @State private var assignedCategoryIds: Set<String> = []
    @State private var showCategorySheet = false
    @State private var novelReadingStatus: ReadingStatus
    @State private var aniListScore: Int? = nil
    @State private var chaptersDescending: Bool = false
    @State private var chapterFilterUnread: Bool = false

    init(novel: Novel, bridge: JSBridge? = nil) {
        _novel = State(initialValue: novel)
        _bridge = State(initialValue: bridge)
        _isInLibrary = State(initialValue: novel.inLibrary)
        _novelReadingStatus = State(initialValue: novel.readingStatus)
    }

    // MARK: - Resume helpers

    private var resumeChapter: NovelChapter? {
        // In-progress (readAt set but not isRead — e.g. abandoned mid-way)
        if let inProgress = chapters.first(where: { !$0.isRead && $0.readAt != nil }) { return inProgress }
        // First unread
        if let firstUnread = chapters.first(where: { !$0.isRead }) { return firstUnread }
        // All read — return last
        return chapters.last
    }

    private var hasStartedReading: Bool {
        chapters.contains { $0.isRead || $0.readAt != nil }
    }

    private var resumeButtonTitle: String {
        guard hasStartedReading, let ch = resumeChapter else { return "Start reading" }
        if let num = ch.chapterNumber {
            let numStr = num.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(num))
                : String(format: "%.1f", num)
            return "Resume Ch. \(numStr)"
        }
        return "Resume"
    }

    // MARK: - Body

    var body: some View {
        List {
            // MARK: Header
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 14) {
                        AsyncImage(url: novel.coverURL) { image in
                            image
                                .resizable()
                                .aspectRatio(2 / 3, contentMode: .fill)
                        } placeholder: {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.3))
                                .aspectRatio(2 / 3, contentMode: .fit)
                        }
                        .frame(width: 110)
                        .cornerRadius(10)
                        .clipped()
                        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)

                        VStack(alignment: .leading, spacing: 7) {
                            Text(novel.title)
                                .font(.title3)
                                .fontWeight(.bold)
                                .fixedSize(horizontal: false, vertical: true)

                            if let author = novel.author {
                                Label(author, systemImage: "person")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            if let sourceName = ExtensionManager.shared.installed
                                .first(where: { $0.id == novel.sourceId })?.name {
                                Label(sourceName, systemImage: "puzzlepiece.extension")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            HStack(spacing: 8) {
                                NovelStatusBadge(status: novel.status)

                                if let score = aniListScore {
                                    Label("\(score)%", systemImage: "star.fill")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.orange)
                                }

                                if isInLibrary {
                                    ReadingStatusMenu(readingStatus: novelReadingStatus) { newStatus in
                                        Task { await updateReadingStatus(newStatus) }
                                    }
                                }
                            }
                        }

                        Spacer(minLength: 0)
                    }

                    // Genre chips
                    if !novel.genres.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(novel.genres, id: \.self) { genre in
                                    Text(genre)
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color.secondary.opacity(0.15), in: Capsule())
                                }
                            }
                        }
                    }

                    // Start / Resume reading button
                    if !isLoadingChapters && !chapters.isEmpty {
                        Button {
                            if let ch = resumeChapter {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                chapterForNav = ch
                                touchLastReadAt()
                            }
                        } label: {
                            Label(resumeButtonTitle,
                                  systemImage: hasStartedReading ? "play.fill" : "book.fill")
                                .frame(maxWidth: .infinity)
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
                .padding(.vertical, 6)
            }

            // MARK: Synopsis
            Section("Synopsis") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(novel.summary ?? "No synopsis available.")
                        .font(.subheadline)
                        .lineLimit(synopsisExpanded ? nil : 4)
                        .textSelection(.enabled)

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
                    Text("No chapters found.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    let displayed: [NovelChapter] = {
                        let base = chapterFilterUnread ? chapters.filter { !$0.isRead } : chapters
                        return chaptersDescending ? base.reversed() : base
                    }()
                    ForEach(displayed, id: \.id) { chapter in
                        Button {
                            chapterForNav = chapter
                            touchLastReadAt()
                        } label: {
                            NovelChapterRow(chapter: chapter)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                toggleRead(chapter)
                            } label: {
                                Label(chapter.isRead ? "Unread" : "Read",
                                      systemImage: chapter.isRead ? "circle" : "checkmark.circle.fill")
                            }
                            .tint(chapter.isRead ? .orange : .green)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Chapters")
                    if !chapters.isEmpty {
                        let readCount = chapters.filter { $0.isRead }.count
                        if readCount > 0 {
                            Text("\(readCount) / \(chapters.count)")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("(\(chapters.count))")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if !chapters.isEmpty {
                        Button {
                            chapterFilterUnread.toggle()
                        } label: {
                            Image(systemName: chapterFilterUnread
                                  ? "line.3.horizontal.decrease.circle.fill"
                                  : "line.3.horizontal.decrease")
                                .font(.caption).fontWeight(.semibold)
                                .foregroundStyle(.tint)
                        }
                        .buttonStyle(.plain)
                        Button {
                            withAnimation(.spring(duration: 0.2)) { chaptersDescending.toggle() }
                        } label: {
                            Image(systemName: chaptersDescending ? "arrow.down" : "arrow.up")
                                .font(.caption).fontWeight(.semibold)
                                .foregroundStyle(.tint)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(novel.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $chapterForNav) { ch in
            if let b = bridge, let idx = chapters.firstIndex(where: { $0.id == ch.id }) {
                TextReaderView(novel: novel, bridge: b, chapters: chapters, startIndex: idx)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        isInLibrary.toggle()
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        Task { await toggleLibrary() }
                    } label: {
                        Label(
                            isInLibrary ? "Remove from Library" : "Add to Library",
                            systemImage: isInLibrary ? "heart.slash" : "heart"
                        )
                    }
                    Button {
                        showCategorySheet = true
                    } label: {
                        Label("Edit categories", systemImage: "tag")
                    }
                    .disabled(!isInLibrary)

                    if !chapters.isEmpty {
                        Divider()
                        Button {
                            markAllChapters(read: true)
                        } label: {
                            Label("Mark all as read", systemImage: "checkmark.circle.fill")
                        }
                        Button {
                            markAllChapters(read: false)
                        } label: {
                            Label("Mark all as unread", systemImage: "circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
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
        .task { await loadChapters() }
        .task { await loadCategories() }
        .task { aniListScore = await AniListService.shared.fetchScore(title: novel.title, isManga: false) }
    }

    // MARK: - Toggle Library

    private func toggleLibrary() async {
        var updated = novel
        updated.inLibrary = isInLibrary
        try? NovelQueries.upsert(updated)
    }

    // MARK: - Update Reading Status

    private func updateReadingStatus(_ status: ReadingStatus) async {
        let novelId = novel.id
        await Task.detached(priority: .userInitiated) {
            try? NovelQueries.updateReadingStatus(novelId: novelId, status: status)
        }.value
        novelReadingStatus = status
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Load Categories

    private func loadCategories() async {
        let novelId = novel.id
        let (all, assigned) = await Task.detached(priority: .userInitiated) {
            let all = (try? CategoryQueries.fetchAll()) ?? []
            let assigned = (try? CategoryQueries.categoriesForNovel(novelId: novelId)) ?? []
            return (all, Set(assigned.map { $0.id }))
        }.value
        allCategories = all
        assignedCategoryIds = assigned
    }

    // MARK: - Toggle Category

    private func toggleCategory(_ category: Category) async {
        let novelId = novel.id
        let catId = category.id
        let isAssigned = assignedCategoryIds.contains(catId)
        await Task.detached(priority: .userInitiated) {
            if isAssigned {
                try? CategoryQueries.unassignNovel(novelId: novelId, categoryId: catId)
            } else {
                try? CategoryQueries.assignNovel(novelId: novelId, categoryId: catId)
            }
        }.value
        if isAssigned {
            assignedCategoryIds.remove(catId)
        } else {
            assignedCategoryIds.insert(catId)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Toggle chapter read

    private func toggleRead(_ chapter: NovelChapter) {
        guard let idx = chapters.firstIndex(where: { $0.id == chapter.id }) else { return }
        var updated = chapters[idx]
        updated.isRead = !updated.isRead
        updated.readAt = updated.isRead ? Date() : nil
        chapters[idx] = updated
        let id = updated.id
        let nowRead = updated.isRead
        Task.detached {
            if nowRead {
                try? NovelQueries.markRead(chapterId: id)
            } else {
                try? NovelQueries.markUnread(chapterId: id)
            }
        }
    }

    private func markAllChapters(read: Bool) {
        let now = Date()
        chapters = chapters.map { ch in
            var c = ch; c.isRead = read; c.readAt = read ? now : nil; return c
        }
        let novelId = novel.id
        Task.detached { try? NovelQueries.markAllChapters(novelId: novelId, read: read) }
    }

    // MARK: - Touch lastReadAt

    private func touchLastReadAt() {
        var updated = novel
        updated.lastReadAt = Date()
        Task.detached { try? NovelQueries.upsert(updated) }
    }

    // MARK: - Load Chapters

    private func loadChapters() async {
        isLoadingChapters = true
        let novelId = novel.id
        let path = novel.path
        let sourceId = novel.sourceId

        // Resolve bridge lazily if not provided at init (e.g. navigated from Updates/History)
        if bridge == nil {
            let ext = ExtensionManager.shared.installed.first(where: { $0.id == sourceId })
            bridge = ext.flatMap { ExtensionManager.shared.bridge(for: $0) }
        }

        guard let b = bridge else {
            let saved = await Task.detached(priority: .userInitiated) {
                (try? NovelQueries.fetchChapters(novelId: novelId)) ?? []
            }.value
            chapters = saved
            isLoadingChapters = false
            return
        }

        let source = await Task.detached(priority: .userInitiated) {
            b.parseNovel(path: path)
        }.value

        guard let source else {
            let saved = await Task.detached(priority: .userInitiated) {
                (try? NovelQueries.fetchChapters(novelId: novelId)) ?? []
            }.value
            chapters = saved
            isLoadingChapters = false
            return
        }

        // Update novel metadata in view (synopsis, author, status, cover)
        if let summary = source.summary, !summary.isEmpty { novel.summary = summary }
        if let author = source.author, !author.isEmpty { novel.author = author }
        if let status = source.status, !status.isEmpty { novel.status = status }
        if let coverStr = source.cover, !coverStr.isEmpty, let coverURL = URL(string: coverStr) {
            novel.coverURL = coverURL
        }

        // Persist updated metadata if in library
        if novel.inLibrary {
            let updated = novel
            await Task.detached { try? NovelQueries.upsert(updated) }.value
        }

        // Build chapters from remote source
        let fetched = source.chapters.enumerated().map { index, c in
            NovelChapter(
                id:             "\(novelId)-ch-\(index)",
                novelId:        novelId,
                path:           c.path,
                name:           c.name,
                chapterNumber:  c.chapterNumber,
                isRead:         false,
                readAt:         nil,
                releaseTime:    c.releaseTime,
                readingSeconds: 0
            )
        }

        // Persist to DB (INSERT OR IGNORE — preserves existing isRead/readingSeconds)
        await Task.detached {
            try? NovelQueries.insertAllIgnoringConflicts(fetched)
        }.value

        // Re-fetch from DB to merge persisted read state
        let merged = await Task.detached {
            (try? NovelQueries.fetchChapters(novelId: novelId)) ?? fetched
        }.value

        chapters = merged
        isLoadingChapters = false
    }
}

// MARK: - NovelChapterRow

private struct NovelChapterRow: View {
    let chapter: NovelChapter

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(chapter.name)
                .font(.subheadline)
                .foregroundStyle(chapter.isRead ? .secondary : .primary)
            if let release = chapter.releaseTime {
                Text(release)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - NovelStatusBadge

private struct NovelStatusBadge: View {
    let status: String

    var body: some View {
        Text(status.capitalized)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch status.lowercased() {
        case "ongoing":   .green
        case "completed": .blue
        case "hiatus":    .orange
        case "cancelled": .red
        default:          .gray
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        NovelDetailView(
            novel: Novel(
                id: "1",
                path: "/novel/re-zero",
                sourceId: "en.royalroad",
                title: "Re:Zero − Starting Life in Another World",
                coverURL: nil,
                summary: "Subaru Natsuki is an ordinary high school student who is suddenly summoned to another world on his way home from a convenience store.",
                author: "Tappei Nagatsuki",
                status: "ongoing",
                genres: ["Fantasy", "Isekai", "Drama"],
                inLibrary: false,
                lastReadAt: nil,
                lastUpdatedAt: nil,
                readingSeconds: 0,
                readingStatus: .none
            ),
            bridge: JSBridge(scriptURL: Bundle.main.url(forResource: "test-source", withExtension: "js")!)!
        )
    }
}
