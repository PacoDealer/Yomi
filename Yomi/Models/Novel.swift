import Foundation

// MARK: - Novel

struct Novel: Identifiable, Codable {
    let id: String
    let path: String
    let sourceId: String
    var title: String
    var coverURL: URL?
    var summary: String?
    var author: String?
    var status: String
    var genres: [String]
    var inLibrary: Bool
    var lastReadAt: Date?
    var lastUpdatedAt: Date?
    var readingSeconds: Int
    var readingStatus: ReadingStatus
    var notes: String?
    /// Relative path under Documents (e.g. "Covers/<id>.jpg"). Absolute paths are legacy.
    var customCoverPath: String? = nil

    /// Returns the absolute filesystem path for the custom cover, handling both
    /// legacy absolute paths (stored before S78 fix) and new relative paths.
    var resolvedCustomCoverPath: String? {
        guard let stored = customCoverPath else { return nil }
        if stored.hasPrefix("/") { return stored }
        return FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(stored).path
    }
}

// MARK: - NovelChapter

struct NovelChapter: Identifiable, Codable, Hashable {
    let id: String
    let novelId: String
    let path: String
    var name: String
    var chapterNumber: Double?
    var isRead: Bool
    var readAt: Date?
    var releaseTime: String?
    var readingSeconds: Int
    var lastScrollPercent: Double? = nil
}
