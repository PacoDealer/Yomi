import Foundation
import CryptoKit

/// Manages installing, listing, and removing extensions (JS plugins)
@Observable
final class ExtensionManager {

    // MARK: - Singleton

    static let shared = ExtensionManager()
    private init() {
        loadInstalled()
        #if DEBUG
        seedBundledPlugins()
        #endif
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

    /// Loads installed extensions from the database, pruning any row whose backing .js
    /// file is missing on disk. Orphaned rows accumulate across ID-scheme migrations
    /// (e.g. an old sha256-based id superseded by a catalog id like "com.yomi.novelfire")
    /// since nothing else ever deletes the stale row — left alone they duplicate every
    /// name-matched entry in Plugins/Browse and can shadow the real, working row wherever
    /// lookups use `.first(where: { $0.id == sourceId })`.
    private func loadInstalled() {
        let all = (try? ExtensionQueries.fetchInstalled()) ?? []
        let dir = extensionsDirectory
        var valid: [Extension] = []
        for ext in all {
            let localURL = dir.appendingPathComponent("\(ext.id).js")
            if FileManager.default.fileExists(atPath: localURL.path) {
                valid.append(ext)
            } else {
                try? ExtensionQueries.delete(id: ext.id)
            }
        }
        installed = valid
    }

    /// MainActor-hopped form of `loadInstalled()` for call sites resuming after an `await` —
    /// see `install()`/`remove()`. `loadInstalled()` itself stays synchronous for `init()`'s
    /// call site, which never crosses an actor boundary.
    private func loadInstalledOnMain() async {
        await MainActor.run { loadInstalled() }
    }

    // MARK: - Seed Bundled Plugins

    /// Copies bundled JS plugins from the app bundle into Documents/Extensions/ and upserts DB records.
    /// In production the .js files are not bundled, so all guard checks silently skip (safe no-op).
    func seedBundledPlugins() {
        let plugins: [(filename: String, name: String, isNSFW: Bool)] = [
            ("mangadex",     "MangaDex",    false),
            ("asurascans",   "Asura Scans",  true),
            ("aquamanga",    "Aqua Manga",  false),
            ("royalroad",    "Royal Road",  false),
            ("scribblehub",  "ScribbleHub", false),
            ("novelfire",    "NovelFire",   false),
            ("freewebnovel", "FreeWebNovel",false),
            ("novelbin",     "NovelBin",    false)
            // comick: removed from catalog (Cloudflare 403 from non-browser clients)
            // lightnovelworld: removed from catalog (site permanently closed Jan 2026)
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

            // Remove any legacy com.yomi.{filename} entry left over from old ID scheme
            let legacyId = "com.yomi.\(plugin.filename)"
            if installed.contains(where: { $0.id == legacyId }) {
                try? ExtensionQueries.delete(id: legacyId)
                try? FileManager.default.removeItem(
                    at: extensionsDirectory.appendingPathComponent("\(legacyId).js"))
                installed.removeAll { $0.id == legacyId }
            }

            if !installed.contains(where: { $0.id == id }) {
                installed.append(ext)
            }
        }
    }

    // MARK: - Install

    /// Downloads the JS file from sourceListURL and registers the extension
    func install(_ ext: Extension) async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        defer { Task { await MainActor.run { isLoading = false } } }

        do {
            // Install/reinstall means "get the current plugin" — a locally cached response
            // (the CDN sends max-age=3600) would silently re-serve stale plugin code, so
            // bypass URLCache the same way PluginCatalogService's force refresh does.
            var request = URLRequest(url: ext.sourceListURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            yomiLogNetwork(request, response: response, data: data)

            // An existing install under a different id (e.g. from an old sha256-hash ID
            // scheme, now superseded by a stable catalog id like "com.yomi.novelfire") would
            // otherwise coexist with this new row forever — both name-match the same catalog
            // entry, so Plugins/Browse show the same source twice. Retire the old one. Gated on
            // sharing the same sourceListURL host so this never touches a genuinely different
            // plugin (e.g. a custom "Install from URL" install from an unrelated domain) that
            // happens to share a display name with a catalog entry — see finding #83.
            for stale in installed
            where stale.name.lowercased() == ext.name.lowercased()
                && stale.id != ext.id
                && stale.sourceListURL.host == ext.sourceListURL.host {
                try? FileManager.default.removeItem(
                    at: extensionsDirectory.appendingPathComponent("\(stale.id).js"))
                try? ExtensionQueries.delete(id: stale.id)
            }

            let localURL = extensionsDirectory.appendingPathComponent("\(ext.id).js")
            try data.write(to: localURL)

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
            await loadInstalledOnMain()
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
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
