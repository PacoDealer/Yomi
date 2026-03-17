import Foundation

/// Represents an installable extension package (like Mihon's .apk extensions).
/// One Extension can expose multiple Sources (e.g. MangaDex with EN, ES, JP sources).
struct Extension: Identifiable, Codable, Hashable {
    let id: String                  // Reverse-domain, e.g. "com.yomi.mangadex"
    var name: String
    var version: String             // Semantic version, e.g. "1.0.0"
    var language: String            // Primary language (BCP 47), e.g. "multi"
    var iconURL: URL?
    var sourceListURL: URL          // URL of the JS file for this extension
    var isInstalled: Bool
    var isNSFW: Bool
    var sourceIds: [String]         // IDs of Sources this extension exposes
}
