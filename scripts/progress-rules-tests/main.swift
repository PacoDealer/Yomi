import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String, line: Int = #line) {
    if !ok { failures += 1; print("FAIL line \(line): \(what)") }
}

// TrackerProgress.count
check(TrackerProgress.count(finished: 3, highestRead: 40) == 40, "re-reading ch 3 keeps 40")
check(TrackerProgress.count(finished: 41, highestRead: 40) == 41, "new chapter raises")
check(TrackerProgress.count(finished: nil, highestRead: 40) == nil, "unnumbered sends nothing")
check(TrackerProgress.count(finished: 0, highestRead: 5) == nil, "chapter 0 (prologue) sends nothing")
check(TrackerProgress.count(finished: 12.5, highestRead: nil) == 12, "12.5 counts as 12")
check(TrackerProgress.count(finished: 1, highestRead: .nan) == 1, "NaN highest ignored")

// Chapter.mergedForRestore
func ch(read: Bool = false, dl: Bool = false, page: Int = 0, prog: Double = 0, secs: Int = 0,
        readAt: Date? = nil, bm: Bool = false) -> Chapter {
    var c = Chapter(id: "c", mangaId: "m", path: "/c", name: "Ch 1", chapterNumber: 1, isRead: read,
                    isDownloaded: dl, downloadedAt: dl ? Date(timeIntervalSince1970: 5) : nil, readAt: readAt,
                    progress: prog, readingSeconds: secs, lastPageRead: page)
    c.isBookmarked = bm
    return c
}
let t1 = Date(timeIntervalSince1970: 100), t2 = Date(timeIntervalSince1970: 200)
var m = Chapter.mergedForRestore(backup: ch(), local: ch(dl: true))
check(m.isDownloaded && m.downloadedAt != nil, "download state kept")
m = Chapter.mergedForRestore(backup: ch(dl: true), local: ch())
check(!m.isDownloaded, "backup can't claim a download")
m = Chapter.mergedForRestore(backup: ch(read: false), local: ch(read: true, readAt: t2))
check(m.isRead && m.readAt == t2, "local read wins")
m = Chapter.mergedForRestore(backup: ch(read: true, readAt: t2), local: ch(readAt: t1))
check(m.isRead && m.readAt == t2, "backup read + later date")
m = Chapter.mergedForRestore(backup: ch(page: 3, prog: 0.2), local: ch(page: 10, prog: 0.6))
check(m.lastPageRead == 10 && m.progress == 0.6, "furthest local position")
m = Chapter.mergedForRestore(backup: ch(page: 12, prog: 0.8, secs: 50), local: ch(page: 10, prog: 0.6, secs: 70))
check(m.lastPageRead == 12 && m.progress == 0.8 && m.readingSeconds == 70, "furthest backup position, max seconds")
m = Chapter.mergedForRestore(backup: ch(bm: false), local: ch(bm: true))
check(m.isBookmarked, "bookmark ORs")

// Manga.mergedForRestore
let older = Date(timeIntervalSince1970: 10), newer = Date(timeIntervalSince1970: 20)
var bk = Manga(id: "m", path: "/m", sourceId: "s", title: "T", coverURL: nil, summary: nil, author: nil, artist: nil,
               status: .unknown, genres: [], inLibrary: false, isLocal: false, lastReadAt: older, lastUpdatedAt: nil,
               readingSeconds: 100)
var lc = bk
lc.inLibrary = true; lc.lastReadAt = newer; lc.readingSeconds = 500; lc.notes = "mine"; lc.readingStatus = .reading
bk.notes = "old"
let mm = Manga.mergedForRestore(backup: bk, local: lc)
check(mm.inLibrary && mm.lastReadAt == newer && mm.readingSeconds == 500 && mm.notes == "mine" && mm.readingStatus == .reading,
      "manga merge keeps the phone's newer state")
var lc2 = bk; lc2.notes = nil
check(Manga.mergedForRestore(backup: bk, local: lc2).notes == "old", "backup fills missing notes")

// ChapterStateConflict (S192, #242)
let at = { (t: Double) in Date(timeIntervalSince1970: t) }
check(ChapterStateConflict.remoteWins(localChangedAt: nil, remoteChangedAt: at(5)), "never changed here: remote wins")
check(ChapterStateConflict.remoteWins(localChangedAt: 100, remoteChangedAt: at(200)), "newer remote wins")
check(!ChapterStateConflict.remoteWins(localChangedAt: 300, remoteChangedAt: at(200)), "offline read newer than iCloud copy is kept")
check(ChapterStateConflict.remoteWins(localChangedAt: 200, remoteChangedAt: at(200)), "tie = own change echoed back")
check(!ChapterStateConflict.remoteWins(localChangedAt: 1, remoteChangedAt: at(0)), "sender didn't know (0) never beats a known change")
check(ChapterStateConflict.remoteWins(localChangedAt: nil, remoteChangedAt: at(0)), "…but fills a chapter never changed here")
check(ChapterStateConflict.remoteTime(field: at(50), savedByServer: at(90)) == at(50), "field beats server save time")
check(ChapterStateConflict.remoteTime(field: nil, savedByServer: at(90)) == at(90), "old build: server save time")
check(ChapterStateConflict.remoteTime(field: nil, savedByServer: nil) == nil, "no time at all")

if failures == 0 { print("23 checks passed") } else { print("\(failures) failed"); exit(1) }
