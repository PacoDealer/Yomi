import Foundation
import CryptoKit

/// A chapter's page list, kept so reopening a chapter that isn't downloaded shows its pages without asking the JS
/// plugin or the Keiyoushi JVM again (D12b, S164; Mihon's `ChapterCache`). One JSON file per chapter path in Caches —
/// iOS may empty it under storage pressure, which only costs a fetch.
///
/// Checked before building it (S164): Asura's CDN URLs are unsigned (`?v=` is an upload stamp, any value loads) and
/// served `immutable` for a year — the same URLs from the Asura JS plugin and from Keiyoushi; MangaFire's (Keiyoushi)
/// are the same on every fetch and served `max-age` 30 days, but need the Referer the bridge returns, which
/// `KeiyoushiCovers` already keeps per host across launches. Lists with bridge-proxied pages
/// (`127.0.0.1/image/<id>`) are never kept: those ids live only as long as the JVM. A cached URL that stops working
/// anyway is the reader's job: it refetches the list once and replaces the entry (`ChapterReaderView`).
nonisolated enum PageListCache {
    /// Old enough that a scanlator's fixed re-upload is picked up, long enough to cover a chapter left half-read.
    static let maxAge: TimeInterval = 7 * 24 * 3600

    private struct Entry: Codable {
        let path: String
        let pages: [String]
        let savedAt: Date
    }

    private static let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PageLists", isDirectory: true)

    /// The kept list for `path`, nil when there is none or it is older than `maxAge`.
    static func pages(for path: String) -> [String]? {
        _ = pruned
        guard let data = try? Data(contentsOf: file(for: path)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              entry.path == path, !entry.pages.isEmpty,
              Date().timeIntervalSince(entry.savedAt) < maxAge else { return nil }
        #if DEBUG
        // `-yomiStalePageList`: every kept URL points at a file that isn't there, to watch the reader recover.
        if UserDefaults.standard.bool(forKey: "yomiStalePageList") {
            return entry.pages.map { url in
                guard let slash = url.lastIndex(of: "/") else { return url }
                return url.replacingCharacters(in: slash...slash, with: "/stale-")
            }
        }
        #endif
        return entry.pages
    }

    /// Keeps a freshly fetched list. Local files, Suwayomi and lists with bridge-proxied pages are skipped.
    static func store(_ pages: [String], for path: String) {
        guard !pages.isEmpty, !path.hasPrefix(LocalLibrary.mangaScheme), SuwayomiService.chapterRef(from: path) == nil,
              !pages.contains(where: { KeiyoushiBridge.isBridgeImage(URL(string: $0)) }) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(Entry(path: path, pages: pages, savedAt: Date())) else { return }
        try? data.write(to: file(for: path), options: .atomic)
    }

    static func remove(path: String) {
        try? FileManager.default.removeItem(at: file(for: path))
    }

    private static func file(for path: String) -> URL {
        let hash = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(hash.prefix(32)).json")
    }

    /// Once per launch: expired entries go, so the folder never grows past a week of reading.
    private static let pruned: Void = {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return }
        let cutoff = Date().addingTimeInterval(-maxAge)
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff { try? fm.removeItem(at: file) }
        }
    }()
}
