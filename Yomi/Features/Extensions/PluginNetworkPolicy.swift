import Foundation

/// What third-party plugin code may touch (S190, from the S189 audit). Foundation-only: scripts/plugin-trust-tests compiles it.
nonisolated enum PluginNetworkPolicy {
    /// `SOURCE.fetch` is for websites: http(s) only, and never this phone itself. `file://` read Yomi's own files
    /// (library database, backups) for a plugin to send anywhere, and 127.0.0.1 is the Keiyoushi bridge, which runs
    /// extensions with the user's cookies and settings.
    static func allows(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]")),
              !host.isEmpty else { return false }
        if host == "localhost" || host.hasSuffix(".localhost") || host == "::1" || host == "0.0.0.0" { return false }
        if host.hasPrefix("127.") || host.hasPrefix("::ffff:127.") || host.hasPrefix("169.254.") || host.hasPrefix("fe80:") {
            return false
        }
        return true
    }

    /// Plugin CODE and the lists that point at it (JS plugins, catalogs, Keiyoushi indexes and APKs) only over https,
    /// to a real host. Over plain http anyone on the network (café Wi-Fi) could swap in their own code (S193). Check
    /// the link before fetching and the response's final URL after, since a redirect can drop to http.
    static func isSecureDownload(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https" else { return false }
        return allows(url)
    }

    /// Two plugin file links come from the same publisher: same host, and on hosts many publishers share (GitHub raw,
    /// GitHub Pages, jsDelivr) the same owner too.
    static func sameOrigin(_ a: URL, _ b: URL) -> Bool {
        guard let ha = a.host?.lowercased(), let hb = b.host?.lowercased(), ha == hb else { return false }
        func owner(_ u: URL) -> String {
            let parts = u.pathComponents.filter { $0 != "/" }
            let rest = (ha == "cdn.jsdelivr.net" && parts.first == "gh") ? Array(parts.dropFirst()) : parts
            return rest.first?.lowercased() ?? ""
        }
        if ha == "raw.githubusercontent.com" || ha == "cdn.jsdelivr.net" || ha == "github.com" {
            return owner(a) == owner(b)
        }
        return true
    }

    /// A plugin id becomes `<id>.js` on disk, so it can't contain a path: no `/`, `\\`, `:`, control characters,
    /// leading `.` or `..` — a hostile catalog could otherwise write or delete files outside the plugins folder
    /// with an id like `../../x`. Real ids (`com.yomi.novelfire`, LNReader's, Mangayomi's numbers) all pass.
    static func isSafePluginId(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 200, !id.hasPrefix("."), !id.contains("..") else { return false }
        return !id.unicodeScalars.contains { $0 == "/" || $0 == "\\" || $0 == ":" || $0.value < 0x20 || $0.value == 0x7F }
    }
}
