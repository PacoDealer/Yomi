#if DEBUG
import Foundation
import Kingfisher
import UIKit

/// DEBUG harness (S144): resolves one Keiyoushi chapter's pages and downloads every page through Kingfisher the
/// way the reader does, logging each page's time/size/error to the console. Martin: "Asura, any series — the
/// first page appeared and the rest did not load". Device only (the JVM doesn't run in the simulator).
///
///   -keiyoushiPageProbe                  first Keiyoushi title in the library, its Continue chapter
///   -keiyoushiPageProbeTitle <text>      pick the title containing <text>
///   -keiyoushiPageProbePause             pause the bridge after listing pages (what going to the background does);
///                                        pages then go through PageRetry + the live-port rewrite, like the reader
enum KeiyoushiPageProbe {
    static func startIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-keiyoushiPageProbe") else { return }
        var title: String?
        if let i = args.firstIndex(of: "-keiyoushiPageProbeTitle"), i + 1 < args.count { title = args[i + 1] }
        let pause = args.contains("-keiyoushiPageProbePause")
        Task { await run(title: title, pause: pause) }
    }

    private static func log(_ s: String) { print("[PageProbe] \(s)") }

    private static func run(title: String?, pause: Bool) async {
        try? await Task.sleep(for: .seconds(3))
        let library = (try? MangaQueries.fetchLibrary()) ?? []
        guard let manga = library.first(where: {
            KeiyoushiMapping.isKeiyoushiSourceId($0.sourceId) && (title.map($0.title.localizedCaseInsensitiveContains) ?? true)
        }) else { return log("no Keiyoushi title in the library") }
        let chapters = ((try? ChapterQueries.fetchAll(mangaId: manga.id)) ?? [])
        guard let resume = ResumeReading.mangaChapter(in: chapters),
              var index = chapters.firstIndex(where: { $0.id == resume.id }) else { return log("no chapters for \(manga.title)") }

        // The Continue chapter, else step back: the newest chapters can be paid early access.
        var urls: [String] = []
        for _ in 0..<4 {
            let chapter = chapters[index]
            log("\(manga.title) — \(chapter.name) (number \(chapter.chapterNumber.map { "\($0)" } ?? "nil"))")
            let t0 = Date()
            if let ref = KeiyoushiMapping.chapterRef(from: chapter.path) {
                do {
                    let pages = try await KeiyoushiBridge.shared.pages(sourceId: ref.sourceId, chapterURL: ref.url,
                                                                       chapterName: ref.name)
                    urls = pages.sorted { $0.index < $1.index }.compactMap { p in
                        if let image = p.imageUrl, !image.isEmpty { return image }
                        return p.url
                    }
                    log("page list: \(urls.count) pages in \(ms(since: t0)) ms")
                } catch {
                    log("page list FAILED in \(ms(since: t0)) ms — \(error)")
                }
            }
            if !urls.isEmpty || index == 0 { break }
            index -= 1
        }
        for u in urls.prefix(3) { log("  \(u.prefix(160))") }
        guard !urls.isEmpty else { return }

        if pause {
            KeiyoushiBridge.shared.pause()
            log("bridge paused (as on going to the background)")
        }

        // The long strip shows a few pages at once; load 3 at a time, like scrolling.
        let start = Date()
        var ok = 0
        await withTaskGroup(of: (Int, String).self) { group in
            var next = 0
            func add() {
                guard next < urls.count else { return }
                let i = next, url = urls[i]
                next += 1
                group.addTask {
                    // Like a reader cell: on failure ask PageRetry, then load the SAME URL again.
                    var attempt = 0
                    while true {
                        let line = await fetch(url)
                        let again = line.hasPrefix("ok") ? false : await PageRetry.shouldRetry(url, attempt: attempt)
                        if !again {
                            return (i, attempt > 0 ? "\(line) (after \(attempt) retr\(attempt == 1 ? "y" : "ies"))" : line)
                        }
                        attempt += 1
                    }
                }
            }
            for _ in 0..<3 { add() }
            for await (i, line) in group {
                if line.hasPrefix("ok") { ok += 1 }
                log("page \(i + 1)/\(urls.count): \(line)")
                add()
            }
        }
        log("done: \(ok)/\(urls.count) pages loaded in \(ms(since: start)) ms")
    }

    private static func fetch(_ url: String) async -> String {
        guard let u = URL(string: url) else { return "bad URL" }
        let t = Date()
        var serializer = DefaultCacheSerializer()
        serializer.preferCacheOriginalData = true
        do {
            let r = try await KingfisherManager.shared.retrieveImage(
                with: u, options: [.forceRefresh, .cacheSerializer(serializer), .backgroundDecode])
            let size = r.image.size
            return "ok \(ms(since: t)) ms, \(Int(size.width))×\(Int(size.height))"
        } catch {
            return "FAILED after \(ms(since: t)) ms — \(error)"
        }
    }

    private static func ms(since d: Date) -> Int { Int(Date().timeIntervalSince(d) * 1000) }
}
#endif
