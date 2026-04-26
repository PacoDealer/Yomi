import Foundation

// MARK: - OPDS Models

struct OPDSEntry: Identifiable {
    let id: String
    let title: String
    let author: String?
    let summary: String?
    /// Absolute or server-relative href for the cover image
    let coverHref: String?
    /// href to load when this is a navigation entry (another feed)
    let navigationHref: String?
    /// href to the acquisition resource (book download)
    let acquisitionHref: String?
    var isNavigation: Bool { navigationHref != nil }
}

struct OPDSFeed {
    let title: String
    let entries: [OPDSEntry]
    let nextPageHref: String?
}

// MARK: - OPDSService

final class OPDSService {

    static let shared = OPDSService()
    private init() {}

    // MARK: - Config

    var baseURL: String {
        var url = AppSettings.shared.opdsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.hasSuffix("/") { url = String(url.dropLast()) }
        return url
    }

    var isEnabled: Bool { !baseURL.isEmpty }

    private var username: String { AppSettings.shared.opdsUsername }
    private var password: String { AppSettings.shared.opdsPassword }

    // MARK: - Fetching

    func fetchFeed(href: String) async throws -> OPDSFeed {
        let urlString = absoluteURL(href: href)
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/atom+xml,application/xml,text/xml", forHTTPHeaderField: "Accept")
        if !username.isEmpty {
            let cred = Data("\(username):\(password)".utf8).base64EncodedString()
            request.setValue("Basic \(cred)", forHTTPHeaderField: "Authorization")
        }
        let (data, resp) = try await URLSession.shared.data(for: request)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try parse(data: data)
    }

    func testConnection() async throws -> Int {
        let feed = try await fetchFeed(href: baseURL)
        return feed.entries.count
    }

    // MARK: - URL helpers

    func absoluteURL(href: String) -> String {
        if href.hasPrefix("http://") || href.hasPrefix("https://") { return href }
        let base: String
        if let url = URL(string: baseURL), let host = url.host {
            let scheme = url.scheme ?? "http"
            let port = url.port.map { ":\($0)" } ?? ""
            base = "\(scheme)://\(host)\(port)"
        } else {
            base = baseURL
        }
        return href.hasPrefix("/") ? "\(base)\(href)" : "\(base)/\(href)"
    }

    func coverURL(for entry: OPDSEntry) -> URL? {
        guard let href = entry.coverHref else { return nil }
        return URL(string: absoluteURL(href: href))
    }

    // MARK: - XML Parsing

    private func parse(data: Data) throws -> OPDSFeed {
        let delegate = OPDSXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        if !parser.parse(), let err = parser.parserError { throw err }
        return delegate.buildFeed()
    }
}

// MARK: - XML Delegate

private final class OPDSXMLDelegate: NSObject, XMLParserDelegate {

    // Feed-level
    var feedTitle = ""
    var nextPageHref: String?

    // Entry accumulation
    var entries: [OPDSEntry] = []

    private var inEntry = false
    private var inAuthor = false
    private var inFeedTitle = false  // feed-level <title>, not entry-level
    private var currentText = ""

    // Current entry builder state
    private var entryId = ""
    private var entryTitle = ""
    private var entryAuthor: String?
    private var entrySummary: String?
    private var entryCoverHref: String?
    private var entryNavigationHref: String?
    private var entryAcquisitionHref: String?

    func parser(_ parser: XMLParser,
                didStartElement localName: String,
                namespaceURI: String?,
                qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentText = ""
        switch localName {
        case "entry":
            inEntry = true
            entryId = ""
            entryTitle = ""
            entryAuthor = nil
            entrySummary = nil
            entryCoverHref = nil
            entryNavigationHref = nil
            entryAcquisitionHref = nil
        case "author":
            inAuthor = true
        case "title":
            if !inEntry { inFeedTitle = true }
        case "link":
            handleLink(attributes: attributes)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser,
                didEndElement localName: String,
                namespaceURI: String?,
                qualifiedName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch localName {
        case "entry":
            if !entryTitle.isEmpty {
                entries.append(OPDSEntry(
                    id: entryId.isEmpty ? UUID().uuidString : entryId,
                    title: entryTitle,
                    author: entryAuthor,
                    summary: entrySummary,
                    coverHref: entryCoverHref,
                    navigationHref: entryNavigationHref,
                    acquisitionHref: entryAcquisitionHref
                ))
            }
            inEntry = false
            inAuthor = false
        case "author":
            inAuthor = false
        case "title":
            if inEntry {
                entryTitle = text
            } else if inFeedTitle {
                feedTitle = text
                inFeedTitle = false
            }
        case "id":
            if inEntry { entryId = text }
        case "name":
            if inAuthor && inEntry { entryAuthor = text }
        case "summary", "content":
            if inEntry && entrySummary == nil && !text.isEmpty {
                // strip basic HTML tags for summary
                entrySummary = text
                    .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        default:
            break
        }
        currentText = ""
    }

    private func handleLink(attributes: [String: String]) {
        guard let href = attributes["href"] else { return }
        let rel  = attributes["rel"]  ?? ""
        let type = attributes["type"] ?? ""

        // Cover image
        if rel == "http://opds-spec.org/image" || rel == "http://opds-spec.org/image/thumbnail" {
            if inEntry { entryCoverHref = href }
            return
        }
        // Acquisition (book download)
        if rel == "http://opds-spec.org/acquisition" || rel.contains("acquisition") {
            if inEntry { entryAcquisitionHref = href }
            return
        }
        // Next page
        if rel == "next" && !inEntry {
            nextPageHref = href
            return
        }
        // Navigation (sub-feed)
        let isAtomType = type.contains("application/atom+xml") || type.contains("application/xml")
        let isNavRel   = rel == "subsection" || rel == "related" || rel.contains("catalog")
        if inEntry && isAtomType && (isNavRel || entryNavigationHref == nil) {
            entryNavigationHref = href
        }
    }

    func buildFeed() -> OPDSFeed {
        OPDSFeed(title: feedTitle.isEmpty ? "OPDS Catalog" : feedTitle,
                 entries: entries,
                 nextPageHref: nextPageHref)
    }
}
