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

    // MARK: - Update

    /// Replaces an installed plugin's script with a catalog version, keeping the installed id. Titles store
    /// their plugin id as `sourceId`, so installing the update under the catalog's id (which differs for
    /// plugins added by URL or under an old id scheme) left them on the old script and the old row
    /// asking for an update forever. Also retires same-name copies such an update made before, when no
    /// title uses them.
    func update(_ ext: Extension, to entry: PluginCatalogEntry) async {
        guard let fileURL = URL(string: entry.fileURL) else { return }
        await install(Extension(
            id:            ext.id,
            name:          ext.name,
            version:       entry.version,
            language:      ext.language,
            iconURL:       entry.iconURL.flatMap { URL(string: $0) } ?? ext.iconURL,
            sourceListURL: fileURL,
            isInstalled:   true,
            isNSFW:        entry.isNSFW,
            sourceIds:     ext.sourceIds
        ))
        guard errorMessage == nil else { return }
        let copies = installed.filter {
            $0.id != ext.id && ($0.name.lowercased() == ext.name.lowercased() || entry.matches($0))
        }
        for copy in copies where !((try? ExtensionQueries.hasTitles(sourceId: copy.id)) ?? true) {
            remove(copy)
        }
    }

    /// Titles whose plugin row is gone but whose plugin is installed under another id — left behind when the old
    /// update path installed a second copy and the user deleted the first (S140). Old ids are recomputable:
    /// "Install from URL" used sha256(plugin URL), the DEBUG seed sha256(file name). Moves those titles over.
    func relinkOrphanedTitles(catalog: [PluginCatalogEntry]) {
        guard let used = try? ExtensionQueries.titleSourceIds() else { return }
        let installedIds = Set(installed.map(\.id))
        let orphans = used.subtracting(installedIds)
        guard !orphans.isEmpty else { return }
        for ext in installed {
            guard let entry = catalog.first(where: { $0.installIds.contains(ext.id) })
                    ?? catalog.first(where: { $0.matches(ext) }) else { continue }
            for old in entry.installIds where old != ext.id && orphans.contains(old) {
                try? ExtensionQueries.moveTitles(from: old, to: ext.id)
                AppSettings.shared.recentSourceKeys = AppSettings.shared.recentSourceKeys.map {
                    $0 == BrowseSourceKey.plugin(old) ? BrowseSourceKey.plugin(ext.id) : $0
                }
            }
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

    /// Returns the shared JSBridge for an installed extension, building it on first use.
    /// Building one costs ~800 ms on device (new JSContext + ~450 KB of bundled libs, RESEARCH §23.6), so
    /// callers should reach this off the main actor. Cached per source and rebuilt when the script file
    /// changes (install/update rewrites it). JSBridge serializes its own calls, so sharing is safe.
    nonisolated func bridge(for ext: Extension) -> JSBridge? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let localURL = docs
            .appendingPathComponent("Extensions", isDirectory: true)
            .appendingPathComponent("\(ext.id).js")
        let stamp = (try? FileManager.default.attributesOfItem(atPath: localURL.path)[.modificationDate]) as? Date
        guard let stamp else { return nil }
        Self.bridgeCacheLock.lock(); defer { Self.bridgeCacheLock.unlock() }
        if let cached = Self.bridgeCache[ext.id], cached.stamp == stamp { return cached.bridge }
        guard let built = JSBridge(scriptURL: localURL) else { return nil }
        Self.bridgeCache[ext.id] = (stamp, built)
        return built
    }

    /// `bridge(for:)` from a main-actor caller without blocking the UI on a first build.
    nonisolated func loadBridge(for ext: Extension) async -> JSBridge? {
        await Task.detached(priority: .userInitiated) { self.bridge(for: ext) }.value
    }

    // Held while building, so two screens opening the same source build it once.
    nonisolated private static let bridgeCacheLock = NSLock()
    nonisolated(unsafe) private static var bridgeCache: [String: (stamp: Date, bridge: JSBridge)] = [:]

    // MARK: - Helpers

    private func sha256id(_ string: String) -> String {
        let hash = SHA256.hash(data: Data(string.utf8))
        return String(hash.compactMap { String(format: "%02x", $0) }.joined().prefix(32))
    }
}
