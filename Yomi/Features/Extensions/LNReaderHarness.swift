#if DEBUG
import Foundation

/// Measures how many LNReader plugins actually work in Yomi's JSBridge (S125), instead of assuming it.
///
/// Launch the Debug app with `-lnreaderHarness` (optionally `-lnreaderHarnessLimit N`). For each English plugin in the
/// LNReader catalog it downloads the script and runs popular → novel details → one chapter, then writes
/// `Documents/lnreader-harness.json` and logs a summary line starting with `[LNReaderHarness]`.
enum LNReaderHarness {
    nonisolated static let catalogURL =
        URL(string: "https://raw.githubusercontent.com/LNReader/lnreader-plugins/plugins/v3.0.0/.dist/plugins.min.json")!

    nonisolated struct Result: Codable, Sendable {
        let id: String
        let name: String
        /// "ok", or the first step that failed: "load", "popular", "novel", "chapter".
        let outcome: String
        let novels: Int
        let chapters: Int
        let chapterChars: Int
        let seconds: Double
        /// The plugin's own error for the failing step, when it reported one.
        let error: String?
    }

    private nonisolated struct Entry: Decodable, Sendable {
        let id: String
        let name: String
        let lang: String
        let url: String
    }

    static func startIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-lnreaderHarness") else { return }
        var limit = Int.max
        if let i = args.firstIndex(of: "-lnreaderHarnessLimit"), i + 1 < args.count, let n = Int(args[i + 1]) {
            limit = n
        }
        JSBridge.debugLogFetches = args.contains("-lnreaderHarnessLogFetches")
        Task.detached(priority: .utility) { await run(limit: limit) }
    }

    nonisolated static func run(limit: Int) async {
        guard let (data, _) = try? await URLSession.shared.data(from: catalogURL),
              let catalog = try? JSONDecoder().decode([Entry].self, from: data) else {
            print("[LNReaderHarness] could not load the catalog")
            return
        }
        var english = Array(catalog.filter { $0.lang == "English" }.prefix(limit))
        // -lnreaderHarnessInstalled: test the novel plugins already installed in this app instead of the catalog.
        if ProcessInfo.processInfo.arguments.contains("-lnreaderHarnessInstalled") {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Extensions")
            let files = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)) ?? []
            english = files.filter { (try? String(contentsOf: $0, encoding: .utf8))?.contains("popularNovels") == true }
                .map { Entry(id: $0.deletingPathExtension().lastPathComponent, name: $0.lastPathComponent,
                             lang: "English", url: $0.absoluteString) }
        }
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-lnreaderHarnessOnly"), i + 1 < args.count {
            let names = Set(args[i + 1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            english = catalog.filter { names.contains($0.name) }
        }
        print("[LNReaderHarness] testing \(english.count) plugins")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lnr-harness", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var results: [Result] = []
        await withTaskGroup(of: Result.self) { group in
            var next = 0
            func add() {
                guard next < english.count else { return }
                let entry = english[next]
                next += 1
                group.addTask { await test(entry, dir: dir) }
            }
            for _ in 0..<8 { add() }
            for await result in group {
                results.append(result)
                print("[LNReaderHarness] \(results.count)/\(english.count) \(result.name): \(result.outcome)"
                      + (result.error.map { " — \($0.prefix(160))" } ?? ""))
                add()
            }
        }

        results.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let counts = Dictionary(grouping: results, by: \.outcome).mapValues(\.count)
        print("[LNReaderHarness] DONE \(counts.sorted { $0.key < $1.key })")
        let out = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("lnreader-harness.json")
        if let json = try? JSONEncoder().encode(results) { try? json.write(to: out) }
    }

    private nonisolated static func test(_ entry: Entry, dir: URL) async -> Result {
        let start = Date()
        func result(_ outcome: String, _ novels: Int = 0, _ chapters: Int = 0, _ chars: Int = 0,
                    error: String? = nil) -> Result {
            Result(id: entry.id, name: entry.name, outcome: outcome, novels: novels, chapters: chapters,
                   chapterChars: chars, seconds: Date().timeIntervalSince(start), error: error)
        }
        guard let url = URL(string: entry.url),
              let (script, _) = try? await URLSession.shared.data(from: url) else { return result("load") }
        let file = dir.appendingPathComponent("\(entry.id).js")
        guard (try? script.write(to: file)) != nil, let bridge = JSBridge(scriptURL: file) else { return result("load") }

        // JSBridge blocks on network calls — keep each plugin on its own detached task.
        return await Task.detached {
            let novels = bridge.popularNovels(page: 1)
            guard let first = novels.first else {
                return result("popular", error: bridge.lastPluginError ?? "no error; result = \(bridge.lastResultSummary)")
            }
            guard let novel = bridge.parseNovel(path: first.path), let chapter = novel.chapters.first else {
                return result("novel", novels.count,
                              error: bridge.lastPluginError ?? "no error; result = \(bridge.lastResultSummary)")
            }
            let text = bridge.parseChapter(path: chapter.path)
            let plain = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            return result(plain.count >= 200 ? "ok" : "chapter", novels.count, novel.chapters.count, plain.count,
                          error: plain.count >= 200 ? nil : bridge.lastPluginError)
        }.value
    }
}
#endif
