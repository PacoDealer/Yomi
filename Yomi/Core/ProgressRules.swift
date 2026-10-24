import Foundation

// Pure progress rules (S190, from the S189 audit). Foundation-only so scripts/progress-rules-tests can compile them.

/// What chapter count the readers send to MAL/AniList/… when a chapter is finished (audit #2).
/// The tracker field is "chapters read", so it must never go DOWN: re-reading chapter 3 of a series
/// read up to 40 used to set the tracker back to 3, and a chapter with no number sent 0.
enum TrackerProgress {
    /// Count to send, or nil to send nothing. `finished` is the number of the chapter just finished;
    /// `highestRead` the highest numbered chapter already marked read.
    nonisolated static func count(finished: Double?, highestRead: Double?) -> Int? {
        guard let finished, finished.isFinite, finished >= 1 else { return nil }
        let highest = highestRead.flatMap { $0.isFinite ? $0 : nil } ?? 0
        return Int(max(finished, highest).rounded(.down))
    }
}

extension Chapter {
    /// A backed-up chapter merged into the one already on this phone (audit #1; Mihon's restore rule): read if
    /// either says so, the furthest position and the latest read date win, and download state is always the
    /// phone's own — the files live here, never in the backup. A whole-row save used to clear `isDownloaded`.
    nonisolated static func mergedForRestore(backup: Chapter, local: Chapter) -> Chapter {
        var c = backup
        c.isDownloaded = local.isDownloaded
        c.downloadedAt = local.downloadedAt
        c.isRead = backup.isRead || local.isRead
        c.readAt = [backup.readAt, local.readAt].compactMap { $0 }.max()
        if local.lastPageRead > backup.lastPageRead || local.progress > backup.progress {
            c.lastPageRead = local.lastPageRead
            c.progress = local.progress
        }
        c.readingSeconds = max(backup.readingSeconds, local.readingSeconds)
        c.isBookmarked = backup.isBookmarked || local.isBookmarked
        return c
    }
}

/// A backed-up title merged into the one already on this phone (S190): restoring an older backup used to put back
/// its reading time, last-read date, notes, status and custom cover over the phone's newer ones. The backup adds
/// what the phone lacks; it never takes away.
extension Manga {
    nonisolated static func mergedForRestore(backup: Manga, local: Manga) -> Manga {
        var m = backup
        m.inLibrary = backup.inLibrary || local.inLibrary
        m.readingSeconds = max(backup.readingSeconds, local.readingSeconds)
        m.lastReadAt = [backup.lastReadAt, local.lastReadAt].compactMap { $0 }.max()
        m.lastUpdatedAt = [backup.lastUpdatedAt, local.lastUpdatedAt].compactMap { $0 }.max()
        if local.readingStatus != .none { m.readingStatus = local.readingStatus }
        if let notes = local.notes, !notes.isEmpty { m.notes = notes }
        if local.customCoverPath != nil { m.customCoverPath = local.customCoverPath }
        if local.trackingTitle != nil { m.trackingTitle = local.trackingTitle }
        return m
    }
}

extension Novel {
    nonisolated static func mergedForRestore(backup: Novel, local: Novel) -> Novel {
        var n = backup
        n.inLibrary = backup.inLibrary || local.inLibrary
        n.readingSeconds = max(backup.readingSeconds, local.readingSeconds)
        n.lastReadAt = [backup.lastReadAt, local.lastReadAt].compactMap { $0 }.max()
        n.lastUpdatedAt = [backup.lastUpdatedAt, local.lastUpdatedAt].compactMap { $0 }.max()
        if local.readingStatus != .none { n.readingStatus = local.readingStatus }
        if let notes = local.notes, !notes.isEmpty { n.notes = notes }
        if local.customCoverPath != nil { n.customCoverPath = local.customCoverPath }
        return n
    }
}
