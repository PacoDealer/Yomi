import SwiftUI
import StoreKit
import Kingfisher

/// Split out of ChapterReaderView.swift (S183, #106): the reader overlay (top/bottom bars + settings sheets) and the discussion web sheet.

// MARK: - ReaderOverlayView

struct ReaderOverlayView: View {
    let manga: Manga
    let chapter: Chapter
    let currentChapterIndex: Int
    let chapters: [Chapter]
    @Binding var currentPage: Int
    let totalPages: Int
    @Binding var readerMode: ReaderMode
    @Binding var showOverlay: Bool
    let showPageNumber: Bool
    let discussURL: URL?
    let sourceURL: URL?
    let hasPrevChapter: Bool
    let hasNextChapter: Bool
    let onDismiss: () -> Void
    let onDiscuss: () -> Void
    let onViewSource: () -> Void
    let onPrevChapter: () -> Void
    let onNextChapter: () -> Void
    var onJumpToChapter: ((Int) -> Void)? = nil
    /// Custom toolbar (L3c): bookmark + mark-previous quick actions, and the page on screen for Share page.
    var isBookmarked = false
    var onToggleBookmark: (() -> Void)? = nil
    var onMarkPreviousRead: (() -> Void)? = nil
    var currentPageURL: String? = nil

    @State private var showChapterSheet = false
    @State private var showSettingsSheet = false
    @State private var showMarkPreviousConfirm = false
    @State private var shareImage: UIImage? = nil
    @State private var pageTextImage: UIImage? = nil
    @State private var settings = AppSettings.shared

    private var isStripMode: Bool {
        switch readerMode {
        case .verticalScroll, .continuousRTL, .continuousLTR: true
        default: false
        }
    }

    @ViewBuilder private var readingModeOptions: some View {
        Label("Right to left", systemImage: "book.pages").tag(ReaderMode.horizontalRTL)
        Label("Left to right", systemImage: "book.pages.fill").tag(ReaderMode.horizontalLTR)
        Label("Paged (vertical)", systemImage: "square.stack").tag(ReaderMode.verticalPaged)
        Label("Continuous (right to left)", systemImage: "arrow.left").tag(ReaderMode.continuousRTL)
        Label("Continuous (left to right)", systemImage: "arrow.right").tag(ReaderMode.continuousLTR)
        Label("Webtoon", systemImage: "scroll").tag(ReaderMode.verticalScroll)
    }

    @ViewBuilder private var spreadOptions: some View {
        Text("Off").tag("single")
        Text("Always").tag("double")
        Text("In landscape").tag("automatic")
    }

    /// Crop borders is two settings (paged / strip, F17) — the button flips the one for the mode being read.
    private var cropBinding: Binding<Bool> {
        isStripMode ? $settings.cropBordersStrip : $settings.cropBorders
    }

    // MARK: - Custom toolbar (L3c)

    /// The saved buttons minus those that don't apply right now (spreads outside the paged modes, comments the source
    /// doesn't have, Share before a page has loaded).
    private var toolbarItems: [ReaderToolbarItem] {
        ReaderToolbarItem.current(settings).filter { item in
            switch item {
            case .spreads:   readerMode == .horizontalRTL || readerMode == .horizontalLTR
            case .comments:  discussURL != nil
            case .sharePage, .pageText: currentPageURL != nil
            default:         true
            }
        }
    }

    @ViewBuilder private func toolbarButton(_ item: ReaderToolbarItem) -> some View {
        switch item {
        case .previousChapter:
            Button(action: onPrevChapter) { toolbarIcon(item.systemImage, dimmed: !hasPrevChapter) }
                .disabled(!hasPrevChapter)
                .accessibilityLabel(item.title)
        case .nextChapter:
            Button(action: onNextChapter) { toolbarIcon(item.systemImage, dimmed: !hasNextChapter) }
                .disabled(!hasNextChapter)
                .accessibilityLabel(item.title)
        case .bookmark:
            Button { onToggleBookmark?() } label: {
                toolbarIcon(isBookmarked ? "bookmark.fill" : "bookmark", tinted: isBookmarked)
            }
            .accessibilityLabel(isBookmarked ? "Remove bookmark" : "Bookmark chapter")
        case .markPreviousRead:
            Button {
                if unreadBefore == 0 { onMarkPreviousRead?() } else { showMarkPreviousConfirm = true }
            } label: {
                toolbarIcon(item.systemImage, dimmed: currentChapterIndex == 0)
            }
            .disabled(currentChapterIndex == 0)
            .accessibilityLabel(item.title)
        case .readingMode:
            Menu {
                Picker("Reading mode", selection: $readerMode) { readingModeOptions }
            } label: { toolbarIcon(item.systemImage) }
            .accessibilityLabel(item.title)
        case .spreads:
            Menu {
                Picker("Two-page spreads", selection: $settings.pageLayout) { spreadOptions }
            } label: { toolbarIcon(item.systemImage, tinted: settings.pageLayout != "single") }
            .accessibilityLabel(item.title)
        case .cropBorders:
            Button { cropBinding.wrappedValue.toggle() } label: {
                toolbarIcon(item.systemImage, tinted: cropBinding.wrappedValue)
            }
            .accessibilityLabel(item.title)
            .accessibilityValue(cropBinding.wrappedValue ? "On" : "Off")
        case .sharePage:
            Button {
                guard let url = currentPageURL else { return }
                Task {
                    if let image = await ReaderPageActions.image(for: url) { shareImage = image }
                    else { ReaderPageActions.say(String(localized: "The page isn't loaded yet")) }
                }
            } label: { toolbarIcon(item.systemImage) }
            .accessibilityLabel(item.title)
        case .pageText:
            Button {
                guard let url = currentPageURL else { return }
                Task {
                    if let image = await ReaderPageActions.image(for: url) { pageTextImage = image }
                    else { ReaderPageActions.say(String(localized: "The page isn't loaded yet")) }
                }
            } label: { toolbarIcon(item.systemImage) }
            .accessibilityLabel(item.title)
        case .comments:
            Button(action: onDiscuss) { toolbarIcon(item.systemImage) }
                .accessibilityLabel(item.title)
        }
    }

    /// Unread chapters before this one — what "Mark previous as read" would change.
    private var unreadBefore: Int {
        chapters.prefix(currentChapterIndex).filter { !$0.isRead }.count
    }

    private func toolbarIcon(_ name: String, dimmed: Bool = false, tinted: Bool = false) -> some View {
        Image(systemName: name)
            .font(.system(size: 17))
            .foregroundStyle(tinted ? Color.accentColor : Color.primary.opacity(dimmed ? 0.3 : 1))
            .frame(minWidth: 28, minHeight: 28)
            .contentShape(Rectangle())
    }

    /// Same settings as More → Settings → Manga & Webtoon, for the mode being read (F16).
    @ViewBuilder private var gesturesSection: some View {
        switch readerMode {
        case .verticalScroll, .continuousRTL, .continuousLTR:
            Section("Gestures") {
                Picker("Tap zones", selection: $settings.stripTapZoneLayout) {
                    Text("Off").tag("disabled")
                    Text("L-shaped").tag("lShaped")
                    Text("Top and bottom").tag("topBottom")
                }
                if readerMode == .verticalScroll {
                    Picker("Long press", selection: $settings.stripLongPress) {
                        Text("Auto-scroll").tag("autoScroll")
                        Text("Scroll while held").tag("hold")
                        Text("Share or save").tag("pageMenu")
                    }
                    if settings.stripLongPress == "autoScroll" {
                        Picker("Stop auto-scroll after", selection: $settings.autoScrollStopMinutes) {
                            Text("Never").tag(0)
                            ForEach([5, 10, 15, 30], id: \.self) { minutes in
                                Text("\(minutes) minutes").tag(minutes)
                            }
                            Text("1 hour").tag(60)
                        }
                    }
                }
            }
        default:
            Section {
                Picker("Tap zones", selection: $settings.tapZoneLayout) {
                    Text("Thirds").tag("default")
                    Text("Edges").tag("sides")
                    Text("L-shaped").tag("lShaped")
                    Text("Kindle").tag("kindle")
                    Text("Left and right halves").tag("rightLeft")
                    Text("Off").tag("disabled")
                }
            } header: { Text("Gestures") } footer: { Text("Hold a page to share or save it.") }
        }
    }

    /// F17: spreads, crop borders and background for the mode being read (same settings as Manga & Webtoon).
    @ViewBuilder private var pagesSection: some View {
        Section("Pages") {
            switch readerMode {
            case .verticalScroll, .continuousRTL, .continuousLTR:
                Toggle("Crop borders", isOn: $settings.cropBordersStrip)
                Toggle("Scroll bar", isOn: $settings.readerScrollIndicator)
            case .horizontalRTL, .horizontalLTR:
                Picker("Two-page spreads", selection: $settings.pageLayout) { spreadOptions }
                if settings.pageLayout != "single" {
                    Toggle("Cover on its own", isOn: $settings.doublePageCoverAlone)
                    Toggle("Swap the two pages", isOn: $settings.doublePageInvert)
                }
                Toggle("Crop borders", isOn: $settings.cropBorders)
            default:
                Toggle("Crop borders", isOn: $settings.cropBorders)
            }
            Toggle("Pinch to zoom", isOn: $settings.readerPinchZoom)
            ReaderBackgroundPicker(selection: $settings.readerBackground)
        }
    }

    /// The bars follow the reader background, not the app theme. The app root's .preferredColorScheme wins over the
    /// reader's .dark, so in system light mode the title was dark text on a black backdrop (S197). Applied to the bars
    /// only: the sheets keep the app's own look, as before.
    private var barScheme: ColorScheme {
        ReaderBackdrop.isLight(settings.readerBackground) ? .light : .dark
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar — individual floating Liquid Glass chips
            HStack(spacing: 10) {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                }
                .glassChip()
                .accessibilityLabel("Close reader")

                VStack(alignment: .leading, spacing: 2) {
                    Text(manga.title)
                        .font(YomiTokens.Font.grotesk(15, weight: .medium))
                        .lineLimit(1)
                    Text(chapter.name)
                        .font(YomiTokens.Font.mono(11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                // Halo opposite the text so it reads over page art too (webtoon pages run under the bar).
                .shadow(color: (barScheme == .dark ? Color.black : Color.white).opacity(0.5), radius: 6)
                .frame(maxWidth: .infinity, alignment: .leading)

                if !chapters.isEmpty {
                    Button {
                        showChapterSheet = true
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 17))
                    }
                    .glassChip()
                    .accessibilityLabel("Chapters")
                }

                if sourceURL != nil {
                    Button(action: onViewSource) {
                        Image(systemName: "globe")
                            .font(.system(size: 17))
                    }
                    .glassChip()
                    .accessibilityLabel("Open on source website")
                }

                Button {
                    showSettingsSheet = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17))
                }
                .glassChip()
                .accessibilityLabel("Reader settings")
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .environment(\.colorScheme, barScheme)
            .sheet(isPresented: $showChapterSheet) {
                let target = currentChapterIndex
                NavigationStack {
                    ScrollViewReader { proxy in
                        List(chapters.indices, id: \.self) { idx in
                            let ch = chapters[idx]
                            Button {
                                showChapterSheet = false
                                onJumpToChapter?(idx)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ch.name)
                                            .font(.subheadline)
                                            .foregroundStyle(idx == target ? Color.accentColor : .primary)
                                            .fontWeight(idx == target ? .semibold : .regular)
                                        if ch.isRead {
                                            Text("Read")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        } else if ch.lastPageRead > 0 {
                                            Text("Page \(ch.lastPageRead + 1)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if idx == target {
                                        Image(systemName: "play.fill")
                                            .font(.caption)
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .id(idx)
                        }
                        .navigationTitle("Chapters")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showChapterSheet = false }
                            }
                        }
                        .onAppear {
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(100))
                                proxy.scrollTo(target, anchor: .center)
                            }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showSettingsSheet) {
                NavigationStack {
                    Form {
                        Section("Reading mode") {
                            Picker("Mode", selection: $readerMode) { readingModeOptions }
                            .pickerStyle(.inline)
                            .labelsHidden()
                        }
                        gesturesSection
                        pagesSection
                        Section {
                            NavigationLink("Toolbar") { ReaderToolbarEditor() }
                        } footer: { Text("Pick the buttons in the bar at the bottom of the reader.") }
                    }
                    .navigationTitle("Reader Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showSettingsSheet = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }

            Spacer()

            // Bottom bar — floating Liquid Glass card
            VStack(spacing: 14) {
                HStack {
                    if let num = chapter.chapterNumber {
                        Text(Notation.pagePosition(chapter: num, page: currentPage + 1, total: totalPages))
                    } else {
                        Text("\(currentPage + 1)/\(totalPages)")
                    }
                    Spacer()
                    // Up to three buttons sit next to the page count (the pre-L3c bar = previous + next).
                    if toolbarItems.count <= 3 {
                        HStack(spacing: 18) {
                            ForEach(toolbarItems) { toolbarButton($0) }
                        }
                    }
                }
                .font(YomiTokens.Font.mono(12))
                .foregroundStyle(.secondary)

                // More than three get a row of their own, spread across the bar.
                if toolbarItems.count > 3 {
                    HStack(spacing: 0) {
                        ForEach(toolbarItems) { toolbarButton($0).frame(maxWidth: .infinity) }
                    }
                }

                if showPageNumber && totalPages > 1 {
                    HStack(spacing: 10) {
                        Text("\(currentPage + 1)")
                            .font(YomiTokens.Font.mono(12))
                            .foregroundStyle(.secondary)

                        YomiScrubber(
                            value: Binding(
                                get: { Double(currentPage) },
                                set: { currentPage = Int($0.rounded()) }
                            ),
                            range: 0...Double(totalPages - 1),
                            accessibilityLabelText: "Page",
                            accessibilityValueText: { String(localized: "Page \(Int($0.rounded()) + 1) of \(totalPages)") }
                        )

                        Text("\(totalPages)")
                            .font(YomiTokens.Font.mono(12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
            .environment(\.colorScheme, barScheme)
        }
        .opacity(showOverlay ? 1 : 0)
        // Faded out is still in the accessibility tree: VoiceOver could reach invisible controls (S129 fixed the novel
        // reader only; S189 audit #11).
        .accessibilityHidden(!showOverlay)
        .motion(.easeInOut(duration: 0.2), value: showOverlay)
        .confirmationDialog("Mark previous as read", isPresented: $showMarkPreviousConfirm, titleVisibility: .hidden) {
            Button("Mark as Read") { onMarkPreviousRead?() }
        } message: {
            Text(unreadBefore == 1 ? "1 unread chapter before this one will be marked as read."
                                   : "\(unreadBefore) unread chapters before this one will be marked as read.")
        }
        .pageTextSheet($pageTextImage)
        .sheet(isPresented: Binding(get: { shareImage != nil }, set: { if !$0 { shareImage = nil } })) {
            if let shareImage {
                ActivityView(items: [shareImage])
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
            }
        }
    }
}

// MARK: - DiscussWebSheet

import WebKit

struct DiscussWebSheet: View {
    let url: URL
    var title: String = String(localized: "Discussion")
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WebView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct WebView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        return webView
    }
    func updateUIView(_ webView: WKWebView, context: Context) {}
}
