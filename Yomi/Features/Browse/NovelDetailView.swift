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
    /// "All", "Unread" or "Bookmarked" (v28) — the same strings ChapterListPrefs saves for manga.
    @State private var chapterFilter: String = "All"
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
    @State private var chaptersShownBefore = 0   // "Show more" taps above / below the chapter window
    @State private var chaptersShownAfter = 0
    @State private var downloadedIds: Set<String> = []
    /// E15: library novels that look like the one being added (Mihon's duplicate dialog).
    @State private var duplicates: [(novel: Novel, chapterCount: Int)] = []
    @State private var showDuplicateDialog = false
    @State private var duplicateToOpen: Novel? = nil
    @State private var showDuplicate = false
    /// True once the header's buttons have scrolled away — the floating bar then gets a material
    /// background and the title, like Apple Music's album pages.
    @State private var scrolledPastHeader = false
    private var downloads: NovelDownloadManager { NovelDownloadManager.shared }

    @Environment(\.yomiCanvas) private var canvas
    @Environment(\.dismiss) private var dismiss

    init(novel: Novel, bridge: JSBridge? = nil) {
        _novel = State(initialValue: novel)
        _bridge = State(initialValue: bridge)
        _isInLibrary = State(initialValue: novel.inLibrary)
        _novelReadingStatus = State(initialValue: novel.readingStatus)
        let prefs = ChapterListPrefs.load(titleId: novel.id, defaultDescending: false)
        _chaptersDescending = State(initialValue: prefs.descending)
        _chapterFilter = State(initialValue: ["Unread", "Bookmarked"].contains(prefs.filter) ? prefs.filter : "All")
    }

    private var chapterListPrefs: ChapterListPrefs {
        ChapterListPrefs(descending: chaptersDescending, filter: chapterFilter,
                         sort: "Chapter Number")
    }

    // MARK: - Resume helpers

    private var resumeChapter: NovelChapter? { ResumeReading.novelChapter(in: chapters) }

    private var hasStartedReading: Bool {
        chapters.contains { $0.isRead || $0.readAt != nil || ($0.lastScrollPercent ?? 0) > 0.01 }
    }

    private var displayedChapters: [NovelChapter] {
        var base: [NovelChapter]
        switch chapterFilter {
        case "Unread":     base = chapters.filter { !$0.isRead }
        case "Bookmarked": base = chapters.filter(\.isBookmarked)
        default:           base = chapters
        }
        if !chapterSearchText.isEmpty {
            base = base.filter { $0.name.localizedStandardContains(chapterSearchText) }
        }
        return chaptersDescending ? base.reversed() : base
    }

    // MARK: - Chapter window (S144)

    /// Rows in the List at once. All 1,432 of Lord of the Mysteries made opening the page hang 754 ms and leaving
    /// it 1.7 s (simulator trace: SwiftUI builds and copies an item per row). Manga pages show 50 at a time; here a
    /// window around the Continue chapter, so the page still opens on where you are. Search shows every match,
    /// and select all / select range still cover the whole list (`displayedChapters`).
    static let chapterWindowStep = 100

    private func chapterWindow(_ shown: [NovelChapter]) -> Range<Int> {
        guard chapterSearchText.isEmpty, shown.count > 150 else { return shown.indices }
        let anchor = resumeChapter.flatMap { r in shown.firstIndex { $0.id == r.id } } ?? 0
        let lower = max(0, anchor - 30 - chaptersShownBefore)
        let upper = min(shown.count, anchor + 70 + chaptersShownAfter)
        return lower..<max(upper, min(shown.count, lower + 100))
    }

    private func showMoreChaptersButton(_ count: Int, up: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label("Show \(count) more", systemImage: up ? "arrow.up" : "arrow.down")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var visibleChapterIds: Set<String> {
        Set(displayedChapters.map { $0.id })
    }

    private var resumeButtonTitle: String {
        // "Continue" while chapters load, so the label doesn't flash "Start" → "Chapter 25".
        if chapters.isEmpty { return String(localized: "Continue") }
        guard hasStartedReading, let ch = resumeChapter else { return String(localized: "Start") }
        if let num = ch.chapterNumber {
            return Notation.chapter(num)
        }
        return String(localized: "Continue")
    }

    private var sourceName: String? {
        ExtensionManager.shared.installed.first(where: { $0.id == novel.sourceId })?.name
    }

    /// "Author · Ongoing · 887 chapters"
    private var metaLine: String {
        var parts: [String] = []
        if let author = novel.author, !author.isEmpty { parts.append(author) }
        if !novel.status.isEmpty { parts.append(Notation.status(novel.status)) }
        if !chapters.isEmpty { parts.append("\(chapters.count) chapters") }
        if let score = aniListScore { parts.append("\(score)%") }
        return parts.joined(separator: " · ")
    }

    /// Apple Music-style album backdrop: the cover blurred into a soft colour wash that fades into the
    /// canvas (S138, RESEARCH §26) — replaces the dark DESIGN_SYSTEM §14 scrim.
    private var backdrop: some View {
        Group {
            if let customPath = novel.resolvedCustomCoverPath,
               let uiImage = UIImage(contentsOfFile: customPath) {
                Image(uiImage: uiImage).resizable().aspectRatio(contentMode: .fill)
            } else {
                KFImage(novel.coverURL)
                    .coverSized()
                    .placeholder { canvas.bg }
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .blur(radius: 60)
        .saturation(1.4)
        .opacity(0.55)
        .mask(LinearGradient(colors: [.black, .black.opacity(0.6), .clear],
                             startPoint: .top, endPoint: .bottom))
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
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top > 410
        } action: { _, past in
            withMotion(.easeInOut(duration: 0.2)) { scrolledPastHeader = past }
        }
        // The header's cover tint runs up under the status bar, like an Apple Music album page.
        .ignoresSafeArea(edges: isSelectingChapters ? [] : .top)
        .background(canvas.bg.ignoresSafeArea())
        .refreshable { await loadChapters(force: true) }
        .navigationTitle(isSelectingChapters
            ? (selectedChapterIds.isEmpty ? "Select" : "\(selectedChapterIds.count) selected")
            : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isSelectingChapters ? .visible : .hidden, for: .navigationBar)
        .navigationBarStaysHidden(!isSelectingChapters)   // #206: an active search on the screen below
        // Selecting: Cancel is the way out and the select bar replaces the tab bar (Tachimanga).
        .navigationBarBackButtonHidden(isSelectingChapters)
        .toolbar(isSelectingChapters ? .hidden : .automatic, for: .tabBar)
        .onChange(of: chapterListPrefs) { _, prefs in
            prefs.save(titleId: novel.id)
            chaptersShownBefore = 0
            chaptersShownAfter = 0
        }
        .navigationDestination(isPresented: $showDuplicate) {
            if let duplicateToOpen { NovelDetailView(novel: duplicateToOpen) }
        }
        .confirmationDialog("Already in your library?", isPresented: $showDuplicateDialog, titleVisibility: .visible) {
            ForEach(duplicates, id: \.novel.id) { entry in
                Button("Open \(entry.novel.title)") {
                    duplicateToOpen = entry.novel
                    showDuplicate = true
                }
            }
            Button("Add Anyway") { Task { await setInLibrary(true) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            // No count when none are saved yet (never opened here) — "0 chapters" read like a broken entry.
            Text(duplicates.map { entry in
                let source = SourceStatus.sourceName(entry.novel.sourceId)
                let count = entry.chapterCount
                return count == 0 ? "\(entry.novel.title) — \(source)"
                                  : String(localized: "\(entry.novel.title) — \(source) · \(count) chapters")
            }.joined(separator: "\n"))
        }
        .navigationDestination(item: $chapterForNav) { ch in
            if bridge != nil || LocalLibrary.isLocalSourceId(novel.sourceId),
               let idx = chapters.firstIndex(where: { $0.id == ch.id }) {
                TextReaderView(novel: novel, bridge: bridge, chapters: chapters, startIndex: idx)
            }
        }
        .toolbar {
            if isSelectingChapters {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        withMotion(.spring(duration: 0.2)) {
                            isSelectingChapters = false
                            selectedChapterIds = []
                        }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // Tachimanga's selection toolbar: range, all, invert.
                    Button {
                        withMotion(.spring(duration: 0.15)) {
                            selectedChapterIds = ChapterSelection.range(selectedChapterIds, in: displayedChapters.map(\.id))
                        }
                    } label: { Image(systemName: "arrow.up.and.down") }
                    .accessibilityLabel("Select range")
                    .disabled(selectedChapterIds.count < 2)
                    Button {
                        withMotion(.spring(duration: 0.15)) {
                            selectedChapterIds = selectedChapterIds.count == visibleChapterIds.count ? [] : visibleChapterIds
                        }
                    } label: { Image(systemName: "checklist") }
                    .accessibilityLabel(selectedChapterIds.count == visibleChapterIds.count ? "Deselect all" : "Select all")
                    Button {
                        withMotion(.spring(duration: 0.15)) {
                            selectedChapterIds = visibleChapterIds.subtracting(selectedChapterIds)
                        }
                    } label: { Image(systemName: "circle.lefthalf.filled") }
                    .accessibilityLabel("Invert selection")
                }
            }
        }
        .overlay(alignment: .top) {
            if !isSelectingChapters {
                glassNavBar
            }
        }
        // After the floating bar, so its ⋯ menu (website, share) is covered too; Go Back is the way out.
        .safeModeCover(sourceId: novel.sourceId, genres: novel.genres)
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
            CFBypassView(initialURL: bridge?.cfBlockedURL ?? "https://", cookieJar: bridge?.cookieJar) {
                bridge?.clearCFBlock()
                Task { await loadChapters(force: true) }
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
                let novelId = novel.id
                Task.detached { try? NovelQueries.updateCustomCover(novelId: novelId, path: "Covers/\(novelId).jpg") }
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
            if !loading { refreshDownloaded() }
        }
        .onChange(of: downloads.completedCount) { _, _ in
            if let saved = downloads.lastSaved, saved.novelId == novel.id {
                downloadedIds.insert(saved.chapterId)
            }
        }
        .onChange(of: downloads.finishedBatchCount) { _, _ in refreshDownloaded() }
        .yomiToast(Binding(
            get: { NovelDownloadManager.shared.failureMessage },
            set: { NovelDownloadManager.shared.failureMessage = $0 }
        ))
        .yomiToast(Binding(
            get: { NetworkMonitor.shared.queuedNotice },
            set: { NetworkMonitor.shared.queuedNotice = $0 }
        ), isError: false)
        .onChange(of: isLoadingChapters) { _, loading in
            guard !loading, let resume = resumeChapter else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                withMotion { proxy.scrollTo(resume.id, anchor: .center) }
            }
        }
        } // ScrollViewReader
    }

    // MARK: - Glass nav bar (DESIGN_SYSTEM §14 — floating chrome over the backdrop)

    private var glassNavBar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .accessibilityLabel("Back")
                    .font(.system(size: 15, weight: .semibold))
            }
            .glassChip()

            Spacer()
            if scrolledPastHeader {
                Text(novel.title)
                    .font(.headline)
                    .foregroundStyle(canvas.textPrimary)
                    .lineLimit(1)
                    .transition(.opacity)
            }
            Spacer()

            Button {
                Task { await heartTapped() }
            } label: {
                Image(systemName: isInLibrary ? "heart.fill" : "heart")
                    .accessibilityLabel(isInLibrary ? Text("Remove from Library") : Text("Add to Library"))
                    .foregroundStyle(isInLibrary ? Color.accentColor : .primary)
            }
            .glassChip()

            Menu {
                if isInLibrary {
                    Picker(selection: Binding(
                        get: { novelReadingStatus },
                        set: { newStatus in Task { await updateReadingStatus(newStatus) } }
                    )) {
                        ForEach(ReadingStatus.allCases) { status in
                            Label(status.label, systemImage: status.systemImage).tag(status)
                        }
                    } label: {
                        Label("Reading status", systemImage: novelReadingStatus.systemImage)
                    }
                    .pickerStyle(.menu)
                }

                Button {
                    showCategorySheet = true
                } label: {
                    Label("Edit categories", systemImage: "tag")
                }
                .disabled(!isInLibrary)

                Button {
                    notesText = novel.notes ?? ""
                    showNotesSheet = true
                } label: {
                    Label(novel.notes?.isEmpty == false ? "Edit note" : "Add note", systemImage: "note.text")
                }

                Button {
                    showCoverPicker = true
                } label: {
                    Label("Change cover", systemImage: "photo")
                }

                Button {
                    withMotion(.spring(duration: 0.2)) {
                        isSelectingChapters = true
                        selectedChapterIds = []
                    }
                } label: {
                    Label("Select chapters", systemImage: "checkmark.circle")
                }
                .disabled(chapters.isEmpty)

                if !chapters.isEmpty {
                    if !downloadedIds.isEmpty {
                        Button(role: .destructive) {
                            downloads.deleteAll(novelId: novel.id)
                            downloadedIds = []
                        } label: {
                            Label("Delete downloads", systemImage: "trash")
                        }
                    }
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
                    .accessibilityLabel("More")
            }
            .glassChip()
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background {
            if scrolledPastHeader {
                Rectangle().fill(.bar).ignoresSafeArea(edges: .top)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder private var headerSection: some View {
        Section {
            VStack(spacing: 0) {
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
                .frame(width: 200, height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .coverHairline(cornerRadius: 8)
                .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
                .padding(.top, 116)

                Text(novel.title)
                    .font(.title2.bold())
                    .foregroundStyle(canvas.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20)

                if let sourceName {
                    Text(sourceName)
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 4)
                }

                if !metaLine.isEmpty {
                    Text(metaLine)
                        .font(.footnote)
                        .foregroundStyle(canvas.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                }

                HStack(spacing: 12) {
                    Button {
                        if let ch = resumeChapter {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            chapterForNav = ch
                            touchLastReadAt()
                        }
                    } label: {
                        Label(resumeButtonTitle, systemImage: "play.fill")
                            .detailPillLabel()
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoadingChapters || chapters.isEmpty)

                    if !LocalLibrary.isLocalSourceId(novel.sourceId) {
                    Menu {
                        Button("Next 10 unread") {
                            download(Array(chapters.filter { !$0.isRead }.prefix(10)))
                        }
                        Button("All unread") { download(chapters.filter { !$0.isRead }) }
                        Button("All chapters") { download(chapters) }
                    } label: {
                        Label("Download", systemImage: "arrow.down")
                            .detailPillLabel()
                    }
                    .disabled(chapters.isEmpty)
                    }
                }
                .padding(.top, 20)
            }
            .padding(.horizontal, YomiTokens.Layout.screenMargin)
            .frame(maxWidth: .infinity)
            .background(alignment: .top) {
                backdrop
                    .frame(height: 580)
                    .clipped()
                    .allowsHitTesting(false)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder private var synopsisSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                if let rawSummary = novel.summary, !rawSummary.isEmpty {
                    let summary = Notation.plainText(rawSummary)
                    VStack(alignment: .leading, spacing: 4) {
                        // Collapsed: one paragraph, so blank lines don't eat the three visible lines.
                        Text(synopsisExpanded ? summary
                             : summary.replacingOccurrences(of: #"\s*\n+\s*"#, with: " ", options: .regularExpression))
                            .font(.subheadline)
                            .foregroundStyle(canvas.textPrimary)
                            .lineLimit(synopsisExpanded ? nil : 3)
                            .textSelection(.enabled)
                        Button(synopsisExpanded ? "Less" : "More") { synopsisExpanded.toggle() }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(canvas.textSecondary)
                            .buttonStyle(.plain)
                    }
                }
                if !novel.genres.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(novel.genres, id: \.self) { genre in
                                Text(genre)
                                    .font(.footnote)
                                    .foregroundStyle(canvas.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(canvas.surface1, in: Capsule())
                            }
                        }
                        .padding(.horizontal, YomiTokens.Layout.screenMargin)
                    }
                    .padding(.horizontal, -YomiTokens.Layout.screenMargin)
                }
            }
            .padding(.top, 24)
            .listRowInsets(EdgeInsets(top: 0, leading: YomiTokens.Layout.screenMargin,
                                      bottom: 0, trailing: YomiTokens.Layout.screenMargin))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    /// Only shown once a note exists — adding one lives in the ⋯ menu (S138: less on screen).
    @ViewBuilder private var notesSection: some View {
        if let notes = novel.notes, !notes.isEmpty {
            Section {
                Button {
                    notesText = notes
                    showNotesSheet = true
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Note")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(canvas.textSecondary)
                        Text(notes)
                            .font(.subheadline)
                            .foregroundStyle(canvas.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                    .background(canvas.surface1, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
                .listRowInsets(EdgeInsets(top: 0, leading: YomiTokens.Layout.screenMargin,
                                          bottom: 0, trailing: YomiTokens.Layout.screenMargin))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
    }

    @ViewBuilder private var chaptersSection: some View {
        Section {
            chaptersHeaderRow
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
                    .background(canvas.surface1, in: Capsule())
                    .listRowInsets(EdgeInsets(top: 4, leading: YomiTokens.Layout.screenMargin,
                                              bottom: 8, trailing: YomiTokens.Layout.screenMargin))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                let shown = displayedChapters
                if shown.isEmpty && !chapterSearchText.isEmpty {
                    Text("No chapters matching \"\(chapterSearchText)\"")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    let window = chapterWindow(shown)
                    if window.lowerBound > 0 {
                        showMoreChaptersButton(min(Self.chapterWindowStep, window.lowerBound), up: true) {
                            chaptersShownBefore += Self.chapterWindowStep
                        }
                    }
                    NovelChapterList(chapters: Array(shown[window]),
                                     isSelecting: isSelectingChapters,
                                     selectedIds: selectedChapterIds,
                                     downloadedIds: downloadedIds,
                                     actions: chapterRowActions)
                        .equatable()
                    if window.upperBound < shown.count {
                        showMoreChaptersButton(min(Self.chapterWindowStep, shown.count - window.upperBound), up: false) {
                            chaptersShownAfter += Self.chapterWindowStep
                        }
                    }
                }
            }
        }
    }

    /// "Chapters   25 of 887 read" — a plain row, not a section header: a plain List pins headers, and
    /// with the cover tint running under the status bar the pinned title sat on top of the clock.
    @ViewBuilder private var chaptersHeaderRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Chapters")
                .font(.title2.bold())
                .foregroundStyle(canvas.textPrimary)
            if !chapters.isEmpty {
                let readCount = chapters.filter { $0.isRead }.count
                Text(verbatim: readCount > 0 ? "\(readCount) of \(chapters.count) read" : "\(chapters.count)")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(canvas.textSecondary)
            }
            Spacer()
            if !chapters.isEmpty {
                Menu {
                    Picker("Show", selection: $chapterFilter) {
                        Label("All chapters", systemImage: "list.bullet").tag("All")
                        Label("Unread only", systemImage: "circle").tag("Unread")
                        Label("Bookmarked", systemImage: "bookmark").tag("Bookmarked")
                    }
                    Picker("Order", selection: $chaptersDescending) {
                        Label("Oldest first", systemImage: "arrow.up").tag(false)
                        Label("Newest first", systemImage: "arrow.down").tag(true)
                    }
                } label: {
                    Image(systemName: chapterFilter != "All"
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                        .font(.title3)
                        .foregroundStyle(chapterFilter != "All" ? Color.accentColor : canvas.textSecondary)
                }
                .accessibilityLabel("Filter and sort")
            }
        }
        .padding(.top, 28)
        .padding(.bottom, 4)
        .listRowInsets(EdgeInsets(top: 0, leading: YomiTokens.Layout.screenMargin,
                                  bottom: 0, trailing: YomiTokens.Layout.screenMargin))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// What a chapter row does. Every closure only touches @State, whose storage outlives this struct copy, so
    /// a NovelChapterList skipped by `.equatable()` still acts on current state.
    private var chapterRowActions: NovelChapterList.Actions {
        NovelChapterList.Actions(
            tap: { chapter in
                if isSelectingChapters {
                    withMotion(.spring(duration: 0.15)) {
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
            },
            toggleRead: { chapter in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                toggleRead(chapter)
            },
            // Only saved chapters can carry a bookmark — a novel outside the library has no rows.
            toggleBookmark: isInLibrary ? { chapter in setBookmarked([chapter.id], !chapter.isBookmarked) } : nil,
            markPrevious: { chapter in
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
            },
            startSelecting: { chapter in
                guard !isSelectingChapters else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withMotion(.spring(duration: 0.2)) {
                    isSelectingChapters = true
                    selectedChapterIds = [chapter.id]
                }
            }
        )
    }

    // MARK: - Formatting

    // MARK: - Toggle Library

    /// Adding checks the library for the same work first (E15); removing goes straight through.
    private func heartTapped() async {
        if !isInLibrary {
            let snapshot = novel
            let found = await Task.detached(priority: .userInitiated) {
                (try? NovelQueries.possibleDuplicates(of: snapshot)) ?? []
            }.value
            if !found.isEmpty {
                duplicates = found
                showDuplicateDialog = true
                return
            }
        }
        await setInLibrary(!isInLibrary)
    }

    private func setInLibrary(_ inLibrary: Bool) async {
        isInLibrary = inLibrary
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        await toggleLibrary()
    }

    private func toggleLibrary() async {
        // Update the view's own copy: every later upsert of `novel` (touchLastReadAt on opening a
        // chapter, the metadata refresh) used to write back the stale inLibrary=false and silently
        // take the novel out of the library again.
        novel.inLibrary = isInLibrary
        let updated = novel
        // Persist the chapters already on screen, so read marks made right after adding stick —
        // otherwise they only exist in the DB after the next reload.
        let loaded = isInLibrary ? chapters : []
        let inLibrary = isInLibrary
        let saved = await Task.detached(priority: .userInitiated) { () -> [NovelChapter]? in
            try? NovelQueries.setInLibrary(updated, inLibrary)
            guard !loaded.isEmpty else { return nil }
            try? NovelQueries.insertAllIgnoringConflicts(loaded)
            return try? NovelQueries.fetchChapters(novelId: updated.id)
        }.value
        // The rows as saved: a chapter already stored under another id keeps that id, and read marks go by id.
        if let saved, !saved.isEmpty { chapters = saved }
        // Same first-save permission ask as MangaDetailView — novels never asked, so a novel-only reader never
        // got chapter notifications (S142 settings audit).
        if isInLibrary && !AppSettings.shared.hasRequestedNotifications {
            AppSettings.shared.hasRequestedNotifications = true
            Task { await NotificationManager.shared.requestPermission() }
        }
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
        // Column-only: a whole-row upsert wrote back this view's stale reading time/metadata (S141).
        let snapshot = novel
        Task.detached { try? NovelQueries.touchLastRead(snapshot) }
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
        let perf = Perf.begin("OpenNovel")
        defer { perf.end() }
        bypassAttempted = false
        autoBypassFailed = false
        await loadChapters()
        guard chapters.isEmpty, !bypassAttempted,
              let cfURL = bridge?.cfBlockedURL, !cfURL.isEmpty,
              let url = URL(string: cfURL) else { return }
        bypassAttempted = true
        isBypassing = true
        let success = await CFBypassManager.autoBypass(url: url, cookieJar: bridge?.cookieJar)
        bridge?.clearCFBlock()
        isBypassing = false
        if success {
            await loadChapters(force: true)
        } else {
            autoBypassFailed = true
        }
    }

    /// `force` = pull to refresh (or a retry): always asks the source. Otherwise a library novel checked within the
    /// hour (L3a, S171, Tachimanga v3.4) keeps the saved chapters it shows first.
    private func loadChapters(force: Bool = false) async {
        isLoadingChapters = true
        let novelId = novel.id
        let path = novel.path
        let sourceId = novel.sourceId

        // Library novels: show the saved chapter list at once and refresh from the source behind it
        // (the network fetch took 1.7–2 s on device, RESEARCH §23.6).
        if novel.inLibrary {
            let saved = await Task.detached(priority: .userInitiated) {
                (try? NovelQueries.fetchChapters(novelId: novelId)) ?? []
            }.value
            if !saved.isEmpty {
                chapters = saved
                isLoadingChapters = false
            }
        }

        // Local EPUB (S148): its chapters come from the file; a scan picks up a replaced/added book.
        if LocalLibrary.isLocalSourceId(sourceId) {
            chapters = await Task.detached(priority: .userInitiated) {
                _ = LocalLibrary.scan()
                return (try? NovelQueries.fetchChapters(novelId: novelId)) ?? []
            }.value
            isLoadingChapters = false
            return
        }

        // Always resolve a fresh bridge — reusing a bridge from SourceBrowseView risks
        // JSContext thread-safety issues when the context was last used on a different thread.
        if let ext = ExtensionManager.shared.installed.first(where: { $0.id == sourceId }) {
            bridge = await ExtensionManager.shared.loadBridge(for: ext)
        }

        guard let b = bridge else {
            let saved = await Task.detached(priority: .userInitiated) {
                (try? NovelQueries.fetchChapters(novelId: novelId)) ?? []
            }.value
            chapters = saved
            isLoadingChapters = false
            return
        }

        if !force, novel.inLibrary, !chapters.isEmpty, AppSettings.shared.detailRefreshHourly,
           await Task.detached(operation: { (try? UpdateScheduleQueries.checkedRecently(.novel, id: novelId)) ?? false }).value {
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
        if !source.genres.isEmpty { novel.genres = source.genres }
        if let coverStr = source.cover, !coverStr.isEmpty, let coverURL = URL(string: coverStr) {
            novel.coverURL = coverURL
        }

        // Persist updated metadata if in library
        if novel.inLibrary {
            let updated = novel
            await Task.detached { try? NovelQueries.updateSourceMetadata(updated) }.value
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
            let checked = !fetched.isEmpty
            await Task.detached {
                try? NovelQueries.insertAllIgnoringConflicts(fetched)
                if checked { try? UpdateScheduleQueries.markChecked(.novel, id: novelId) }
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

            // Mihon/Tachimanga "mark previous as read": everything before the one selected chapter.
            Button {
                markPreviousAsRead()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "text.badge.checkmark")
                    Text("Read before").font(.caption2)
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(selectedChapterIds.count != 1)

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

            // Bookmarks all selected, or clears them when every one is already bookmarked.
            let selected = chapters.filter { selectedChapterIds.contains($0.id) }
            let allBookmarked = !selected.isEmpty && selected.allSatisfy(\.isBookmarked)
            Button {
                setBookmarked(selected.map(\.id), !allBookmarked)
                endSelection()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: allBookmarked ? "bookmark.slash" : "bookmark")
                    Text(allBookmarked ? "Unmark" : "Bookmark").font(.caption2)
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(selectedChapterIds.isEmpty || !isInLibrary)

            Button {
                download(chapters.filter { selectedChapterIds.contains($0.id) })
                endSelection()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle")
                    Text("Download").font(.caption2)
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(selectedChapterIds.subtracting(downloadedIds).isEmpty || LocalLibrary.isLocalSourceId(novel.sourceId))

            Button {
                let doomed = chapters.filter { selectedChapterIds.contains($0.id) && downloadedIds.contains($0.id) }
                downloads.delete(chapters: doomed, novelId: novel.id)
                downloadedIds.subtract(doomed.map(\.id))
                endSelection()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "trash")
                    Text("Delete").font(.caption2)
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(selectedChapterIds.isDisjoint(with: downloadedIds))
        }
        .padding(.vertical, 12)
        .glassEffect(.regular, in: Capsule())
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// Bookmarks (or clears) chapters on screen and in the DB.
    private func setBookmarked(_ ids: [String], _ bookmarked: Bool) {
        let idSet = Set(ids)
        chapters = chapters.map { ch in
            idSet.contains(ch.id) ? { var c = ch; c.isBookmarked = bookmarked; return c }() : ch
        }
        let novelId = novel.id
        Task.detached { try? NovelQueries.setBookmarked(chapterIds: ids, novelId: novelId, bookmarked: bookmarked) }
    }

    private func endSelection() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withMotion(.spring(duration: 0.2)) {
            isSelectingChapters = false
            selectedChapterIds = []
        }
    }

    private func download(_ targets: [NovelChapter]) {
        guard !targets.isEmpty else { return }
        downloads.enqueue(targets, novel: novel)
    }

    private func refreshDownloaded() {
        let novelId = novel.id
        let chs = chapters
        Task {
            downloadedIds = await Task.detached(priority: .utility) {
                NovelDownloadStore.downloadedChapterIds(novelId: novelId, chapters: chs)
            }.value
        }
    }

    /// Marks every chapter before the single selected one (in reading order, ignoring the current
    /// filter/search/sort) as read — how you catch up to where another app left you.
    private func markPreviousAsRead() {
        guard selectedChapterIds.count == 1, let id = selectedChapterIds.first,
              let pos = chapters.firstIndex(where: { $0.id == id }) else { return }
        selectedChapterIds = Set(chapters[..<pos].filter { !$0.isRead }.map(\.id))
        markSelected(read: true)
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
            if read {
                // One transaction — "Read before" can cover hundreds of chapters.
                try? NovelQueries.markReadBatch(chapterIds: Array(ids), novelId: novelId)
            } else {
                for id in ids { try? NovelQueries.markUnread(chapterId: id) }
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withMotion(.spring(duration: 0.2)) {
            isSelectingChapters = false
            selectedChapterIds = []
        }
    }
}

// MARK: - NovelChapterList

/// The chapter rows, as their own Equatable view. Any @State change on NovelDetailView re-runs its body — opening
/// the reader sets `chapterForNav` — and with the rows built inline that rebuilt and re-diffed all ~880 of them
/// during the push: most of a 410 ms hang on the first chapter open (S136, RESEARCH §23.6). `.equatable()` skips
/// this view unless the rows' own inputs changed; the closures are left out of `==` on purpose.
private struct NovelChapterList: View, Equatable {
    struct Actions {
        let tap: (NovelChapter) -> Void
        let toggleRead: (NovelChapter) -> Void
        let toggleBookmark: ((NovelChapter) -> Void)?
        let markPrevious: (NovelChapter) -> Void
        let startSelecting: (NovelChapter) -> Void
    }

    let chapters: [NovelChapter]
    let isSelecting: Bool
    let selectedIds: Set<String>
    let downloadedIds: Set<String>
    let actions: Actions
    @Environment(\.yomiCanvas) private var canvas

    static func == (a: Self, b: Self) -> Bool {
        a.isSelecting == b.isSelecting && a.selectedIds == b.selectedIds
            && a.downloadedIds == b.downloadedIds && a.chapters == b.chapters
    }

    var body: some View {
        // No `.id(…)` on the rows: an explicit id on every row made the List resolve all of them up front (S144
        // trace: 859 ms hang opening Lord of the Mysteries, 1,432 rows). ForEach's own ids are what scrollTo uses.
        ForEach(chapters, id: \.id) { chapter in
            row(chapter)
        }
    }

    /// Tap + long-press gestures, not a Button: a Button inside a List swallowed the long press, so holding a
    /// chapter never started select mode on novels (Martin S144) — same setup as MangaDetailView's rows.
    @ViewBuilder private func row(_ chapter: NovelChapter) -> some View {
        HStack(spacing: 12) {
            if isSelecting {
                let isSelected = selectedIds.contains(chapter.id)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    // Known Issue #118: canvas tokens, not system secondary.
                    .foregroundStyle(isSelected ? Color.accentColor : canvas.textSecondary)
                    .font(.title3)
            }
            NovelChapterRow(chapter: chapter)
            Spacer(minLength: 0)
            if chapter.isBookmarked {
                Image(systemName: "bookmark.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("Bookmarked")
            }
            NovelChapterDownloadBadge(chapterId: chapter.id,
                                      isDownloaded: downloadedIds.contains(chapter.id))
            if !chapter.isRead && !isSelecting {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("Unread")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { actions.tap(chapter) }
        .onLongPressGesture(minimumDuration: 0.4) { actions.startSelecting(chapter) }
        .accessibilityAddTraits(.isButton)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: YomiTokens.Layout.screenMargin,
                                  bottom: 0, trailing: YomiTokens.Layout.screenMargin))
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .listRowSeparatorTint(canvas.hairline)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !isSelecting {
                Button {
                    actions.toggleRead(chapter)
                } label: {
                    Label(chapter.isRead ? "Unread" : "Read",
                          systemImage: chapter.isRead ? "circle" : "checkmark.circle.fill")
                }
                .tint(chapter.isRead ? .orange : .green)
                if let toggleBookmark = actions.toggleBookmark {
                    Button {
                        toggleBookmark(chapter)
                    } label: {
                        Label(chapter.isBookmarked ? "Unbookmark" : "Bookmark",
                              systemImage: chapter.isBookmarked ? "bookmark.slash" : "bookmark")
                    }
                    .tint(.indigo)
                }
                Button {
                    actions.markPrevious(chapter)
                } label: {
                    Label("Mark previous", systemImage: "checkmark.circle")
                }
                .tint(.blue)
            }
        }
    }
}

// MARK: - NovelChapterRow

private struct NovelChapterRow: View {
    let chapter: NovelChapter
    @Environment(\.yomiCanvas) private var canvas

    /// "Reading · 40%" while in progress, else the source's release time.
    private var detail: String? {
        if let pct = chapter.lastScrollPercent, pct > 0.02, !chapter.isRead {
            return String(localized: "Reading · \(Notation.progress(min(pct, 1)))")
        }
        return chapter.releaseTime
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Notation.chapterTitle(chapter.name, number: chapter.chapterNumber))
                .font(.body)
                .foregroundStyle(chapter.isRead ? canvas.textSecondary : canvas.textPrimary)
                .lineLimit(2)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(canvas.textSecondary)
            }
        }
        .padding(.vertical, 6)
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

/// The per-row download indicator. It reads the download queue itself so that only the rows re-render while
/// downloads run (the reader's download-ahead included); reading it in NovelDetailView's body made every queue
/// change rebuild the whole ~880-row chapter list under the open reader (RESEARCH §23.6).
private struct NovelChapterDownloadBadge: View {
    let chapterId: String
    let isDownloaded: Bool
    @Environment(\.yomiCanvas) private var canvas

    var body: some View {
        if NovelDownloadManager.shared.isPending(chapterId: chapterId) {
            ProgressView().controlSize(.mini)
        } else if isDownloaded {
            Image(systemName: "arrow.down.circle.fill")
                .font(.footnote)
                .foregroundStyle(canvas.textSecondary)
                .accessibilityLabel("Downloaded")
        }
    }
}

// MARK: - Detail pill buttons

extension Label where Title == Text, Icon == Image {
    /// Apple Music's Play / Shuffle buttons: equal-width grey capsules, accent text (S138). Shared with
    /// MangaDetailView.
    func detailPillLabel() -> some View {
        self
            .font(.body.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.primary.opacity(0.08), in: Capsule())
            .contentShape(Capsule())
    }
}
