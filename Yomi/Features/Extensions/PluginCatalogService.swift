import Foundation
import Observation

// MARK: - PluginCatalogEntry

struct PluginCatalogEntry: Codable, Identifiable {
    let id: String
    let name: String
    let version: String
    let language: String
    let description: String
    let iconURL: String?
    let fileURL: String
    let isNSFW: Bool
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
    private let ttl: TimeInterval = 3600 // 1 hour

    // MARK: - Fetch

    /// Fetches the catalog from Firebase. Skipped if data is fresh (< 1 hour old).
    /// Pass `force: true` to bypass TTL (e.g. pull-to-refresh).
    func fetchCatalog(force: Bool = false) async {
        guard !isLoading else { return }
        if !force, !entries.isEmpty, let last = lastFetchedAt, Date().timeIntervalSince(last) < ttl {
            return
        }
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            guard let url = URL(string: AppSettings.shared.pluginCatalogURL) else {
                await MainActor.run {
                    errorMessage = "Invalid catalog URL"
                    isLoading = false
                }
                return
            }
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode([PluginCatalogEntry].self, from: data)
            await MainActor.run {
                entries = decoded
                lastFetchedAt = Date()
                isLoading = false
            }
        } catch is CancellationError {
            await MainActor.run { isLoading = false }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    // MARK: - Helpers

    func isInstalled(_ entry: PluginCatalogEntry) -> Bool {
        ExtensionManager.shared.installed.contains(where: { $0.name == entry.name })
    }
}
