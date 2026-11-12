import Foundation
import CryptoKit

// MARK: - Models

/// One source inside a Mihon extension. A multi-language extension (e.g. MangaFire) has one per language.
nonisolated struct KeiyoushiSource: Codable, Hashable, Identifiable, Sendable {
    /// Mihon's signed 64-bit source id, as a decimal string — the same id Mihon/Tachiyomi backups store,
    /// and the one M-Extension-Server's `sourceId` selects by.
    let id: String
    let name: String
    let lang: String
    let homeURL: String
}

/// One installable extension from a Mihon extension repository index (`index.pb`).
nonisolated struct KeiyoushiExtension: Codable, Hashable, Identifiable, Sendable {
    let name: String
    let packageName: String
    let versionName: String
    let versionCode: Int64
    let apkURL: String
    let iconURL: String
    /// Repository content warning: 0 unspecified, 1 safe, 2 mixed, 3 NSFW.
    let contentWarning: Int
    let sources: [KeiyoushiSource]
    /// The repository index this entry came from (S142: several Mihon repositories). nil in installs saved earlier.
    var repoURL: String? = nil

    var id: String { packageName }
    var isNSFW: Bool { contentWarning == 3 }
    /// "all" for a multi-language extension, like Mihon shows it.
    var lang: String {
        let langs = Set(sources.map(\.lang))
        return langs.count == 1 ? langs.first! : "all"
    }
}

/// An extension installed on this device: the repository entry plus where its APK lives.
nonisolated struct InstalledKeiyoushiExtension: Codable, Hashable, Identifiable, Sendable {
    var info: KeiyoushiExtension
    /// File name under `KeiyoushiRepository.apkDirectory`.
    var apkFileName: String
    var installedAt: Date
    /// Languages the user chose to show for a multi-language extension (MangaFire lists ~10). `nil` = all of
    /// them, which is also what installs saved before this field existed decode to.
    var enabledLangs: [String]? = nil
    /// SHA-256 of the certificate that signed this APK (`ApkSignature`, S193). Updates must be signed by the same key.
    /// nil in installs saved earlier — the APK on disk is checked instead at the next update.
    var signerSHA256: String? = nil

    var id: String { info.packageName }

    /// The sources Browse lists: the chosen languages, or every source when nothing was chosen.
    var enabledSources: [KeiyoushiSource] {
        guard let enabledLangs, !enabledLangs.isEmpty else { return info.sources }
        let chosen = info.sources.filter { enabledLangs.contains($0.lang) }
        return chosen.isEmpty ? info.sources : chosen
    }
}

enum KeiyoushiError: LocalizedError {
    case badRepoURL
    case insecure
    case badSignature
    case signerChanged
    case notAnIndex
    case download(String)
    case runtimeUnavailable
    case bridge(String)
    /// An index that holds no list, only the link to one (index.pb field 102). Followed once by `fetchIndex`.
    case pointsTo(String)

    var errorDescription: String? {
        switch self {
        case .badRepoURL: return String(localized: "That isn't a valid repository URL.")
        case .insecure: return String(localized: "Extensions are only downloaded over a secure (https) link.")
        case .badSignature: return String(localized: "This extension isn't properly signed, so it wasn't installed.")
        case .signerChanged:
            return String(localized: "This update is signed by a different key than the installed extension, so it wasn't installed.")
        case .notAnIndex: return String(localized: "That link isn't a Mihon extension repository (index.pb or index.min.json).")
        case .download(let why): return String(localized: "Download failed — \(why)")
        case .runtimeUnavailable:
            return String(localized: "Keiyoushi extensions need the on-device runtime, which this build doesn't include.")
        case .bridge(let why): return why
        case .pointsTo: return KeiyoushiError.notAnIndex.errorDescription
        }
    }
}

// MARK: - Repository + installed extensions

/// One Mihon extension repository the user added, with its last decoded index.
struct MihonRepo: Identifiable {
    let url: String
    var name: String?
    var extensions: [KeiyoushiExtension]
    var error: String?
    var id: String { url }
}

/// The user's Mihon extension repositories (Keiyoushi and any other Mihon/Tachiyomi repository) and the extensions
/// installed from them.
///
/// S142: any number of repositories, in either index format — Keiyoushi's protobuf `index.pb` (since 2026-08) or
/// the classic `index.min.json` other repositories still publish (Suwayomi's, Kavita's — checked live). Before,
/// Yomi held one repository and adding a second replaced the first.
///
/// Extensions run on the device through the embedded JVM (`KeiyoushiBridge`), so "install" just downloads the
/// extension's APK into Application Support; the bridge converts and loads it on first use. Each index is cached
/// on disk so the list still shows offline.
@Observable
final class KeiyoushiRepository {
    static let shared = KeiyoushiRepository()

    private(set) var repos: [MihonRepo] = []
    /// Every repository's extensions; a package in two repositories appears once (highest version).
    private(set) var available: [KeiyoushiExtension] = []
    private(set) var installed: [InstalledKeiyoushiExtension] = []
    private(set) var isLoading = false
    var errorMessage: String?
    /// When every repository index was last fetched (S147). Starts from the oldest on-disk cache, so a list left
    /// over from weeks ago counts as stale on the first screen that asks.
    private var lastRefreshAt: Date?
    /// Repository indexes go stale as extensions update — and an old index points at APKs the repository has
    /// already deleted (PacoDealer's phone, S147: a Sep 24 index made MangaPill / Qi Scans / Webtoons 404).
    nonisolated static let maxIndexAge: TimeInterval = 6 * 3600

    nonisolated static let rootDirectory: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Keiyoushi", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    nonisolated static let apkDirectory: URL = {
        let dir = rootDirectory.appendingPathComponent("apks", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    nonisolated private static let installedFile = rootDirectory.appendingPathComponent("installed.json")
    /// The single-repository cache from before S142 — read once as the first repository's cache.
    nonisolated private static let legacyIndexCacheFile = rootDirectory.appendingPathComponent("index.pb")

    nonisolated private static func cacheFile(for url: String) -> URL {
        let key = SHA256.hash(data: Data(url.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return rootDirectory.appendingPathComponent("index-\(key).cache")
    }

    /// The repository's name from its `repo.json` (A9), for indexes that carry none (index.min.json).
    nonisolated private static func nameFile(for url: String) -> URL {
        cacheFile(for: url).deletingPathExtension().appendingPathExtension("name")
    }

    private init() {
        installed = Self.loadInstalled()
        let urls = AppSettings.shared.mihonRepoURLs
        repos = urls.enumerated().map { i, url in
            var data = try? Data(contentsOf: Self.cacheFile(for: url))
            if data == nil, i == 0 { data = try? Data(contentsOf: Self.legacyIndexCacheFile) }
            let decoded = data.flatMap { try? Self.decodeIndex($0, repoURL: url) }
            let name = decoded.flatMap { $0.name.isEmpty ? nil : $0.name }
                ?? (try? String(contentsOf: Self.nameFile(for: url), encoding: .utf8))
            return MihonRepo(url: url, name: name, extensions: decoded?.extensions ?? [])
        }
        rebuildAvailable()
        let cacheDates = urls.enumerated().map { i, url -> Date? in
            let file = i == 0 && !FileManager.default.fileExists(atPath: Self.cacheFile(for: url).path)
                ? Self.legacyIndexCacheFile : Self.cacheFile(for: url)
            return (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
        lastRefreshAt = cacheDates.contains(where: { $0 == nil }) ? nil : cacheDates.compactMap { $0 }.min()
    }

    /// Re-fetches the repository indexes when they are older than `maxIndexAge` (or were never fetched).
    func refreshIfStale() async {
        guard !AppSettings.shared.mihonRepoURLs.isEmpty, !isLoading else { return }
        if let last = lastRefreshAt, Date().timeIntervalSince(last) < Self.maxIndexAge { return }
        await refresh()
    }

    /// Every enabled source across all installed extensions (languages the user turned off are left out).
    var installedSources: [(ext: InstalledKeiyoushiExtension, source: KeiyoushiSource)] {
        installed.flatMap { ext in ext.enabledSources.map { (ext, $0) } }
    }

    /// Chooses which languages of a multi-language extension Browse shows.
    func setEnabledLangs(_ langs: [String], for packageName: String) {
        guard let i = installed.firstIndex(where: { $0.id == packageName }) else { return }
        let all = Set(installed[i].info.sources.map(\.lang))
        installed[i].enabledLangs = Set(langs) == all ? nil : langs.sorted()
        saveInstalled()
    }

    func installedExtension(forSourceId sourceId: String) -> InstalledKeiyoushiExtension? {
        installed.first { $0.info.sources.contains { $0.id == sourceId } }
    }

    /// A newer version from the SAME repository the extension was installed from (S189 audit #9): a second repository
    /// listing the same package name with a higher version must not be able to replace its APK. Installs from before
    /// the repository was remembered (`repoURL` nil) keep the old any-repository rule.
    func availableUpdate(for ext: InstalledKeiyoushiExtension) -> KeiyoushiExtension? {
        let candidates: [KeiyoushiExtension]
        if let origin = ext.info.repoURL {
            candidates = isTurnedOff(origin) ? [] : repos.first { $0.url == origin }?.extensions ?? []
        } else {
            candidates = available
        }
        guard let remote = candidates.first(where: { $0.packageName == ext.info.packageName }),
              remote.versionCode > ext.info.versionCode else { return nil }
        return remote
    }

    /// The repository's own name ("Keiyoushi"), or the link's host when the index has none.
    func repoName(for ext: KeiyoushiExtension) -> String {
        let repo = repos.first { $0.url == ext.repoURL } ?? repos.first
        return repo?.name.flatMap { $0.isEmpty ? nil : $0 }
            ?? repo.map { PluginCatalogService.repoLabel(from: $0.url) } ?? "Mihon"
    }

    func isTurnedOff(_ url: String) -> Bool { AppSettings.shared.turnedOffMihonRepoURLs.contains(url) }

    /// Turns a repository off or back on (A9). Off: its extensions leave the list and get no updates; nothing is
    /// deleted. On: fetched again at once.
    func setRepository(_ url: String, turnedOff: Bool) async {
        var list = AppSettings.shared.turnedOffMihonRepoURLs.filter { $0 != url }
        if turnedOff { list.append(url) }
        AppSettings.shared.turnedOffMihonRepoURLs = list
        rebuildAvailable()
        if !turnedOff { await refresh() }
    }

    private func rebuildAvailable() {
        var best: [String: KeiyoushiExtension] = [:]
        for ext in repos.filter({ !isTurnedOff($0.url) }).flatMap(\.extensions) {
            if let have = best[ext.packageName], have.versionCode >= ext.versionCode { continue }
            best[ext.packageName] = ext
        }
        available = best.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: Repositories

    /// Adds a repository link. Accepts the index itself (…/index.pb, …/index.min.json) or the repository's folder,
    /// in which case both index names are tried. Throws if the link isn't a Mihon repository.
    func addRepository(_ link: String) async throws {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true, url.host != nil else {
            throw KeiyoushiError.badRepoURL
        }
        guard PluginNetworkPolicy.isSecureDownload(url) else { throw KeiyoushiError.insecure }
        var candidates = Self.indexCandidates(for: url)
        // repo.json's `index_v2` wins (A9): Keiyoushi's old index.min.json — the link most guides still give — is
        // now a two-entry "Outdated App" stub, and repo.json next to it points at the real index.pb.
        if let first = candidates.first, let v2 = await Self.fetchRepoMeta(near: first).indexV2 {
            candidates.removeAll { $0 == v2 }
            candidates.insert(v2, at: 0)
        }
        var lastError: Error = KeiyoushiError.notAnIndex
        for candidate in candidates {
            let key = candidate.absoluteString
            guard !AppSettings.shared.mihonRepoURLs.contains(key) else { return }
            do {
                let (data, decoded) = try await Self.fetchIndex(key)
                try? data.write(to: Self.cacheFile(for: key), options: .atomic)
                Self.saveName(decoded.name, for: key)
                AppSettings.shared.mihonRepoURLs.append(key)
                repos.append(MihonRepo(url: key, name: decoded.name, extensions: decoded.extensions))
                rebuildAvailable()
                return
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// The index links a pasted repository link may stand for (A9, S212). An index link is itself; a folder is tried
    /// as `index.pb` then `index.min.json`; a GitHub page (`github.com/<owner>/<repo>[/tree/<branch>/<path>]`, what
    /// people copy from a browser) becomes its raw files — branch `repo` when none is named, Mihon's convention for
    /// published extension repositories. A `…/blob|raw/<branch>/…/index.pb` link becomes that file's raw link.
    nonisolated static func indexCandidates(for url: URL) -> [URL] {
        func indexes(in folder: URL) -> [URL] {
            [folder.appendingPathComponent("index.pb"), folder.appendingPathComponent("index.min.json")]
        }
        let isIndex = { (u: URL) in u.path.lowercased().hasSuffix(".pb") || u.path.lowercased().hasSuffix(".json") }
        if url.host()?.lowercased() == "github.com" {
            let parts = url.pathComponents.filter { $0 != "/" }
            if parts.count >= 2, var raw = URL(string: "https://raw.githubusercontent.com") {
                let repo = parts[1].hasSuffix(".git") ? String(parts[1].dropLast(4)) : parts[1]
                raw.append(path: parts[0])
                raw.append(path: repo)
                if parts.count >= 4, ["tree", "blob", "raw"].contains(parts[2]) {
                    for p in parts[3...] { raw.append(path: p) }
                } else {
                    raw.append(path: "repo")
                }
                return isIndex(raw) ? [raw] : indexes(in: raw)
            }
        }
        return isIndex(url) ? [url] : indexes(in: url)
    }

    nonisolated private static func saveName(_ name: String, for url: String) {
        let file = nameFile(for: url)
        if name.isEmpty { try? FileManager.default.removeItem(at: file) }
        else { try? name.write(to: file, atomically: true, encoding: .utf8) }
    }

    /// Removes a repository. Extensions already added from it stay installed.
    func removeRepository(_ url: String) {
        AppSettings.shared.mihonRepoURLs.removeAll { $0 == url }
        AppSettings.shared.turnedOffMihonRepoURLs.removeAll { $0 == url }
        repos.removeAll { $0.url == url }
        try? FileManager.default.removeItem(at: Self.cacheFile(for: url))
        try? FileManager.default.removeItem(at: Self.nameFile(for: url))
        rebuildAvailable()
    }

    /// Re-fetches every repository's index. A repository that fails keeps its last list and shows its error.
    func refresh() async {
        let urls = AppSettings.shared.mihonRepoURLs
        repos = urls.map { url in repos.first { $0.url == url } ?? MihonRepo(url: url, extensions: []) }
        guard !urls.isEmpty else { available = []; return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        for url in urls where !isTurnedOff(url) {
            if url.lowercased().hasSuffix(".json"), await moveToIndexV2(url) { continue }
            do {
                let (data, decoded) = try await Self.fetchIndex(url)
                try? data.write(to: Self.cacheFile(for: url), options: .atomic)
                Self.saveName(decoded.name, for: url)
                if let i = repos.firstIndex(where: { $0.url == url }) {
                    repos[i] = MihonRepo(url: url, name: decoded.name, extensions: decoded.extensions)
                }
            } catch {
                if let i = repos.firstIndex(where: { $0.url == url }) { repos[i].error = error.localizedDescription }
                errorMessage = error.localizedDescription
            }
        }
        if errorMessage == nil { lastRefreshAt = Date() }
        rebuildAvailable()
    }

    private static func fetchIndex(_ urlString: String, followPointer: Bool = true) async throws
        -> (Data, (name: String, extensions: [KeiyoushiExtension])) {
        guard let url = URL(string: urlString) else { throw KeiyoushiError.badRepoURL }
        guard PluginNetworkPolicy.isSecureDownload(url) else { throw KeiyoushiError.insecure }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        yomiLogNetwork(request, response: response, data: data, error: nil)
        guard PluginNetworkPolicy.isSecureDownload(response.url) else { throw KeiyoushiError.insecure }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw KeiyoushiError.download("HTTP \(http.statusCode)")
        }
        do {
            var decoded = try await Task.detached(priority: .userInitiated) {
                try decodeIndex(data, repoURL: urlString)
            }.value
            if decoded.name.isEmpty, let name = await fetchRepoName(near: url) { decoded.name = name }
            return (data, decoded)
        } catch KeiyoushiError.pointsTo(let link) where followPointer {
            // The list lives elsewhere (A9): fetch it once (never a chain), and keep this link as the repository —
            // the extensions remember it, so updates still come from the repository the user added.
            guard let target = URL(string: link, relativeTo: url)?.absoluteURL else { throw KeiyoushiError.notAnIndex }
            var (listData, decoded) = try await fetchIndex(target.absoluteString, followPointer: false)
            for i in decoded.extensions.indices { decoded.extensions[i].repoURL = urlString }
            if decoded.name.isEmpty, let name = await fetchRepoName(near: url) { decoded.name = name }
            return (listData, decoded)
        }
    }

    /// `repo.json` next to the index — Mihon's repository metadata: `{"index_v2": …, "meta": {"name": …}}` — for
    /// its display name and the link to the current index. Optional: any failure returns nothing.
    private static func fetchRepoMeta(near index: URL) async -> (name: String?, indexV2: URL?) {
        struct RepoJSON: Decodable {
            struct Meta: Decodable { let name: String? }
            let meta: Meta?
            let index_v2: String?
        }
        let link = index.deletingLastPathComponent().appendingPathComponent("repo.json")
        guard PluginNetworkPolicy.isSecureDownload(link),
              let (data, response) = try? await URLSession.shared.data(from: link),
              PluginNetworkPolicy.isSecureDownload(response.url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let repo = try? JSONDecoder().decode(RepoJSON.self, from: data) else { return (nil, nil) }
        let name = repo.meta?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        // Same shape as a pasted link (github.com/…/raw/… → raw.githubusercontent.com), so it matches one already added.
        let v2 = repo.index_v2.flatMap { URL(string: $0, relativeTo: link)?.absoluteURL }
            .flatMap { indexCandidates(for: $0).first }
            .flatMap { PluginNetworkPolicy.isSecureDownload($0) && $0.path.lowercased().hasSuffix(".pb") ? $0 : nil }
        return (name.flatMap { $0.isEmpty || $0.count > 80 ? nil : $0 }, v2)
    }

    private static func fetchRepoName(near index: URL) async -> String? {
        await fetchRepoMeta(near: index).name
    }

    /// An index.min.json repository whose repo.json now names an index.pb (A9): fetch that, and if it works, the
    /// repository becomes that link everywhere — the list, the turned-off list, and the extensions installed from it
    /// (their updates are matched by repository link). Returns false to fall back to the old link as it is.
    private func moveToIndexV2(_ url: String) async -> Bool {
        guard let old = URL(string: url), let v2 = await Self.fetchRepoMeta(near: old).indexV2 else { return false }
        let new = v2.absoluteString
        guard new != url, !AppSettings.shared.mihonRepoURLs.contains(new),
              let (data, decoded) = try? await Self.fetchIndex(new) else { return false }
        try? data.write(to: Self.cacheFile(for: new), options: .atomic)
        Self.saveName(decoded.name, for: new)
        try? FileManager.default.removeItem(at: Self.cacheFile(for: url))
        try? FileManager.default.removeItem(at: Self.nameFile(for: url))
        AppSettings.shared.mihonRepoURLs = AppSettings.shared.mihonRepoURLs.map { $0 == url ? new : $0 }
        AppSettings.shared.turnedOffMihonRepoURLs = AppSettings.shared.turnedOffMihonRepoURLs.map { $0 == url ? new : $0 }
        if let i = repos.firstIndex(where: { $0.url == url }) {
            repos[i] = MihonRepo(url: new, name: decoded.name, extensions: decoded.extensions)
        }
        var changed = false
        for i in installed.indices where installed[i].info.repoURL == url {
            installed[i].info.repoURL = new
            changed = true
        }
        if changed { saveInstalled() }
        return true
    }

    // MARK: Install / uninstall

    /// `langs` limits a multi-language extension to the languages the user picked; `nil` keeps what a previous
    /// install chose (an update shouldn't reset it).
    func install(_ ext: KeiyoushiExtension, langs: [String]? = nil) async throws {
        var ext = ext
        guard let url = URL(string: ext.apkURL) else { throw KeiyoushiError.badRepoURL }
        guard PluginNetworkPolicy.isSecureDownload(url) else { throw KeiyoushiError.insecure }
        var (data, response) = try await URLSession.shared.data(from: url)
        // 404 = the repository replaced this version since our index was fetched: refresh it and take the current one.
        if (response as? HTTPURLResponse)?.statusCode == 404 {
            await refresh()
            // Same repository only (audit #9) — never swap in another repository's APK under the same name.
            let pool = ext.repoURL.flatMap { origin in repos.first { $0.url == origin }?.extensions } ?? available
            if let fresh = pool.first(where: { $0.packageName == ext.packageName }), fresh.apkURL != ext.apkURL,
               let freshURL = URL(string: fresh.apkURL), PluginNetworkPolicy.isSecureDownload(freshURL) {
                ext = fresh
                (data, response) = try await URLSession.shared.data(from: freshURL)
            }
        }
        guard PluginNetworkPolicy.isSecureDownload(response.url) else { throw KeiyoushiError.insecure }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw KeiyoushiError.download("HTTP \(http.statusCode)")
        }
        // An APK is a zip: refuse an HTML error page or truncated body before it replaces a working install.
        guard data.count > 1024, data.prefix(2) == Data([0x50, 0x4B]) else {
            throw KeiyoushiError.download("the file isn't an Android package")
        }
        // Android's own install rule (S193, #227): a valid v2/v3 signature, and an update signed by the key the
        // installed version was signed with — a compromised repository can't swap in its own code.
        let fileName = "\(ext.packageName).apk"
        let previous = installed.first { $0.id == ext.packageName }
        let previousFile = previous.map { Self.apkDirectory.appendingPathComponent($0.apkFileName) }
        let downloaded = data
        let (signer, pinned) = try await Task.detached(priority: .userInitiated) {
            () throws -> (String, String?) in
            let signer: String
            do { signer = try ApkSignature.verify(downloaded) } catch { throw KeiyoushiError.badSignature }
            let pinned = previous?.signerSHA256
                ?? previousFile.flatMap { try? Data(contentsOf: $0) }.flatMap { try? ApkSignature.verify($0) }
            return (signer, pinned)
        }.value
        if let pinned, pinned != signer { throw KeiyoushiError.signerChanged }
        try data.write(to: Self.apkDirectory.appendingPathComponent(fileName), options: .atomic)
        let previousLangs = previous?.enabledLangs
        let allLangs = Set(ext.sources.map(\.lang))
        let chosen = langs.map { Set($0) == allLangs ? nil : $0.sorted() } ?? previousLangs
        let entry = InstalledKeiyoushiExtension(info: ext, apkFileName: fileName, installedAt: Date(),
                                                enabledLangs: chosen, signerSHA256: signer)
        installed.removeAll { $0.id == ext.packageName }
        installed.append(entry)
        installed.sort { $0.info.name.localizedCaseInsensitiveCompare($1.info.name) == .orderedAscending }
        saveInstalled()
        KeiyoushiBridge.shared.forget(packageName: ext.packageName)
    }

    func uninstall(_ ext: InstalledKeiyoushiExtension) async {
        try? FileManager.default.removeItem(at: Self.apkDirectory.appendingPathComponent(ext.apkFileName))
        installed.removeAll { $0.id == ext.id }
        saveInstalled()
        KeiyoushiBridge.shared.forget(packageName: ext.id)
    }

    private func saveInstalled() {
        let snapshot = installed
        Task.detached(priority: .utility) {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: Self.installedFile, options: .atomic)
            }
        }
    }

    nonisolated private static func loadInstalled() -> [InstalledKeiyoushiExtension] {
        guard let data = try? Data(contentsOf: installedFile) else { return [] }
        return (try? JSONDecoder().decode([InstalledKeiyoushiExtension].self, from: data)) ?? []
    }

    // MARK: index.pb decoding

    /// Decodes a Mihon extension repository index (gzip'd or plain protobuf). Field numbers follow Suwayomi's
    /// `NetworkExtensionStore` (verified S124 against Keiyoushi's live index: 1,399 extensions, all inline in
    /// field 101). An index that only points elsewhere (field 102, `extensionListUrl`) throws `.pointsTo` for
    /// `fetchIndex` to follow (A9, S212).
    nonisolated static func decodeIndex(_ raw: Data, repoURL: String) throws
        -> (name: String, extensions: [KeiyoushiExtension]) {
        let data = raw.starts(with: [0x1f, 0x8b]) ? try TachiyomiBackupParser.gunzip(raw) : raw
        if data.first(where: { ![9, 10, 13, 32].contains($0) }) == UInt8(ascii: "[") {
            return try decodeJSONIndex(data, repoURL: repoURL)
        }
        let top = ProtoReader(data)
        var name = ""
        var extensions: [KeiyoushiExtension] = []
        var sawList = false
        var pointer: String?
        while top.hasNext {
            let (field, wire) = try top.readTag()
            switch (field, wire) {
            case (1, 2): name = try top.readString()
            case (101, 2):
                sawList = true
                let list = ProtoReader(try top.readLengthDelimited())
                while list.hasNext {
                    let (f, w) = try list.readTag()
                    if f == 1, w == 2, var ext = try decodeExtension(list.readLengthDelimited()) {
                        ext.repoURL = repoURL
                        extensions.append(ext)
                    } else {
                        try list.skip(wireType: w)
                    }
                }
            case (102, 2): pointer = try top.readString()
            default: try top.skip(wireType: wire)
            }
        }
        guard sawList else {
            if let pointer, !pointer.isEmpty { throw KeiyoushiError.pointsTo(pointer) }
            throw KeiyoushiError.notAnIndex
        }
        extensions.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return (name, extensions)
    }

    nonisolated private static func decodeExtension(_ data: Data) throws -> KeiyoushiExtension? {
        let r = ProtoReader(data)
        var name = "", pkg = "", versionName = "", apk = "", icon = ""
        var versionCode: Int64 = 0
        var warning = 0
        var sources: [KeiyoushiSource] = []
        while r.hasNext {
            let (f, w) = try r.readTag()
            switch (f, w) {
            case (1, 2): name = try r.readString()
            case (2, 2): pkg = try r.readString()
            case (3, 2):
                let res = ProtoReader(try r.readLengthDelimited())
                while res.hasNext {
                    let (rf, rw) = try res.readTag()
                    switch (rf, rw) {
                    case (1, 2): apk = try res.readString()
                    case (2, 2): icon = try res.readString()
                    default: try res.skip(wireType: rw)
                    }
                }
            case (5, 0): versionCode = Int64(bitPattern: try r.readVarint64())
            case (6, 2): versionName = try r.readString()
            case (7, 0): warning = Int(try r.readVarint64())
            case (8, 2):
                let s = ProtoReader(try r.readLengthDelimited())
                var id: Int64 = 0
                var sName = "", lang = "", home = ""
                while s.hasNext {
                    let (sf, sw) = try s.readTag()
                    switch (sf, sw) {
                    case (1, 0): id = Int64(bitPattern: try s.readVarint64())
                    case (2, 2): sName = try s.readString()
                    case (3, 2): lang = try s.readString()
                    case (4, 2): home = try s.readString()
                    default: try s.skip(wireType: sw)
                    }
                }
                sources.append(KeiyoushiSource(id: String(id), name: sName, lang: lang, homeURL: home))
            default: try r.skip(wireType: w)
            }
        }
        guard Self.isValidPackageName(pkg), !apk.isEmpty, !sources.isEmpty else { return nil }
        return KeiyoushiExtension(name: name, packageName: pkg, versionName: versionName, versionCode: versionCode,
                                  apkURL: apk, iconURL: icon, contentWarning: warning, sources: sources)
    }

    // MARK: index.min.json decoding

    private nonisolated struct JSONIndexEntry: Decodable {
        struct Source: Decodable { let name: String; let lang: String; let id: String; let baseUrl: String? }
        let name: String
        let pkg: String
        let apk: String
        let code: Int64
        let version: String
        let nsfw: Int?
        let sources: [Source]?
    }

    /// The package name becomes a file name (`<pkg>.apk`) — only a Java package name is accepted, so a hostile index
    /// can't write outside the APK folder with `../` (S189 audit).
    nonisolated static func isValidPackageName(_ pkg: String) -> Bool {
        !pkg.isEmpty && pkg.count <= 255 && !pkg.hasPrefix(".")
            && pkg.unicodeScalars.allSatisfy { ($0.isASCII && (CharacterSet.alphanumerics.contains($0))) || $0 == "." || $0 == "_" }
    }

    /// The classic Tachiyomi/Mihon repository index: an array of extensions whose APK and icon live next to it in
    /// `apk/<file>` and `icon/<package>.png` (format checked live against Suwayomi's and Kavita's repositories).
    nonisolated private static func decodeJSONIndex(_ data: Data, repoURL: String) throws
        -> (name: String, extensions: [KeiyoushiExtension]) {
        guard let entries = try? JSONDecoder().decode([JSONIndexEntry].self, from: data) else {
            throw KeiyoushiError.notAnIndex
        }
        let base = URL(string: repoURL)?.deletingLastPathComponent()
        let extensions: [KeiyoushiExtension] = entries.compactMap { e in
            guard let base, Self.isValidPackageName(e.pkg), let sources = e.sources, !sources.isEmpty else { return nil }
            return KeiyoushiExtension(
                name: e.name.replacingOccurrences(of: "Tachiyomi: ", with: ""),
                packageName: e.pkg, versionName: e.version, versionCode: e.code,
                apkURL: base.appendingPathComponent("apk").appendingPathComponent(e.apk).absoluteString,
                iconURL: base.appendingPathComponent("icon").appendingPathComponent("\(e.pkg).png").absoluteString,
                contentWarning: (e.nsfw ?? 0) == 1 ? 3 : 1,
                sources: sources.map { KeiyoushiSource(id: $0.id, name: $0.name, lang: $0.lang, homeURL: $0.baseUrl ?? "") },
                repoURL: repoURL)
        }
        // These indexes carry no repository name — the link's host names it (`repoName(for:)`).
        return ("", extensions.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    }
}
