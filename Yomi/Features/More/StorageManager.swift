import Foundation
import Kingfisher

// MARK: - StorageBreakdown

struct StorageBreakdown {
    var downloads: Int64 = 0
    var covers: Int64 = 0
    var extensions: Int64 = 0
    var database: Int64 = 0
    var imageCache: Int64 = 0
    var webCache: Int64 = 0
    var other: Int64 = 0

    var total: Int64 {
        downloads + covers + extensions + database + imageCache + webCache + other
    }
}

// MARK: - StorageManager

/// Pure FileManager/Kingfisher I/O for the Storage composition view. Safe to call from
/// Task.detached — no MainActor state read anywhere here.
enum StorageManager {

    private nonisolated static func documentsURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Recursive byte size of a directory. Missing directories return 0.
    nonisolated static func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    nonisolated static func fileSize(_ url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

    nonisolated static func computeBreakdown() async -> StorageBreakdown {
        let docs = documentsURL()

        let downloads  = directorySize(docs.appendingPathComponent("Downloads"))
        let covers     = directorySize(docs.appendingPathComponent("Covers"))
        let extensions = directorySize(docs.appendingPathComponent("Extensions"))

        var database = fileSize(docs.appendingPathComponent("yomi.db"))
        database += fileSize(docs.appendingPathComponent("yomi.db-wal"))
        database += fileSize(docs.appendingPathComponent("yomi.db-shm"))

        let imageCache = (try? await ImageCache.default.diskStorageSize).map(Int64.init) ?? 0
        let webCache   = Int64(URLCache.shared.currentDiskUsage)

        let documentsTotal = directorySize(docs)
        let other = max(0, documentsTotal - downloads - covers - extensions - database)

        return StorageBreakdown(
            downloads: downloads, covers: covers, extensions: extensions,
            database: database, imageCache: imageCache, webCache: webCache, other: other
        )
    }
}
