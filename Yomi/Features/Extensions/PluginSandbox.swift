import Foundation

// S192 (S189 audit, "JS security"): what keeps one JS plugin away from another's site cookies, and a runaway plugin
// from fetching forever. Foundation-only: scripts/plugin-sandbox-tests compiles it.

// MARK: - PluginCookieJar

/// One cookie store per plugin, keyed by its id (the script's file name, `<id>.js`). Before S192 every plugin used
/// `URLSession.shared`, so a Cloudflare check or a website login done for one source was sent by every other plugin
/// that asked for that site. Now a plugin only ever sends cookies it got itself or that Yomi gave it (its own
/// Cloudflare check / Website page).
///
/// The store is the private one of an ephemeral `URLSessionConfiguration` (a plain `HTTPCookieStorage()` silently
/// keeps nothing — checked on macOS, S192). Persistent cookies are saved to `Application Support/PluginCookies/<id>.plist`
/// after any request that changed them; session cookies live until the app quits, like the shared store.
nonisolated final class PluginCookieJar: @unchecked Sendable {
    let id: String
    let storage: HTTPCookieStorage
    /// One session per plugin, shared by every bridge built from its script (detail page, Browse, readers): its
    /// cookies, its in-memory response cache, and the redirect check.
    let session: URLSession

    private let fileURL: URL?
    private let lock = NSLock()
    private var savedSignature: Int

    private init(id: String, directory: URL?) {
        self.id = id
        let config = URLSessionConfiguration.ephemeral
        let storage = config.httpCookieStorage ?? HTTPCookieStorage.shared   // never nil for .ephemeral
        storage.cookieAcceptPolicy = .always
        config.httpCookieAcceptPolicy = .always
        self.storage = storage
        session = URLSession(configuration: config, delegate: PluginRedirectGuard(), delegateQueue: nil)
        fileURL = directory.flatMap { dir in
            PluginNetworkPolicy.isSafePluginId(id) ? dir.appendingPathComponent("\(id).plist") : nil
        }
        savedSignature = 0
        for cookie in fileURL.map(Self.load) ?? [] { storage.setCookie(cookie) }
        savedSignature = signature()
    }

    // MARK: Registry

    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var registry: [String: PluginCookieJar] = [:]

    /// Where jars are saved. Tests point it at a temporary folder; nil keeps jars in memory only.
    nonisolated(unsafe) static var directory: URL? = {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        var dir = base.appendingPathComponent("PluginCookies", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Logins and Cloudflare clearances belong to this phone (Cloudflare binds them to its IP and User-Agent).
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        return dir
    }()

    /// The jar for a plugin id — the same object for every caller, loaded from disk on first use.
    static func forPlugin(_ id: String) -> PluginCookieJar {
        registryLock.lock(); defer { registryLock.unlock() }
        if let jar = registry[id] { return jar }
        let jar = PluginCookieJar(id: id, directory: directory)
        registry[id] = jar
        return jar
    }

    /// Forget a removed plugin's cookies (memory and disk).
    static func remove(id: String) {
        forPlugin(id).clear()
    }

    /// Storage → "Clear web cache & cookies": every plugin's jar, including ones not loaded this launch.
    static func clearAll() {
        registryLock.lock()
        let jars = Array(registry.values)
        registryLock.unlock()
        for jar in jars { jar.clear() }
        if let dir = directory,
           let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "plist" { try? FileManager.default.removeItem(at: file) }
        }
    }

    // MARK: Cookies

    /// Cookies a request to `host` would send: same domain, or a parent domain (`.example.com` for `www.example.com`).
    /// WebKit's store holds every site's cookies, so only these are handed to a plugin.
    static func matching(_ cookies: [HTTPCookie], host: String) -> [HTTPCookie] {
        let host = host.lowercased()
        guard !host.isEmpty else { return [] }
        return cookies.filter { c in
            let cd = (c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain).lowercased()
            return cd == host || host.hasSuffix("." + cd)
        }
    }

    /// Cookies Yomi hands this plugin: its own Cloudflare check or Website page.
    func importCookies(_ cookies: [HTTPCookie]) {
        for cookie in cookies { storage.setCookie(cookie) }
        saveIfChanged()
    }

    /// After every plugin request: save what changed, and copy the cookies for that address into the shared store,
    /// which Kingfisher (covers, reader pages) and the Keiyoushi bridge read — images that need a cookie the plugin's
    /// own request set keep working as before S192. Plugins never read the shared store, so this doesn't leak back.
    func didFinishRequest(to url: URL?) {
        if let url, let cookies = storage.cookies(for: url) {
            for cookie in cookies { HTTPCookieStorage.shared.setCookie(cookie) }
        }
        saveIfChanged()
    }

    func clear() {
        for cookie in storage.cookies ?? [] { storage.deleteCookie(cookie) }
        lock.lock(); defer { lock.unlock() }
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        savedSignature = signature()
    }

    func saveIfChanged() {
        lock.lock(); defer { lock.unlock() }
        let now = signature()
        guard now != savedSignature, let fileURL else { savedSignature = now; return }
        let plist = persistentCookies().map(Self.plistValue)
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        else { return }
        if (try? data.write(to: fileURL, options: .atomic)) != nil { savedSignature = now }
    }

    private func persistentCookies() -> [HTTPCookie] {
        let now = Date()
        return (storage.cookies ?? []).filter { !$0.isSessionOnly && ($0.expiresDate ?? .distantFuture) > now }
    }

    private func signature() -> Int {
        var hasher = Hasher()
        for c in persistentCookies().sorted(by: { ($0.domain, $0.path, $0.name) < ($1.domain, $1.path, $1.name) }) {
            hasher.combine(c.domain); hasher.combine(c.path); hasher.combine(c.name); hasher.combine(c.value)
            hasher.combine(c.expiresDate)
        }
        return hasher.finalize()
    }

    private static func plistValue(_ cookie: HTTPCookie) -> [String: Any] {
        var out: [String: Any] = [:]
        for (key, value) in cookie.properties ?? [:] {
            switch value {
            case let url as URL: out[key.rawValue] = url.absoluteString
            case is String, is Date, is NSNumber: out[key.rawValue] = value
            default: out[key.rawValue] = "\(value)"
            }
        }
        return out
    }

    private static func load(_ url: URL) -> [HTTPCookie] {
        guard let data = try? Data(contentsOf: url),
              let list = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]]
        else { return [] }
        let now = Date()
        return list.compactMap { dict in
            var props: [HTTPCookiePropertyKey: Any] = [:]
            for (key, value) in dict { props[HTTPCookiePropertyKey(key)] = value }
            guard let cookie = HTTPCookie(properties: props), (cookie.expiresDate ?? .distantFuture) > now else { return nil }
            return cookie
        }
    }
}

// MARK: - Redirects

/// `PluginNetworkPolicy` checked only the address a plugin asked for, so a site redirecting to 127.0.0.1 (the
/// Keiyoushi bridge) still got through (S190 note on #228). A refused redirect isn't followed: the plugin gets the
/// 3xx response itself.
nonisolated final class PluginRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let allowed = request.url.map { PluginNetworkPolicy.allows($0) } ?? false
        completionHandler(allowed ? request : nil)
    }
}

// MARK: - PluginCallGate

/// Serialises a bridge's plugin calls (the old NSRecursiveLock) and gives each outermost call a time limit.
///
/// JavaScriptCore has no public way to stop running script (`JSContextGroupSetExecutionTimeLimit` is private API —
/// not in the iOS SDK headers, Guideline 2.5.1), so the limit is enforced where plugins wait: once a call is over its
/// time, every `SOURCE.fetch`/`fetchApi` request is refused with a JS error, and the entry point returns its empty
/// value instead of whatever partial result the plugin assembled (a cut-short chapter list must never look like the
/// real one). A plugin stuck in a loop that never fetches can't be stopped this way; it keeps only its own source busy.
nonisolated final class PluginCallGate: @unchecked Sendable {
    static let defaultLimit: TimeInterval = 120

    let limit: TimeInterval
    private let now: () -> Date
    private let callLock = NSRecursiveLock()
    private let stateLock = NSLock()
    private var depth = 0
    private var deadline: Date?
    private var refused = false

    init(limit: TimeInterval = PluginCallGate.defaultLimit, now: @escaping () -> Date = Date.init) {
        self.limit = limit
        self.now = now
    }

    /// Nested calls (an entry point asking `isLNReaderPlugin`) share the outermost call's time.
    func lock() {
        callLock.lock()
        stateLock.lock(); defer { stateLock.unlock() }
        depth += 1
        if depth == 1 { deadline = now().addingTimeInterval(limit); refused = false }
    }

    func unlock() {
        stateLock.lock()
        depth -= 1
        if depth == 0 { deadline = nil }
        stateLock.unlock()
        callLock.unlock()
    }

    /// Runs `body` as one plugin call; returns `empty` if the time limit refused a request during it.
    func run<T>(_ empty: T, _ body: () -> T) -> T {
        lock(); defer { unlock() }
        let result = body()
        return timedOut ? empty : result
    }

    /// A fresh limit for the next step of a long call Yomi itself drives (one page of a paged chapter list).
    func restart() {
        stateLock.lock(); defer { stateLock.unlock() }
        if depth > 0, !refused { deadline = now().addingTimeInterval(limit) }
    }

    /// Asked before each plugin request. Outside a call (the script's top level while loading) there is no limit.
    func allowsRequest() -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        if refused { return false }
        guard let deadline else { return true }
        if now() > deadline { refused = true; return false }
        return true
    }

    var timedOut: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return refused
    }
}
