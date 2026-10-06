import CryptoKit
import Foundation
import Kingfisher
import Synchronization

// MARK: - Bridge response models (M-Extension-Server's JManga / JChapter / JPage)

nonisolated struct KeiyoushiManga: Decodable, Sendable {
    let url: String
    let title: String
    let artist: String?
    let author: String?
    let description: String?
    let genre: String?
    let status: Int?
    let thumbnail_url: String?
    /// The bridge's image-proxy URL for the cover (our server patch); a fallback, see `KeiyoushiCovers`.
    let thumbnail_proxy_url: String?
}

nonisolated struct KeiyoushiMangaPage: Decodable, Sendable {
    let mangas: [KeiyoushiManga]?
    let hasNextPage: Bool?
}

nonisolated struct KeiyoushiChapter: Decodable, Sendable {
    let url: String
    let name: String
    let date_upload: Int64?
    let chapter_number: Double?
    let scanlator: String?
}

nonisolated struct KeiyoushiPage: Decodable, Sendable {
    let index: Int
    let url: String?
    let imageUrl: String?
}

private nonisolated struct BridgeErrorBody: Decodable {
    let error: String?
    let code: Int?
}

// MARK: - KeiyoushiBridge

/// Client for the M-Extension-Server bridge running in-process (`KeiyoushiJVMHost`), speaking its one endpoint,
/// `POST /dalvik`. The first call per extension per launch sends the APK; later calls reuse the handle the server
/// returns in `X-Mangayomi-Extension-Id` (409 = handle gone → resend). Converted extensions are cached on disk by
/// the bridge itself (our patch), so only the very first load of an extension version pays for dex2jar.
///
/// Requests carry Yomi's bypass User-Agent and the source site's cookies: the bridge copies both into the
/// extension's HTTP client, which is how a Cloudflare `cf_clearance` solved in `CFBypassView` reaches it.
final class KeiyoushiBridge {
    static let shared = KeiyoushiBridge()
    private init() {}

    private var port: Int? {
        didSet {
            Self.livePort.withLock { $0 = port }
            if port != nil { everStarted = true }
        }
    }
    private var starting: Task<Int, Error>?
    private var everStarted = false

    // MARK: Page images across a pause (S144)

    /// The port the bridge serves on right now (nil while paused), readable from any thread — Kingfisher's
    /// request modifier runs off the main actor.
    nonisolated static let livePort = Mutex<Int?>(nil)

    /// A page or cover served by the bridge: `http://127.0.0.1:<port>/image/<id>`.
    nonisolated static func isBridgeImage(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.host == "127.0.0.1" && url.path.hasPrefix("/image/")
    }

    /// Image ids outlive a pause but the port doesn't (verified on device S144: a chapter's 20 page ids all loaded
    /// after the restart once moved to the new port). Pages keep the URL they were listed with — so Kingfisher's
    /// cache keys stay put — and every request is pointed at the live port here.
    nonisolated static func pointAtLivePort(_ request: URLRequest) -> URLRequest {
        guard isBridgeImage(request.url), let live = livePort.withLock({ $0 }), request.url?.port != live,
              let url = request.url, var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return request }
        c.port = live
        var moved = request
        moved.url = c.url ?? url
        return moved
    }

    /// Back in the foreground: serve again right away if Keiyoushi was in use, so an open chapter's remaining pages
    /// load (before S144 they all failed until some other Keiyoushi call happened to restart the bridge).
    func resumeIfPaused() async {
        guard everStarted, port == nil else { return }
        _ = try? await ensurePort()
    }
    private var handles: [String: String] = [:]   // packageName → server-issued extension handle

    // MARK: Lifecycle

    private func ensurePort() async throws -> Int {
        if let port { return port }
        if let starting { return try await starting.value }
        guard KeiyoushiJVMHost.isAvailable else { throw KeiyoushiError.runtimeUnavailable }
        let task = Task<Int, Error> {
            try await withCheckedThrowingContinuation { cont in
                KeiyoushiJVMHost.shared.start { port, error in
                    if port > 0 {
                        cont.resume(returning: port)
                    } else {
                        cont.resume(throwing: KeiyoushiError.bridge(error ?? "The extension runtime didn't start."))
                    }
                }
            }
        }
        starting = task
        defer { starting = nil }
        let started = try await task.value
        port = started
        return started
    }

    /// The port the bridge serves on now, starting it again if it was paused (page images are fetched straight
    /// from it, not through `call`).
    func servingPort() async throws -> Int { try await ensurePort() }

    /// App going to the background: stop serving (iOS would suspend the socket anyway) but keep extensions loaded.
    func pause() {
        guard port != nil else { return }
        port = nil
        KeiyoushiJVMHost.shared.pauseBridge()
    }

    /// Drops the cached handle after an install/update/uninstall, so the next call loads the new APK.
    func forget(packageName: String) {
        handles[packageName] = nil
    }

    // MARK: Source API

    func popular(sourceId: String, page: Int) async throws -> KeiyoushiMangaPage {
        await withCovers(sourceId, try await call(sourceId: sourceId, method: "getPopularManga", params: ["page": page]))
    }

    func latest(sourceId: String, page: Int) async throws -> KeiyoushiMangaPage {
        await withCovers(sourceId, try await call(sourceId: sourceId, method: "getLatestManga", params: ["page": page]))
    }

    func search(sourceId: String, query: String, page: Int) async throws -> KeiyoushiMangaPage {
        await withCovers(sourceId, try await call(sourceId: sourceId, method: "getSearchManga",
                                                      params: ["page": page, "search": query, "filterList": [Any]()]))
    }

    private var imageHeaders: [String: [String: String]] = [:]   // sourceId → the source's request headers

    /// Records each cover's headers and proxy fallback before the page is shown (see `KeiyoushiCovers`).
    private func withCovers(_ sourceId: String, _ page: KeiyoushiMangaPage) async -> KeiyoushiMangaPage {
        await rememberCovers(sourceId, page.mangas ?? [])
        return page
    }

    private func rememberCovers(_ sourceId: String, _ mangas: [KeiyoushiManga]) async {
        if imageHeaders[sourceId] == nil {
            // headersManga returns [name, value, name, value…]. User-Agent stays Yomi's (Kingfisher sets it).
            let flat = (try? await call(sourceId: sourceId, method: "headersManga", params: [:]) as [String]) ?? []
            var headers: [String: String] = [:]
            for i in stride(from: 0, to: flat.count - 1, by: 2) where flat[i].lowercased() != "user-agent" {
                headers[flat[i]] = flat[i + 1]
            }
            imageHeaders[sourceId] = headers
        }
        KeiyoushiCovers.shared.remember(mangas, headers: imageHeaders[sourceId] ?? [:])
    }

    func supportsLatest(sourceId: String) async -> Bool {
        (try? await call(sourceId: sourceId, method: "supportLatestManga", params: [:]) as Bool) ?? false
    }

    func details(sourceId: String, mangaURL: String) async throws -> KeiyoushiManga {
        let manga: KeiyoushiManga = try await call(sourceId: sourceId, method: "getDetailsManga",
                                                   params: ["mangaData": ["url": mangaURL]])
        await rememberCovers(sourceId, [manga])
        return manga
    }

    func chapters(sourceId: String, mangaURL: String) async throws -> [KeiyoushiChapter] {
        try await call(sourceId: sourceId, method: "getChapterList", params: ["mangaData": ["url": mangaURL]])
    }

    func pages(sourceId: String, chapterURL: String, chapterName: String) async throws -> [KeiyoushiPage] {
        try await call(sourceId: sourceId, method: "getPageList",
                       params: ["chapterData": ["url": chapterURL, "name": chapterName]])
    }

    // MARK: Transport

    private func call<T: Decodable>(sourceId: String, method: String, params: [String: Any]) async throws -> T {
        guard let ext = KeiyoushiRepository.shared.installedExtension(forSourceId: sourceId) else {
            throw KeiyoushiError.bridge("This Keiyoushi source isn't installed.")
        }
        let port = try await ensurePort()
        let pkg = ext.id
        let homeURL = ext.info.sources.first { $0.id == sourceId }?.homeURL
        var body = params
        body["method"] = method
        body["sourceId"] = sourceId

        for attempt in 0..<2 {
            if let handle = handles[pkg], attempt == 0 {
                body["extensionId"] = handle
                body["data"] = nil
            } else {
                body["extensionId"] = nil
                let apk = KeiyoushiRepository.apkDirectory.appendingPathComponent(ext.apkFileName)
                body["data"] = try await Task.detached(priority: .userInitiated) {
                    try Data(contentsOf: apk).base64EncodedString()
                }.value
            }
            var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/dalvik")!)
            request.httpMethod = "POST"
            // Zero is an interpreter and the first call converts the extension — allow a slow first response.
            request.timeoutInterval = 180
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(CFBypassConstants.userAgent, forHTTPHeaderField: "User-Agent")
            if let homeURL, let site = URL(string: homeURL),
               let cookies = HTTPCookieStorage.shared.cookies(for: site), !cookies.isEmpty {
                request.setValue(cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; "),
                                 forHTTPHeaderField: "Cookie")
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            if let handle = http?.value(forHTTPHeaderField: "X-Mangayomi-Extension-Id") { handles[pkg] = handle }
            switch http?.statusCode ?? 0 {
            case 200:
                return try await Task.detached(priority: .userInitiated) {
                    try JSONDecoder().decode(T.self, from: data)
                }.value
            case 409 where attempt == 0:
                handles[pkg] = nil   // the bridge dropped this extension — resend the APK once
                continue
            default:
                let err = try? JSONDecoder().decode(BridgeErrorBody.self, from: data)
                if err?.code == 403 || http?.statusCode == 403, let homeURL {
                    throw KeiyoushiError.bridge("CLOUDFLARE:\(homeURL)")
                }
                throw KeiyoushiError.bridge(err?.error ?? "The extension failed (HTTP \(http?.statusCode ?? 0)).")
            }
        }
        throw KeiyoushiError.bridge("The extension could not be loaded.")
    }
}

// MARK: - Mapping onto Yomi's models

enum KeiyoushiMapping {
    nonisolated static let sourcePrefix = "keiyoushi_"
    nonisolated static let chapterScheme = "keiyoushi://"

    /// True for manga produced by `manga(from:sourceId:)`.
    nonisolated static func isKeiyoushiSourceId(_ sourceId: String) -> Bool { sourceId.hasPrefix(sourcePrefix) }

    /// The Mihon source id inside a Yomi `sourceId` ("keiyoushi_{mihonId}").
    nonisolated static func mihonSourceId(_ yomiSourceId: String) -> String {
        String(yomiSourceId.dropFirst(sourcePrefix.count))
    }

    /// Stable short key for a source URL. The bridge appends a `|mangayomi-memo|…` suffix to some URLs (state it
    /// needs back verbatim), so ids hash only the part before it.
    nonisolated static func key(_ url: String) -> String {
        let base = url.components(separatedBy: "|mangayomi-memo|").first ?? url
        return SHA256.hash(data: Data(base.utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func manga(from m: KeiyoushiManga, sourceId: String) -> Manga {
        Manga(
            id: "\(sourcePrefix)\(sourceId)_\(key(m.url))",
            path: m.url,
            sourceId: "\(sourcePrefix)\(sourceId)",
            title: m.title,
            coverURL: m.thumbnail_url.flatMap { URL(string: $0) },
            summary: m.description,
            author: m.author,
            artist: m.artist,
            status: status(m.status),
            genres: genres(m.genre),
            inLibrary: false,
            isLocal: false,
            lastReadAt: nil,
            lastUpdatedAt: nil,
            readingSeconds: 0
        )
    }

    /// `path` is a self-describing `keiyoushi://` reference (source id + the extension's own chapter URL + name),
    /// so the reader can fetch pages from the path alone — the same pattern as Suwayomi's `suwayomi://` (S120).
    nonisolated static func chapter(from c: KeiyoushiChapter, mangaId: String, sourceId: String,
                                    mangaTitle: String) -> Chapter {
        Chapter(
            id: "\(mangaId)_\(key(c.url))",
            mangaId: mangaId,
            path: chapterPath(sourceId: sourceId, url: c.url, name: c.name),
            name: c.name,
            // -1 = the source doesn't know; Mihon then reads it from the name, and so do we (S144).
            chapterNumber: ChapterRecognition.number(mangaTitle: mangaTitle, chapterName: c.name,
                                                     sourceNumber: c.chapter_number),
            isRead: false,
            isDownloaded: false,
            downloadedAt: nil,
            readAt: nil,
            progress: 0,
            readingSeconds: 0,
            lastPageRead: 0,
            scanlator: c.scanlator?.isEmpty == true ? nil : c.scanlator
        )
    }

    nonisolated static func chapterPath(sourceId: String, url: String, name: String) -> String {
        let payload = (try? JSONSerialization.data(withJSONObject: ["s": sourceId, "u": url, "n": name])) ?? Data()
        let b64 = payload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return chapterScheme + b64
    }

    nonisolated static func chapterRef(from path: String) -> (sourceId: String, url: String, name: String)? {
        guard path.hasPrefix(chapterScheme) else { return nil }
        var b64 = String(path.dropFirst(chapterScheme.count))
            .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let s = obj["s"], let u = obj["u"] else { return nil }
        return (s, u, obj["n"] ?? "")
    }

    /// Mihon SManga status: 1 ongoing, 2 completed, 3 licensed, 4 publishing finished, 5 cancelled, 6 on hiatus.
    nonisolated static func status(_ raw: Int?) -> MangaStatus {
        switch raw {
        case 1: return .ongoing
        case 2, 4: return .completed
        case 5: return .cancelled
        case 6: return .hiatus
        default: return .unknown
        }
    }

    nonisolated static func genres(_ raw: String?) -> [String] {
        (raw ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

// MARK: - Covers loaded natively

/// Keiyoushi covers are downloaded by Kingfisher straight from the source's CDN, not through the bridge's image
/// proxy: the embedded JVM has no hardware crypto, so it spent up to 8 s decrypting one 5 MB cover (S134, measured
/// on Martin's iPhone 17) and ~7 s of CPU per Browse page. Sources often want their own headers (Referer, Origin)
/// on image requests — kept here per cover host, persisted so library covers still get them after a relaunch.
/// The proxy URL is kept for this launch as a fallback for covers that only load through the extension.
nonisolated final class KeiyoushiCovers: @unchecked Sendable {
    static let shared = KeiyoushiCovers()

    private static let defaultsKey = "keiyoushiCoverHeaders"
    private let lock = NSLock()
    private var headersByHost: [String: [String: String]]
    private var proxyByCover: [URL: URL] = [:]

    private init() {
        headersByHost = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: [String: String]] ?? [:]
    }

    /// Headers to add to an image request for `url` (empty for hosts no Keiyoushi source uses).
    func headers(for url: URL?) -> [String: String] {
        guard let host = url?.host else { return [:] }
        return lock.withLock { headersByHost[host] ?? [:] }
    }

    /// The bridge's proxy URL for a cover, if this launch saw one.
    func proxy(for url: URL?) -> URL? {
        guard let url else { return nil }
        return lock.withLock { proxyByCover[url] }
    }

    func remember(_ mangas: [KeiyoushiManga], headers: [String: String]) {
        lock.withLock {
            var changed = false
            for m in mangas {
                guard let cover = m.thumbnail_url.flatMap(URL.init(string:)) else { continue }
                if let proxy = m.thumbnail_proxy_url.flatMap(URL.init(string:)) { proxyByCover[cover] = proxy }
                if let host = cover.host, !headers.isEmpty, headersByHost[host] != headers {
                    headersByHost[host] = headers
                    changed = true
                }
            }
            if changed { UserDefaults.standard.set(headersByHost, forKey: Self.defaultsKey) }
        }
    }

    /// Covers saved before S134 point at the bridge's proxy (`http://127.0.0.1:<port>/image/<token>`), which dies
    /// with the launch that issued it.
    static func isProxyURL(_ url: URL?) -> Bool { url?.host == "127.0.0.1" && url?.path.hasPrefix("/image/") == true }
}

extension KFImage {
    /// Falls back to the Keiyoushi bridge's image proxy when a cover won't load directly (see `KeiyoushiCovers`).
    func keiyoushiCoverFallback(_ url: URL?) -> KFImage {
        alternativeSources(KeiyoushiCovers.shared.proxy(for: url).map { [.network($0)] })
    }
}
