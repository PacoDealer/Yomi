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
        PluginCatalogEntry(
            id: id,
            name: name,
            version: version,
            language: lang,
            description: site,
            iconURL: iconUrl,
            fileURL: url,
            isNSFW: false
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
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        return Self.parseEntries(from: data)
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

    /// Tries Yomi native format, falls back to LNReader format.
    private nonisolated static func parseEntries(from data: Data) -> [PluginCatalogEntry] {
        if let entries = try? JSONDecoder().decode([PluginCatalogEntry].self, from: data) {
            return entries
        }
        if let lnEntries = try? JSONDecoder().decode([LNReaderEntry].self, from: data) {
            return lnEntries.map { $0.toEntry() }
        }
        return []
    }

    // MARK: - Helpers

    func isInstalled(_ entry: PluginCatalogEntry) -> Bool {
        ExtensionManager.shared.installed.contains(where: { $0.name == entry.name })
    }

    func invalidateCache() {
        lastFetchedAt = nil
    }
}
