import Foundation
import CryptoKit

// MARK: - LocalLibrary
//
// S148 part C (RESEARCH §25.10 #6): read the user's own files. Mihon's local-source layout (mihon.app/docs/guides/
// local-source): one folder per series; inside it each chapter is a CBZ/ZIP archive or a folder of images, plus an
// optional cover.jpg. Martin's picks: an EPUB is a NOVEL (its table of contents = chapters, read in the novel reader),
// files come in two ways — Import (copied into Yomi's own `Documents/Local`) and a folder the user links once in the
// Files app (security-scoped bookmark; Yomi's Documents stays hidden because it holds the database) — and CBR/RAR is
// skipped for now (KNOWN_ISSUES).
//
// Titles are ordinary `manga`/`novel` rows with sourceId "local"; chapter paths say where the file is:
//   manga chapter  local://<root>/<relative path>              (archive or image folder)
//   novel chapter  local-epub://<root>/<relative path>#<href>  (spine document inside the EPUB)
// A scan never deletes: a file that vanished (an iCloud folder offline) keeps its chapters and read state.

nonisolated enum LocalLibrary {
    static let sourceId = "local"
    static let mangaScheme = "local://"
    static let epubScheme = "local-epub://"

    static func isLocalSourceId(_ id: String) -> Bool { id == sourceId }
    static func isLocalPath(_ path: String) -> Bool { path.hasPrefix(mangaScheme) || path.hasPrefix(epubScheme) }

    enum Root: String, CaseIterable, Sendable {
        /// `Documents/Local` — what Import copies into.
        case app
        /// The folder the user linked in the Files app.
        case folder
    }

    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "avif", "heic", "heif", "bmp"]
    static let archiveExtensions: Set<String> = ["cbz", "zip"]
    static let unsupportedArchiveExtensions: Set<String> = ["cbr", "rar", "cb7", "7z"]

    // MARK: - Roots

    static var appRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Local", isDirectory: true)
    }

    static let bookmarkKey = "localFolderBookmark"
    nonisolated(unsafe) private static var linkedURL: URL?
    private static let lock = NSLock()

    /// The linked folder, with security-scoped access held for the rest of the run (pages are read lazily).
    static func linkedFolder() -> URL? {
        lock.lock(); defer { lock.unlock() }
        if let linkedURL { return linkedURL }
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        if stale, let fresh = try? url.bookmarkData() { UserDefaults.standard.set(fresh, forKey: bookmarkKey) }
        linkedURL = url
        return url
    }

    /// `url` comes from the folder picker (already security-scoped).
    static func linkFolder(_ url: URL) throws {
        _ = url.startAccessingSecurityScopedResource()
        let data = try url.bookmarkData()
        lock.lock()
        linkedURL?.stopAccessingSecurityScopedResource()
        linkedURL = url
        lock.unlock()
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }

    /// Forgets the folder. Its titles stay in the database (read state kept) — they just can't open until relinked.
    static func unlinkFolder() {
        lock.lock()
        linkedURL?.stopAccessingSecurityScopedResource()
        linkedURL = nil
        lock.unlock()
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    static func url(of root: Root) -> URL? {
        switch root {
        case .app: return appRoot
        case .folder: return linkedFolder()
        }
    }

    /// File URL for `<root>/<relative>` from a stored path's body.
    static func resolve(_ body: String) -> URL? {
        guard let slash = body.firstIndex(of: "/"), let root = Root(rawValue: String(body[..<slash])),
              let base = url(of: root) else { return nil }
        let rel = String(body[body.index(after: slash)...])
        return rel.isEmpty ? base : base.appendingPathComponent(rel)
    }

    // MARK: - Ids

    static func key(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Import

    struct ImportResult: Sendable {
        var imported: [String] = []
        var skipped: [String] = []
    }

    /// Copies picked files/folders into `Documents/Local`: a folder as it is (a series folder, or a folder of
    /// series), a loose CBZ/ZIP into a folder named after its series, an EPUB as it is. Nothing is overwritten.
    static func importItems(_ urls: [URL]) -> ImportResult {
        var result = ImportResult()
        let fm = FileManager.default
        try? fm.createDirectory(at: appRoot, withIntermediateDirectories: true)
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let name = url.lastPathComponent
            let ext = url.pathExtension.lowercased()
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { result.skipped.append(name); continue }
            let destination: URL
            if isDir.boolValue {
                destination = appRoot.appendingPathComponent(name, isDirectory: true)
            } else if archiveExtensions.contains(ext) {
                let series = seriesName(forArchive: url)
                let dir = appRoot.appendingPathComponent(series, isDirectory: true)
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
                destination = dir.appendingPathComponent(name)
            } else if ext == "epub" {
                destination = appRoot.appendingPathComponent(name)
            } else if unsupportedArchiveExtensions.contains(ext) {
                result.skipped.append("\(name) — CBR/RAR isn't supported yet; convert it to CBZ")
                continue
            } else {
                result.skipped.append("\(name) — not a CBZ, ZIP, EPUB or folder")
                continue
            }
            if fm.fileExists(atPath: destination.path) {
                if isDir.boolValue { mergeCopy(from: url, into: destination) ; result.imported.append(name) }
                else { result.skipped.append("\(name) — already imported") }
                continue
            }
            do {
                try fm.copyItem(at: url, to: destination)
                result.imported.append(name)
            } catch {
                result.skipped.append("\(name) — \(error.localizedDescription)")
            }
        }
        return result
    }

    /// Adds the files of `source` that `destination` doesn't have yet (re-importing a series folder with new chapters).
    private static func mergeCopy(from source: URL, into destination: URL) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for item in items {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            if !fm.fileExists(atPath: target.path) { try? fm.copyItem(at: item, to: target) }
            else if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                mergeCopy(from: item, into: target)
            }
        }
    }

    // MARK: - Scan

    struct ScanResult: Sendable {
        var newTitles = 0
        var newChapters = 0
        var skipped: [String] = []
    }

    private struct SeriesDraft {
        var root: Root
        var name: String
        var chapters: [(rel: String, name: String, comicInfo: ComicInfo?)] = []
        var coverFile: URL?
    }

    /// Walks both roots and adds what's new to the database (new titles go straight into the Library).
    static func scan() -> ScanResult {
        var result = ScanResult()
        for root in Root.allCases {
            guard let base = url(of: root) else { continue }
            var series: [String: SeriesDraft] = [:]
            var epubs: [String] = []
            scanContainer(base, rel: "", root: root, depth: 0, into: &series, epubs: &epubs, skipped: &result.skipped)
            for draft in series.values {
                let added = saveManga(draft)
                result.newTitles += added.newTitle ? 1 : 0
                result.newChapters += added.newChapters
            }
            for rel in epubs {
                do {
                    let added = try saveEpub(root: root, rel: rel)
                    result.newTitles += added.newTitle ? 1 : 0
                    result.newChapters += added.newChapters
                } catch {
                    result.skipped.append("\(rel) — \(error.localizedDescription)")
                }
            }
        }
        return result
    }

    /// A folder of series (the root, or e.g. a copied Mihon `local` folder): its sub-folders are series — or
    /// containers again, up to 3 levels — and loose archives are grouped into series by name.
    private static func scanContainer(_ dir: URL, rel: String, root: Root, depth: Int,
                                      into series: inout [String: SeriesDraft], epubs: inout [String],
                                      skipped: inout [String]) {
        let items = ((try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [])
            .sorted(by: naturalOrder)
        for item in items {
            let name = item.lastPathComponent
            let itemRel = rel.isEmpty ? name : "\(rel)/\(name)"
            let ext = item.pathExtension.lowercased()
            if isDirectory(item) {
                if depth < 3, isContainer(item) {
                    scanContainer(item, rel: itemRel, root: root, depth: depth + 1, into: &series, epubs: &epubs,
                                  skipped: &skipped)
                } else {
                    scanSeriesFolder(item, rel: itemRel, root: root, into: &series, epubs: &epubs, skipped: &skipped)
                }
            } else if archiveExtensions.contains(ext) {
                let info = ComicInfo.read(archive: item)
                let seriesTitle = info?.series ?? seriesName(fromFileName: item.deletingPathExtension().lastPathComponent)
                series[seriesTitle, default: SeriesDraft(root: root, name: seriesTitle)]
                    .chapters.append((itemRel, item.deletingPathExtension().lastPathComponent, info))
            } else if ext == "epub" {
                epubs.append(itemRel)
            } else if unsupportedArchiveExtensions.contains(ext) {
                skipped.append("\(name) — CBR/RAR isn't supported yet")
            }
        }
    }

    /// True when the folder's sub-folders are series (they hold archives or chapter folders) rather than chapters.
    private static func isContainer(_ dir: URL) -> Bool {
        let fm = FileManager.default
        let subdirs = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                                                    options: [.skipsHiddenFiles])) ?? []).filter(isDirectory)
        return subdirs.contains { sub in
            let children = (try? fm.contentsOfDirectory(at: sub, includingPropertiesForKeys: [.isDirectoryKey],
                                                       options: [.skipsHiddenFiles])) ?? []
            return children.contains { child in
                archiveExtensions.contains(child.pathExtension.lowercased()) || child.pathExtension.lowercased() == "epub"
                    || (isDirectory(child) && containsImages(child))
            }
        }
    }

    private static func scanSeriesFolder(_ dir: URL, rel: String, root: Root, into series: inout [String: SeriesDraft],
                                         epubs: inout [String], skipped: inout [String]) {
        let fm = FileManager.default
        let name = dir.lastPathComponent
        let children = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                                                    options: [.skipsHiddenFiles])) ?? []).sorted(by: naturalOrder)
        var draft = series[name] ?? SeriesDraft(root: root, name: name)
        var looseImages = false
        for child in children {
            let ext = child.pathExtension.lowercased()
            let rel = "\(rel)/\(child.lastPathComponent)"
            if isDirectory(child) {
                if containsImages(child) { draft.chapters.append((rel, child.lastPathComponent, nil)) }
            } else if archiveExtensions.contains(ext) {
                draft.chapters.append((rel, child.deletingPathExtension().lastPathComponent, ComicInfo.read(archive: child)))
            } else if ext == "epub" {
                epubs.append(rel)
            } else if imageExtensions.contains(ext) {
                if child.deletingPathExtension().lastPathComponent.lowercased() == "cover" { draft.coverFile = child }
                else { looseImages = true }
            } else if unsupportedArchiveExtensions.contains(ext) {
                skipped.append("\(child.lastPathComponent) — CBR/RAR isn't supported yet")
            }
        }
        // A series folder holding images directly (no chapter folders) is one chapter.
        if looseImages && draft.chapters.isEmpty { draft.chapters.append((rel, name, nil)) }
        if !draft.chapters.isEmpty { series[name] = draft }
    }

    private static func saveManga(_ draft: SeriesDraft) -> (newTitle: Bool, newChapters: Int) {
        let mangaId = "local_" + key("\(draft.root.rawValue)/\(draft.name)")
        let existing = try? MangaQueries.fetchOne(id: mangaId)
        let firstInfo = draft.chapters.lazy.compactMap(\.comicInfo).first
        var chapters: [Chapter] = draft.chapters.map { ch in
            Chapter(
                id: "\(mangaId)_\(key(ch.rel))",
                mangaId: mangaId,
                path: "\(mangaScheme)\(draft.root.rawValue)/\(ch.rel)",
                name: ch.comicInfo?.title.map { t in "\(ch.name) — \(t)" } ?? ch.name,
                chapterNumber: ch.comicInfo?.number
                    ?? ChapterRecognition.number(mangaTitle: draft.name, chapterName: ch.name, sourceNumber: -1),
                isRead: false, isDownloaded: false, downloadedAt: nil, readAt: nil,
                progress: 0, readingSeconds: 0, lastPageRead: 0, scanlator: nil
            )
        }
        // Yomi assumes ascending order everywhere; unnumbered chapters keep file order at the end.
        chapters.sort { a, b in
            switch (a.chapterNumber, b.chapterNumber) {
            case let (x?, y?) where x != y: return x < y
            case (.some, .none): return true
            case (.none, .some): return false
            default: return a.path.localizedStandardCompare(b.path) == .orderedAscending
            }
        }
        let known = Set(((try? ChapterQueries.fetchAll(mangaId: mangaId)) ?? []).map(\.id))
        let fresh = chapters.filter { !known.contains($0.id) }

        if existing == nil {
            let manga = Manga(
                id: mangaId, path: "\(mangaScheme)\(draft.root.rawValue)/\(draft.name)", sourceId: sourceId,
                title: draft.name, coverURL: nil, summary: firstInfo?.summary, author: firstInfo?.writer,
                artist: nil, status: .unknown, genres: firstInfo?.genres ?? [], inLibrary: true, isLocal: true,
                lastReadAt: nil, lastUpdatedAt: Date(), readingSeconds: 0,
                customCoverPath: saveCover(mangaId: mangaId, draft: draft, firstChapter: chapters.first)
            )
            try? ChapterQueries.insertMangaAndChapters(manga: manga, chapters: chapters)
            return (true, chapters.count)
        }
        if !fresh.isEmpty {
            try? ChapterQueries.insertAllIgnoringConflicts(fresh)
            try? MangaQueries.touchLastUpdated(mangaId: mangaId)
        }
        return (false, fresh.count)
    }

    /// cover.jpg from the series folder, else the first page of the first chapter — saved under `LocalCovers/`
    /// and stored RELATIVE (absolute container paths change on reinstall, S78).
    private static func saveCover(mangaId: String, draft: SeriesDraft, firstChapter: Chapter?) -> String? {
        var data: Data?
        var ext = "jpg"
        if let file = draft.coverFile {
            data = try? Data(contentsOf: file)
            ext = file.pathExtension.lowercased()
        } else if let chapter = firstChapter, let first = firstPage(chapterPath: chapter.path) {
            data = first.data
            ext = first.ext
        }
        return writeCover(data, id: mangaId, ext: ext)
    }

    /// Just the first page's bytes — a scan of 40 series must not unpack 40 whole chapters.
    private static func firstPage(chapterPath: String) -> (data: Data, ext: String)? {
        guard let source = resolve(String(chapterPath.dropFirst(mangaScheme.count))) else { return nil }
        if isDirectory(source) {
            guard let url = (try? pageURLs(chapterPath: chapterPath))?.first, let data = try? Data(contentsOf: url)
            else { return nil }
            return (data, url.pathExtension.lowercased())
        }
        guard let zip = try? ZipArchive(url: source),
              let entry = zip.files
                .filter({ !$0.path.hasPrefix("__MACOSX") && imageExtensions.contains(($0.path as NSString).pathExtension.lowercased()) })
                .min(by: { $0.path.localizedStandardCompare($1.path) == .orderedAscending }),
              let data = try? zip.contents(of: entry) else { return nil }
        return (data, (entry.path as NSString).pathExtension.lowercased())
    }

    private static func writeCover(_ data: Data?, id: String, ext: String) -> String? {
        guard let data, !data.isEmpty else { return nil }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let rel = "LocalCovers/\(id).\(ext.isEmpty || ext == "dat" ? "jpg" : ext)"
        let url = docs.appendingPathComponent(rel)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? data.write(to: url, options: .atomic)) != nil ? rel : nil
    }

    // MARK: - Manga pages

    /// Image files of one chapter, in reading order. An archive is unpacked once into Caches (kept until its
    /// size or date changes); an image folder is read in place.
    static func pageURLs(chapterPath: String) throws -> [URL] {
        guard chapterPath.hasPrefix(mangaScheme), let source = resolve(String(chapterPath.dropFirst(mangaScheme.count)))
        else { throw LocalError.notFound }
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { throw LocalError.notFound }
        if isDirectory(source) {
            let files = (try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil,
                                                     options: [.skipsHiddenFiles])) ?? []
            return files.filter { imageExtensions.contains($0.pathExtension.lowercased())
                && $0.deletingPathExtension().lastPathComponent.lowercased() != "cover" }
                .sorted(by: naturalOrder)
        }

        let attrs = try? fm.attributesOfItem(atPath: source.path)
        let stamp = "\((attrs?[.size] as? Int) ?? 0)-\(((attrs?[.modificationDate] as? Date) ?? .distantPast).timeIntervalSince1970)"
        let cache = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalPages/\(key(chapterPath))", isDirectory: true)
        let marker = cache.appendingPathComponent(".stamp")
        if (try? String(contentsOf: marker, encoding: .utf8)) == stamp,
           let cached = try? fm.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]),
           !cached.isEmpty {
            return cached.sorted(by: naturalOrder)
        }
        try? fm.removeItem(at: cache)
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        let zip = try ZipArchive(url: source)
        // Mihon: folders inside an archive are ignored — every image is a page, ordered by its path.
        let images = zip.files
            .filter { !$0.path.hasPrefix("__MACOSX") && !($0.path as NSString).lastPathComponent.hasPrefix(".")
                && imageExtensions.contains(($0.path as NSString).pathExtension.lowercased()) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        var out: [URL] = []
        for (i, entry) in images.enumerated() {
            let ext = (entry.path as NSString).pathExtension.lowercased()
            let file = cache.appendingPathComponent(String(format: "%04d.%@", i + 1, ext))
            try zip.contents(of: entry).write(to: file)
            out.append(file)
        }
        try stamp.write(to: marker, atomically: true, encoding: .utf8)
        return out
    }

    enum LocalError: LocalizedError {
        case notFound, notAnEpub(String)
        var errorDescription: String? {
            switch self {
            case .notFound: return "The file isn't there any more. If it was in a linked folder, link it again in Browse → Local."
            case .notAnEpub(let why): return "This EPUB couldn't be read (\(why))."
            }
        }
    }

    // MARK: - EPUB → novel

    private static func saveEpub(root: Root, rel: String) throws -> (newTitle: Bool, newChapters: Int) {
        guard let base = url(of: root) else { throw LocalError.notFound }
        let book = try EpubBook(url: base.appendingPathComponent(rel))
        let novelId = "local_" + key("\(root.rawValue)/\(rel)")
        let chapters: [NovelChapter] = book.chapters.enumerated().map { i, ch in
            NovelChapter(id: "\(novelId)_\(key(ch.href))", novelId: novelId,
                         path: "\(epubScheme)\(root.rawValue)/\(rel)#\(ch.href)", name: ch.title,
                         chapterNumber: Double(i + 1), isRead: false, readAt: nil, releaseTime: nil,
                         readingSeconds: 0)
        }
        if (try? NovelQueries.fetchOne(id: novelId)) != nil {
            let known = Set(((try? NovelQueries.fetchChapters(novelId: novelId)) ?? []).map(\.id))
            let fresh = chapters.filter { !known.contains($0.id) }
            if !fresh.isEmpty { try NovelQueries.insertAllIgnoringConflicts(fresh) }
            return (false, fresh.count)
        }
        let coverExt = book.coverPath.map { ($0 as NSString).pathExtension } ?? "jpg"
        let novel = Novel(
            id: novelId, path: "\(epubScheme)\(root.rawValue)/\(rel)", sourceId: sourceId,
            title: book.title ?? ((rel as NSString).lastPathComponent as NSString).deletingPathExtension,
            coverURL: nil, summary: book.summary, author: book.author, status: "", genres: book.subjects,
            inLibrary: true, lastReadAt: nil, lastUpdatedAt: Date(), readingSeconds: 0, readingStatus: .none,
            notes: nil, customCoverPath: writeCover(book.coverData(), id: novelId, ext: coverExt)
        )
        try NovelQueries.upsert(novel)
        try NovelQueries.insertAllIgnoringConflicts(chapters)
        return (true, chapters.count)
    }

    /// The chapter's HTML for the novel reader: the spine document's body, scripts/styles removed, images inlined.
    static func epubChapterHTML(path: String) -> String? {
        guard path.hasPrefix(epubScheme), let hash = path.lastIndex(of: "#") else { return nil }
        let body = String(path[path.index(path.startIndex, offsetBy: epubScheme.count)..<hash])
        let href = String(path[path.index(after: hash)...])
        guard let url = resolve(body), let book = try? EpubBook(url: url) else { return nil }
        return book.html(forHref: href)
    }

    // MARK: - Helpers

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private static func containsImages(_ dir: URL) -> Bool {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .contains { imageExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
    }

    static func naturalOrder(_ a: URL, _ b: URL) -> Bool {
        a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
    }

    /// Series name for a loose archive: ComicInfo's <Series>, else the file name minus its chapter part
    /// ("Solo Leveling - Chapter 12 [Group]" → "Solo Leveling").
    static func seriesName(forArchive url: URL) -> String {
        ComicInfo.read(archive: url)?.series ?? seriesName(fromFileName: url.deletingPathExtension().lastPathComponent)
    }

    static func seriesName(fromFileName stem: String) -> String {
        let pattern = #"(?i)[\s._\-–]*(\b(ch(apter)?|ep(isode)?|vol(ume)?|v|c)\.?\s*|#)?\d+(\.\d+)?\b.*$"#
        let cleaned = stem.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? stem : cleaned
    }
}

// MARK: - NovelContent

/// One place every novel screen gets a chapter's HTML from (reader, preload, read-aloud): local EPUB → downloaded
/// copy → the plugin. Runs off the main actor (a plugin call blocks its thread).
nonisolated enum NovelContent {
    static func html(novelId: String, path: String, bridge: JSBridge?) -> String {
        if path.hasPrefix(LocalLibrary.epubScheme) { return LocalLibrary.epubChapterHTML(path: path) ?? "" }
        return NovelDownloadStore.content(novelId: novelId, chapterPath: path) ?? bridge?.parseChapter(path: path) ?? ""
    }
}

// MARK: - ComicInfo

/// The fields Yomi uses from a CBZ's `ComicInfo.xml` (the ComicRack schema Mihon/Komga/Kavita read).
nonisolated struct ComicInfo: Sendable {
    var series: String?
    var number: Double?
    var title: String?
    var summary: String?
    var writer: String?
    var genres: [String] = []

    static func read(archive url: URL) -> ComicInfo? {
        guard let zip = try? ZipArchive(url: url),
              let entry = zip.files.first(where: { ($0.path as NSString).lastPathComponent.lowercased() == "comicinfo.xml" }),
              let data = try? zip.contents(of: entry),
              let xml = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        func tag(_ name: String) -> String? {
            guard let r = xml.range(of: "<\(name)>([\\s\\S]*?)</\(name)>", options: [.regularExpression, .caseInsensitive])
            else { return nil }
            let inner = xml[r].replacingOccurrences(of: "</?\(name)>", with: "", options: [.regularExpression, .caseInsensitive])
            let text = XMLText.decode(inner).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        var info = ComicInfo()
        info.series = tag("Series")
        info.number = tag("Number").flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
        info.title = tag("Title")
        info.summary = tag("Summary")
        info.writer = tag("Writer")
        info.genres = tag("Genre")?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        return info
    }
}

nonisolated enum XMLText {
    static func decode(_ s: String) -> String {
        var out = s.replacingOccurrences(of: "<!\\[CDATA\\[([\\s\\S]*?)\\]\\]>", with: "$1", options: .regularExpression)
        for (entity, char) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'"), ("&amp;", "&")] {
            out = out.replacingOccurrences(of: entity, with: char)
        }
        return out
    }
}
