import CryptoKit
import Foundation
import Observation

// MARK: - PluginCatalogEntry

struct PluginCatalogEntry: nonisolated Codable, Identifiable {
    let id: String
    let name: String
    let version: String
    let language: String
    let description: String?
    let iconURL: String?
    let fileURL: String
    let isNSFW: Bool
    var repoURL: String = ""
    /// "novel" or "manga". Optional in Yomi catalogs; LNReader catalogs are always novels.
    var kind: String? = nil
    /// Hex SHA-256 of the plugin file, optional. When a catalog gives it, an install whose bytes differ is refused
    /// (#151: a truncated or swapped file never replaces a working plugin).
    var sha256: String? = nil

    var isNovel: Bool { kind == "novel" }
    /// Novel or manga when the catalog says so, nil when it doesn't.
    var knownIsNovel: Bool? { kind.map { $0 == "novel" } }

    /// Ids this entry's plugin may be installed under: the catalog id, "Install from URL"'s sha256(file URL), and —
    /// for Yomi's own catalog only — the old DEBUG seed's sha256(file name) and "com.yomi.<file name>" (both legacy
    /// schemes only ever named Yomi's plugins; for another repository's royalroad.js they claimed Yomi's install, #171). A plugin added by link also keeps the
    /// name inside its script ("WeTried TLs" vs the catalog's "WeTried Translations"), so names alone miss it (S141).
    /// Filled once by `fetchCatalog` (`withInstallIds()`): computing the hashes on every lookup froze the
    /// Extensions list, which matches each catalog entry against each installed plugin per render (S141).
    private(set) var installIds: Set<String> = []

    nonisolated func withInstallIds() -> PluginCatalogEntry {
        var entry = self
        let fileName = URL(string: fileURL)?.deletingPathExtension().lastPathComponent ?? ""
        entry.installIds = [id, Self.sha256id(fileURL)]
        if repoURL.contains("yomi-plugins") {
            entry.installIds.formUnion([Self.sha256id(fileName), "com.yomi.\(fileName)"])
        }
        return entry
    }

    /// The installed plugin is this entry: same id (any of `installIds`), or same name when no catalog entry claims
    /// the installed id (a plugin added by link). By name alone, Yomi's Royal Road also counted as LNReader's (#171).
    func matches(_ ext: Extension) -> Bool {
        id == ext.id || installIds.contains(ext.id)
            || (!PluginCatalogService.shared.claimedIds.contains(ext.id) && name.lowercased() == ext.name.lowercased())
    }

    nonisolated static func sha256id(_ string: String) -> String {
        let hash = SHA256.hash(data: Data(string.utf8))
        return String(hash.compactMap { String(format: "%02x", $0) }.joined().prefix(32))
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, version, language, description, iconURL, fileURL, isNSFW, kind, sha256
    }
}

// MARK: - PluginCatalogGroup

struct PluginCatalogGroup: Identifiable {
    let name: String
    let entries: [PluginCatalogEntry]
    var id: String { "\(entries[0].repoURL)\n\(name)" }
    var isMultiLang: Bool { entries.count > 1 }
    var primaryEntry: PluginCatalogEntry { entries[0] }
}

// MARK: - LNReader catalog format

private nonisolated struct LNReaderEntry: Decodable {
    let id: String
    let name: String
    let version: String
    let lang: String
    let iconUrl: String?
    let url: String
    let site: String?

    nonisolated func toEntry() -> PluginCatalogEntry {
        var entry = PluginCatalogEntry(
            id: id,
            name: name,
            version: version,
            language: lang,
            description: site,
            iconURL: iconUrl,
            fileURL: url,
            isNSFW: false
        )
        entry.kind = "novel"
        return entry
    }
}

// MARK: - Mangayomi catalog format

private nonisolated struct MangayomiEntry: Decodable {
    let id: Int
    let name: String
    let version: String
    let lang: String
    let iconUrl: String?
    let sourceCodeUrl: String
    let isNsfw: Bool?
    let baseUrl: String?

    nonisolated func toEntry() -> PluginCatalogEntry {
        PluginCatalogEntry(
            id: String(id),
            name: name,
            version: version,
            language: lang,
            description: baseUrl,
            iconURL: iconUrl,
            fileURL: sourceCodeUrl,
            isNSFW: isNsfw ?? false
        )
    }
}

// MARK: - Lenient

/// One array element that may fail to decode without failing the array.
private nonisolated struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

// MARK: - PluginCatalogService

@Observable final class PluginCatalogService {

    // MARK: - Singleton

    static let shared = PluginCatalogService()
    init() {}

    // MARK: - State

    var entries: [PluginCatalogEntry] = [] {
        didSet { claimedIds = entries.reduce(into: Set<String>()) { $0.formUnion($1.installIds) } }
    }
    /// Every installed id some catalog entry owns — see `PluginCatalogEntry.matches`.
    private(set) var claimedIds: Set<String> = []
    var isLoading: Bool = false
    var errorMessage: String? = nil
    private var lastFetchedAt: Date? = nil
    private let ttl: TimeInterval = 3600

    // MARK: - Fetch

    /// Fetches catalogs from all configured URLs in parallel, merges by id — the repository listed first wins, whatever
    /// order the responses arrive in (#155) — and sorts by name.
    /// Per-URL failures are skipped gracefully — only sets errorMessage if ALL catalogs fail.
    func fetchCatalog(force: Bool = false) async {
        guard !isLoading else { return }
        if !force, !entries.isEmpty, let last = lastFetchedAt, Date().timeIntervalSince(last) < ttl {
            return
        }
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        let urls = AppSettings.shared.pluginCatalogURLs
            .compactMap { URL(string: $0) }

        // No repositories is a normal state (fresh installs start with none, S140), not an error.
        guard !urls.isEmpty else {
            await MainActor.run {
                entries = []
                isLoading = false
            }
            return
        }

        // Fetch all catalogs concurrently; per-URL failures return empty (don't break the group)
        let results: [[PluginCatalogEntry]] = await withTaskGroup(of: (Int, [PluginCatalogEntry]).self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    let repoURL = url.absoluteString
                    do {
                        // force means "check for updates now" — a locally cached response
                        // (the CDN sends max-age=3600) would defeat that, so bypass URLCache.
                        var request = URLRequest(url: url)
                        if force { request.cachePolicy = .reloadIgnoringLocalCacheData }
                        let (data, response) = try await URLSession.shared.data(for: request)
                        yomiLogNetwork(request, response: response, data: data)
                        let parsed = Self.parseEntries(from: data)
                        return (index, parsed.map { entry -> PluginCatalogEntry in var e = entry; e.repoURL = repoURL; return e.withInstallIds() })
                    } catch {
                        return (index, [])
                    }
                }
            }
            var all: [(Int, [PluginCatalogEntry])] = []
            for await result in group {
                all.append(result)
            }
            return all.sorted { $0.0 < $1.0 }.map(\.1)
        }

        // Merge: first-wins dedup by id, sorted by name
        var seen = Set<String>()
        var merged: [PluginCatalogEntry] = []
        for batch in results {
            for entry in batch {
                if seen.insert(entry.id).inserted {
                    merged.append(entry)
                }
            }
        }
        merged.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        await MainActor.run {
            entries = merged
            lastFetchedAt = Date()
            isLoading = false
            if merged.isEmpty {
                errorMessage = "Could not load any catalog. Check your repository URLs."
            }
            ExtensionManager.shared.relinkOrphanedTitles(catalog: merged)
        }
    }

    // MARK: - Multi-format parser

    /// Tries Yomi native → LNReader → Mangayomi formats in order. Entries are decoded one by one: a single malformed
    /// entry used to fail the whole array, so one typo emptied the repository (#154). The first format that reads
    /// at least one entry wins; entries it can't read are skipped.
    nonisolated static func parseEntries(from data: Data) -> [PluginCatalogEntry] {
        let entries = decodeEach(PluginCatalogEntry.self, from: data)
        if !entries.isEmpty { return entries }
        let lnEntries = decodeEach(LNReaderEntry.self, from: data)
        if !lnEntries.isEmpty { return lnEntries.map { $0.toEntry() } }
        return decodeEach(MangayomiEntry.self, from: data)
            .filter { $0.sourceCodeUrl.lowercased().hasSuffix(".js") }
            .map { $0.toEntry() }
    }

    private nonisolated static func decodeEach<T: Decodable>(_ type: T.Type, from data: Data) -> [T] {
        (try? JSONDecoder().decode([Lenient<T>].self, from: data))?.compactMap { $0.value } ?? []
    }

    // MARK: - Helpers

    func isInstalled(_ entry: PluginCatalogEntry) -> Bool {
        ExtensionManager.shared.installed.contains(where: entry.matches)
    }

    func isGroupInstalled(_ group: PluginCatalogGroup) -> Bool {
        group.entries.contains { isInstalled($0) }
    }

    /// Returns the catalog entry for an installed extension if a newer version is available.
    func availableUpdate(for ext: Extension) -> PluginCatalogEntry? {
        let entry = entries.first(where: { $0.installIds.contains(ext.id) }) ?? entries.first(where: { $0.matches(ext) })
        guard let entry else { return nil }
        return Self.isNewer(entry.version, than: ext.version) ? entry : nil
    }

    private static func isNewer(_ catalog: String, than installed: String) -> Bool {
        let cv = catalog.split(separator: ".").compactMap { Int($0) }
        let iv = installed.split(separator: ".").compactMap { Int($0) }
        guard !cv.isEmpty, !iv.isEmpty else { return catalog != installed }
        let len = max(cv.count, iv.count)
        for i in 0..<len {
            let c = i < cv.count ? cv[i] : 0
            let ins = i < iv.count ? iv[i] : 0
            if c != ins { return c > ins }
        }
        return false
    }

    /// Groups entries by name (case-insensitive) within one repository, sorted alphabetically.
    /// Multi-language sources (same name, different lang) are collapsed into one group; the same name in two
    /// repositories stays two groups (merging them offered "English" twice, S140).
    var groupedEntries: [PluginCatalogGroup] {
        var groups: [String: [PluginCatalogEntry]] = [:]
        for entry in entries {
            groups["\(entry.repoURL)\n\(entry.name.lowercased())", default: []].append(entry)
        }
        return groups.values
            .map { PluginCatalogGroup(name: $0[0].name, entries: $0.sorted { $0.language < $1.language }) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Short display label derived from the catalog URL (e.g. "Yomi", "LNReader", "Mangayomi").
    nonisolated static func repoLabel(from repoURL: String) -> String {
        if repoURL.contains("yomi-plugins") { return "Yomi" }
        if repoURL.lowercased().contains("lnreader") { return "LNReader" }
        if repoURL.contains("mangayomi") { return "Mangayomi" }
        guard let url = URL(string: repoURL), let host = url.host else { return "" }
        // A repository on GitHub is named by its owner ("keiyoushi"), not by the host every one of them shares.
        let parts = url.pathComponents.filter { $0 != "/" }
        if host.hasSuffix("github.io") { return String(host.split(separator: ".")[0]) }
        if ["github.com", "raw.githubusercontent.com"].contains(host), let owner = parts.first { return owner }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    func invalidateCache() {
        lastFetchedAt = nil
    }
}
