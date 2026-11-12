import CryptoKit
import Foundation
import Kingfisher
import Security
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
    /// Request headers for a page the bridge returns as a direct image URL (S159; upstream `6dc99f4`). Pages the
    /// extension must process itself (Asura's scrambled tiles, a `fetchImage` override) still come back proxied.
    let headers: [String: String]?
}

/// One setting an extension declares for a source (AndroidX `Preference` on Android). The bridge sends each as
/// `{"key": …, "<kind>": {title, summary, value…}}` and takes the same shape back.
nonisolated struct KeiyoushiPreference: Decodable, Sendable, Identifiable {
    enum Value: Sendable, Equatable {
        case toggle(Bool)
        case text(String)
        /// One of `entries`; `index` is -1 when the stored value matches none.
        case choice(index: Int, entries: [String], entryValues: [String])
        case multiChoice(selected: Set<String>, entries: [String], entryValues: [String])
    }

    let key: String
    /// The bridge's name for the kind, sent back unchanged (a check box and a switch are both `.toggle`).
    let kind: String
    let title: String
    let summary: String
    var value: Value

    var id: String { key }

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    private struct Body: Decodable {
        let title: String?
        let summary: String?
        let entries: [String]?
        let entryValues: [String]?
        let valueIndex: Int?
    }

    /// Fails for a setting without a key or of a kind Yomi doesn't know — `LossyPreference` drops those, so one
    /// odd setting doesn't hide the rest.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        key = try c.decode(String.self, forKey: AnyKey("key"))
        guard let kindKey = c.allKeys.first(where: { $0.stringValue != "key" }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "no kind"))
        }
        kind = kindKey.stringValue
        let body = try c.decode(Body.self, forKey: kindKey)
        let raw = try c.nestedContainer(keyedBy: AnyKey.self, forKey: kindKey)
        title = body.title ?? key
        let entries = body.entries ?? []
        let entryValues = body.entryValues ?? []
        switch kind {
        case "checkBoxPreference", "switchPreferenceCompat":
            value = .toggle((try? raw.decode(Bool.self, forKey: AnyKey("value"))) ?? false)
        case "editTextPreference":
            value = .text((try? raw.decode(String.self, forKey: AnyKey("value"))) ?? "")
        case "listPreference":
            value = .choice(index: body.valueIndex ?? -1, entries: entries, entryValues: entryValues)
        case "multiSelectListPreference":
            let selected = (try? raw.decode([String].self, forKey: AnyKey("values"))) ?? []
            value = .multiChoice(selected: Set(selected), entries: entries, entryValues: entryValues)
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "unknown kind \(kind)"))
        }
        // Android fills "%s" in a list's summary with the chosen entry.
        var text = body.summary ?? ""
        if case .choice(let index, let entries, _) = value, text.contains("%s") {
            text = text.replacingOccurrences(of: "%s", with: entries.indices.contains(index) ? entries[index] : "")
        }
        summary = text
    }

    /// The JSON the bridge expects for this setting with its current `value`.
    var wire: [String: Any] {
        let body: [String: Any]
        switch value {
        case .toggle(let on): body = ["value": on]
        case .text(let text): body = ["value": text]
        case .choice(let index, let entries, let entryValues):
            body = ["valueIndex": index, "entries": entries, "entryValues": entryValues]
        case .multiChoice(let selected, let entries, let entryValues):
            body = ["values": selected.sorted(), "entries": entries, "entryValues": entryValues]
        }
        return ["key": key, kind: body]
    }
}

private nonisolated struct LossyPreference: Decodable {
    let preference: KeiyoushiPreference?
    init(from decoder: Decoder) throws { preference = try? KeiyoushiPreference(from: decoder) }
}

private nonisolated struct BridgeErrorBody: Decodable {
    let error: String?
    let code: Int?
}

// MARK: - KeiyoushiBridge

/// Client for the M-Extension-Server bridge running in-process (`KeiyoushiJVMHost`), speaking its one request shape,
/// `/dalvik`. Since A6 (S210) that goes straight through JNI (`YomiHost`): no loopback server, no port to lose after
/// a suspend, no token. The old loopback transport stays for one build behind `httpTransportKey`.
/// The first call per extension per launch names the APK (its file path; base64 over HTTP); later calls reuse the
/// handle the server returns (409 = handle gone → resend). Converted extensions are cached on disk by
/// the bridge itself (our patch), so only the very first load of an extension version pays for dex2jar.
///
/// Requests carry Yomi's bypass User-Agent and the source site's cookies: the bridge copies both into the
/// extension's HTTP client, which is how a Cloudflare `cf_clearance` solved in `CFBypassView` reaches it.
final class KeiyoushiBridge {
    static let shared = KeiyoushiBridge()
    private init() {}

    // MARK: Transport choice (A6, S210)

    /// Hidden fallback switch (UserDefaults): true = the old loopback HTTP server. Read once per launch — the
    /// extension runtime hands out one image-URL scheme per process. Kept for one TestFlight build so a phone problem
    /// can be told apart from a site problem; the build after a clean phone check removes the HTTP path.
    nonisolated static let httpTransportKey = "keiyoushiHTTPTransport"
    nonisolated static let usesJNI: Bool = !UserDefaults.standard.bool(forKey: httpTransportKey)

    /// Page and cover images the extension serves itself: `keiyoushi-image://<id>` (`KeiyoushiImageProtocol`).
    nonisolated static let imageScheme = "keiyoushi-image"

    private var engine: Task<Void, Error>?
    private var engineReady = false

    /// Starts the extension runtime once per process (JNI transport). Nothing to pause or resume afterwards.
    private func ensureEngine() async throws {
        if engineReady { return }
        if let engine { return try await engine.value }
        guard KeiyoushiJVMHost.isAvailable else { throw KeiyoushiError.runtimeUnavailable }
        let dir = KeiyoushiRepository.apkDirectory.path
        let task = Task<Void, Error> {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                KeiyoushiJVMHost.shared.startEngine(withAPKDirectory: dir) { error in
                    if let error { cont.resume(throwing: KeiyoushiError.bridge(error)) } else { cont.resume() }
                }
            }
        }
        engine = task
        defer { engine = nil }
        try await task.value
        engineReady = true
    }

    private var port: Int? {
        didSet {
            Self.livePort.withLock { $0 = port }
            if port != nil { everStarted = true }
        }
    }
    private var starting: Task<Int, Error>?
    private var everStarted = false
    /// Bumped by `pause()`. A start that finishes after a pause must not keep its port: the server is paused right
    /// after it (the host runs start and pause in order), so the cached port would point at nothing and
    /// `resumeIfPaused` would think the bridge was still up (S189 audit #13, S193).
    private var pauseCount = 0

    // MARK: Lock (S191)

    /// Every request to the bridge must carry this header with `token`, or the bridge answers 401. Loopback is open
    /// to every app on the phone and to web pages in our web views (the Cloudflare screen), and `/dalvik` runs any
    /// APK it is sent — the token is what keeps them out. Plugins can't reach 127.0.0.1 at all (`PluginNetworkPolicy`).
    nonisolated static let tokenHeader = "X-Yomi-Bridge-Token"

    /// 256 random bits, new each launch — the JVM lives exactly as long as the process, so the server holds the
    /// same token across pause/resume. Never logged or stored.
    nonisolated static let token: String = {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        return bytes.map { String(format: "%02x", $0) }.joined()
    }()

    // MARK: Page images across a pause (S144)

    /// The port the bridge serves on right now (nil while paused), readable from any thread — Kingfisher's
    /// request modifier runs off the main actor.
    nonisolated static let livePort = Mutex<Int?>(nil)

    /// A page or cover served by the bridge: `http://127.0.0.1:<port>/image/<id>`.
    nonisolated static func isBridgeImage(_ url: URL?) -> Bool {
        guard let url else { return false }
        if url.scheme == imageScheme { return true }
        return url.host == "127.0.0.1" && url.path.hasPrefix("/image/")
    }

    /// Prepares a request for a page or cover the bridge serves; any other request comes back unchanged.
    /// - Adds the bridge token (S191).
    /// - Image ids outlive a pause but the port doesn't (verified on device S144: a chapter's 20 page ids all loaded
    ///   after the restart once moved to the new port). Pages keep the URL they were listed with — so Kingfisher's
    ///   cache keys stay put — and every request is pointed at the live port here.
    nonisolated static func bridgeImageRequest(_ request: URLRequest) -> URLRequest {
        guard isBridgeImage(request.url), let url = request.url, url.scheme == "http" else { return request }
        var prepared = request
        prepared.setValue(token, forHTTPHeaderField: tokenHeader)
        if let live = livePort.withLock({ $0 }), url.port != live,
           var c = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            c.port = live
            prepared.url = c.url ?? url
        }
        return prepared
    }

    /// Back in the foreground: serve again right away if Keiyoushi was in use, so an open chapter's remaining pages
    /// load (before S144 they all failed until some other Keiyoushi call happened to restart the bridge).
    /// A cached port is checked too: a listener that died while suspended would otherwise stay dead for page images,
    /// which don't go through `call`'s retry. The server's `start` returns the live port at once when it is up (S193).
    func resumeIfPaused() async {
        guard !Self.usesJNI, everStarted else { return }
        if let cached = port, starting == nil { dropDeadPort(cached) }
        _ = try? await ensurePort()
    }
    private var handles: [String: String] = [:]   // packageName → server-issued extension handle

    // MARK: Lifecycle

    private func ensurePort() async throws -> Int {
        if let port { return port }
        if let starting { return try await starting.value }
        guard KeiyoushiJVMHost.isAvailable else { throw KeiyoushiError.runtimeUnavailable }
        everStarted = true   // so coming back from a pause during this start restarts the bridge
        let pausesBefore = pauseCount
        let task = Task<Int, Error> {
            try await withCheckedThrowingContinuation { cont in
                KeiyoushiJVMHost.shared.start(withToken: Self.token) { port, error in
                    if port > 0 {
                        cont.resume(returning: port)
                    } else {
                        cont.resume(throwing: KeiyoushiError.bridge(error ?? String(localized: "The extension runtime didn't start.")))
                    }
                }
            }
        }
        starting = task
        defer { starting = nil }
        let started = try await task.value
        if pauseCount == pausesBefore { port = started }
        return started
    }

    /// The listener behind the cached port is gone (killed while suspended, or paused under us): forget the port so
    /// the next `ensurePort` asks the server again — its `start` returns the live port, or opens a new listener.
    private func dropDeadPort(_ dead: Int) {
        if port == dead { port = nil }
    }

    /// Nothing listening on the port (connection refused / dropped before any reply).
    private nonisolated static func isDeadListener(_ error: Error) -> Bool {
        guard let code = (error as? URLError)?.code else { return false }
        return code == .cannotConnectToHost || code == .networkConnectionLost
    }

    /// True once bridge-served page images can load again (the runtime is up; over HTTP, a live port).
    func imagesReady() async -> Bool {
        if Self.usesJNI { return (try? await ensureEngine()) != nil }
        return (try? await ensurePort()) != nil
    }

    /// App going to the background: stop serving (iOS would suspend the socket anyway) but keep extensions loaded.
    func pause() {
        guard !Self.usesJNI, port != nil || starting != nil else { return }
        pauseCount += 1
        port = nil
        KeiyoushiJVMHost.shared.pauseBridge()   // queued after any start in flight
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

    /// `filterList` = `KeiyoushiFilter.wire` (empty = the extension's own defaults).
    func search(sourceId: String, query: String, page: Int,
                filterList: [[String: Any]] = []) async throws -> KeiyoushiMangaPage {
        await withCovers(sourceId, try await call(sourceId: sourceId, method: "getSearchManga",
                                                      params: ["page": page, "search": query, "filterList": filterList]))
    }

    /// The source's search filters as the extension has them now, nothing chosen. Some extensions (Asura) fetch
    /// part of the list in the background on the first ask, so a later ask can return more.
    func filters(sourceId: String) async throws -> [KeiyoushiFilter] {
        KeiyoushiFilter.numbered(try await call(sourceId: sourceId, method: "filtersManga", params: [:]))
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
        let pages: [KeiyoushiPage] = try await call(sourceId: sourceId, method: "getPageList",
                                                    params: ["chapterData": ["url": chapterURL, "name": chapterName]])
        KeiyoushiCovers.shared.remember(pages)
        return pages
    }

    // MARK: Extension settings (S156)

    /// The extension's own settings for one source (Mihon's "source preferences"), with their current values.
    /// Empty for a source that has none. The bridge keeps the values on disk, per source id.
    func preferences(sourceId: String) async throws -> [KeiyoushiPreference] {
        let all: [LossyPreference] = try await call(sourceId: sourceId, method: "preferencesManga", params: [:])
        return all.compactMap(\.preference)
    }

    /// Changes one setting and returns the whole list again — an extension may adjust the value it was given.
    func setPreference(_ preference: KeiyoushiPreference, to value: KeiyoushiPreference.Value,
                       sourceId: String) async throws -> [KeiyoushiPreference] {
        var changed = preference
        changed.value = value
        // The bridge's protocol: a context entry naming the changed key, then that setting with its new value.
        let all: [LossyPreference] = try await call(
            sourceId: sourceId, method: "setPreferenceManga",
            params: ["preferences": [["key": "__mangayomi_bridge_context__", "changedPreferenceKey": preference.key],
                                     changed.wire]])
        return all.compactMap(\.preference)
    }

    // MARK: Transport

    private func call<T: Decodable>(sourceId: String, method: String, params: [String: Any]) async throws -> T {
        guard let ext = KeiyoushiRepository.shared.installedExtension(forSourceId: sourceId) else {
            throw KeiyoushiError.bridge(String(localized: "This Keiyoushi source isn't installed."))
        }
        let pkg = ext.id
        let homeURL = ext.info.sources.first { $0.id == sourceId }?.homeURL
        var body = params
        body["method"] = method
        body["sourceId"] = sourceId
        var cookieHeader: String?
        if let homeURL, let site = URL(string: homeURL),
           let cookies = HTTPCookieStorage.shared.cookies(for: site), !cookies.isEmpty {
            cookieHeader = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        }

        var attempt = 0
        while attempt < 2 {
            defer { attempt += 1 }
            body["extensionId"] = nil
            body["data"] = nil
            body["apkPath"] = nil
            if let handle = handles[pkg], attempt == 0 {
                body["extensionId"] = handle
            } else {
                let apk = KeiyoushiRepository.apkDirectory.appendingPathComponent(ext.apkFileName)
                if Self.usesJNI {
                    body["apkPath"] = apk.path   // read by the runtime itself, only inside the APK directory
                } else {
                    body["data"] = try await Task.detached(priority: .userInitiated) {
                        try Data(contentsOf: apk).base64EncodedString()
                    }.value
                }
            }
            let reply = try await send(try JSONSerialization.data(withJSONObject: body), cookies: cookieHeader)
            if let handle = reply.extensionId { handles[pkg] = handle }
            switch reply.status {
            case 200:
                let data = reply.data
                return try await Task.detached(priority: .userInitiated) {
                    try JSONDecoder().decode(T.self, from: data)
                }.value
            case 409 where attempt == 0:
                handles[pkg] = nil   // the bridge dropped this extension — resend the APK once
                continue
            default:
                let err = try? JSONDecoder().decode(BridgeErrorBody.self, from: reply.data)
                if err?.code == 403 || reply.status == 403, let homeURL {
                    throw KeiyoushiError.bridge("CLOUDFLARE:\(homeURL)")
                }
                // S208: extensions whose site check needs a WebView (Batcave's guard) can't open one on iOS; they
                // report Mihon's "Open in WebView to bypass …". Same remedy as Cloudflare: verify in CFBypassView,
                // whose cookies reach the extension through the cookie header above.
                if let message = err?.error, message.localizedCaseInsensitiveContains("open in webview"), let homeURL {
                    throw KeiyoushiError.bridge("CLOUDFLARE:\(homeURL)")
                }
                throw KeiyoushiError.bridge(err?.error ?? String(localized: "The extension failed (HTTP \(reply.status))."))
            }
        }
        throw KeiyoushiError.bridge(String(localized: "The extension could not be loaded."))
    }

    private struct Reply: Sendable {
        let status: Int
        let data: Data
        let extensionId: String?
    }

    /// Zero is an interpreter and the first call converts the extension — allow a slow first answer.
    private nonisolated static let callTimeout: TimeInterval = 180

    private func send(_ json: Data, cookies: String?) async throws -> Reply {
        guard Self.usesJNI else { return try await sendHTTP(json, cookies: cookies) }
        try await ensureEngine()
        let once = Mutex(false)   // the answer or the timeout, whichever comes first
        return await withCheckedContinuation { (cont: CheckedContinuation<Reply, Never>) in
            let finish: @Sendable (Reply) -> Void = { reply in
                if once.withLock({ done in defer { done = true }; return !done }) { cont.resume(returning: reply) }
            }
            KeiyoushiJVMHost.shared.call(withRequest: json, userAgent: CFBypassConstants.userAgent,
                                         cookies: cookies) { status, data, extensionId in
                finish(Reply(status: status, data: data, extensionId: extensionId))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.callTimeout) {
                let body = (try? JSONSerialization.data(withJSONObject: [
                    "error": String(localized: "The extension took too long to answer."), "code": 504,
                ])) ?? Data()
                finish(Reply(status: 504, data: body, extensionId: nil))
            }
        }
    }

    /// The pre-A6 transport: `POST http://127.0.0.1:<port>/dalvik` with the per-launch token.
    private func sendHTTP(_ json: Data, cookies: String?) async throws -> Reply {
        var port = try await ensurePort()
        var restarted = false
        while true {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/dalvik")!)
            request.httpMethod = "POST"
            request.timeoutInterval = Self.callTimeout
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(Self.token, forHTTPHeaderField: Self.tokenHeader)
            request.setValue(CFBypassConstants.userAgent, forHTTPHeaderField: "User-Agent")
            if let cookies { request.setValue(cookies, forHTTPHeaderField: "Cookie") }
            request.httpBody = json
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let http = response as? HTTPURLResponse
                return Reply(status: http?.statusCode ?? 0, data: data,
                             extensionId: http?.value(forHTTPHeaderField: "X-Mangayomi-Extension-Id"))
            } catch where !restarted && Self.isDeadListener(error) {
                // Once per call: restart the listener and send the same request again (it never reached the server).
                restarted = true
                dropDeadPort(port)
                port = try await ensurePort()
            }
        }
    }
}

// MARK: - Images served by the extension (A6)

/// Serves `keiyoushi-image://<id>` — pages and covers only the extension can fetch (Asura's scrambled tiles, a
/// `fetchImage` override) — by asking the runtime over JNI. Registered for `URLSession.shared` and in Kingfisher's
/// session, so the reader, prefetcher and downloads load them like any other URL; cache keys don't change
/// (`PageNames` keys bridge pages by chapter + index).
nonisolated final class KeiyoushiImageProtocol: URLProtocol, @unchecked Sendable {
    private let stopped = Mutex(false)

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == KeiyoushiBridge.imageScheme
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let id = url.host, !id.isEmpty else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Task { [weak self] in
            // Normally the runtime is already up (the page list came from it); a cached cover URL after a relaunch
            // starts it here — its id is gone then, so that request ends 404 and the cover's own URL is used.
            _ = await KeiyoushiBridge.shared.imagesReady()
            let (status, contentType, bytes) = await KeiyoushiJVMHost.shared.image(withId: id)
            self?.finish(url: url, status: status, contentType: contentType, bytes: bytes)
        }
    }

    override func stopLoading() {
        stopped.withLock { $0 = true }
    }

    private func finish(url: URL, status: Int, contentType: String?, bytes: Data?) {
        guard !stopped.withLock({ $0 }), let client else { return }
        guard status == 200, let bytes else {
            // 503 = runtime not up: retryable for the reader (PageRetry); 404 = id gone with a relaunch.
            client.urlProtocol(self, didFailWithError: URLError(status == 404 ? .fileDoesNotExist : .cannotLoadFromNetwork))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": contentType ?? "application/octet-stream",
            "Content-Length": String(bytes.count),
        ])!
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: bytes)
        client.urlProtocolDidFinishLoading(self)
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

    /// A whole chapter list as the source returned it, repeated URLs dropped. Numbers come from the list, not each
    /// name alone (Mihon v0.21, S165): a number every similar name shares isn't the chapter number, and chapters
    /// without one are numbered after their neighbours (2, "The Return", 4 → 3).
    nonisolated static func chapters(from items: [KeiyoushiChapter], mangaId: String, sourceId: String,
                                     mangaTitle: String) -> [Chapter] {
        let numbers = ChapterRecognition.numbers(mangaTitle: mangaTitle, names: items.map(\.name),
                                                 sourceNumbers: items.map(\.chapter_number))
        var seen = Set<String>()   // ids hash the chapter URL; never let a repeated URL become a duplicate row
        return zip(items, numbers).compactMap { item, number in
            var chapter = chapter(from: item, mangaId: mangaId, sourceId: sourceId, mangaTitle: mangaTitle)
            guard seen.insert(chapter.id).inserted else { return nil }
            chapter.chapterNumber = number
            return chapter
        }
    }

    /// The source's upload date per chapter id, for the update schedule (S166). Extensions send epoch milliseconds,
    /// 0 when they don't know.
    nonisolated static func uploadDates(from items: [KeiyoushiChapter], mangaId: String) -> [String: Date] {
        var dates: [String: Date] = [:]
        for item in items {
            guard let ms = item.date_upload, ms > 0 else { continue }
            dates["\(mangaId)_\(key(item.url))"] = Date(timeIntervalSince1970: Double(ms) / 1000)
        }
        return dates
    }

    nonisolated static func chapterPath(sourceId: String, url: String, name: String) -> String {
        let payload = (try? JSONSerialization.data(withJSONObject: ["s": sourceId, "u": url, "n": name])) ?? Data()
        let b64 = payload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return chapterScheme + b64
    }

    /// The chapter's page on the source's site, for the reader's "Open in WebView" (A7, S212). Mihon's default
    /// `getChapterUrl`: the chapter url when absolute, else the source's base URL + that path.
    @MainActor static func chapterWebURL(from path: String) -> URL? {
        guard let ref = chapterRef(from: path) else { return nil }
        if ref.url.hasPrefix("http://") || ref.url.hasPrefix("https://") { return URL(string: ref.url) }
        guard let home = KeiyoushiRepository.shared.installedExtension(forSourceId: ref.sourceId)?
                .info.sources.first(where: { $0.id == ref.sourceId })?.homeURL, !home.isEmpty else { return nil }
        let base = home.hasSuffix("/") ? String(home.dropLast()) : home
        return URL(string: base + (ref.url.hasPrefix("/") ? ref.url : "/" + ref.url))
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
/// on PacoDealer's iPhone 17) and ~7 s of CPU per Browse page. Sources often want their own headers (Referer, Origin)
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

    /// Reader pages the bridge returns as direct URLs load natively too (S159: through the proxy each Asura page
    /// spent 1.5–2 s in the JVM on top of its download); their headers go in the same per-host store.
    func remember(_ pages: [KeiyoushiPage]) {
        lock.withLock {
            var changed = false
            for page in pages {
                guard let headers = page.headers, !headers.isEmpty,
                      let host = page.imageUrl.flatMap(URL.init(string:))?.host,
                      headersByHost[host] != headers else { continue }
                headersByHost[host] = headers
                changed = true
            }
            if changed { UserDefaults.standard.set(headersByHost, forKey: Self.defaultsKey) }
        }
    }

    /// A plain `URLSession` request for a page or cover, with the headers Kingfisher's request modifier adds
    /// (including the bridge token and live port for pages the bridge serves).
    func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        for (name, value) in headers(for: url) { request.setValue(value, forHTTPHeaderField: name) }
        request.setValue(CFBypassConstants.userAgent, forHTTPHeaderField: "User-Agent")
        return KeiyoushiBridge.bridgeImageRequest(request)
    }

    /// Covers saved before S134 point at the bridge's proxy (`http://127.0.0.1:<port>/image/<token>`, since A6
    /// `keiyoushi-image://<token>`), which dies with the launch that issued it.
    static func isProxyURL(_ url: URL?) -> Bool {
        url?.scheme == KeiyoushiBridge.imageScheme || (url?.host == "127.0.0.1" && url?.path.hasPrefix("/image/") == true)
    }
}

extension KFImage {
    /// Falls back to the Keiyoushi bridge's image proxy when a cover won't load directly (see `KeiyoushiCovers`).
    func keiyoushiCoverFallback(_ url: URL?) -> KFImage {
        alternativeSources(KeiyoushiCovers.shared.proxy(for: url).map { [.network($0)] })
    }
}
