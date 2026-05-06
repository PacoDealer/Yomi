import Foundation
import Observation

// MARK: - PluginCatalogEntry

struct PluginCatalogEntry: Codable, Identifiable {
    let id: String
    let name: String
    let version: String
    let language: String
    let description: String?
    let iconURL: String?
    let fileURL: String
    let isNSFW: Bool
    var repoURL: String = ""
    var isNovel: Bool = false

    private enum CodingKeys: String, CodingKey {
        case id, name, version, language, description, iconURL, fileURL, isNSFW
    }
}

// MARK: - PluginCatalogGroup

struct PluginCatalogGroup: Identifiable {
    let name: String
    let entries: [PluginCatalogEntry]
    var id: String { name }
    var isMultiLang: Bool { entries.count > 1 }
    var primaryEntry: PluginCatalogEntry { entries[0] }
}

// MARK: - LNReader catalog format

private struct LNReaderEntry: Decodable {
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
        entry.isNovel = true
        return entry
    }
}

// MARK: - Mangayomi catalog format

private struct MangayomiEntry: Decodable {
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

// MARK: - PluginCatalogService

@Observable final class PluginCatalogService {

    // MARK: - Singleton

    static let shared = PluginCatalogService()
    init() {}

    // MARK: - State

    var entries: [PluginCatalogEntry] = []
    var isLoading: Bool = false
    var errorMessage: String? = nil
    private var lastFetchedAt: Date? = nil
    private let ttl: TimeInterval = 3600

    // MARK: - Fetch

    /// Fetches catalogs from all configured URLs in parallel, merges by id (first-wins), sorts by name.
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

        guard !urls.isEmpty else {
            await MainActor.run {
                errorMessage = "No catalog URLs configured"
                isLoading = false
            }
            return
        }

        // Fetch all catalogs concurrently; per-URL failures return empty (don't break the group)
        let results: [[PluginCatalogEntry]] = await withTaskGroup(of: [PluginCatalogEntry].self) { group in
            for url in urls {
                group.addTask {
                    let repoURL = url.absoluteString
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        let parsed = Self.parseEntries(from: data)
                        return parsed.map { entry -> PluginCatalogEntry in var e = entry; e.repoURL = repoURL; return e }
                    } catch {
                        return []
                    }
                }
            }
            var all: [[PluginCatalogEntry]] = []
            for await result in group {
                all.append(result)
            }
            return all
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
        }
    }

    // MARK: - Multi-format parser

    /// Tries Yomi native → LNReader → Mangayomi formats in order.
    private nonisolated static func parseEntries(from data: Data) -> [PluginCatalogEntry] {
        if let entries = try? JSONDecoder().decode([PluginCatalogEntry].self, from: data) {
            return entries
        }
        if let lnEntries = try? JSONDecoder().decode([LNReaderEntry].self, from: data) {
            return lnEntries.map { $0.toEntry() }
        }
        if let mgEntries = try? JSONDecoder().decode([MangayomiEntry].self, from: data) {
            return mgEntries
                .filter { $0.sourceCodeUrl.lowercased().hasSuffix(".js") }
                .map { $0.toEntry() }
        }
        return []
    }

    // MARK: - Helpers

    func isInstalled(_ entry: PluginCatalogEntry) -> Bool {
        ExtensionManager.shared.installed.contains(where: { $0.id == entry.id || $0.name == entry.name })
    }

    func isGroupInstalled(_ group: PluginCatalogGroup) -> Bool {
        group.entries.contains { isInstalled($0) }
    }

    /// Returns the catalog entry for an installed extension if a newer version is available.
    func availableUpdate(for ext: Extension) -> PluginCatalogEntry? {
        let entry = entries.first(where: { $0.id == ext.id }) ?? entries.first(where: { $0.name == ext.name })
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

    /// Groups entries by name (case-insensitive), sorted alphabetically.
    /// Multi-language sources (same name, different lang) are collapsed into one group.
    var groupedEntries: [PluginCatalogGroup] {
        var groups: [String: [PluginCatalogEntry]] = [:]
        for entry in entries {
            groups[entry.name.lowercased(), default: []].append(entry)
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
        return URL(string: repoURL)?.host.map { String($0.prefix(20)) } ?? ""
    }

    func invalidateCache() {
        lastFetchedAt = nil
    }
}
