import SwiftUI
import WebKit
import AVFoundation

// MARK: - NovelTheme

enum NovelTheme: String, CaseIterable {
    case light  = "Light"
    case sepia  = "Sepia"
    case warm   = "Warm"
    case dark   = "Dark"
    case amoled = "AMOLED"

    var bg: String {
        switch self {
        case .light:  return "#FFFFFF"
        case .sepia:  return "#F8F1E3"   // Research-validated warm cream (Apple Books standard)
        case .warm:   return "#1A1209"   // Dark amber night
        case .dark:   return "#1C1C1E"   // iOS system dark
        case .amoled: return "#0A0A0A"   // Near-black avoids OLED scroll pixel jitter
        }
    }

    var fg: String {
        switch self {
        case .light:  return "#1C1C1E"
        case .sepia:  return "#2C2015"   // Dark warm brown for sepia
        case .warm:   return "#CDB38B"   // Warm amber text
        case .dark:   return "#E8E8E8"
        case .amoled: return "#E0E0E0"
        }
    }

    var linkColor: String {
        switch self {
        case .light, .sepia: return "#0A6ADA"
        case .warm, .dark, .amoled: return "#5BA3F5"
        }
    }

    var isDark: Bool {
        switch self {
        case .dark, .amoled, .warm: return true
        case .light, .sepia:        return false
        }
    }

    var colorScheme: ColorScheme { isDark ? .dark : .light }

    /// Color for the theme swatch circle in the overlay
    var swatchColor: Color {
        switch self {
        case .light:  return Color(white: 1.0)
        case .sepia:  return Color(red: 0.961, green: 0.929, blue: 0.839)
        case .warm:   return Color(red: 0.102, green: 0.071, blue: 0.035)
        case .dark:   return Color(red: 0.11,  green: 0.11,  blue: 0.118)
        case .amoled: return Color(white: 0.0)
        }
    }

    var uiColor: UIColor {
        UIColor(hex: bg) ?? .systemBackground
    }
}

// MARK: - TextReaderView

struct TextReaderView: View {
    let novel: Novel
    let bridge: JSBridge
    let chapters: [NovelChapter]

    @Environment(\.dismiss) private var dismiss

    @State private var currentChapterIndex: Int
    @State private var rawContent: String = ""
    @State private var isLoading = true
    @State private var errorMessage: String? = nil

    // Reader settings — initialized from persisted AppSettings
    @State private var fontSize: Double        = AppSettings.shared.fontSize
    @State private var lineSpacing: Double     = AppSettings.shared.lineSpacing
    @State private var novelTheme: NovelTheme  = NovelTheme(rawValue: AppSettings.shared.novelTheme) ?? .light
    @State private var fontFamily: String      = AppSettings.shared.novelFontFamily
    @State private var hPadding: Int           = AppSettings.shared.novelHorizontalPadding

    @State private var showOverlay = true
    @State private var showFinishedBanner = false
    @State private var sessionStart: Date = Date()
    @State private var readingTimer: Timer? = nil
    @State private var lastKnownScrollPercent: Double? = nil

    // TTS
    @State private var isSpeaking = false
    @State private var ttsDelegate: TTSDelegate? = nil

    init(novel: Novel, bridge: JSBridge, chapters: [NovelChapter], startIndex: Int = 0) {
        self.novel   = novel
        self.bridge  = bridge
        self.chapters = chapters
        _currentChapterIndex = State(initialValue: startIndex)
    }

    // MARK: - Computed

    private var activeChapter: NovelChapter { chapters[currentChapterIndex] }
    private var hasPrevChapter: Bool { currentChapterIndex > 0 }
    private var hasNextChapter: Bool { currentChapterIndex < chapters.count - 1 }

    private var fontFamilyCSS: String {
        fontFamily == "Serif"
            ? "Georgia, \"Times New Roman\", serif"
            : "-apple-system, \"Helvetica Neue\", sans-serif"
    }

    /// Full HTML document with viewport meta tag — fixes the large-margin bug caused by
    /// WKWebView's default 980px virtual viewport when no viewport tag is present.
    private var styledHTML: String {
        let fs  = Int(fontSize)
        let ls  = String(format: "%.2f", lineSpacing)
        let bg  = novelTheme.bg
        let fg  = novelTheme.fg
        let lnk = AppSettings.shared.accentColor
        let hp  = hPadding

        let css = """
            * { box-sizing: border-box; }
            html, body { margin: 0; padding: 0; }
            body {
                font-family: \(fontFamilyCSS);
                font-size: \(fs)px;
                line-height: \(ls);
                padding: 24px \(hp)px 200px \(hp)px;
                background: \(bg);
                color: \(fg);
                -webkit-text-size-adjust: 100%;
                word-break: break-word;
                overflow-wrap: break-word;
            }
            p {
                margin: 0 0 0.75em 0;
            }
            img {
                max-width: 100%;
                height: auto;
                display: block;
                margin: 0.5em auto;
            }
            a {
                color: \(lnk);
                text-decoration: none;
            }
            a svg, a svg path, a svg polygon, a svg rect {
                fill: \(lnk);
                stroke: \(lnk);
            }
            svg { fill: currentColor; }
            h1, h2, h3 {
                margin: 0.5em 0 0.4em 0;
                line-height: 1.3;
            }
            """

        return """
            <!DOCTYPE html>
            <html>
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes">
            <style>
            \(css)
            </style>
            </head>
            <body>
            \(rawContent)
            </body>
            </html>
            """
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(novelTheme.uiColor)
                .ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .tint(novelTheme.isDark ? .white : .gray)
            } else if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                ReaderWebView(
                    html: styledHTML,
                    onTap: {
                        withAnimation(.easeInOut(duration: 0.2)) { showOverlay.toggle() }
                    },
                    onReadComplete: {
                        if !AppSettings.shared.isIncognito {
                            let chapterId = activeChapter.id
                            Task { try? NovelQueries.markRead(chapterId: chapterId) }
                        }
                        withAnimation(.spring(duration: 0.4)) { showFinishedBanner = true }
                    },
                    restoreScrollPercent: activeChapter.lastScrollPercent,
                    onScrollUpdate: { pct in
                        lastKnownScrollPercent = pct
                        guard !AppSettings.shared.isIncognito else { return }
                        let cid = activeChapter.id
                        Task.detached(priority: .background) {
                            try? NovelQueries.updateScrollPercent(chapterId: cid, percent: pct)
                        }
                    }
                )
                .ignoresSafeArea()
            }

            if showFinishedBanner {
                chapterFinishedBanner
            }

            TextReaderOverlayView(
                novel:                novel,
                chapter:              activeChapter,
                currentChapterIndex:  currentChapterIndex,
                chapters:             chapters,
                fontSize:             $fontSize,
                novelTheme:           $novelTheme,
                fontFamily:           $fontFamily,
                hPadding:             $hPadding,
                showOverlay:          $showOverlay,
                isSpeaking:           $isSpeaking,
                hasPrevChapter:       hasPrevChapter,
                hasNextChapter:       hasNextChapter,
                onDismiss:            { dismiss() },
                onPrevChapter:        { navigateToChapter(currentChapterIndex - 1) },
                onNextChapter:        { navigateToChapter(currentChapterIndex + 1) },
                onJumpToChapter:      { navigateToChapter($0) },
                onToggleTTS:          { toggleTTS() }
            )
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(!showOverlay)
        .preferredColorScheme(novelTheme.colorScheme)
        .task(id: activeChapter.id) { await loadContent() }
        .onChange(of: fontSize)   { _, v in AppSettings.shared.fontSize = v }
        .onChange(of: novelTheme) { _, v in
            AppSettings.shared.novelTheme  = v.rawValue
            AppSettings.shared.novelSepia  = (v == .sepia)
        }
        .onChange(of: fontFamily) { _, v in AppSettings.shared.novelFontFamily = v }
        .onChange(of: hPadding)   { _, v in AppSettings.shared.novelHorizontalPadding = v }
        .onAppear {
            sessionStart  = Date()
            readingTimer  = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in }
        }
        .onDisappear {
            stopTTS()
            flushScrollPercent()
            flushReadingTime()
        }
    }

    // MARK: - Chapter Finished Banner

    @ViewBuilder private var chapterFinishedBanner: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
                Text(hasNextChapter ? "Chapter finished" : "All caught up!")
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundStyle(.primary)
                Spacer()
                if hasNextChapter {
                    Button {
                        navigateToChapter(currentChapterIndex + 1)
                    } label: {
                        Label("Next", systemImage: "chevron.right")
                            .labelStyle(.titleAndIcon)
                            .font(.subheadline).fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            .padding(.horizontal, 16)
            .padding(.bottom, 36)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear {
            Task {
                try? await Task.sleep(for: .seconds(5))
                withAnimation(.easeOut(duration: 0.25)) { showFinishedBanner = false }
            }
        }
    }

    // MARK: - Scroll Position

    private func flushScrollPercent() {
        guard !AppSettings.shared.isIncognito, let pct = lastKnownScrollPercent else { return }
        let cid = activeChapter.id
        Task.detached(priority: .background) {
            try? NovelQueries.updateScrollPercent(chapterId: cid, percent: pct)
        }
    }

    // MARK: - Reading Time

    private func flushReadingTime() {
        readingTimer?.invalidate()
        readingTimer = nil
        let elapsed = Int(Date().timeIntervalSince(sessionStart))
        guard !AppSettings.shared.isIncognito, elapsed > 3 else { return }
        let cid = activeChapter.id
        let nid = novel.id
        Task.detached(priority: .background) {
            try? NovelQueries.addReadingTime(chapterId: cid, novelId: nid, seconds: elapsed)
        }
    }

    // MARK: - Navigate

    private func navigateToChapter(_ index: Int) {
        guard index >= 0, index < chapters.count else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showFinishedBanner = false
        stopTTS()
        flushScrollPercent()
        lastKnownScrollPercent = nil
        flushReadingTime()
        sessionStart  = Date()
        readingTimer  = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in }
        let chapterId = activeChapter.id
        if !AppSettings.shared.isIncognito {
            Task.detached(priority: .background) { try? NovelQueries.markRead(chapterId: chapterId) }
        }
        rawContent    = ""
        isLoading     = true
        errorMessage  = nil
        currentChapterIndex = index
    }

    // MARK: - TTS

    private func toggleTTS() {
        if isSpeaking {
            stopTTS()
        } else {
            startTTS()
        }
    }

    private func startTTS() {
        guard !rawContent.isEmpty else { return }
        let plain = rawContent
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: plain)
        utterance.rate = AppSettings.shared.ttsSpeechRate
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier ?? "en")
        let delegate = TTSDelegate { self.isSpeaking = false }
        ttsDelegate = delegate
        let synth = AVSpeechSynthesizer()
        synth.delegate = delegate
        delegate.synthesizer = synth
        isSpeaking = true
        synth.speak(utterance)
    }

    private func stopTTS() {
        ttsDelegate?.synthesizer?.stopSpeaking(at: .immediate)
        ttsDelegate = nil
        isSpeaking = false
    }

    // MARK: - Load Content

    private func loadContent() async {
        isLoading    = true
        errorMessage = nil
        rawContent   = ""
        let path = activeChapter.path
        let html = await Task.detached(priority: .userInitiated) {
            bridge.parseChapter(path: path)
        }.value

        if html.isEmpty {
            errorMessage = "Unable to load chapter content. The source may be temporarily unavailable."
        } else {
            rawContent = html
        }
        isLoading = false
    }
}

// MARK: - ReaderWebView

struct ReaderWebView: UIViewRepresentable {
    let html: String
    let onTap: () -> Void
    let onReadComplete: () -> Void
    var restoreScrollPercent: Double? = nil
    var onScrollUpdate: ((Double) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, onReadComplete: onReadComplete,
                    restoreScrollPercent: restoreScrollPercent,
                    onScrollUpdate: onScrollUpdate)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.dataDetectorTypes = []

        config.userContentController.add(context.coordinator, name: "readComplete")
        config.userContentController.add(context.coordinator, name: "scrollPosition")

        let setupJS = WKUserScript(source: """
            (function() {
                if ('scrollRestoration' in history) { history.scrollRestoration = 'manual'; }

                // Fire readComplete at 90% scroll
                var fired = false;
                window.addEventListener('scroll', function() {
                    if (fired) return;
                    var ratio = (window.scrollY + window.innerHeight) / document.body.scrollHeight;
                    if (ratio >= 0.9) {
                        fired = true;
                        window.webkit.messageHandlers.readComplete.postMessage('done');
                    }
                }, { passive: true });

                // Debounced scroll position save (400 ms)
                var scrollTimer = null;
                window.addEventListener('scroll', function() {
                    if (scrollTimer) clearTimeout(scrollTimer);
                    scrollTimer = setTimeout(function() {
                        var maxScroll = document.body.scrollHeight - window.innerHeight;
                        var pct = maxScroll > 0 ? window.scrollY / maxScroll : 0;
                        window.webkit.messageHandlers.scrollPosition.postMessage(pct);
                    }, 400);
                }, { passive: true });
            })();
            """, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(setupJS)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .clear
        webView.isOpaque        = false
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = context.coordinator

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap))
        tap.delegate = context.coordinator
        webView.addGestureRecognizer(tap)

        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onScrollUpdate = onScrollUpdate

        guard !html.isEmpty else { return }

        // Re-inject only the <style> block to avoid a full page reload
        if let styleStart = html.range(of: "<style>"),
           let styleEnd   = html.range(of: "</style>") {
            let styleContent = String(html[styleStart.lowerBound...styleEnd.upperBound])
            let escaped = styleContent
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`",  with: "\\`")
            let js = """
            (function() {
                var existing = document.querySelector('style');
                if (existing) {
                    existing.outerHTML = `\(escaped)`;
                } else {
                    document.head.insertAdjacentHTML('beforeend', `\(escaped)`);
                }
            })();
            """
            webView.evaluateJavaScript(js)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIGestureRecognizerDelegate, WKScriptMessageHandler, WKNavigationDelegate {
        let onTap: () -> Void
        let onReadComplete: () -> Void
        var onScrollUpdate: ((Double) -> Void)?
        private let restoreScrollPercent: Double?
        private var hasRestored = false

        init(onTap: @escaping () -> Void, onReadComplete: @escaping () -> Void,
             restoreScrollPercent: Double?, onScrollUpdate: ((Double) -> Void)?) {
            self.onTap = onTap
            self.onReadComplete = onReadComplete
            self.restoreScrollPercent = restoreScrollPercent
            self.onScrollUpdate = onScrollUpdate
        }

        @objc func handleTap() { onTap() }

        // MARK: WKNavigationDelegate — restore scroll after page load
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !hasRestored else { return }
            hasRestored = true
            guard let pct = restoreScrollPercent, pct > 0.01 else { return }
            let js = """
            (function() {
                var maxScroll = document.body.scrollHeight - window.innerHeight;
                if (maxScroll > 0) { window.scrollTo(0, \(pct) * maxScroll); }
            })();
            """
            webView.evaluateJavaScript(js)
        }

        // MARK: WKScriptMessageHandler
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            if message.name == "readComplete" { onReadComplete() }
            if message.name == "scrollPosition", let pct = message.body as? Double {
                DispatchQueue.main.async { self.onScrollUpdate?(pct) }
            }
        }

        func gestureRecognizer(_ gr: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

// MARK: - TextReaderOverlayView

struct TextReaderOverlayView: View {
    let novel:                Novel
    let chapter:              NovelChapter
    let currentChapterIndex:  Int
    let chapters:             [NovelChapter]
    @Binding var fontSize:    Double
    @Binding var novelTheme:  NovelTheme
    @Binding var fontFamily:  String
    @Binding var hPadding:    Int
    @Binding var showOverlay: Bool
    @Binding var isSpeaking:  Bool
    var hasPrevChapter:       Bool = false
    var hasNextChapter:       Bool = false
    let onDismiss:            () -> Void
    var onPrevChapter:        (() -> Void)? = nil
    var onNextChapter:        (() -> Void)? = nil
    var onJumpToChapter:      ((Int) -> Void)? = nil
    var onToggleTTS:          (() -> Void)? = nil

    @State private var showChapterSheet = false

    private let paddingOptions: [(label: String, value: Int)] = [
        ("Narrow", 8), ("Normal", 16), ("Wide", 28)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // ── Top bar ──────────────────────────────────────────────────
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [Color.black.opacity(0.8), Color.clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 100)
                    .ignoresSafeArea(edges: .top)

                HStack(spacing: 12) {
                    Button(action: onDismiss) {
                        Image(systemName: "chevron.left")
                            .font(.title3).fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(novel.title)
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundStyle(.white).lineLimit(1)
                        Text(chapter.name)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !chapters.isEmpty {
                        Button {
                            showChapterSheet = true
                        } label: {
                            Image(systemName: "list.bullet")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .sheet(isPresented: $showChapterSheet) {
                    NavigationStack {
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
                                            .foregroundStyle(idx == currentChapterIndex ? Color.accentColor : .primary)
                                            .fontWeight(idx == currentChapterIndex ? .semibold : .regular)
                                        if ch.isRead {
                                            Text("Read")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        } else if let pct = ch.lastScrollPercent, pct > 0.01 {
                                            Text("\(Int(pct * 100))%")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if idx == currentChapterIndex {
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
                            // Scroll to current chapter immediately
                        }
                    }
                    .presentationDetents([.medium, .large])
                }
            }

            Spacer()

            // ── Bottom bar ───────────────────────────────────────────────
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color.clear, Color.black.opacity(0.9)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 240)
                    .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 14) {

                    // Row 1: Font size slider
                    HStack(spacing: 10) {
                        Text("A").font(.caption).foregroundStyle(.white.opacity(0.7))
                        Slider(value: $fontSize, in: 14...28, step: 1).tint(.white)
                        Text("A").font(.subheadline).fontWeight(.medium).foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 20)

                    // Row 2: Font family + horizontal margin
                    HStack(spacing: 16) {
                        // Font family toggle
                        Button {
                            fontFamily = (fontFamily == "Serif") ? "System" : "Serif"
                        } label: {
                            Text(fontFamily == "Serif" ? "Aa" : "Aa")
                                .font(fontFamily == "Serif"
                                      ? .system(.subheadline, design: .serif).bold()
                                      : .subheadline.bold())
                                .foregroundStyle(fontFamily == "Serif" ? Color.white : Color.white.opacity(0.5))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(fontFamily == "Serif" ? 0.18 : 0.06))
                                .clipShape(Capsule())
                        }

                        Spacer()

                        // Margin control: Narrow / Normal / Wide
                        HStack(spacing: 0) {
                            ForEach(paddingOptions, id: \.value) { opt in
                                Button {
                                    hPadding = opt.value
                                } label: {
                                    Text(opt.label)
                                        .font(.caption2).fontWeight(.medium)
                                        .foregroundStyle(hPadding == opt.value ? Color.black : Color.white.opacity(0.7))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(hPadding == opt.value ? Color.white : Color.clear)
                                }
                            }
                        }
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .padding(.horizontal, 20)

                    // Row 3: Theme swatches
                    HStack(spacing: 12) {
                        Spacer()
                        ForEach(NovelTheme.allCases, id: \.rawValue) { theme in
                            Button {
                                novelTheme = theme
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(theme.swatchColor)
                                        .frame(width: 30, height: 30)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                                        )
                                    if novelTheme == theme {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(theme.isDark ? Color.white : Color.black)
                                    }
                                }
                            }
                        }
                        Spacer()
                    }

                    // Row 4: Prev / TTS / Next chapter
                    HStack(spacing: 0) {
                        Button { onPrevChapter?() } label: {
                            Image(systemName: "chevron.left.2")
                                .font(.title3).fontWeight(.semibold)
                                .foregroundStyle(hasPrevChapter ? .white : .white.opacity(0.25))
                                .frame(width: 56, height: 40)
                        }
                        .disabled(!hasPrevChapter)

                        Spacer()

                        Button { onToggleTTS?() } label: {
                            Image(systemName: isSpeaking ? "stop.circle.fill" : "play.circle")
                                .font(.title2)
                                .foregroundStyle(isSpeaking ? Color.accentColor : .white.opacity(0.7))
                        }

                        Spacer()

                        Button { onNextChapter?() } label: {
                            Image(systemName: "chevron.right.2")
                                .font(.title3).fontWeight(.semibold)
                                .foregroundStyle(hasNextChapter ? .white : .white.opacity(0.25))
                                .frame(width: 56, height: 40)
                        }
                        .disabled(!hasNextChapter)
                    }
                    .padding(.horizontal, 8)
                }
                .padding(.top, 16)
            }
        }
        .opacity(showOverlay ? 1 : 0)
        .allowsHitTesting(showOverlay)
        .animation(.easeInOut(duration: 0.2), value: showOverlay)
    }
}

// MARK: - TTSDelegate

private final class TTSDelegate: NSObject, AVSpeechSynthesizerDelegate {
    var onFinish: () -> Void
    var synthesizer: AVSpeechSynthesizer?

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.onFinish() }
    }
}

// MARK: - UIColor hex init (needed for NovelTheme.uiColor)

private extension UIColor {
    convenience init?(hex: String) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        self.init(red:   CGFloat((val >> 16) & 0xFF) / 255,
                  green: CGFloat((val >>  8) & 0xFF) / 255,
                  blue:  CGFloat( val        & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - Preview

#Preview {
    let chapter = NovelChapter(
        id: "ch-1", novelId: "1", path: "/novel/re-zero/chapter/1",
        name: "Chapter 1 — The Beginning", chapterNumber: 1.0,
        isRead: false, readAt: nil, releaseTime: "2021-01-01", readingSeconds: 0
    )
    TextReaderView(
        novel: Novel(
            id: "1", path: "/novel/re-zero", sourceId: "en.royalroad",
            title: "Re:Zero − Starting Life in Another World",
            coverURL: nil, summary: nil, author: "Tappei Nagatsuki",
            status: "ongoing", genres: ["Fantasy", "Isekai"],
            inLibrary: false, lastReadAt: nil, lastUpdatedAt: nil,
            readingSeconds: 0, readingStatus: .none, notes: nil
        ),
        bridge: JSBridge(scriptURL: Bundle.main.url(forResource: "test-source", withExtension: "js")!)!,
        chapters: [chapter], startIndex: 0
    )
}
