import Foundation

/// Manages installing, listing, and removing extensions (JS plugins)
@Observable
final class ExtensionManager {

    // MARK: - Singleton

    static let shared = ExtensionManager()
    private init() {
        loadInstalled()
    }

    // MARK: - State

    var installed: [Extension] = []
    var isLoading: Bool = false
    var errorMessage: String? = nil

    // MARK: - Directories

    private var extensionsDirectory: URL {
        let docs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Extensions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Load

    /// Loads installed extensions from the database
    private func loadInstalled() {
        installed = (try? ExtensionQueries.fetchInstalled()) ?? []
    }

    // MARK: - Install

    /// Downloads the JS file from sourceListURL and registers the extension
    func install(_ ext: Extension) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // Download JS file
            let (data, _) = try await URLSession.shared.data(from: ext.sourceListURL)

            // Save to local filesystem
            let localURL = extensionsDirectory.appendingPathComponent("\(ext.id).js")
            try data.write(to: localURL)

            // Persist to database
            var installed = ext
            installed = Extension(
                id:            ext.id,
                name:          ext.name,
                version:       ext.version,
                language:      ext.language,
                iconURL:       ext.iconURL,
                sourceListURL: localURL,
                isInstalled:   true,
                isNSFW:        ext.isNSFW,
                sourceIds:     ext.sourceIds
            )
            try ExtensionQueries.upsert(installed)
            loadInstalled()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Remove

    /// Deletes the JS file and removes the extension from the database
    func remove(_ ext: Extension) {
        let localURL = extensionsDirectory.appendingPathComponent("\(ext.id).js")
        try? FileManager.default.removeItem(at: localURL)
        try? ExtensionQueries.delete(id: ext.id)
        loadInstalled()
    }

    // MARK: - Bridge

    /// Returns a JSBridge instance for the given installed extension
    func bridge(for ext: Extension) -> JSBridge? {
        JSBridge(scriptURL: ext.sourceListURL)
    }
}
