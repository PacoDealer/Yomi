import Foundation
import GRDB

// S195: download bookkeeping had no test (S189 audit, "Tests"). Covers the page files on disk (`DownloadedPages`:
// what counts as a page, what a resumed download fetches again, reading order) and the chapter row's flag
// (`DownloadQueries`, and the INSERT OR IGNORE refresh rule that must never clear it).

var failures = 0, checks = 0
func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    if !ok { failures += 1; print("FAIL \(name) \(detail())") }
}

let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent("yomi-download-tests-\(UUID().uuidString)")
defer { try? fm.removeItem(at: root) }
var dirCount = 0
func freshDir(_ files: [String] = []) -> URL {
    dirCount += 1
    let dir = root.appendingPathComponent("ch\(dirCount)")
    try! fm.createDirectory(at: dir, withIntermediateDirectories: true)
    for f in files { try! Data(f.utf8).write(to: dir.appendingPathComponent(f)) }
    return dir
}
func names(_ dir: URL) -> Set<String> {
    Set(((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []))
}
func base(_ urls: [URL]) -> [String] { urls.map(\.lastPathComponent) }

// MARK: File names

check("fileName whole page", DownloadedPages.fileName(page: 7, part: 0, of: 1) == "7.dat")
check("fileName part", DownloadedPages.fileName(page: 7, part: 2, of: 4) == "7-2of4.dat")

// MARK: scan

do {
    let dir = freshDir(["0.dat", "1.dat", "2-1of2.dat", "2-0of2.dat", "notes.txt", "x.dat", "3-1.dat", "4-2of2.dat"])
    let s = DownloadedPages.scan(dir)
    check("scan: whole pages", base(s.pages[0] ?? []) == ["0.dat"] && base(s.pages[1] ?? []) == ["1.dat"])
    check("scan: complete part set in part order", base(s.pages[2] ?? []) == ["2-0of2.dat", "2-1of2.dat"],
          "\(base(s.pages[2] ?? []))")
    check("scan: junk names and other files ignored", s.pages.count == 3 && s.incomplete.isEmpty,
          "\(s.pages.keys.sorted()) incomplete \(base(s.incomplete))")
}
do {
    let dir = freshDir(["0-0of3.dat", "0-2of3.dat"])
    let s = DownloadedPages.scan(dir)
    check("scan: part set missing a part is not a page", s.pages[0] == nil)
    check("scan: …and both its files are incomplete", Set(base(s.incomplete)) == ["0-0of3.dat", "0-2of3.dat"])
}
do {
    let dir = freshDir(["5.dat", "5-0of2.dat", "5-1of2.dat"])
    let s = DownloadedPages.scan(dir)
    check("scan: whole page wins over parts", base(s.pages[5] ?? []) == ["5.dat"])
    check("scan: …parts are incomplete", Set(base(s.incomplete)) == ["5-0of2.dat", "5-1of2.dat"])
}
do {
    // Both mirror cases: the folder listing order isn't fixed, and the first part seen sets the expected count.
    let dir = freshDir(["1-0of2.dat", "1-1of3.dat", "2-0of3.dat", "2-1of2.dat"])
    let s = DownloadedPages.scan(dir)
    check("scan: parts with different counts never make a page", s.pages[1] == nil && s.pages[2] == nil,
          "\(s.pages.mapValues(base))")
    check("scan: …and are all cleared", s.incomplete.count == 4, "\(base(s.incomplete))")
}
do {
    // A complete split next to a leftover part of an older, different split: the complete one is the page.
    let dir = freshDir(["3-0of2.dat", "3-1of2.dat", "3-2of3.dat", "4-0of3.dat", "4-0of2.dat", "4-1of2.dat"])
    let s = DownloadedPages.scan(dir)
    check("scan: complete set wins over an older split's leftover",
          base(s.pages[3] ?? []) == ["3-0of2.dat", "3-1of2.dat"] && base(s.pages[4] ?? []) == ["4-0of2.dat", "4-1of2.dat"],
          "\(s.pages.mapValues(base))")
    check("scan: …leftovers cleared", Set(base(s.incomplete)) == ["3-2of3.dat", "4-0of3.dat"], "\(base(s.incomplete))")
}
do {
    // Two complete splits of one page: which is current can't be told, so neither counts and the page is refetched.
    let dir = freshDir(["6-0of2.dat", "6-1of2.dat", "6-0of3.dat", "6-1of3.dat", "6-2of3.dat"])
    let s = DownloadedPages.scan(dir)
    check("scan: two complete splits → no page, all cleared", s.pages[6] == nil && s.incomplete.count == 5,
          "\(s.pages.mapValues(base)) \(base(s.incomplete))")
}
check("scan: missing folder = nothing", DownloadedPages.scan(root.appendingPathComponent("nope")).pages.isEmpty)

// MARK: Reading order

check("init: empty folder = not downloaded", DownloadedPages(dir: freshDir()) == nil)
check("init: no folder = not downloaded", DownloadedPages(dir: root.appendingPathComponent("nope")) == nil)
do {
    let dir = freshDir(["10.dat", "2.dat", "1-1of2.dat", "1-0of2.dat", "0.dat"])
    let p = DownloadedPages(dir: dir)
    check("init: numeric page order, parts in place", base(p?.urls ?? []) ==
          ["0.dat", "1-0of2.dat", "1-1of2.dat", "2.dat", "10.dat"], "\(base(p?.urls ?? []))")
    check("init: each image knows its source page", p?.sourcePages == [0, 1, 1, 2, 10], "\(p?.sourcePages ?? [])")
}

// MARK: Resume (what a retry or a resumed pause fetches)

do {
    let dir = freshDir()
    check("resume: empty folder → every page", DownloadedPages.prepareResume(dir, pageCount: 4) == [0, 1, 2, 3])
    check("resume: zero pages → nothing", DownloadedPages.prepareResume(dir, pageCount: 0) == [])
}
do {
    let dir = freshDir(["0.dat", "2-0of2.dat", "2-1of2.dat", "3-0of2.dat"])
    let missing = DownloadedPages.prepareResume(dir, pageCount: 5)
    check("resume: only missing pages, half split refetched", missing == [1, 3, 4], "\(missing)")
    check("resume: half split removed, whole pages kept", names(dir) == ["0.dat", "2-0of2.dat", "2-1of2.dat"],
          "\(names(dir))")
}
do {
    // The source's page list got shorter: old pages 3, 4 (one split) must go or the reader shows them at the end.
    let dir = freshDir(["0.dat", "1.dat", "2.dat", "3.dat", "4-0of2.dat", "4-1of2.dat", "cover.jpg"])
    let missing = DownloadedPages.prepareResume(dir, pageCount: 3)
    check("resume: shorter list → nothing missing", missing == [], "\(missing)")
    check("resume: pages past the end deleted (whole + parts), other files kept",
          names(dir) == ["0.dat", "1.dat", "2.dat", "cover.jpg"], "\(names(dir))")
    check("resume: reader then sees exactly the new count", DownloadedPages(dir: dir)?.urls.count == 3)
}
do {
    let dir = freshDir(["0.dat", "1.dat"])
    check("resume: complete chapter → nothing to fetch, files untouched",
          DownloadedPages.prepareResume(dir, pageCount: 2) == [] && names(dir) == ["0.dat", "1.dat"])
}
check("resume: no folder yet → every page",
      DownloadedPages.prepareResume(root.appendingPathComponent("nope"), pageCount: 2) == [0, 1])

// MARK: Tall-page split rows (what the part files cover)

do {
    let rows = TallPageSplitter.partRows(width: 900, height: 16000)
    let contiguous = zip(rows, rows.dropFirst()).allSatisfy { $0.upperBound == $1.lowerBound }
    check("split: 900x16000 → parts ≤ 4096 covering every row",
          rows.count == 4 && rows.first?.lowerBound == 0 && rows.last?.upperBound == 16000 && contiguous
            && rows.allSatisfy { $0.count <= TallPageSplitter.maxPartHeight }, "\(rows)")
    check("split: ordinary page not split", TallPageSplitter.partRows(width: 800, height: 1200).count == 1)
    check("split: wide-but-tall under 4096 not split", TallPageSplitter.partRows(width: 1000, height: 4000).count == 1)
}

// MARK: The downloaded flag in the database

func chapter(_ id: String, manga: String = "m1", number: Double?, downloaded: Bool = false) -> Chapter {
    Chapter(id: id, mangaId: manga, path: "/\(id)", name: "Chapter \(number.map { "\($0)" } ?? "?")",
            chapterNumber: number, isRead: false, isDownloaded: downloaded, downloadedAt: nil, readAt: nil,
            progress: 0, readingSeconds: 0, lastPageRead: 0)
}

do {
    appDatabase = try DatabaseQueue()
    try DatabaseManager.makeMigrator().migrate(appDatabase)
    try appDatabase.write { db in
        for m in ["m1", "m2"] {
            try db.execute(sql: "INSERT INTO manga (id, path, sourceId, title, inLibrary) VALUES (?, ?, 'asura', ?, 1)",
                           arguments: [m, "/\(m)", "Title \(m)"])
        }
        for c in [chapter("c3", number: 3), chapter("c1", number: 1), chapter("cx", number: nil),
                  chapter("c2", number: 2), chapter("o1", manga: "m2", number: 1)] {
            try c.insert(db)
        }
    }
    func row(_ id: String) throws -> Chapter? { try appDatabase.read { try Chapter.fetchOne($0, key: id) } }

    let before = Date()
    for id in ["c3", "cx", "c1", "o1"] { try DownloadQueries.markDownloaded(chapterId: id) }
    let c1 = try row("c1")
    check("db: markDownloaded sets the flag and the time",
          c1?.isDownloaded == true && (c1?.downloadedAt.map { $0 >= before.addingTimeInterval(-1) } ?? false))
    check("db: other chapters untouched", try row("c2")?.isDownloaded == false)

    let ordered = try DownloadQueries.fetchDownloaded(mangaId: "m1").map(\.id)
    check("db: downloaded list = this title only, by number, unnumbered last", ordered == ["c1", "c3", "cx"], "\(ordered)")
    check("db: all downloaded across titles", Set(try DownloadQueries.fetchAllDownloaded().map(\.id)) == ["c1", "c3", "cx", "o1"])

    // A source refresh returns every chapter with isDownloaded = false; the INSERT OR IGNORE rule
    // (`ChapterQueries.insertAllIgnoringConflicts`) must keep the saved flag and time.
    try appDatabase.write { db in
        for c in [chapter("c1", number: 1), chapter("c3", number: 3), chapter("c4", number: 4)] {
            try c.insert(db, onConflict: .ignore)
        }
    }
    let refreshed = try row("c1")
    check("db: refresh insert keeps the flag", refreshed?.isDownloaded == true)
    check("db: refresh insert keeps the time", refreshed?.downloadedAt != nil && refreshed?.downloadedAt == c1?.downloadedAt)
    check("db: refresh adds the new chapter not downloaded", try row("c4")?.isDownloaded == false)

    try DownloadQueries.markNotDownloaded(chapterId: "c3")
    let c3 = try row("c3")
    check("db: markNotDownloaded clears flag and time", c3?.isDownloaded == false && c3?.downloadedAt == nil)
    check("db: …and the list drops it", try DownloadQueries.fetchDownloaded(mangaId: "m1").map(\.id) == ["c1", "cx"])
    try DownloadQueries.markDownloaded(chapterId: "missing")
    check("db: marking an unknown id adds nothing", try appDatabase.read { try Chapter.fetchCount($0) } == 6)
} catch { check("db tests ran", false, "\(error)") }

print(failures == 0 ? "OK \(checks) checks" : "\(failures) of \(checks) checks FAILED")
exit(failures == 0 ? 0 : 1)
