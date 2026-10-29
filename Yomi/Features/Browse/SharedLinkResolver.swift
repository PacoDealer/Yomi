import Foundation

/// What a website link opens (S196). The matching rules live in `Core/SharedLink.swift` (tested); this asks the
/// installed sources. Research and the reasons for each step: `reports/S196-shared-links.md`.
enum SharedLinkTarget {
    case manga(Manga)
    case novel(Novel, JSBridge)
    /// No source could open it: search all sources for these words ("" = nothing usable in the link).
    case search(String)
}

enum SharedLinkResolver {

    /// 1. A Keiyoushi extension for the link's website, searched with the whole link (its search opens that title).
    /// 2. The one novel plugin whose website the link starts with (LNReader's rule).
    /// 3. Otherwise the words in the link. Turned-off sources and Safe Mode are respected throughout.
    @MainActor
    static func resolve(_ link: URL) async -> SharedLinkTarget {
        let off = Set(AppSettings.shared.turnedOffSourceIds)
        let safe = SafeMode.filter

        if let manga = await keiyoushiManga(for: link, off: off, safe: safe) {
            return .manga(manga)
        }
        if let novel = await novel(for: link, off: off, safe: safe) {
            return .novel(novel.novel, novel.bridge)
        }
        return .search(SharedLink.searchWords(from: link))
    }

    // MARK: - Keiyoushi

    @MainActor
    private static func keiyoushiManga(for link: URL, off: Set<String>, safe: SafeFilter) async -> Manga? {
        let candidates = KeiyoushiRepository.shared.installedSources.filter { entry in
            let id = KeiyoushiMapping.sourcePrefix + entry.source.id
            return !off.contains(id) && !safe.hidesSource(id) && SharedLink.sameSite(link, home: entry.source.homeURL)
        }
        for entry in candidates {
            guard let page = try? await KeiyoushiBridge.shared.search(sourceId: entry.source.id,
                                                                       query: link.absoluteString, page: 1),
                  let first = page.mangas?.first else { continue }
            let manga = KeiyoushiMapping.manga(from: first, sourceId: entry.source.id)
            if SafeMode.hidesGenres(manga.genres) { continue }
            // Same id as browsing (hash of the source's url), so a title already saved opens as itself.
            let saved = await Task.detached { try? MangaQueries.fetchOne(id: manga.id) }.value
            return saved ?? manga
        }
        return nil
    }

    // MARK: - Novel plugins

    private struct NovelMatch: @unchecked Sendable {
        let sourceId: String
        let path: String
        let bridge: JSBridge
    }

    @MainActor
    private static func novel(for link: URL, off: Set<String>, safe: SafeFilter) async -> (novel: Novel, bridge: JSBridge)? {
        // Only scripts that are (or may be) novel plugins; known manga plugins are skipped without loading them.
        let ids = ExtensionManager.shared.installed
            .filter { !off.contains($0.id) && !safe.hidesSource($0.id) && PluginKindCache.isNovel[$0.id] != false }
            .map(\.id)
        guard !ids.isEmpty else { return nil }

        let matches: [NovelMatch] = await Task.detached(priority: .userInitiated) {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            var found: [NovelMatch] = []
            for id in ids {
                let url = docs.appendingPathComponent("Extensions", isDirectory: true).appendingPathComponent("\(id).js")
                guard let bridge = JSBridge(scriptURL: url), bridge.isLNReaderPlugin,
                      let site = bridge.novelSite,
                      let path = SharedLink.novelPath(link: link, site: site) else { continue }
                found.append(NovelMatch(sourceId: id, path: path, bridge: bridge))
            }
            return found
        }.value
        // Like LNReader: two plugins for the same website is ambiguous, so search instead of guessing.
        guard matches.count == 1, let match = matches.first else { return nil }

        // A title in the Library opens as itself even when the link's slashes differ from the saved path.
        let saved = await Task.detached {
            ((try? NovelQueries.fetchLibrary()) ?? []).first {
                $0.sourceId == match.sourceId && SharedLink.samePath($0.path, match.path)
            }
        }.value
        if let saved { return (saved, match.bridge) }

        // The link must name a real novel page (not a list, a chapter, or a half-typed link): ask the plugin first,
        // and search instead when it finds nothing.
        guard let details = await Task.detached(priority: .userInitiated, operation: {
            match.bridge.parseNovel(path: match.path)
        }).value, !details.name.isEmpty, !details.chapters.isEmpty else { return nil }
        let novel = Novel(id: "\(match.sourceId)_\(match.path)", path: match.path, sourceId: match.sourceId,
                          title: details.name, coverURL: details.cover.flatMap { URL(string: $0) },
                          summary: details.summary, author: details.author, status: details.status ?? "unknown",
                          genres: details.genres, inLibrary: false, lastReadAt: nil, lastUpdatedAt: nil,
                          readingSeconds: 0, readingStatus: .none, notes: nil)
        if SafeMode.hidesGenres(novel.genres) { return nil }
        return (novel, match.bridge)
    }
}
