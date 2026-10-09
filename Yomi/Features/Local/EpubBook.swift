import Foundation

// MARK: - EpubBook
//
// S148: an EPUB read as a novel (Martin's pick) — META-INF/container.xml → the OPF package (metadata, manifest,
// spine) → chapters = the spine's linear documents, titled from the EPUB 3 nav document or the EPUB 2 toc.ncx.
// Every href is stored as a full path inside the archive. Regex-based on purpose: OPF/nav/ncx are small and regular,
// and the novel reader only needs each chapter's body.

nonisolated struct EpubBook {
    struct Chapter: Sendable {
        /// Full path of the spine document inside the archive.
        let href: String
        let title: String
    }

    let zip: ZipArchive
    let title: String?
    let author: String?
    let summary: String?
    let subjects: [String]
    let chapters: [Chapter]
    let coverPath: String?

    init(url: URL) throws {
        let zip = try ZipArchive(url: url)
        self.zip = zip
        guard let containerData = try zip.contents(of: "META-INF/container.xml"),
              let container = String(data: containerData, encoding: .utf8),
              let opfPath = Self.firstAttribute("full-path", inTagsNamed: "rootfile", of: container),
              let opfData = try zip.contents(of: opfPath),
              let opf = String(data: opfData, encoding: .utf8) else {
            throw LocalLibrary.LocalError.notAnEpub("no package document")
        }
        let opfDir = (opfPath as NSString).deletingLastPathComponent

        title = Self.element("dc:title", in: opf)
        author = Self.element("dc:creator", in: opf)
        summary = Self.element("dc:description", in: opf).map(Self.plainText)
        subjects = Self.elements("dc:subject", in: opf)

        // Manifest: id → (full path, media type, properties).
        var manifest: [String: (path: String, type: String, props: String)] = [:]
        for tag in Self.tags("item", in: opf) {
            guard let id = Self.attribute("id", in: tag), let href = Self.attribute("href", in: tag) else { continue }
            manifest[id] = (Self.join(opfDir, href), Self.attribute("media-type", in: tag) ?? "",
                            Self.attribute("properties", in: tag) ?? "")
        }

        // Cover: EPUB 3 properties="cover-image", else EPUB 2 <meta name="cover" content="id">.
        var cover = manifest.values.first { $0.props.contains("cover-image") }?.path
        if cover == nil {
            let metaCover = Self.tags("meta", in: opf).first { Self.attribute("name", in: $0) == "cover" }
                .flatMap { Self.attribute("content", in: $0) }
            cover = metaCover.flatMap { manifest[$0]?.path }
        }
        coverPath = cover

        // Table of contents: full path (no fragment) → first title.
        var tocTitles: [String: String] = [:]
        if let nav = manifest.values.first(where: { $0.props.split(separator: " ").contains("nav") }),
           let data = try? zip.contents(of: nav.path), let html = String(data: data, encoding: .utf8) {
            let navDir = (nav.path as NSString).deletingLastPathComponent
            let scope = html.range(of: #"<nav[^>]*toc[\s\S]*?</nav>"#, options: .regularExpression).map { String(html[$0]) } ?? html
            for match in Self.matches(#"<a\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)</a>"#, in: scope) {
                let path = Self.join(navDir, match[0].components(separatedBy: "#")[0])
                let text = Self.plainText(match[1])
                if !text.isEmpty, tocTitles[path] == nil { tocTitles[path] = text }
            }
        }
        if tocTitles.isEmpty,
           let ncx = manifest.values.first(where: { $0.type == "application/x-dtbncx+xml" }),
           let data = try? zip.contents(of: ncx.path), let xml = String(data: data, encoding: .utf8) {
            let ncxDir = (ncx.path as NSString).deletingLastPathComponent
            for match in Self.matches(#"<navLabel>\s*<text>([\s\S]*?)</text>\s*</navLabel>\s*<content\b[^>]*src\s*=\s*["']([^"']+)["']"#, in: xml) {
                let path = Self.join(ncxDir, match[1].components(separatedBy: "#")[0])
                let text = Self.plainText(match[0])
                if !text.isEmpty, tocTitles[path] == nil { tocTitles[path] = text }
            }
        }

        var chapters: [Chapter] = []
        for tag in Self.tags("itemref", in: opf) {
            guard let idref = Self.attribute("idref", in: tag), let item = manifest[idref],
                  Self.attribute("linear", in: tag) != "no" else { continue }
            let title = tocTitles[item.path] ?? Self.documentTitle(zip: zip, path: item.path)
                ?? "Section \(chapters.count + 1)"
            chapters.append(Chapter(href: item.path, title: title))
        }
        guard !chapters.isEmpty else { throw LocalLibrary.LocalError.notAnEpub("no chapters") }
        self.chapters = chapters
    }

    func coverData() -> Data? {
        coverPath.flatMap { try? zip.contents(of: $0) }
    }

    /// Body of one spine document for the novel reader: no scripts/styles/links, images as data: URIs.
    func html(forHref href: String) -> String? {
        guard let data = try? zip.contents(of: href) else { return nil }
        let doc = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        var body = doc.range(of: #"<body[^>]*>([\s\S]*)</body>"#, options: .regularExpression)
            .map { String(doc[$0]).replacingOccurrences(of: #"^<body[^>]*>|</body>$"#, with: "", options: .regularExpression) }
            ?? doc
        for pattern in [#"<script[\s\S]*?</script>"#, #"<style[\s\S]*?</style>"#, #"<link\b[^>]*>"#] {
            body = body.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        // SVG-wrapped covers/illustrations (<svg><image xlink:href=…/></svg>) → a plain <img>.
        body = body.replacingOccurrences(
            of: #"<svg\b[\s\S]*?<image\b[^>]*?(?:xlink:)?href\s*=\s*["']([^"']+)["'][\s\S]*?</svg>"#,
            with: "<img src=\"$1\">", options: [.regularExpression, .caseInsensitive])

        let dir = (href as NSString).deletingLastPathComponent
        var out = ""
        let imgSrc = try? NSRegularExpression(pattern: #"(<img\b[^>]*?\bsrc\s*=\s*["'])([^"']+)(["'])"#, options: .caseInsensitive)
        let ns = body as NSString
        var last = 0
        for m in imgSrc?.matches(in: body, range: NSRange(location: 0, length: ns.length)) ?? [] {
            out += ns.substring(with: NSRange(location: last, length: m.range(at: 2).location - last))
            let src = ns.substring(with: m.range(at: 2))
            out += dataURI(for: Self.join(dir, src)) ?? src
            last = m.range(at: 2).location + m.range(at: 2).length
        }
        out += ns.substring(from: last)
        return out
    }

    private func dataURI(for path: String) -> String? {
        guard !path.hasPrefix("data:"), let data = try? zip.contents(of: path) else { return nil }
        let mime: String
        switch (path as NSString).pathExtension.lowercased() {
        case "png": mime = "image/png"
        case "gif": mime = "image/gif"
        case "webp": mime = "image/webp"
        case "svg": mime = "image/svg+xml"
        default: mime = "image/jpeg"
        }
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }

    // MARK: Parsing helpers

    /// `dir` + a relative href, with `..` resolved and percent-escapes removed (archive entry names are plain).
    static func join(_ dir: String, _ href: String) -> String {
        let decoded = href.removingPercentEncoding ?? href
        if decoded.hasPrefix("/") { return String(decoded.dropFirst()) }
        var parts = dir.isEmpty ? [] : dir.split(separator: "/").map(String.init)
        for piece in decoded.split(separator: "/", omittingEmptySubsequences: true) {
            if piece == ".." { if !parts.isEmpty { parts.removeLast() } }
            else if piece != "." { parts.append(String(piece)) }
        }
        return parts.joined(separator: "/")
    }

    static func tags(_ name: String, in xml: String) -> [String] {
        matches("(<(?:[a-zA-Z0-9]+:)?\(name)\\b[^>]*>)", in: xml).map { $0[0] }
    }

    static func attribute(_ name: String, in tag: String) -> String? {
        guard let r = tag.range(of: "\\b\(name)\\s*=\\s*[\"']([^\"']*)[\"']", options: .regularExpression) else { return nil }
        let raw = tag[r].replacingOccurrences(of: "^[^=]*=\\s*[\"']|[\"']$", with: "", options: .regularExpression)
        return XMLText.decode(raw)
    }

    static func firstAttribute(_ name: String, inTagsNamed tagName: String, of xml: String) -> String? {
        tags(tagName, in: xml).lazy.compactMap { attribute(name, in: $0) }.first
    }

    static func element(_ name: String, in xml: String) -> String? {
        elements(name, in: xml).first
    }

    static func elements(_ name: String, in xml: String) -> [String] {
        matches("<\(name)\\b[^>]*>([\\s\\S]*?)</\(name)>", in: xml)
            .map { XMLText.decode($0[0]).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func plainText(_ html: String) -> String {
        XMLText.decode(html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Capture groups of every match.
    static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            (1..<m.numberOfRanges).map { i in
                m.range(at: i).location == NSNotFound ? "" : ns.substring(with: m.range(at: i))
            }
        }
    }

    /// A spine document with no table-of-contents entry: its <title>, else its first heading.
    private static func documentTitle(zip: ZipArchive, path: String) -> String? {
        guard let data = try? zip.contents(of: path), let html = String(data: data, encoding: .utf8) else { return nil }
        for pattern in [#"<h[1-3][^>]*>([\s\S]*?)</h[1-3]>"#, #"<title[^>]*>([\s\S]*?)</title>"#] {
            if let first = matches(pattern, in: html).first, case let text = plainText(first[0]), !text.isEmpty {
                return text
            }
        }
        return nil
    }
}
