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

    /// Whether a request to `url` would send one of these cookies (a Cloudflare clearance, A5 S209).
    func hasCookie(named names: Set<String>, for url: URL) -> Bool {
        (storage.cookies(for: url) ?? []).contains { names.contains($0.name) }
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

// MARK: - PluginStore

/// LNReader's `@libs/storage` for one plugin (A4, S209), saved to `Application Support/PluginStorage/<id>.json`. Before
/// S209 it was an in-memory object, so a plugin's login token, its settings (`pluginSettings`) and anything it cached
/// were gone at every launch. The keys follow LNReader's (`helpers/storage.ts`, MIT): `_DB_<key>` holds a stored item
/// (JSON written by the JS side, which also handles expiry), `_LocalStorage` / `_SessionStorage` what the site's page
/// stored, saved from the Website sheet for plugins with `webStorageUtilized`. One object per plugin id, shared by
/// every bridge built from its script, so a setting changed in the settings form reaches the cached bridge at once.
nonisolated final class PluginStore: @unchecked Sendable {
    let id: String
    private let fileURL: URL?
    private let lock = NSLock()
    private var values: [String: String]

    static let itemPrefix = "_DB_"
    static let localStorageKey = "_LocalStorage"
    static let sessionStorageKey = "_SessionStorage"

    private init(id: String, directory: URL?) {
        self.id = id
        fileURL = directory.flatMap { dir in
            PluginNetworkPolicy.isSafePluginId(id) ? dir.appendingPathComponent("\(id).json") : nil
        }
        values = fileURL.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }

    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var registry: [String: PluginStore] = [:]

    /// Where stores are saved. Tests point it at a temporary folder; nil keeps them in memory only. Kept out of
    /// iCloud backups like the cookie jars: logins and tokens belong to this phone.
    nonisolated(unsafe) static var directory: URL? = {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        var dir = base.appendingPathComponent("PluginStorage", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        return dir
    }()

    static func forPlugin(_ id: String) -> PluginStore {
        registryLock.lock(); defer { registryLock.unlock() }
        if let store = registry[id] { return store }
        let store = PluginStore(id: id, directory: directory)
        registry[id] = store
        return store
    }

    /// A removed plugin's data goes with it (memory and disk).
    static func remove(id: String) {
        forPlugin(id).clear()
    }

    func get(_ key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }

    /// nil deletes the key.
    func set(_ key: String, _ value: String?) {
        lock.lock(); defer { lock.unlock() }
        guard values[key] != value else { return }
        values[key] = value
        save()
    }

    func keys() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return values.keys.sorted()
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        values = [:]
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }

    /// Caller holds the lock.
    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(values) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: Plugin items (`storage.get/set`)

    /// A stored item the way LNReader writes it: `{"created": …, "value": …, "expires": ms}`; nil when missing or
    /// expired (an expired item is deleted, like LNReader's `get`).
    func itemValueJSON(_ key: String, now: Date = Date()) -> String? {
        guard let raw = get(Self.itemPrefix + key),
              let item = try? JSONSerialization.jsonObject(with: Data(raw.utf8), options: [.fragmentsAllowed]) as? [String: Any]
        else { return nil }
        if let expires = item["expires"] as? Double, now.timeIntervalSince1970 * 1000 > expires {
            set(Self.itemPrefix + key, nil)
            return nil
        }
        guard let value = item["value"],
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Writes `value` (any JSON) as a LNReader item, never expiring — what the settings form saves.
    func setItemValue(_ key: String, json valueJSON: String, now: Date = Date()) {
        let created = ISO8601DateFormatter().string(from: now)
        let item = "{\"created\":\"\(created)\",\"value\":\(valueJSON)}"
        set(Self.itemPrefix + key, item)
    }
}

// MARK: - PluginImageHeaders

/// LNReader plugins' `imageRequestInit.headers` (A4, S209) by image host — LNReader sends them with every cover and
/// chapter image of the plugin; without them hot-link-protected sites answer covers with 403. Filled by `JSBridge` from
/// the plugin's site and the covers it returns (a CDN host is often not the site's); read by Kingfisher's request
/// modifier (YomiApp). The User-Agent is never taken: Cloudflare clearances are bound to Yomi's.
nonisolated enum PluginImageHeaders {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var byHost: [String: [String: String]] = [:]

    static func register(_ headers: [String: String], forHostsOf urls: [String?]) {
        let usable = headers.filter { $0.key.lowercased() != "user-agent" && !$0.value.isEmpty }
        guard !usable.isEmpty else { return }
        let hosts = Set(urls.compactMap { $0.flatMap(URL.init(string:))?.host()?.lowercased() })
        guard !hosts.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        for host in hosts where byHost[host] != usable { byHost[host] = usable }
    }

    static func headers(for url: URL?) -> [String: String] {
        guard let host = url?.host()?.lowercased() else { return [:] }
        lock.lock(); defer { lock.unlock() }
        return byHost[host] ?? [:]
    }
}

// MARK: - PluginSettingField

/// One control of an LNReader plugin's `pluginSettings` form (A4, S209; types from LNReader's plugins/types, MIT).
/// The value the user picks is saved in the plugin's `PluginStore` under the field's key — the plugin reads it back
/// with `storage.get(key)`.
nonisolated struct PluginSettingField: Identifiable, Sendable, Equatable {
    struct Option: Sendable, Equatable, Hashable {
        let label: String
        let value: String
    }
    enum Kind: Sendable, Equatable {
        case text(String)
        case toggle(Bool)
        case select(String, [Option])
        case checkboxes([String], [Option])
    }
    let key: String
    let label: String
    /// The plugin's default.
    let kind: Kind
    var id: String { key }

    init?(json: [String: Any]) {
        guard let key = json["key"] as? String, !key.isEmpty else { return nil }
        self.key = key
        label = json["label"] as? String ?? key
        let options = (json["options"] as? [[String: Any]] ?? []).compactMap { o -> Option? in
            guard let value = o["value"].map({ "\($0)" }) else { return nil }
            return Option(label: o["label"] as? String ?? value, value: value)
        }
        switch json["type"] as? String {
        case "Switch": kind = .toggle((json["value"] as? Bool) ?? false)
        case "Select": kind = .select(json["value"].map { "\($0)" } ?? options.first?.value ?? "", options)
        case "CheckboxGroup": kind = .checkboxes((json["value"] as? [Any] ?? []).map { "\($0)" }, options)
        default: kind = .text(json["value"].map { "\($0)" } ?? "")
        }
    }

    /// The saved value as this field's kind, or the default when nothing (or something of another type) is saved.
    func current(in store: PluginStore) -> Kind {
        let saved = store.itemValueJSON(key)
            .flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8), options: [.fragmentsAllowed]) }
        switch kind {
        case .text(let d): return .text(saved as? String ?? d)
        case .toggle(let d): return .toggle(saved as? Bool ?? d)
        case .select(let d, let o): return .select(saved as? String ?? d, o)
        case .checkboxes(let d, let o): return .checkboxes(saved as? [String] ?? d, o)
        }
    }

    func save(_ value: Kind, in store: PluginStore) {
        let object: Any = switch value {
        case .text(let v): v
        case .toggle(let v): v
        case .select(let v, _): v
        case .checkboxes(let v, _): v
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed]),
              let json = String(data: data, encoding: .utf8) else { return }
        store.setItemValue(key, json: json)
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
