import Foundation
import CryptoKit

/// Manages installing, listing, and removing extensions (JS plugins)
@Observable
final class ExtensionManager {

    // MARK: - Singleton

    static let shared = ExtensionManager()
    private init() {
        loadInstalled()
        seedBundledPlugins()
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

    // MARK: - Seed Bundled Plugins

    /// Copies bundled JS plugins from the app bundle into Documents/Extensions/ on every launch
    /// (skips copy if the file is already on disk) and upserts the DB record.#imageLiteral(resourceName: "Screenshot 2026-03-23 at 12.37.05 AM.png")
    func seedBundledPlugins() {
        let plugins: [(filename: String, name: String, isNSFW: Bool)] = [
            ("mangadex",   "MangaDex",    false),
            ("asurascans", "Asura Scans", true),
            ("aquamanga",  "Aqua Manga",  false),
            ("royalroad",  "Royal Road",  false),
            ("scribblehub","ScribbleHub", false),
            ("novelfire",  "NovelFire",   false),
            ("comick",     "Comick",      false)
        ]

        for plugin in plugins {
            guard let bundleURL = Bundle.main.url(forResource: plugin.filename, withExtension: "js")
            else { continue }

            let id = sha256id(plugin.filename)
            let destURL = extensionsDirectory.appendingPathComponent("\(id).js")

            // Always overwrite bundled plugins so fixes take effect on next launch
            try? FileManager.default.removeItem(at: destURL)
            guard (try? FileManager.default.copyItem(at: bundleURL, to: destURL)) != nil
            else { continue }

            let ext = Extension(
                id:            id,
                name:          plugin.name,
                version:       "1.0.0",
                language:      "en",
                iconURL:       nil,
                sourceListURL: destURL,
                isInstalled:   true,
                isNSFW:        plugin.isNSFW,
                sourceIds:     []
            )
            try? ExtensionQueries.upsert(ext)

            if !installed.contains(where: { $0.id == id }) {
                installed.append(ext)
            }
        }
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
            let updated = Extension(
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
            try ExtensionQueries.upsert(updated)
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

    /// Returns a JSBridge instance for the given installed extension.
    /// nonisolated so it can be called from Task.detached without actor hopping.
    nonisolated func bridge(for ext: Extension) -> JSBridge? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let localURL = docs
            .appendingPathComponent("Extensions", isDirectory: true)
            .appendingPathComponent("\(ext.id).js")
        return JSBridge(scriptURL: localURL)
    }

    // MARK: - Helpers

    private func sha256id(_ string: String) -> String {
        let hash = SHA256.hash(data: Data(string.utf8))
        return String(hash.compactMap { String(format: "%02x", $0) }.joined().prefix(32))
    }
}
