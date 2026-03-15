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
    @State private var fontSize: Double = 18
    @State private var isDarkMode: Bool = true
    @State private var showOverlay = true

    // MARK: - Computed

    private var styledHTML: String {
        let bg   = isDarkMode ? "#111111" : "#ffffff"
        let fg   = isDarkMode ? "#e8e8e8" : "#1a1a1a"
        let style = """
        <style>
        body { font-family: -apple-system; font-size: \(Int(fontSize))px;
               line-height: 1.8; padding: 20px 16px;
               background: \(bg); color: \(fg); max-width: 680px; margin: 0 auto; }
        img  { max-width: 100%; }
        a    { color: #4a9eff; }
        </style>
        """
        return style + rawContent
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(isDarkMode ? UIColor.black : UIColor.white)
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
                novel:        novel,
                chapter:      chapter,
                fontSize:     $fontSize,
                isDarkMode:   $isDarkMode,
                showOverlay:  $showOverlay,
                onDismiss:    { dismiss() }
            )
        }
        .navigationBarHidden(true)
        .statusBarHidden(!showOverlay)
        .preferredColorScheme(.dark)
        .task { await loadContent() }
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
        }
        isLoading = false

        // Mark as read — fire and forget
        Task { try? NovelQueries.markRead(chapterId: chapter.id) }
    }
}

// MARK: - ReaderWebView

/// WKWebView wrapped in UIViewRepresentable.
/// Only reloads when the HTML string actually changes (tracked via Coordinator).
/// Tap gesture forwarded to SwiftUI via onTap closure.
struct ReaderWebView: UIViewRepresentable {
    let html: String
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: Coordinator

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var lastHTML: String = ""
        var onTap: (() -> Void)?

        @objc func handleTap() { onTap?() }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }
    }

    // MARK: UIViewRepresentable

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .always

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap)
        )
        tap.delegate = context.coordinator
        webView.addGestureRecognizer(tap)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onTap = onTap
        guard html != context.coordinator.lastHTML else { return }
        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }
}

// MARK: - TextReaderOverlayView

private struct TextReaderOverlayView: View {
    let novel: Novel
    let chapter: NovelChapter
    @Binding var fontSize: Double
    @Binding var isDarkMode: Bool
    @Binding var showOverlay: Bool
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
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
                .frame(height: 110)
                .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 10) {
                    // Font size slider
                    HStack(spacing: 10) {
                        Text("Aa")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                        Slider(value: $fontSize, in: 14...26, step: 1)
                            .tint(.white)
                        Text("Aa")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 20)

                    // Dark / light toggle
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isDarkMode.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isDarkMode ? "sun.max" : "moon")
                            Text(isDarkMode ? "Light mode" : "Dark mode")
                                .font(.caption)
                        }
                        .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .padding(.top, 14)
            }
        }
        .opacity(showOverlay ? 1 : 0)
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
