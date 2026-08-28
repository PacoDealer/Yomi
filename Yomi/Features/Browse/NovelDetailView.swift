import SwiftUI
import PhotosUI
import Kingfisher

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
    @State private var showNotesSheet = false
    @State private var notesText: String = ""
    @State private var showCFBypass = false
    @State private var isBypassing = false
    @State private var autoBypassFailed = false
    @State private var bypassAttempted = false
    @State private var showCoverPicker = false
    @State private var selectedCoverItem: PhotosPickerItem? = nil
    @State private var isSelectingChapters = false
    @State private var selectedChapterIds: Set<String> = []
    @State private var chapterSearchText: String = ""

    @Environment(\.yomiCanvas) private var canvas
    @Environment(\.dismiss) private var dismiss

    init(novel: Novel, bridge: JSBridge? = nil) {
        _novel = State(initialValue: novel)
        _bridge = State(initialValue: bridge)
        _isInLibrary = State(initialValue: novel.inLibrary)
        _novelReadingStatus = State(initialValue: novel.readingStatus)
    }

    // MARK: - Resume helpers

    private var resumeChapter: NovelChapter? {
        // In-progress: scroll saved (any amount) or readAt touched but not fully read
        if let inProgress = chapters.first(where: {
            !$0.isRead && (($0.lastScrollPercent ?? 0) > 0.01 || $0.readAt != nil)
        }) { return inProgress }
        // First unread
        if let firstUnread = chapters.first(where: { !$0.isRead }) { return firstUnread }
        // All read — return last
        return chapters.last
    }

    private var hasStartedReading: Bool {
        chapters.contains { $0.isRead || $0.readAt != nil || ($0.lastScrollPercent ?? 0) > 0.01 }
    }

    private var displayedChapters: [NovelChapter] {
        var base = chapterFilterUnread ? chapters.filter { !$0.isRead } : chapters
        if !chapterSearchText.isEmpty {
            base = base.filter { $0.name.localizedStandardContains(chapterSearchText) }
        }
        return chaptersDescending ? base.reversed() : base
    }

    private var visibleChapterIds: Set<String> {
        Set(displayedChapters.map { $0.id })
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

    /// Full-bleed blurred cover backdrop with dark scrim, per DESIGN_SYSTEM §14.
    private var backdrop: some View {
        ZStack {
            Group {
                if let customPath = novel.resolvedCustomCoverPath,
                   let uiImage = UIImage(contentsOfFile: customPath) {
                    Image(uiImage: uiImage).resizable().aspectRatio(contentMode: .fill)
                } else {
                    KFImage(novel.coverURL)
                        .placeholder { canvas.surface1 }
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
            .blur(radius: 30)
            .overlay(canvas.bg.opacity(0.3))

            LinearGradient(
                colors: [canvas.bg.opacity(0.15), canvas.bg.opacity(0.55), canvas.bg],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
        List {
            headerSection
            synopsisSection
            notesSection
            chaptersSection
        }
        .listStyle(.insetGrouped)
        .refreshable { await loadChapters() }
        .navigationTitle(isSelectingChapters
            ? (selectedChapterIds.isEmpty ? "Select" : "\(selectedChapterIds.count) selected")
            : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isSelectingChapters ? .visible : .hidden, for: .navigationBar)
        .navigationDestination(item: $chapterForNav) { ch in
            if let b = bridge, let idx = chapters.firstIndex(where: { $0.id == ch.id }) {
                TextReaderView(novel: novel, bridge: b, chapters: chapters, startIndex: idx)
            }
        }
        .toolbar {
            if isSelectingChapters {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        withAnimation(.spring(duration: 0.2)) {
                            isSelectingChapters = false
                            selectedChapterIds = []
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(selectedChapterIds.count == visibleChapterIds.count ? "Deselect All" : "Select All") {
                        withAnimation(.spring(duration: 0.15)) {
                            if selectedChapterIds.count == visibleChapterIds.count {
                                selectedChapterIds = []
                            } else {
                                selectedChapterIds = visibleChapterIds
                            }
                        }
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            if !isSelectingChapters {
                glassNavBar
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelectingChapters {
                novelSelectionActionBar
            }
        }
        .sheet(isPresented: $showCategorySheet) {
            NavigationStack {
                List {
                    ForEach(allCategories) { cat in
                        HStack {
                            Text(cat.name)
                            Spacer()
                            if assignedCategoryIds.contains(cat.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task { await toggleCategory(cat) }
                        }
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
        .task { await loadChaptersWithBypass() }
        .task { await loadCategories() }
        .task { aniListScore = await AniListService.shared.fetchScore(title: novel.title, isManga: false) }
        .task { notesText = novel.notes ?? "" }
        .overlay {
            if isBypassing {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text("Bypassing Cloudflare…")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if autoBypassFailed {
                HStack(spacing: 10) {
                    Image(systemName: "shield.slash").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-bypass failed")
                            .font(.subheadline).fontWeight(.medium)
                        Text("Tap the shield button to bypass manually.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { autoBypassFailed = false } label: {
                        Image(systemName: "xmark").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.bar)
            }
        }
        .sheet(isPresented: $showNotesSheet) {
            NotesEditorSheet(mangaTitle: novel.title, text: $notesText) {
                let saved = notesText.isEmpty ? nil : notesText
                novel.notes = saved
                let novelId = novel.id
                let text = notesText
                Task.detached { try? NovelQueries.updateNotes(novelId: novelId, notes: text) }
            }
        }
        .sheet(isPresented: $showCFBypass) {
            CFBypassView(initialURL: bridge?.cfBlockedURL ?? "https://") {
                bridge?.clearCFBlock()
                Task { await loadChapters() }
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
                let fileURL = coversDir.appendingPathComponent("\(novel.id).jpg")
                try? data.write(to: fileURL)
                novel.customCoverPath = "Covers/\(novel.id).jpg"
                let updated = novel
                Task.detached { try? NovelQueries.upsert(updated) }
            }
        }
        .onChange(of: chapterForNav) { old, new in
            guard new == nil, old != nil else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                await refreshChaptersFromDB()
            }
        }
        .onChange(of: isLoadingChapters) { _, loading in
            guard !loading, let resume = resumeChapter else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                withAnimation { proxy.scrollTo("ch_\(resume.id)", anchor: .center) }
            }
        }
        } // ScrollViewReader
    }

    // MARK: - Glass nav bar (DESIGN_SYSTEM §14 — floating chrome over the backdrop)

    private var glassNavBar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
            }
            .glassChip()

            Spacer()

            Button {
                isInLibrary.toggle()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task { await toggleLibrary() }
            } label: {
                Image(systemName: isInLibrary ? "heart.fill" : "heart")
                    .foregroundStyle(isInLibrary ? Color.accentColor : .primary)
            }
            .glassChip()

            Menu {
                Button {
                    showCategorySheet = true
                } label: {
                    Label("Edit categories", systemImage: "tag")
                }
                .disabled(!isInLibrary)

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
                Image(systemName: "ellipsis")
            }
            .glassChip()
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    // MARK: - Sections

    @ViewBuilder private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                ZStack(alignment: .bottomLeading) {
                    backdrop
                        .frame(height: 230)
                        .clipped()

                    HStack(alignment: .bottom, spacing: 14) {
                        Group {
                            if let customPath = novel.resolvedCustomCoverPath,
                               let uiImage = UIImage(contentsOfFile: customPath) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(2 / 3, contentMode: .fill)
                            } else {
                                CoverImage(url: novel.coverURL)
                            }
                        }
                        .frame(width: 110, height: 162)
                        .clipShape(RoundedRectangle(cornerRadius: YomiTokens.Radius.cover))
                        .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 6)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(novel.title)
                                .font(YomiTokens.Font.grotesk(22, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)

                            if let author = novel.author {
                                Text(author)
                                    .font(YomiTokens.Font.grotesk(14))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .lineLimit(1)
                            }

                            if let sourceName = ExtensionManager.shared.installed
                                .first(where: { $0.id == novel.sourceId })?.name {
                                Text(sourceName.uppercased())
                                    .font(YomiTokens.Font.mono(11))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .lineLimit(1)
                            }

                            HStack(spacing: 8) {
                                Text(Notation.status(novel.status))
                                    .font(YomiTokens.Font.mono(10))
                                    .tracking(0.4)
                                    .foregroundStyle(.white.opacity(0.7))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))

                                if let score = aniListScore {
                                    Text("\(score)%")
                                        .font(YomiTokens.Font.mono(11, bold: true))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .padding(.bottom, 4)
                    }
                    .padding(.horizontal, 16)
                    .offset(y: 12)
                }
                .padding(.bottom, 12)

                if isInLibrary {
                    ReadingStatusMenu(readingStatus: novelReadingStatus) { newStatus in
                        Task { await updateReadingStatus(newStatus) }
                    }
                    .padding(.horizontal, 16)
                }

                if !novel.genres.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(novel.genres, id: \.self) { genre in
                                Text(genre).font(YomiTokens.Font.grotesk(12))
                                    .foregroundStyle(canvas.textPrimary)
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(canvas.surface2, in: Capsule())
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                // Reading progress bar
                if !chapters.isEmpty {
                    let readCount = chapters.filter { $0.isRead }.count
                    if readCount > 0 {
                        let totalSecs = chapters.reduce(0) { $0 + $1.readingSeconds }
                        VStack(alignment: .leading, spacing: 3) {
                            ProgressView(value: Double(readCount), total: Double(chapters.count))
                                .tint(.accentColor)
                            let fraction = Double(readCount) / Double(chapters.count)
                            let time = Notation.readingTime(seconds: totalSecs)
                            let pctText = Text(Notation.progress(fraction)).foregroundStyle(Color.accentColor)
                            Text("\(readCount) OF \(chapters.count) · \(pctText)\(time.isEmpty ? "" : " · \(time)")")
                                .font(YomiTokens.Font.mono(11))
                                .foregroundStyle(canvas.textSecondary)
                        }
                        .padding(.horizontal, 16)
                    }
                }

                if !isLoadingChapters && !chapters.isEmpty {
                    Button {
                        if let ch = resumeChapter {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            chapterForNav = ch
                            touchLastReadAt()
                        }
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: hasStartedReading ? "play.fill" : "book.fill")
                                .font(.system(size: 13))
                            Text(resumeButtonTitle)
                                .font(YomiTokens.Font.grotesk(15, weight: .medium))
                        }
                        .foregroundStyle(AppSettings.shared.accentForeground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color.accentColor, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 6)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder private var synopsisSection: some View {
        Section("Synopsis") {
            VStack(alignment: .leading, spacing: 6) {
                Text(novel.summary ?? "No synopsis available.")
                    .font(.subheadline)
                    .lineLimit(synopsisExpanded ? nil : 4)
                    .textSelection(.enabled)
                Button(synopsisExpanded ? "Less" : "More") { synopsisExpanded.toggle() }
                    .font(.subheadline).buttonStyle(.plain).foregroundStyle(.tint)
            }
        }
    }

    @ViewBuilder private var notesSection: some View {
        Section("Notes") {
            if let notes = novel.notes, !notes.isEmpty {
                Text(notes).font(.subheadline).foregroundStyle(.primary).textSelection(.enabled)
            }
            Button(novel.notes?.isEmpty == false ? "Edit note" : "Add a note") {
                notesText = novel.notes ?? ""
                showNotesSheet = true
            }
            .font(.subheadline).foregroundStyle(.tint)
        }
    }

    @ViewBuilder private var chaptersSection: some View {
        Section {
            if isLoadingChapters {
                HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 4)
            } else if chapters.isEmpty {
                if let cfURL = bridge?.cfBlockedURL, !cfURL.isEmpty {
                    VStack(spacing: 10) {
                        Label("Cloudflare blocked this source.", systemImage: "shield.slash")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button {
                            showCFBypass = true
                        } label: {
                            Label("Bypass Cloudflare", systemImage: "shield.slash")
                                .font(.subheadline)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                } else {
                    Text("No chapters found.").font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                if chapters.count > 30 {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.subheadline)
                        TextField("Search chapters", text: $chapterSearchText)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        if !chapterSearchText.isEmpty {
                            Button { chapterSearchText = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
                if displayedChapters.isEmpty && !chapterSearchText.isEmpty {
                    Text("No chapters matching \"\(chapterSearchText)\"")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(displayedChapters, id: \.id) { chapter in
                        chapterRow(chapter)
                            .id("ch_\(chapter.id)")
                    }
                }
            }
        } header: {
            HStack {
                Text("Chapters")
                    .font(YomiTokens.Font.grotesk(15, weight: .semibold))
                if !chapters.isEmpty {
                    let readCount = chapters.filter { $0.isRead }.count
                    if readCount > 0 {
                        Text("\(readCount) / \(chapters.count)")
                            .font(YomiTokens.Font.mono(12))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("(\(chapters.count))")
                            .font(YomiTokens.Font.mono(12))
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
                            .font(.caption).fontWeight(.semibold).foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                    Button {
                        withAnimation(.spring(duration: 0.2)) { chaptersDescending.toggle() }
                    } label: {
                        Image(systemName: chaptersDescending ? "arrow.down" : "arrow.up")
                            .font(.caption).fontWeight(.semibold).foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private func chapterRow(_ chapter: NovelChapter) -> some View {
        Button {
            if isSelectingChapters {
                withAnimation(.spring(duration: 0.15)) {
                    if selectedChapterIds.contains(chapter.id) {
                        selectedChapterIds.remove(chapter.id)
                    } else {
                        selectedChapterIds.insert(chapter.id)
                    }
                }
            } else {
                chapterForNav = chapter
                touchLastReadAt()
            }
        } label: {
            HStack(spacing: 10) {
                if isSelectingChapters {
                    let isSelected = selectedChapterIds.contains(chapter.id)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        // `canvas` was already in scope here and still bypassed (Known Issue #118).
                        .foregroundStyle(isSelected ? Color.accentColor : canvas.textSecondary)
                        .font(.title3)
                } else {
                    Circle()
                        .fill(chapter.isRead ? Color.clear : Color.accentColor)
                        .frame(width: 6, height: 6)
                }
                NovelChapterRow(chapter: chapter)
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !isSelectingChapters {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    toggleRead(chapter)
                } label: {
                    Label(chapter.isRead ? "Unread" : "Read",
                          systemImage: chapter.isRead ? "circle" : "checkmark.circle.fill")
                }
                .tint(chapter.isRead ? .orange : .green)
                Button {
                    guard let pos = chapters.firstIndex(where: { $0.id == chapter.id }),
                          pos > 0 else { return }
                    let ids = chapters[0..<pos].filter { !$0.isRead }.map { $0.id }
                    guard !ids.isEmpty else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    let markSet = Set(ids)
                    let novelId = novel.id
                    Task.detached { ids.forEach { try? NovelQueries.markRead(chapterId: $0, novelId: novelId) } }
                    chapters = chapters.map { ch in
                        markSet.contains(ch.id) ? { var c = ch; c.isRead = true; return c }() : ch
                    }
                } label: {
                    Label("Mark previous", systemImage: "checkmark.circle")
                }
                .tint(.blue)
            }
        }
        .onLongPressGesture {
            guard !isSelectingChapters else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(duration: 0.2)) {
                isSelectingChapters = true
                selectedChapterIds = [chapter.id]
            }
        }
    }

    // MARK: - Formatting

    // MARK: - Toggle Library

    private func toggleLibrary() async {
        var updated = novel
        updated.inLibrary = isInLibrary
        try? NovelQueries.upsert(updated)
        if isInLibrary, let defaultCatId = AppSettings.shared.defaultCategoryId {
            let novelId = novel.id
            Task.detached {
                try? CategoryQueries.assignNovel(novelId: novelId, categoryId: defaultCatId)
            }
        }
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
        let novelId = novel.id
        Task.detached {
            if nowRead {
                try? NovelQueries.markRead(chapterId: id, novelId: novelId)
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
        guard !AppSettings.shared.isIncognito else { return }
        var updated = novel
        updated.lastReadAt = Date()
        Task.detached { try? NovelQueries.upsert(updated) }
    }

    // MARK: - Load Chapters

    private func refreshChaptersFromDB() async {
        let novelId = novel.id
        let refreshed = await Task.detached(priority: .userInitiated) {
            (try? NovelQueries.fetchChapters(novelId: novelId)) ?? []
        }.value
        guard !refreshed.isEmpty else { return }
        chapters = refreshed
    }

    /// Auto-retries a background Cloudflare bypass before ever showing the user a blocked state,
    /// matching SourceBrowseView.loadWithBypass() — see finding #86. Falls back to the manual
    /// "Bypass Cloudflare" button (chaptersSection) only if the automatic attempt fails.
    private func loadChaptersWithBypass() async {
        bypassAttempted = false
        autoBypassFailed = false
        await loadChapters()
        guard chapters.isEmpty, !bypassAttempted,
              let cfURL = bridge?.cfBlockedURL, !cfURL.isEmpty,
              let url = URL(string: cfURL) else { return }
        bypassAttempted = true
        isBypassing = true
        let success = await CFBypassManager.autoBypass(url: url)
        bridge?.clearCFBlock()
        isBypassing = false
        if success {
            await loadChapters()
        } else {
            autoBypassFailed = true
        }
    }

    private func loadChapters() async {
        isLoadingChapters = true
        let novelId = novel.id
        let path = novel.path
        let sourceId = novel.sourceId

        // Always resolve a fresh bridge — reusing a bridge from SourceBrowseView risks
        // JSContext thread-safety issues when the context was last used on a different thread.
        if let ext = ExtensionManager.shared.installed.first(where: { $0.id == sourceId }) {
            bridge = ExtensionManager.shared.bridge(for: ext)
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

        if novel.inLibrary {
            // Persist to DB (INSERT OR IGNORE — preserves existing isRead/readingSeconds)
            await Task.detached {
                try? NovelQueries.insertAllIgnoringConflicts(fetched)
            }.value

            // Re-fetch from DB to merge persisted read state
            let merged = await Task.detached {
                (try? NovelQueries.fetchChapters(novelId: novelId)) ?? fetched
            }.value
            chapters = merged
        } else {
            // Browse-only (not in library) — no DB row exists, use remote data directly.
            // Sorted ascending (nulls last) since TextReaderView navigates purely by array
            // index and assumes ascending order — a source returning newest-first would
            // otherwise make Next/Prev go backward. Same bug class as Known Issue #50 for
            // manga; see finding #85.
            chapters = fetched.sorted { lhs, rhs in
                switch (lhs.chapterNumber, rhs.chapterNumber) {
                case let (l?, r?): return l < r
                case (nil, _?):    return false
                case (_?, nil):    return true
                case (nil, nil):   return false
                }
            }
        }
        isLoadingChapters = false
    }
}

// MARK: - Selection Action Bar

extension NovelDetailView {
    private var novelSelectionActionBar: some View {
        HStack(spacing: 0) {
            Button {
                markSelected(read: true)
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle")
                    Text("Read").font(.caption2)
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(selectedChapterIds.isEmpty)

            Button {
                markSelected(read: false)
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "circle")
                    Text("Unread").font(.caption2)
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(selectedChapterIds.isEmpty)
        }
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func markSelected(read: Bool) {
        let ids = selectedChapterIds
        let now = Date()
        chapters = chapters.map { ch in
            guard ids.contains(ch.id) else { return ch }
            var updated = ch
            updated.isRead = read
            updated.readAt = read ? now : nil
            return updated
        }
        let novelId = novel.id
        Task.detached {
            for id in ids {
                if read {
                    try? NovelQueries.markRead(chapterId: id, novelId: novelId)
                } else {
                    try? NovelQueries.markUnread(chapterId: id)
                }
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(duration: 0.2)) {
            isSelectingChapters = false
            selectedChapterIds = []
        }
    }
}

// MARK: - NovelChapterRow

private struct NovelChapterRow: View {
    let chapter: NovelChapter

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(chapter.name)
                .font(YomiTokens.Font.grotesk(15))
                .foregroundStyle(chapter.isRead ? .secondary : .primary)
            if let release = chapter.releaseTime {
                Text(release)
                    .font(YomiTokens.Font.mono(11))
                    .foregroundStyle(.secondary)
            }
            if let pct = chapter.lastScrollPercent, pct > 0.02, !chapter.isRead {
                GeometryReader { geo in
                    Capsule()
                        .fill(Color.accentColor.opacity(0.5))
                        .frame(width: geo.size.width * CGFloat(min(pct, 1)), height: 2)
                }
                .frame(height: 2)
                .padding(.top, 2)
            }
        }
        .opacity(chapter.isRead ? 0.45 : 1.0)
        .padding(.vertical, 2)
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
                readingStatus: .none,
                notes: nil
            ),
            bridge: {
                guard let url = Bundle.main.url(forResource: "test-source", withExtension: "js"),
                      let b = JSBridge(scriptURL: url) else {
                    fatalError("test-source.js must be in the Debug target for Simulator previews")
                }
                return b
            }()
        )
    }
}
