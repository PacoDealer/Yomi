import SwiftUI
import PhotosUI

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

    // Feature 2 — Chapter pagination + filter
    @State private var displayedChapterCount: Int = 50
    @State private var chaptersDescending: Bool = true
    @State private var chapterFilter: ChapterFilter = .all
    @State private var chapterSortOption: ChapterSortOption = .chapterNumber

    enum ChapterFilter: String, CaseIterable {
        case all        = "All"
        case unread     = "Unread"
        case downloaded = "Downloaded"
    }

    enum ChapterSortOption: String, CaseIterable {
        case chapterNumber = "Chapter Number"
        case name          = "Name"
    }

    // Feature 3 — Storage size
    @State private var storageSizeLabel: String? = nil

    // Feature 4 — Chapter selection
    @State private var isSelectingChapters = false
    @State private var selectedChapterIds: Set<String> = []
    @State private var chapterForNav: Chapter? = nil

    // Feature 5 — Scanlator filter
    @State private var scanlatorFilter: String? = nil

    // Feature 6 — Custom cover
    @State private var showCoverPicker = false
    @State private var selectedCoverItem: PhotosPickerItem? = nil

    // Feature 7 — Notes
    @State private var showNotesSheet = false
    @State private var notesText: String = ""

    // AniList score
    @State private var aniListScore: Int? = nil

    init(manga: Manga) {
        _manga = State(initialValue: manga)
    }

    // MARK: - Resume helpers

    private var resumeChapter: Chapter? {
        guard !chapters.isEmpty else { return nil }
        // In-progress (partially read) chapter
        if let partial = chapters.first(where: { $0.lastPageRead > 0 && !$0.isRead }) {
            return partial
        }
        // First unread chapter in ascending order
        if let firstUnread = chapters.first(where: { !$0.isRead }) {
            return firstUnread
        }
        // All read — go back to last chapter
        return chapters.last
    }

    private var hasStartedReading: Bool {
        chapters.contains { $0.isRead || $0.lastPageRead > 0 }
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
                    // Cover + meta
                    HStack(alignment: .top, spacing: 14) {
                        Group {
                            if let customPath = manga.customCoverPath,
                               let uiImage = UIImage(contentsOfFile: customPath) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(2 / 3, contentMode: .fill)
                            } else {
                                AsyncImage(url: manga.coverURL) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(2 / 3, contentMode: .fill)
                                } placeholder: {
                                    Rectangle()
                                        .fill(Color.secondary.opacity(0.3))
                                        .aspectRatio(2 / 3, contentMode: .fit)
                                }
                            }
                        }
                        .frame(width: 110)
                        .cornerRadius(10)
                        .clipped()
                        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)

                        VStack(alignment: .leading, spacing: 7) {
                            Text(manga.title)
                                .font(.title3)
                                .fontWeight(.bold)
                                .fixedSize(horizontal: false, vertical: true)

                            if let author = manga.author, !author.isEmpty {
                                Label(author, systemImage: "person")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            if let sourceName = ExtensionManager.shared.installed
                                .first(where: { $0.id == manga.sourceId })?.name {
                                Label(sourceName, systemImage: "puzzlepiece.extension")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            HStack(spacing: 8) {
                                StatusBadge(status: manga.status)

                                if let score = aniListScore {
                                    Label("\(score)%", systemImage: "star.fill")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.orange)
                                }

                                if manga.inLibrary {
                                    ReadingStatusMenu(readingStatus: manga.readingStatus) { newStatus in
                                        Task { await updateReadingStatus(newStatus) }
                                    }
                                }
                            }
                        }

                        Spacer(minLength: 0)
                    }

                    // Genre chips
                    if !manga.genres.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(manga.genres, id: \.self) { genre in
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
                    if !isLoadingChapters && !chapters.isEmpty && bridge != nil {
                        Button {
                            if let ch = resumeChapter {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                chapterForNav = ch
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
                    Text(manga.summary ?? "No synopsis available.")
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

            // MARK: Notes
            Section("Notes") {
                if let notes = manga.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
                Button(manga.notes?.isEmpty == false ? "Edit note" : "Add a note") {
                    notesText = manga.notes ?? ""
                    showNotesSheet = true
                }
                .font(.subheadline)
                .foregroundStyle(.tint)
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
                    scanlatorChipRow
                    let sorted: [Chapter] = {
                        switch chapterSortOption {
                        case .chapterNumber:
                            return chaptersDescending ? Array(chapters.reversed()) : chapters
                        case .name:
                            return chapters.sorted { chaptersDescending ? $0.name > $1.name : $0.name < $1.name }
                        }
                    }()
                    let filtered: [Chapter] = {
                        let base: [Chapter]
                        switch chapterFilter {
                        case .all:        base = sorted
                        case .unread:     base = sorted.filter { !$0.isRead }
                        case .downloaded: base = sorted.filter { $0.isDownloaded }
                        }
                        if let s = scanlatorFilter { return base.filter { $0.scanlator == s } }
                        return base
                    }()
                    let visible = Array(filtered.prefix(displayedChapterCount).enumerated())
                    ForEach(visible, id: \.element.id) { _, chapter in
                        ChapterRow(
                            chapter: chapter,
                            manga: manga,
                            bridge: bridge,
                            isSelecting: isSelectingChapters,
                            isSelected: selectedChapterIds.contains(chapter.id),
                            onTap: {
                                if isSelectingChapters {
                                    withAnimation(.spring(duration: 0.15)) {
                                        if selectedChapterIds.contains(chapter.id) {
                                            selectedChapterIds.remove(chapter.id)
                                        } else {
                                            selectedChapterIds.insert(chapter.id)
                                        }
                                    }
                                } else if bridge != nil {
                                    chapterForNav = chapter
                                }
                            },
                            onLongPress: {
                                guard !isSelectingChapters else { return }
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                withAnimation(.spring(duration: 0.2)) {
                                    isSelectingChapters = true
                                    selectedChapterIds = [chapter.id]
                                }
                            },
                            onToggleRead: {
                                let id = chapter.id
                                let newRead = !chapter.isRead
                                Task.detached { try? ChapterQueries.setRead(chapterId: id, isRead: newRead) }
                                chapters = chapters.map { ch in
                                    ch.id == id ? { var c = ch; c.isRead = newRead; return c }() : ch
                                }
                            },
                            onMarkPreviousRead: {
                                guard let pos = chapters.firstIndex(where: { $0.id == chapter.id }),
                                      pos > 0 else { return }
                                let ids = chapters[0..<pos].filter { !$0.isRead }.map { $0.id }
                                guard !ids.isEmpty else { return }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                let markSet = Set(ids)
                                Task.detached { ids.forEach { try? ChapterQueries.setRead(chapterId: $0, isRead: true) } }
                                chapters = chapters.map { ch in
                                    markSet.contains(ch.id) ? { var c = ch; c.isRead = true; return c }() : ch
                                }
                            }
                        )
                    }
                    if filtered.count > displayedChapterCount {
                        Button("Load \(min(50, filtered.count - displayedChapterCount)) more") {
                            displayedChapterCount += 50
                        }
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    } else if filtered.isEmpty && chapterFilter != .all {
                        Text("No \(chapterFilter.rawValue.lowercased()) chapters")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                }
            } header: {
                chapterSectionHeader
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await loadChapters() }
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
                    let sortedChapters: [Chapter] = {
                        switch chapterSortOption {
                        case .chapterNumber:
                            return chaptersDescending ? Array(chapters.reversed()) : chapters
                        case .name:
                            return chapters.sorted { chaptersDescending ? $0.name > $1.name : $0.name < $1.name }
                        }
                    }()
                    let filteredChapters: [Chapter] = {
                        switch chapterFilter {
                        case .all:        return sortedChapters
                        case .unread:     return sortedChapters.filter { !$0.isRead }
                        case .downloaded: return sortedChapters.filter { $0.isDownloaded }
                        }
                    }()
                    let visibleIds = Set(filteredChapters.prefix(displayedChapterCount).map { $0.id })
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
                            showCoverPicker = true
                        } label: {
                            Label("Change cover", systemImage: "photo")
                        }

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

                        if !chapters.isEmpty {
                            Button {
                                Task { await markAllChapters(read: true) }
                            } label: {
                                Label("Mark all as read", systemImage: "checkmark.circle.fill")
                            }
                            Button {
                                Task { await markAllChapters(read: false) }
                            } label: {
                                Label("Mark all as unread", systemImage: "circle")
                            }
                            Divider()
                        }

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
        .onAppear { Task { await refreshChapterStates() } }
        .onChange(of: downloadManager.completedDownloadCount) { _, _ in
            Task { await refreshChapterStates() }
        }
        .onChange(of: chapterForNav) { old, new in
            // User returned from reader — wait for DB writes to finish then refresh
            guard new == nil, old != nil else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                await refreshChapterStates()
            }
        }
        .navigationDestination(item: $chapterForNav) { chapter in
            if let b = bridge {
                ChapterReaderView(
                    manga: manga,
                    bridge: b,
                    chapters: chapters,
                    chapterIndex: chapters.firstIndex(where: { $0.id == chapter.id }) ?? 0
                )
            }
        }
        .task { await loadChapters() }
        .task { await touchLastRead() }
        .task { await loadCategories() }
        .task { computeStorageSize() }
        .task { notesText = manga.notes ?? "" }
        .task { aniListScore = await AniListService.shared.fetchScore(title: manga.title, isManga: true) }
        .sheet(isPresented: $showNotesSheet) {
            NotesEditorSheet(mangaTitle: manga.title, text: $notesText) {
                let id = manga.id
                let saved = notesText.isEmpty ? nil : notesText
                manga.notes = saved
                Task.detached { try? MangaQueries.updateNotes(mangaId: id, notes: saved) }
            }
        }
        .photosPicker(isPresented: $showCoverPicker, selection: $selectedCoverItem, matching: .images)
        .onChange(of: selectedCoverItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                let coversDir = FileManager.default
                    .urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Covers")
                try? FileManager.default.createDirectory(at: coversDir, withIntermediateDirectories: true)
                let fileURL = coversDir.appendingPathComponent("\(manga.id).jpg")
                try? data.write(to: fileURL)
                manga.customCoverPath = fileURL.path
                let updated = manga
                Task.detached { try? MangaQueries.update(updated) }
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
    }

    // MARK: - Chapter Section Header

    private var chapterSectionHeader: some View {
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
            if let size = storageSizeLabel {
                Text("· \(size)")
                    .foregroundStyle(.secondary)
            }
            Spacer()

            // Filter menu
            Menu {
                ForEach(ChapterFilter.allCases, id: \.self) { filter in
                    Button {
                        chapterFilter = filter
                        displayedChapterCount = 50
                    } label: {
                        HStack {
                            Text(filter.rawValue)
                            if chapterFilter == filter {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: chapterFilter == .all
                      ? "line.3.horizontal.decrease"
                      : "line.3.horizontal.decrease.circle.fill")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)

            // Sort option + direction
            Menu {
                ForEach(ChapterSortOption.allCases, id: \.self) { option in
                    Button {
                        withAnimation(.spring(duration: 0.2)) { chapterSortOption = option }
                    } label: {
                        HStack {
                            Text(option.rawValue)
                            if chapterSortOption == option { Image(systemName: "checkmark") }
                        }
                    }
                }
                Divider()
                Button {
                    withAnimation(.spring(duration: 0.2)) { chaptersDescending.toggle() }
                } label: {
                    Label(chaptersDescending ? "Descending" : "Ascending",
                          systemImage: chaptersDescending ? "arrow.down" : "arrow.up")
                }
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

    // MARK: - Scanlator Chip Row

    @ViewBuilder
    private var scanlatorChipRow: some View {
        let available = Array(Set(chapters.compactMap { $0.scanlator })).sorted()
        if available.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Button("All") { scanlatorFilter = nil }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(scanlatorFilter == nil ? Color.accentColor : Color.gray)
                    ForEach(available, id: \.self) { s in
                        Button(s) {
                            scanlatorFilter = scanlatorFilter == s ? nil : s
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(scanlatorFilter == s ? Color.accentColor : Color.gray)
                    }
                }
                .padding(.vertical, 2)
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 2, trailing: 12))
        }
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

    // MARK: - Refresh Chapter States

    /// Re-reads persisted state (isRead, isDownloaded, progress, lastPageRead) from DB
    /// and merges it into the in-memory chapters array. Lightweight — no network call.
    private func refreshChapterStates() async {
        guard !chapters.isEmpty else { return }
        let mangaId = manga.id
        let saved = await Task.detached(priority: .userInitiated) {
            (try? ChapterQueries.fetchAll(mangaId: mangaId)) ?? []
        }.value
        guard !saved.isEmpty else { return }
        let savedMap = Dictionary(uniqueKeysWithValues: saved.map { ($0.id, $0) })
        chapters = chapters.map { ch in
            guard let p = savedMap[ch.id] else { return ch }
            var merged = ch
            merged.isRead       = p.isRead
            merged.isDownloaded = p.isDownloaded
            merged.progress     = p.progress
            merged.lastPageRead = p.lastPageRead
            merged.readAt       = p.readAt
            return merged
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
        guard manga.inLibrary, !AppSettings.shared.isIncognito else { return }
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

        guard let ext = ExtensionManager.shared.installed.first(where: { $0.id == sourceId }) else {
            // Extension not installed — show whatever chapters are already in DB
            let saved = await Task.detached(priority: .userInitiated) {
                (try? ChapterQueries.fetchAll(mangaId: mangaId)) ?? []
            }.value
            chapters = saved
            isLoadingChapters = false
            return
        }

        isLoadingChapters = true

        let loadedBridge = ExtensionManager.shared.bridge(for: ext)
        let (loadedChapters, mangayomiMeta) = await Task.detached(priority: .userInitiated) {
            let chapters = loadedBridge?.getChapterList(mangaPath: mangaPath, mangaId: mangaId) ?? []
            let meta = loadedBridge?.lastMangayomiMeta
            return (chapters, meta)
        }.value

        // Apply Mangayomi detail metadata (synopsis, cover, status) if missing
        if let meta = mangayomiMeta {
            if let summary = meta.summary, !summary.isEmpty, (manga.summary == nil || manga.summary!.isEmpty) {
                manga.summary = summary
            }
            if let coverURL = meta.coverURL, manga.coverURL == nil {
                manga.coverURL = coverURL
            }
            if let status = meta.status, !status.isEmpty {
                let mapped = MangaStatus(rawValue: status.lowercased()) ?? .unknown
                if mapped != .unknown { manga.status = mapped }
            }
            let updated = manga
            Task.detached { try? MangaQueries.update(updated) }
        }

        // Ensure manga row exists first (FK constraint on chapter.mangaId),
        // then insert chapters — INSERT OR IGNORE preserves existing read/download state.
        // Manga INSERT OR IGNORE is a no-op for library manga; creates a browse-only row otherwise.
        let mangaSnapshot = manga
        await Task.detached(priority: .userInitiated) {
            try? ChapterQueries.insertMangaAndChapters(manga: mangaSnapshot, chapters: loadedChapters)
        }.value

        bridge = loadedBridge

        // Fetch persisted chapters from DB (off main thread per GRDB rule)
        let saved = await Task.detached(priority: .userInitiated) {
            (try? ChapterQueries.fetchAll(mangaId: mangaId)) ?? []
        }.value

        if loadedChapters.isEmpty {
            // API returned nothing (network failure, Cloudflare block, etc.) —
            // fall back to DB so previously-loaded chapters remain accessible.
            chapters = saved
        } else {
            let savedMap = Dictionary(uniqueKeysWithValues: saved.map { ($0.id, $0) })
            chapters = loadedChapters.map { ch in
                guard let persisted = savedMap[ch.id] else { return ch }
                var merged = ch
                merged.isRead = persisted.isRead
                merged.isDownloaded = persisted.isDownloaded
                merged.readingSeconds = persisted.readingSeconds
                merged.progress = persisted.progress
                merged.lastPageRead = persisted.lastPageRead
                merged.readAt = persisted.readAt
                return merged
            }
        }

        isLoadingChapters = false
    }

    // MARK: - Mark Selected Read/Unread

    private func markSelected(read: Bool) async {
        let ids = selectedChapterIds
        let mangaId = manga.id
        // When marking as read, collect downloaded chapters so we can auto-delete
        let downloadedIds: Set<String> = read
            ? Set(chapters.filter { ids.contains($0.id) && $0.isDownloaded }.map { $0.id })
            : []
        await Task.detached(priority: .userInitiated) {
            for id in ids {
                try? ChapterQueries.setRead(chapterId: id, isRead: read)
            }
            // Auto-delete downloaded files when marking as read
            for id in downloadedIds {
                let dir = FileManager.default
                    .urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Downloads/\(mangaId)/\(id)")
                try? FileManager.default.removeItem(at: dir)
                try? DownloadQueries.markNotDownloaded(chapterId: id)
            }
        }.value
        // Update in-memory state
        chapters = chapters.map { ch in
            if ids.contains(ch.id) {
                var updated = ch
                updated.isRead = read
                if downloadedIds.contains(ch.id) { updated.isDownloaded = false }
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

    // MARK: - Mark All Chapters

    private func markAllChapters(read: Bool) async {
        let ids = Set(chapters.map { $0.id })
        let mangaId = manga.id
        let downloadedIds: Set<String> = read
            ? Set(chapters.filter { $0.isDownloaded }.map { $0.id })
            : []
        await Task.detached(priority: .userInitiated) {
            for id in ids {
                try? ChapterQueries.setRead(chapterId: id, isRead: read)
            }
            if read {
                for id in downloadedIds {
                    let dir = FileManager.default
                        .urls(for: .documentDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("Downloads/\(mangaId)/\(id)")
                    try? FileManager.default.removeItem(at: dir)
                    try? DownloadQueries.markNotDownloaded(chapterId: id)
                }
            }
        }.value
        chapters = chapters.map { ch in
            var updated = ch
            updated.isRead = read
            if downloadedIds.contains(ch.id) { updated.isDownloaded = false }
            return updated
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
    var onLongPress: (() -> Void)? = nil
    var onToggleRead: (() -> Void)? = nil
    var onMarkPreviousRead: (() -> Void)? = nil

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
                // Subtitle: date + page progress
                HStack(spacing: 4) {
                    if let readAt = chapter.readAt {
                        Text(readAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let number = chapter.chapterNumber {
                        Text("Chapter \(number, specifier: "%.1f")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if chapter.lastPageRead > 0 && !chapter.isRead {
                        Text("· Page \(chapter.lastPageRead + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .opacity(chapter.isRead ? 0.45 : 1.0)

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
        .onTapGesture { onTap?() }
        .onLongPressGesture(minimumDuration: 0.4) { onLongPress?() }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
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
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !isSelecting {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onToggleRead?()
                } label: {
                    Label(chapter.isRead ? "Unread" : "Read",
                          systemImage: chapter.isRead ? "circle" : "checkmark.circle.fill")
                }
                .tint(chapter.isRead ? .orange : .green)
                if let markPrev = onMarkPreviousRead {
                    Button(action: markPrev) {
                        Label("Mark previous", systemImage: "checkmark.circle")
                    }
                    .tint(.blue)
                }
            }
        }
    }
}

// MARK: - ReadingStatusMenu

struct ReadingStatusMenu: View {
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

// MARK: - NotesEditorSheet

struct NotesEditorSheet: View {
    let mangaTitle: String
    @Binding var text: String
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .padding(12)
                .navigationTitle("Notes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") {
                            onSave()
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
        .presentationDetents([.medium, .large])
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
