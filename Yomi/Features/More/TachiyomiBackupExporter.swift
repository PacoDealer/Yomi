import Foundation

// MARK: - TachiyomiBackupExporter
//
// Produces a Tachiyomi / Mihon-compatible .tachibk file (gzip-compressed protobuf3) from Yomi's
// library — the reverse direction of TachiyomiBackupParser, for migrating *out* to Tachiyomi/Mihon
// or a fork (Yomi's own export/import round-trip already covers Yomi → Yomi via BackupManager's
// JSON format; this is purely for interop). Same field layout as the parser's doc comment:
//   BackupManga    → source(1), url(2), title(3), artist(4), author(5), description(6),
//                    genre(7), status(8), thumbnailUrl(9), chapters(16), favorite(100)
//   BackupChapter  → url(1), name(2), scanlator(3), read(4), lastPageRead(6),
//                    chapterNumber(9, fixed32/float), sourceOrder(10)
//
// Scope: metadata + read-state only, matching what the parser actually reads back. Yomi sources
// have no real Tachiyomi source ID (only MangaDex round-trips via the existing sourceMap) — every
// other manga exports with source(1) = 0, which Tachiyomi's own restore flow already treats as a
// normal "no matching source installed" case rather than a failure, so the library/read-history
// still comes across even where the source itself doesn't.

enum TachiyomiBackupExporter {

    // MARK: - Entry point

    static func export(mangas: [Manga], chaptersByMangaId: [String: [Chapter]]) -> Data {
        var body = Data()
        for manga in mangas {
            let chapters = chaptersByMangaId[manga.id] ?? []
            let mangaMessage = encodeManga(manga, chapters: chapters)
            body.appendTag(field: 1, wireType: 2)
            body.appendVarint(UInt64(mangaMessage.count))
            body.append(mangaMessage)
        }
        return gzip(body)
    }

    // MARK: - Reverse of TachiyomiBackupParser.sourceMap (Yomi plugin ID → Tachiyomi source ID)

    private static let reverseSourceMap: [String: UInt64] = [
        "mangadex": 2499283573021220255,
    ]

    // MARK: - BackupManga encoder

    private static func encodeManga(_ manga: Manga, chapters: [Chapter]) -> Data {
        var out = Data()

        out.appendField(1, varint: reverseSourceMap[manga.sourceId] ?? 0)
        out.appendField(2, string: manga.path)
        out.appendField(3, string: manga.title)
        if let artist = manga.artist { out.appendField(4, string: artist) }
        if let author = manga.author { out.appendField(5, string: author) }
        if let summary = manga.summary { out.appendField(6, string: summary) }
        for genre in manga.genres { out.appendField(7, string: genre) }
        out.appendField(8, varint: UInt64(statusCode(manga.status)))
        if let cover = manga.coverURL { out.appendField(9, string: cover.absoluteString) }

        for (index, chapter) in chapters.enumerated() {
            let chapterMessage = encodeChapter(chapter, sourceOrder: chapters.count - index)
            out.appendTag(field: 16, wireType: 2)
            out.appendVarint(UInt64(chapterMessage.count))
            out.append(chapterMessage)
        }

        out.appendField(100, varint: manga.inLibrary ? 1 : 0)
        return out
    }

    // MARK: - BackupChapter encoder

    private static func encodeChapter(_ chapter: Chapter, sourceOrder: Int) -> Data {
        var out = Data()
        out.appendField(1, string: chapter.path)
        out.appendField(2, string: chapter.name)
        if let scanlator = chapter.scanlator { out.appendField(3, string: scanlator) }
        out.appendField(4, varint: chapter.isRead ? 1 : 0)
        out.appendField(6, varint: UInt64(chapter.lastPageRead))
        if let number = chapter.chapterNumber {
            out.appendTag(field: 9, wireType: 5)
            out.appendFixed32(Float(number).bitPattern)
        }
        out.appendField(10, varint: UInt64(sourceOrder))
        return out
    }

    // MARK: - Status mapping (Yomi MangaStatus → Tachiyomi int), inverse of parser's publicationStatus

    private static func statusCode(_ status: MangaStatus) -> Int32 {
        switch status {
        case .ongoing:   return 1
        case .completed: return 2
        case .hiatus:    return 4
        case .cancelled: return 5
        case .unknown:   return 0
        }
    }

    // MARK: - Gzip compression (libz, windowBits=31 = raw gzip encoding)

    private static func gzip(_ data: Data) -> Data {
        var stream = z_stream()
        // 31 = MAX_WBITS(15) + 16 — tells zlib to wrap the deflate stream in a gzip header/trailer
        let initResult = deflateInit2_(
            &stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 31, 8, Z_DEFAULT_STRATEGY,
            ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)
        )
        guard initResult == Z_OK else { return data }
        defer { deflateEnd(&stream) }

        var output = Data(capacity: max(data.count / 2, 1024))
        let chunkSize = 65_536
        var chunk = [UInt8](repeating: 0, count: chunkSize)

        data.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
            stream.next_in  = UnsafeMutablePointer(mutating: src.baseAddress?.assumingMemoryBound(to: UInt8.self))
            stream.avail_in = uInt(data.count)
            var status: Int32 = Z_OK
            repeat {
                chunk.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) in
                    stream.next_out  = dst.baseAddress!.assumingMemoryBound(to: UInt8.self)
                    stream.avail_out = uInt(chunkSize)
                    status = deflate(&stream, Z_FINISH)
                    let produced = chunkSize - Int(stream.avail_out)
                    if produced > 0 {
                        output.append(dst.baseAddress!.assumingMemoryBound(to: UInt8.self), count: produced)
                    }
                }
            } while status != Z_STREAM_END
        }
        return output
    }
}

// MARK: - Protobuf writer helpers (varint / length-delimited / fixed32)

private extension Data {
    mutating func appendVarint(_ value: UInt64) {
        var v = value
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            append(byte)
        } while v != 0
    }

    mutating func appendTag(field: Int, wireType: Int) {
        appendVarint(UInt64((field << 3) | wireType))
    }

    mutating func appendFixed32(_ bits: UInt32) {
        let le = bits.littleEndian
        append(UInt8(le & 0xFF))
        append(UInt8((le >> 8) & 0xFF))
        append(UInt8((le >> 16) & 0xFF))
        append(UInt8((le >> 24) & 0xFF))
    }

    mutating func appendField(_ field: Int, varint value: UInt64) {
        guard value != 0 else { return }
        appendTag(field: field, wireType: 0)
        appendVarint(value)
    }

    mutating func appendField(_ field: Int, string value: String) {
        guard !value.isEmpty else { return }
        let bytes = Data(value.utf8)
        appendTag(field: field, wireType: 2)
        appendVarint(UInt64(bytes.count))
        append(bytes)
    }
}
