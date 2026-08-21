import Foundation

/// Represents a chapter of a work
struct Chapter: Identifiable, Codable, Hashable {
    /// Local unique identifier
    let id: String
    /// ID of the manga this chapter belongs to
    let mangaId: String
    /// Relative path within the source (used to fetch pages)
    let path: String
    /// Chapter name or title (e.g. "Chapter 1" or "Prologue")
    var name: String
    /// Chapter number; may be nil if the source doesn't provide one
    var chapterNumber: Double?
    /// Whether the user has already read this chapter
    var isRead: Bool
    /// Whether the chapter is downloaded for offline reading
    var isDownloaded: Bool
    /// Date and time the chapter's download completed (nil if not downloaded)
    var downloadedAt: Date?
    /// Date and time the user finished or marked the chapter as read
    var readAt: Date?
    /// Reading progress between 0.0 (unread) and 1.0 (completed)
    var progress: Double
    /// Total recorded reading time in seconds for this chapter
    var readingSeconds: Int
    /// Last page read (0 = not started); restored when the chapter is opened
    var lastPageRead: Int
    /// Scanlation group that published this chapter (optional, provided by the plugin)
    var scanlator: String? = nil
}
