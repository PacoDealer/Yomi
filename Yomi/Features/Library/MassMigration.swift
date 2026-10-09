import Foundation
import Observation

// MARK: - MigrationTarget
//
// S148: a source titles can move TO — an installed JS manga plugin or an installed Keiyoushi source.

struct MigrationTarget: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case js(Extension)
        case keiyoushi(mihonId: String)
    }

    /// The stored `Manga.sourceId` this target produces (plugin id or `keiyoushi_<id>`).
    let id: String
    let name: String
    let kind: Kind

    /// Every installed source that can take manga, alphabetical. JS novel (LNReader) plugins are left out —
    /// they can't hold manga. Building a bridge is cached (S131), so this is cheap after the first call.
    static func available(excluding sourceId: String?) async -> [MigrationTarget] {
        let plugins = ExtensionManager.shared.installed.filter { $0.id != sourceId }
        let keiyoushi = KeiyoushiJVMHost.isAvailable
            ? KeiyoushiRepository.shared.installedSources.map { entry in
                MigrationTarget(
                    id: KeiyoushiMapping.sourcePrefix + entry.source.id,
                    name: entry.ext.info.sources.count > 1
                        ? "\(entry.source.name) · \(entry.source.lang.uppercased())" : entry.source.name,
                    kind: .keiyoushi(mihonId: entry.source.id))
            }.filter { $0.id != sourceId }
            : []
        let manager = ExtensionManager.shared
        let js = await Task.detached(priority: .userInitiated) {
            plugins.filter { ext in manager.bridge(for: ext).map { !$0.isLNReaderPlugin } ?? false }
                .map { MigrationTarget(id: $0.id, name: $0.name, kind: .js($0)) }
        }.value
        return (js + keiyoushi).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: Source calls

    func search(_ query: String) async -> [Manga] {
        switch kind {
        case .js(let ext):
            let manager = ExtensionManager.shared
            return await Task.detached(priority: .userInitiated) {
                manager.bridge(for: ext)?.searchManga(query: query, page: 1, sourceId: ext.id) ?? []
            }.value
        case .keiyoushi(let mihonId):
            guard let page = try? await KeiyoushiBridge.shared.search(sourceId: mihonId, query: query, page: 1)
            else { return [] }
            return (page.mangas ?? []).map { KeiyoushiMapping.manga(from: $0, sourceId: mihonId) }
        }
    }

    func chapters(for manga: Manga) async throws -> [Chapter] {
        switch kind {
        case .js(let ext):
            let manager = ExtensionManager.shared
            return await Task.detached(priority: .userInitiated) {
                manager.bridge(for: ext)?.getChapterList(mangaPath: manga.path, mangaId: manga.id) ?? []
            }.value
        case .keiyoushi(let mihonId):
            var seen = Set<String>()
            return try await KeiyoushiBridge.shared.chapters(sourceId: mihonId, mangaURL: manga.path)
                .map { KeiyoushiMapping.chapter(from: $0, mangaId: manga.id, sourceId: mihonId, mangaTitle: manga.title) }
                .filter { seen.insert($0.id).inserted }
        }
    }
}

// MARK: - TitleMatch
//
// Port of Mihon's `BaseSmartSearchEngine` (mihon/feature/migration/list/search): search the title, keep results whose
// normalized Levenshtein similarity is ≥ 0.4, take the closest. When the plain title finds nothing, search a cleaned
// title (lowercased, bracketed text and punctuation removed) — Mihon's "deep search", first query only.

enum TitleMatch {
    nonisolated static let threshold = 0.4

    nonisolated static func best(for title: String, in candidates: [Manga]) -> Manga? {
        let target = clean(title)
        return candidates
            .map { ($0, similarity(target, clean($0.title))) }
            .filter { $0.1 >= threshold }
            .max { $0.1 < $1.1 }?.0
    }

    nonisolated static func clean(_ title: String) -> String {
        var depth = 0
        var out = ""
        for ch in title.lowercased() {
            if "([<{".contains(ch) { depth += 1 } else if ")]}>".contains(ch) { if depth > 0 { depth -= 1 } }
            else if depth == 0 { out.append(ch) }
        }
        // Letters of any script stay (Korean/Japanese titles); punctuation (’ ' : ! ?) becomes a space.
        let kept = out.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    /// 1 − Levenshtein distance / longer length (Mihon's `NormalizedLevenshtein`).
    nonisolated static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        let x = Array(a), y = Array(b)
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        var previous = Array(0...y.count)
        var current = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            current[0] = i
            for j in 1...y.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            swap(&previous, &current)
        }
        return 1 - Double(previous[y.count]) / Double(max(x.count, y.count))
    }
}

// MARK: - MassMigration
//
// One run of Browse → Migrate: for each picked title, search the chosen targets in order (or all of them, keeping
// the match with the most chapters), fetch the match's chapter list, let the user review, then migrate.

@Observable
final class MassMigration {
    enum SearchState {
        case waiting
        case searching
        case found(match: Manga, target: MigrationTarget, chapters: [Chapter])
        case notFound
    }

    struct Item: Identifiable, Hashable {
        let old: Manga
        /// Highest chapter number on the old title (nil when it has no numbered chapters).
        var oldLatest: Double?
        var state: SearchState = .waiting
        var migrated = false
        /// Left out by the user (the match is kept, so un-skipping costs nothing).
        var skipped = false
        var error: String?
        var id: String { old.id }

        static func == (a: Item, b: Item) -> Bool { a.id == b.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    struct Summary {
        var migrated = 0
        var readChapters = 0
        var failed: [String] = []
    }

    var items: [Item]
    let targets: [MigrationTarget]
    let mostChapters: Bool
    private(set) var options: MigrationService.Options
    private(set) var isMigrating = false
    private(set) var migratedCount = 0
    var summary: Summary?

    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init(titles: [Manga], targets: [MigrationTarget], mostChapters: Bool, options: MigrationService.Options) {
        self.items = titles.map { Item(old: $0) }
        self.targets = targets
        self.mostChapters = mostChapters
        self.options = options
    }

    var searchedCount: Int {
        items.filter { if case .waiting = $0.state { return false }; if case .searching = $0.state { return false }; return true }.count
    }
    var isSearching: Bool { searchedCount < items.count }
    var readyCount: Int { items.filter { if case .found = $0.state { return !$0.migrated && !$0.skipped }; return false }.count }

    // MARK: Search

    /// Searches three titles at a time (the Keiyoushi pool size Updates uses).
    func start() {
        guard searchTask == nil else { return }
        let ids = items.map(\.id)
        for i in items.indices {
            items[i].oldLatest = (try? ChapterQueries.fetchAll(mangaId: items[i].id))?.compactMap(\.chapterNumber).max()
        }
        searchTask = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                var next = 0
                func addNext() {
                    guard next < ids.count, let self else { return }
                    let id = ids[next]
                    next += 1
                    group.addTask { await self.search(itemId: id) }
                }
                for _ in 0..<3 { addNext() }
                for await _ in group {
                    if Task.isCancelled { break }
                    addNext()
                }
            }
        }
    }

    func cancel() { searchTask?.cancel() }

    private func index(_ id: String) -> Int? { items.firstIndex { $0.id == id } }

    private func search(itemId: String) async {
        guard let i = index(itemId), case .waiting = items[i].state else { return }
        items[i].state = .searching
        let title = items[i].old.title
        var best: (Manga, MigrationTarget, [Chapter])?
        for target in targets {
            if Task.isCancelled { return }
            guard let match = await Self.find(title, on: target, excludingPath: items[i].old.path),
                  let chapters = try? await target.chapters(for: match), !chapters.isEmpty else { continue }
            if !mostChapters { best = (match, target, chapters); break }
            if best == nil || Self.latest(chapters) > Self.latest(best!.2) { best = (match, target, chapters) }
        }
        guard let i = index(itemId) else { return }
        items[i].state = best.map { .found(match: $0.0, target: $0.1, chapters: $0.2) } ?? .notFound
    }

    nonisolated static func find(_ title: String, on target: MigrationTarget, excludingPath: String) async -> Manga? {
        let first = await target.search(title).filter { $0.path != excludingPath }
        if let hit = TitleMatch.best(for: title, in: first) { return hit }
        let cleaned = TitleMatch.clean(title)
        guard cleaned != title.lowercased(), cleaned.count >= 2 else { return nil }
        return TitleMatch.best(for: title, in: await target.search(cleaned).filter { $0.path != excludingPath })
    }

    nonisolated static func latest(_ chapters: [Chapter]) -> Double {
        chapters.compactMap(\.chapterNumber).max() ?? Double(chapters.count)
    }

    // MARK: Review

    func toggleSkip(_ id: String) {
        guard let i = index(id) else { return }
        items[i].skipped.toggle()
    }

    /// A match the user picked by hand (the per-title search screen).
    func choose(_ match: Manga, on target: MigrationTarget, for id: String) async throws {
        let chapters = try await target.chapters(for: match)
        guard !chapters.isEmpty else { throw MigrationService.MigrationError.noChaptersFromNewSource }
        guard let i = index(id) else { return }
        items[i].state = .found(match: match, target: target, chapters: chapters)
    }

    // MARK: Migrate

    /// `keepOld` = the Copy button (S149): the old entries stay in the Library too.
    func migrateReady(keepOld: Bool = false) async {
        guard !isMigrating else { return }
        options.keepOld = keepOld
        isMigrating = true
        var summary = Summary()
        let options = options
        for item in items {
            guard case .found(let match, _, let chapters) = item.state, !item.migrated, !item.skipped else { continue }
            let old = item.old
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try MigrationService.migrate(from: old, to: match, newChapters: chapters, options: options)
                }.value
                if let i = index(item.id) { items[i].migrated = true }
                summary.migrated += 1
                summary.readChapters += result.readChapters
            } catch {
                if let i = index(item.id) { items[i].error = error.localizedDescription }
                summary.failed.append(old.title)
            }
            migratedCount += 1
        }
        isMigrating = false
        self.summary = summary
    }
}
