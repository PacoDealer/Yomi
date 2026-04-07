import SwiftUI
import WebKit

// MARK: - TextReaderView

struct TextReaderView: View {
    let chapter: NovelChapter
    let novel: Novel
    let bridge: JSBridge

    @Environment(\.dismiss) private var dismiss

    @State private var rawContent: String = ""
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var fontSize: Double = AppSettings.shared.fontSize
    @State private var isDarkMode: Bool = true
    @State private var isSepia: Bool = AppSettings.shared.novelSepia
    @State private var showOverlay = true

    // MARK: - Computed

    private var lineSpacing: Double { AppSettings.shared.lineSpacing }

    private var styledHTML: String {
        let fs = Int(fontSize)               // no clamp — use value directly
        let ls = lineSpacing
        let bg: String
        let fg: String
        if isSepia {
            bg = "#FFF8F0"
            fg = "#2C1810"
        } else {
            bg = isDarkMode ? "#1C1C1E" : "#FFFFFF"
            fg = isDarkMode ? "#E8E8E8" : "#1C1C1E"
        }
        let style = """
        <style>
        * { box-sizing: border-box; }
        body {
            font-family: -apple-system, sans-serif;
            font-size: \(fs)px;
            line-height: \(String(format: "%.2f", ls));
            padding: 20px 16px 60px 16px;
            background: \(bg);
            color: \(fg);
            max-width: 680px;
            margin: 0 auto;
        }
        img { max-width: 100%; }
        a   { color: #4a9eff; }
        </style>
        """
        return style + rawContent
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(isDarkMode ? UIColor(named: "ReaderDark") ?? .black : .white)
                .ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .tint(isDarkMode ? .white : .gray)
            } else if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                ReaderWebView(html: styledHTML) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showOverlay.toggle()
                    }
                }
                .ignoresSafeArea()
            }

            TextReaderOverlayView(
                novel:       novel,
                chapter:     chapter,
                fontSize:    $fontSize,
                isDarkMode:  $isDarkMode,
                isSepia:     $isSepia,
                showOverlay: $showOverlay,
                onDismiss:   { dismiss() }
            )
        }
        .navigationBarHidden(true)
        .statusBarHidden(!showOverlay)
        .preferredColorScheme(.dark)
        .task { await loadContent() }
        .onChange(of: fontSize) { _, newValue in
            AppSettings.shared.fontSize = newValue
        }
    }

    // MARK: - Load Content

    private func loadContent() async {
        let path = chapter.path
        let html = await Task.detached(priority: .userInitiated) {
            bridge.parseChapter(path: path)
        }.value

        if html.isEmpty {
            errorMessage = "No content found for this chapter."
        } else {
            rawContent = html
            Task { try? NovelQueries.markRead(chapterId: chapter.id) }
        }
        isLoading = false
    }
}

// MARK: - ReaderWebView

struct ReaderWebView: UIViewRepresentable {
    let html: String
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.dataDetectorTypes = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap)
        )
        tap.delegate = context.coordinator
        webView.addGestureRecognizer(tap)

        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Re-inject style via JS to avoid a full page reload.
        // Only the <style> block changes; rawContent is stable after first load.
        guard !html.isEmpty else { return }

        // Extract just the <style>...</style> portion and re-apply it.
        if let styleStart = html.range(of: "<style>"),
           let styleEnd   = html.range(of: "</style>") {
            let styleContent = String(html[styleStart.lowerBound...styleEnd.upperBound])
            // Escape for JS string injection
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

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let onTap: () -> Void
        init(onTap: @escaping () -> Void) { self.onTap = onTap }

        @objc func handleTap() { onTap() }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }
    }
}

// MARK: - TextReaderOverlayView

struct TextReaderOverlayView: View {
    let novel:      Novel
    let chapter:    NovelChapter
    @Binding var fontSize:   Double
    @Binding var isDarkMode: Bool
    @Binding var isSepia:    Bool
    @Binding var showOverlay: Bool
    let onDismiss: () -> Void

    var body: some View {
        VStack {
            if showOverlay {
                // Top bar
                ZStack(alignment: .bottom) {
                    LinearGradient(
                        colors: [Color.black.opacity(0.8), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 88)
                    .ignoresSafeArea(edges: .top)

                    HStack(spacing: 12) {
                        Button(action: onDismiss) {
                            Image(systemName: "chevron.left")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .padding(.trailing, 4)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(novel.title)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(chapter.name)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }

                Spacer()

                // Bottom bar
                ZStack(alignment: .top) {
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 120)
                    .ignoresSafeArea(edges: .bottom)

                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            Text("A")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.7))
                            Slider(value: $fontSize, in: 14...28, step: 1)
                                .tint(.white)
                            Text("A")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .padding(.horizontal, 20)

                        HStack(spacing: 24) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isDarkMode.toggle()
                                    isSepia = false
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: isDarkMode ? "sun.max" : "moon")
                                    Text(isDarkMode ? "Light" : "Dark")
                                        .font(.caption)
                                }
                                .foregroundStyle(.white.opacity(0.85))
                            }

                            Button {
                                isSepia.toggle()
                                AppSettings.shared.novelSepia = isSepia
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: isSepia ? "s.circle.fill" : "s.circle")
                                    Text("Sepia")
                                        .font(.caption)
                                }
                                .foregroundStyle(.white.opacity(isSepia ? 1.0 : 0.6))
                            }
                        }
                    }
                    .padding(.top, 14)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showOverlay)
    }
}

// MARK: - Preview

#Preview {
    TextReaderView(
        chapter: NovelChapter(
            id: "ch-1",
            novelId: "1",
            path: "/novel/re-zero/chapter/1",
            name: "Chapter 1 — The Beginning",
            chapterNumber: 1.0,
            isRead: false,
            readAt: nil,
            releaseTime: "2021-01-01"
        ),
        novel: Novel(
            id: "1",
            path: "/novel/re-zero",
            sourceId: "en.royalroad",
            title: "Re:Zero − Starting Life in Another World",
            coverURL: nil,
            summary: nil,
            author: "Tappei Nagatsuki",
            status: "ongoing",
            genres: ["Fantasy", "Isekai"],
            inLibrary: false,
            lastReadAt: nil,
            lastUpdatedAt: nil,
            readingSeconds: 0
        ),
        bridge: JSBridge(scriptURL: Bundle.main.url(forResource: "test-source", withExtension: "js")!)!
    )
}
