import Foundation

enum MangaStatus: String, Codable {
    case unknown    = "unknown"
    case ongoing    = "ongoing"
    case completed  = "completed"
    case hiatus     = "hiatus"
    case cancelled  = "cancelled"
}

enum ReadingStatus: String, Codable, CaseIterable, Identifiable {
    case none       = "none"
    case planToRead = "planToRead"
    case reading    = "reading"
    case onHold     = "onHold"
    case completed  = "completed"
    case dropped    = "dropped"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none:       return "Not set"
        case .planToRead: return "Plan to read"
        case .reading:    return "Reading"
        case .onHold:     return "On hold"
        case .completed:  return "Completed"
        case .dropped:    return "Dropped"
        }
    }

    var systemImage: String {
        switch self {
        case .none:       return "circle.dotted"
        case .planToRead: return "bookmark"
        case .reading:    return "book.open"
        case .onHold:     return "pause.circle"
        case .completed:  return "checkmark.circle"
        case .dropped:    return "xmark.circle"
        }
    }
}

struct Manga: Identifiable, Codable {
    let id: String
    let path: String
    let sourceId: String
    var title: String
    var coverURL: URL?
    var summary: String?
    var author: String?
    var artist: String?
    var status: MangaStatus
    var genres: [String]
    var inLibrary: Bool
    var isLocal: Bool
    var lastReadAt: Date?
    var lastUpdatedAt: Date?
    var readingSeconds: Int
    var readingStatus: ReadingStatus = .none
    /// Relative path under Documents (e.g. "Covers/<id>.jpg"). Absolute paths are legacy.
    var customCoverPath: String? = nil
    var notes: String? = nil

    /// Returns the absolute filesystem path for the custom cover, handling both
    /// legacy absolute paths (stored before S78 fix) and new relative paths.
    nonisolated var resolvedCustomCoverPath: String? {
        guard let stored = customCoverPath else { return nil }
        if stored.hasPrefix("/") { return stored }
        return FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(stored).path
    }
}
