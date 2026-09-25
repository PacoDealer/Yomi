#if DEBUG
import SwiftUI

/// UI-test fixture (S129, RESEARCH §23.4). Launch the Debug app with `-yomiReaderFixture` and it opens the novel reader
/// straight away on a 3-chapter offline novel, skipping onboarding and the tabs. The chapters are saved as downloads,
/// so they load in a few ms, the same fast path that left the old chapter on screen after Next (bug #1).
/// Each paragraph reads "Fixture chapter N, paragraph K" so a test can tell which chapter the web view shows.
enum ReaderFixture {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-yomiReaderFixture") }

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

    struct RootView: View {
        @State private var bridge: JSBridge? = ReaderFixture.prepare()
        var body: some View {
            NavigationStack {
                if let bridge {
                    TextReaderView(novel: ReaderFixture.novel, bridge: bridge, chapters: ReaderFixture.chapters)
                } else {
                    Text("Reader fixture failed to start")
                }
            }
        }
    }
}
#endif
