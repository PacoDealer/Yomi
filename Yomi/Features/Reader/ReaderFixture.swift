#if DEBUG
import SwiftUI

/// UI-test fixture (S129, RESEARCH §23.4). Launch the Debug app with `-yomiReaderFixture` and it opens the novel reader
/// straight away on a 3-chapter offline novel, skipping onboarding and the tabs. The chapters are saved as downloads,
/// so they load in a few ms, the same fast path that left the old chapter on screen after Next (bug #1).
/// Each paragraph reads "Fixture chapter N, paragraph K" so a test can tell which chapter the web view shows.
enum ReaderFixture {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-yomiReaderFixture") }
    /// `-yomiReaderFixture manga`: the manga reader on a long-strip chapter instead (S179 perf gates).
    static var isManga: Bool {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-yomiReaderFixture"), i + 1 < args.count else { return false }
        return args[i + 1] == "manga"
    }

    static let novel = Novel(
        id: "fixture-novel", path: "/fixture", sourceId: "fixture", title: "Fixture Novel",
        coverURL: nil, summary: nil, author: nil, status: "", genres: [], inLibrary: false,
        lastReadAt: nil, lastUpdatedAt: nil, readingSeconds: 0, readingStatus: .none, notes: nil)

    static let chapters: [NovelChapter] = (1...3).map { n in
        NovelChapter(id: "fixture-novel-ch-\(n - 1)", novelId: novel.id, path: "/fixture/\(n)",
                     name: "Chapter \(n)", chapterNumber: Double(n), isRead: false, readAt: nil,
                     releaseTime: nil, readingSeconds: 0)
    }

    /// Writes the chapters as downloads and builds a bridge from an empty script (never asked for content).
    static func prepare() -> JSBridge? {
        let meta = NovelDownloadStore.Meta(id: novel.id, path: novel.path, sourceId: novel.sourceId,
                                           title: novel.title, coverURL: nil)
        for (i, chapter) in chapters.enumerated() {
            let body = (1...60).map { "<p>Fixture chapter \(i + 1), paragraph \($0).</p>" }.joined()
            try? NovelDownloadStore.save(body, chapterPath: chapter.path, meta: meta)
        }
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("fixture-plugin.js")
        try? "var fixture = true;".write(to: script, atomically: true, encoding: .utf8)
        return JSBridge(scriptURL: script)
    }

    // MARK: Manga long strip

    static let manga = Manga(
        id: "fixture-manga", path: "local://app/.perf-fixture", sourceId: LocalLibrary.sourceId, title: "Perf Fixture",
        coverURL: nil, summary: nil, author: nil, artist: nil, status: .unknown, genres: [], inLibrary: false,
        isLocal: true, lastReadAt: nil, lastUpdatedAt: nil, readingSeconds: 0)

    static let mangaChapter = Chapter(
        id: "fixture-manga-ch-1", mangaId: manga.id, path: "local://app/.perf-fixture/Chapter 1", name: "Chapter 1",
        chapterNumber: 1, isRead: false, isDownloaded: false, downloadedAt: nil, readAt: nil, progress: 0,
        readingSeconds: 0, lastPageRead: 0)

    nonisolated static let stripPages = 8
    /// Asura's shape (900×16000, #190/#209): tall enough that the reader must draw them in strips.
    nonisolated static let stripSize = CGSize(width: 900, height: 16000)

    /// Writes the chapter's pages once, into Documents/Local/.perf-fixture/Chapter 1 (hidden: a Local Files scan skips
    /// it) — bands of colour with numbers, so the JPEGs aren't trivially small.
    nonisolated static func prepareManga() {
        let dir = LocalLibrary.appRoot.appendingPathComponent(".perf-fixture/Chapter 1", isDirectory: true)
        let fm = FileManager.default
        if ((try? fm.contentsOfDirectory(atPath: dir.path))?.count ?? 0) >= stripPages { return }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: stripSize, format: format)
        for page in 1...stripPages {
            let data = renderer.jpegData(withCompressionQuality: 0.7) { ctx in
                for band in 0..<Int(stripSize.height / 200) {
                    let hue = CGFloat((page * 37 + band * 11) % 360) / 360
                    UIColor(hue: hue, saturation: 0.5, brightness: 0.85, alpha: 1).setFill()
                    ctx.fill(CGRect(x: 0, y: CGFloat(band) * 200, width: stripSize.width, height: 200))
                    ("Page \(page) · \(band)" as NSString).draw(
                        at: CGPoint(x: 40, y: CGFloat(band) * 200 + 70),
                        withAttributes: [.font: UIFont.boldSystemFont(ofSize: 56), .foregroundColor: UIColor.black])
                }
            }
            try? data.write(to: dir.appendingPathComponent(String(format: "%03d.jpg", page)))
        }
    }

    struct MangaRootView: View {
        @State private var ready = false
        @State private var path = ["reader"]
        var body: some View {
            NavigationStack(path: $path) {
                Text("Fixture home")
                    .navigationDestination(for: String.self) { _ in
                        if ready {
                            ChapterReaderView(manga: ReaderFixture.manga, bridge: nil,
                                              chapters: [ReaderFixture.mangaChapter], chapterIndex: 0)
                        } else {
                            ProgressView("Preparing pages")
                        }
                    }
            }
            .task {
                await Task.detached(priority: .userInitiated) { ReaderFixture.prepareManga() }.value
                ready = true
            }
        }
    }

    struct RootView: View {
        @State private var bridge: JSBridge? = ReaderFixture.prepare()
        // The reader starts pushed on top of a home screen, so swipe-back has somewhere to go.
        @State private var path = ["reader"]
        var body: some View {
            NavigationStack(path: $path) {
                Text("Fixture home")
                    .navigationDestination(for: String.self) { _ in
                        if let bridge {
                            TextReaderView(novel: ReaderFixture.novel, bridge: bridge, chapters: ReaderFixture.chapters)
                        } else {
                            Text("Reader fixture failed to start")
                        }
                    }
            }
        }
    }
}
#endif
