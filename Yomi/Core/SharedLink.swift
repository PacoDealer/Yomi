import Foundation

/// Opening a title from a website link (S196, research `reports/S196-shared-links.md`). Pure rules, no app state, so
/// `scripts/shared-link-tests` can compile this file alone.
/// - Keiyoushi: an extension whose website has the link's host is searched with the whole link as the query — its
///   search turns a link into that one title (`KeiSource.getSearchManga` → `getMangaByUrl`).
/// - LNReader-format plugins: LNReader 2.1's rule — the ONE plugin whose website (`site`, or `BASE_URL` in Yomi's
///   own plugins) the link starts with; the rest of the link is the novel's path (`novelPath`).
/// - Anything else: search all sources for the words in the link's last part.
nonisolated enum SharedLink {

    /// The http(s) link in a pasted or shared text, or nil when it isn't one.
    static func url(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(" "), let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// The host without a leading "www." and in lower case, so www.site.com and site.com match.
    static func bareHost(_ host: String) -> String {
        let h = host.lowercased()
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    /// True when `link` is on the same website as `home` (a source's home URL).
    static func sameSite(_ link: URL, home: String) -> Bool {
        guard let linkHost = link.host, let homeHost = URL(string: home)?.host else { return false }
        return bareHost(linkHost) == bareHost(homeHost)
    }

    /// LNReader's rule, written as the exact reverse of how Yomi builds a novel's web link (`site + path`, a plain
    /// join — `JSBridge.resolveSourceURL`): the link (query and fragment dropped) must be on `site`'s host and under
    /// its path; the rest is the novel's path. It keeps a leading "/" when `site` has no trailing one, so Yomi's own
    /// plugins (`BASE_URL = "https://wetriedtls.com"`, paths "/series/x") get the same id as when browsing.
    /// nil when it doesn't match or nothing is left. "www." is ignored on both sides.
    static func novelPath(link: URL, site: String) -> String? {
        let site = site.trimmingCharacters(in: .whitespaces)
        guard let siteURL = URL(string: site), let siteHost = siteURL.host, let linkHost = link.host,
              bareHost(siteHost) == bareHost(linkHost) else { return nil }
        let basePath = siteURL.path.hasSuffix("/") ? String(siteURL.path.dropLast()) : siteURL.path
        let linkPath = link.path
        guard linkPath.hasPrefix(basePath + "/") else { return nil }
        let rest = trimSlashes(String(linkPath.dropFirst(basePath.count)))
        guard !rest.isEmpty else { return nil }
        return site.hasSuffix("/") ? rest : "/" + rest
    }

    /// Two paths name the same title when they differ only by leading/trailing slashes.
    static func samePath(_ a: String, _ b: String) -> Bool { trimSlashes(a) == trimSlashes(b) }

    /// Words to search for when no source can open the link: the last part of the path that has letters, with
    /// dashes and underscores as spaces and a trailing id dropped ("solo-leveling-12345" → "solo leveling").
    static func searchWords(from link: URL) -> String {
        let parts = link.path.split(separator: "/").map(String.init)
        guard let part = parts.last(where: { $0.contains(where: \.isLetter) && !isGenericSegment($0) }) else {
            return ""
        }
        var slug = part.replacingOccurrences(of: ".html", with: "").replacingOccurrences(of: ".htm", with: "")
        // MangaFire-style "one-piece.dkw": a short code after the last dot is an id.
        if let dot = slug.lastIndex(of: "."), slug[slug.index(after: dot)...].count <= 5, slug[..<dot].contains("-") {
            slug = String(slug[..<dot])
        }
        var words = slug
            .split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == "+" || $0 == "." })
            .map(String.init)
        // Sites often end a slug with an id ("-12345", "-a1b2c3d4"): drop trailing parts that are digits or short
        // letter+digit codes, keeping at least one word.
        while words.count > 1, let last = words.last, isIdLike(last) { words.removeLast() }
        return words.joined(separator: " ").removingPercentEncoding ?? words.joined(separator: " ")
    }

    // MARK: - Helpers

    static func trimSlashes(_ s: String) -> String {
        s.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func isIdLike(_ s: String) -> Bool {
        if s.allSatisfy(\.isNumber) { return true }
        let hasDigit = s.contains(where: \.isNumber), hasLetter = s.contains(where: \.isLetter)
        return hasDigit && hasLetter && s.count >= 5 && s.count <= 12 && !s.contains(where: \.isUppercase)
            && s.filter(\.isNumber).count >= 2
    }

    /// Path parts that name a section, not a title ("/manga/…", "/chapter-12").
    private static func isGenericSegment(_ s: String) -> Bool {
        let lower = s.lowercased()
        if ["manga", "manhwa", "manhua", "comic", "comics", "series", "novel", "novels", "book", "books", "title",
            "read", "webtoon", "webtoons", "en", "es"].contains(lower) { return true }
        // "chapter-12", "ch-3", "episode-4": a chapter, so the title is the part before it.
        for prefix in ["chapter", "ch-", "episode", "ep-", "capitulo", "vol-"] where lower.hasPrefix(prefix) {
            return true
        }
        return false
    }
}
