import Foundation

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

    var id: String { info.packageName }
}

enum KeiyoushiError: LocalizedError {
    case badRepoURL
    case notAnIndex
    case download(String)
    case runtimeUnavailable
    case bridge(String)

    var errorDescription: String? {
        switch self {
        case .badRepoURL: return "That isn't a valid repository URL."
        case .notAnIndex: return "That URL didn't return a Mihon extension index (index.pb)."
        case .download(let why): return "Download failed — \(why)"
        case .runtimeUnavailable:
            return "Keiyoushi extensions need the on-device runtime, which this build doesn't include."
        case .bridge(let why): return why
        }
    }
}

// MARK: - Repository + installed extensions

/// The user's Mihon extension repository (e.g. Keiyoushi) and the extensions installed from it.
///
/// Extensions run on the device through the embedded JVM (`KeiyoushiBridge`), so "install" just downloads the
/// extension's APK into Application Support; the bridge converts and loads it on first use. The index is cached
/// on disk so the list still shows offline.
@Observable
final class KeiyoushiRepository {
    static let shared = KeiyoushiRepository()

    private(set) var available: [KeiyoushiExtension] = []
    private(set) var installed: [InstalledKeiyoushiExtension] = []
    private(set) var repoName: String?
    private(set) var isLoading = false
    var errorMessage: String?

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
    nonisolated private static let indexCacheFile = rootDirectory.appendingPathComponent("index.pb")

    private init() {
        installed = Self.loadInstalled()
        if let cached = try? Data(contentsOf: Self.indexCacheFile),
           let decoded = try? Self.decodeIndex(cached) {
            repoName = decoded.name
            available = decoded.extensions
        }
    }

    /// Every installed source across all installed extensions, for Browse.
    var installedSources: [(ext: InstalledKeiyoushiExtension, source: KeiyoushiSource)] {
        installed.flatMap { ext in ext.info.sources.map { (ext, $0) } }
    }

    func installedExtension(forSourceId sourceId: String) -> InstalledKeiyoushiExtension? {
        installed.first { $0.info.sources.contains { $0.id == sourceId } }
    }

    func availableUpdate(for ext: InstalledKeiyoushiExtension) -> KeiyoushiExtension? {
        guard let remote = available.first(where: { $0.packageName == ext.info.packageName }),
              remote.versionCode > ext.info.versionCode else { return nil }
        return remote
    }

    // MARK: Index

    /// Fetches and decodes the configured repository index. Keeps the previous list on failure.
    func refresh() async {
        let urlString = AppSettings.shared.keiyoushiRepoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty else {
            available = []
            repoName = nil
            return
        }
        guard let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true else {
            errorMessage = KeiyoushiError.badRepoURL.localizedDescription
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            yomiLogNetwork(request, response: response, data: data, error: nil)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw KeiyoushiError.download("HTTP \(http.statusCode)")
            }
            let decoded = try await Task.detached(priority: .userInitiated) {
                try Self.decodeIndex(data)
            }.value
            try? data.write(to: Self.indexCacheFile, options: .atomic)
            repoName = decoded.name
            available = decoded.extensions
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Install / uninstall

    func install(_ ext: KeiyoushiExtension) async throws {
        guard let url = URL(string: ext.apkURL) else { throw KeiyoushiError.badRepoURL }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw KeiyoushiError.download("HTTP \(http.statusCode)")
        }
        // An APK is a zip: refuse an HTML error page or truncated body before it replaces a working install.
        guard data.count > 1024, data.prefix(2) == Data([0x50, 0x4B]) else {
            throw KeiyoushiError.download("the file isn't an Android package")
        }
        let fileName = "\(ext.packageName).apk"
        try data.write(to: Self.apkDirectory.appendingPathComponent(fileName), options: .atomic)
        let entry = InstalledKeiyoushiExtension(info: ext, apkFileName: fileName, installedAt: Date())
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
    /// field 101). An index that only points elsewhere (field 102, `extensionListUrl`) isn't followed yet.
    nonisolated static func decodeIndex(_ raw: Data) throws -> (name: String, extensions: [KeiyoushiExtension]) {
        let data = raw.starts(with: [0x1f, 0x8b]) ? try TachiyomiBackupParser.gunzip(raw) : raw
        let top = ProtoReader(data)
        var name = ""
        var extensions: [KeiyoushiExtension] = []
        var sawList = false
        while top.hasNext {
            let (field, wire) = try top.readTag()
            switch (field, wire) {
            case (1, 2): name = try top.readString()
            case (101, 2):
                sawList = true
                let list = ProtoReader(try top.readLengthDelimited())
                while list.hasNext {
                    let (f, w) = try list.readTag()
                    if f == 1, w == 2, let ext = try decodeExtension(list.readLengthDelimited()) {
                        extensions.append(ext)
                    } else {
                        try list.skip(wireType: w)
                    }
                }
            default: try top.skip(wireType: wire)
            }
        }
        guard sawList else { throw KeiyoushiError.notAnIndex }
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
        guard !pkg.isEmpty, !apk.isEmpty, !sources.isEmpty else { return nil }
        return KeiyoushiExtension(name: name, packageName: pkg, versionName: versionName, versionCode: versionCode,
                                  apkURL: apk, iconURL: icon, contentWarning: warning, sources: sources)
    }
}
