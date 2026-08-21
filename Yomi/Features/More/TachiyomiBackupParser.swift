import Foundation

// MARK: - TachiyomiBackupParser
//
// Parses Tachiyomi / Mihon .tachibk files (gzip-compressed protobuf3).
// Zero external dependencies:
//   • gzip decompression via libz (always linked on iOS) using inflateInit2_
//   • protobuf decoding via hand-written varint reader matching the known schema
//
// Proto schema (from https://gist.github.com/intrnl/f7ced6833ca6a1d353dd8742c7917db5):
//   Backup         → backupManga[], backupCategories[], backupSources[]
//   BackupManga    → source(1), url(2), title(3), artist(4), author(5), description(6),
//                    genre(7), status(8), thumbnailUrl(9), chapters(16), favorite(100)
//   BackupChapter  → url(1), name(2), scanlator(3), read(4), lastPageRead(6),
//                    chapterNumber(9, fixed32/float), sourceOrder(10)

enum TachiyomiBackupParser {

    // MARK: - Result

    struct ImportResult {
        var mangas: [Manga] = []
        var chapters: [Chapter] = []
        var mappedCount: Int = 0
        var unmappedCount: Int = 0

        var totalCount: Int { mappedCount + unmappedCount }
    }

    // MARK: - Known Tachiyomi source IDs → Yomi plugin IDs
    // Tachiyomi source IDs are int64 hashes embedded in each extension.
    // Unmapped sources are imported with a "tachiyomi_{id}" placeholder sourceId
    // so users get their full library even for sources Yomi doesn't have plugins for.

    private static let sourceMap: [UInt64: String] = [
        2499283573021220255: "mangadex",        // MangaDex (English)
        1998944621         : "mangadex",        // MangaDex (alternate / older ID)
    ]

    // MARK: - Entry point

    static func parse(_ data: Data) throws -> ImportResult {
        let decompressed = try gunzip(data)
        return try decodeBackup(decompressed)
    }

    // MARK: - Gzip decompression (libz, windowBits=47 = auto gzip/zlib detection)

    private static func gunzip(_ data: Data) throws -> Data {
        guard data.count >= 2, data[0] == 0x1f, data[1] == 0x8b else {
            throw BackupParseError.notGzip
        }
        var stream = z_stream()
        // 47 = MAX_WBITS(15) + 32 — tells zlib to auto-detect gzip or zlib wrapper
        let initResult = inflateInit2_(&stream, 47, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initResult == Z_OK else { throw BackupParseError.zlibError(initResult) }
        defer { inflateEnd(&stream) }

        var output = Data(capacity: max(data.count * 4, 65_536))
        var status: Int32 = Z_OK
        let chunkSize = 65_536
        var chunk = [UInt8](repeating: 0, count: chunkSize)

        data.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
            stream.next_in  = UnsafeMutablePointer(mutating: src.baseAddress!.assumingMemoryBound(to: UInt8.self))
            stream.avail_in = uInt(data.count)
            while status == Z_OK, stream.avail_in > 0 {
                chunk.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) in
                    stream.next_out  = dst.baseAddress!.assumingMemoryBound(to: UInt8.self)
                    stream.avail_out = uInt(chunkSize)
                    status = inflate(&stream, Z_NO_FLUSH)
                    let produced = chunkSize - Int(stream.avail_out)
                    if produced > 0 {
                        output.append(dst.baseAddress!.assumingMemoryBound(to: UInt8.self), count: produced)
                    }
                }
            }
        }

        guard status == Z_STREAM_END || status == Z_OK else {
            throw BackupParseError.zlibError(status)
        }
        return output
    }

    // MARK: - Backup-level decoder (Backup message, field 1 = repeated BackupManga)

    private static func decodeBackup(_ data: Data) throws -> ImportResult {
        var result = ImportResult()
        let reader = ProtoReader(data)

        while reader.hasNext {
            guard let (field, wire) = try? reader.readTag() else { break }
            if field == 1, wire == 2 {
                if let mangaData = try? reader.readLengthDelimited(),
                   let (manga, chapters) = parseManga(mangaData) {
                    result.mangas.append(manga)
                    result.chapters.append(contentsOf: chapters)
                    // parseManga sets manga.sourceId to sourceMap[tachiyomiSourceId] when a mapping
                    // exists, falling back to "tachiyomi_<id>" only when it doesn't — so the prefix
                    // itself is the mapped/unmapped signal, not a re-derivation through sourceMap.
                    if manga.sourceId.hasPrefix("tachiyomi_") {
                        result.unmappedCount += 1
                    } else {
                        result.mappedCount += 1
                    }
                }
            } else {
                try? reader.skip(wireType: wire)
            }
        }

        return result
    }

    // MARK: - BackupManga decoder

    private static func parseManga(_ data: Data) -> (Manga, [Chapter])? {
        var tachiyomiSourceId: UInt64 = 0
        var url = ""
        var title = ""
        var artist: String?
        var author: String?
        var description: String?
        var genres: [String] = []
        var statusCode: Int32 = 0
        var thumbnailUrl: String?
        var favorite = false
        var backupChapters: [(url: String, name: String, read: Bool, lastPage: Int,
                              chapterNumber: Double, scanlator: String?)] = []

        let reader = ProtoReader(data)
        while reader.hasNext {
            guard let (field, wire) = try? reader.readTag() else { break }
            switch field {
            case 1:   tachiyomiSourceId = (try? reader.readVarint64()) ?? 0
            case 2:   url               = (try? reader.readString())   ?? ""
            case 3:   title             = (try? reader.readString())   ?? ""
            case 4:   artist            = try? reader.readString()
            case 5:   author            = try? reader.readString()
            case 6:   description       = try? reader.readString()
            case 7:   if let g = try? reader.readString() { genres.append(g) }
            case 8:   statusCode        = Int32(truncatingIfNeeded: (try? reader.readVarint64()) ?? 0)
            case 9:   thumbnailUrl      = try? reader.readString()
            case 16:
                if wire == 2, let chData = try? reader.readLengthDelimited(),
                   let ch = parseChapter(chData) {
                    backupChapters.append(ch)
                }
            case 100: favorite = ((try? reader.readVarint64()) ?? 0) != 0
            default:  try? reader.skip(wireType: wire)
            }
        }

        guard !url.isEmpty, !title.isEmpty else { return nil }

        let yomiSourceId: String = sourceMap[tachiyomiSourceId]
            ?? "tachiyomi_\(tachiyomiSourceId)"

        let mangaId = "\(yomiSourceId)_\(url.components(separatedBy: "/").last ?? url.prefix(40).description)"

        let manga = Manga(
            id:             mangaId,
            path:           url,
            sourceId:       yomiSourceId,
            title:          title,
            coverURL:       thumbnailUrl.flatMap { URL(string: $0) },
            summary:        description,
            author:         author,
            artist:         artist,
            status:         publicationStatus(statusCode),
            genres:         genres,
            inLibrary:      favorite,
            isLocal:        false,
            lastReadAt:     nil,
            lastUpdatedAt:  nil,
            readingSeconds: 0
        )

        let chapters: [Chapter] = backupChapters.enumerated().compactMap { idx, ch in
            let chPath = ch.url.isEmpty ? url + "/ch\(idx)" : ch.url
            let chId   = "\(mangaId)_\(chPath.components(separatedBy: "/").last ?? "\(idx)")"
            return Chapter(
                id:             chId,
                mangaId:        mangaId,
                path:           chPath,
                name:           ch.name,
                chapterNumber:  ch.chapterNumber >= 0 ? ch.chapterNumber : nil,
                isRead:         ch.read,
                isDownloaded:   false,
                downloadedAt:   nil,
                readAt:         ch.read ? Date(timeIntervalSince1970: 0) : nil,
                progress:       ch.read ? 1.0 : 0,
                readingSeconds: 0,
                lastPageRead:   ch.lastPage,
                scanlator:      ch.scanlator
            )
        }

        return (manga, chapters)
    }

    // MARK: - BackupChapter decoder

    private static func parseChapter(
        _ data: Data
    ) -> (url: String, name: String, read: Bool, lastPage: Int,
          chapterNumber: Double, scanlator: String?)? {
        var url            = ""
        var name           = ""
        var scanlator: String?
        var read           = false
        var lastPage       = 0
        var chapterNumber: Double = -1

        let reader = ProtoReader(data)
        while reader.hasNext {
            guard let (field, wire) = try? reader.readTag() else { break }
            switch field {
            case 1:  url           = (try? reader.readString()) ?? ""
            case 2:  name          = (try? reader.readString()) ?? ""
            case 3:  scanlator     = try? reader.readString()
            case 4:  read          = ((try? reader.readVarint64()) ?? 0) != 0
            case 6:  lastPage      = Int((try? reader.readVarint64()) ?? 0)
            case 9 where wire == 5:
                if let bits = try? reader.readFixed32() {
                    chapterNumber = Double(Float(bitPattern: bits))
                }
            default: try? reader.skip(wireType: wire)
            }
        }

        guard !name.isEmpty else { return nil }
        return (url: url, name: name, read: read, lastPage: lastPage,
                chapterNumber: chapterNumber, scanlator: scanlator)
    }

    // MARK: - Status mapping (Tachiyomi int → Yomi MangaStatus)

    private static func publicationStatus(_ code: Int32) -> MangaStatus {
        switch code {
        case 1: return .ongoing
        case 2: return .completed
        case 4: return .hiatus
        case 5: return .cancelled
        default: return .unknown
        }
    }
}

// MARK: - Error

enum BackupParseError: LocalizedError {
    case notGzip
    case zlibError(Int32)
    case truncated

    var errorDescription: String? {
        switch self {
        case .notGzip:             return "File is not a gzip archive (.tachibk)"
        case .zlibError(let c):   return "Decompression error (zlib code \(c))"
        case .truncated:           return "Backup file is incomplete"
        }
    }
}

// MARK: - ProtoReader (protobuf3 binary format)

private final class ProtoReader {
    private let data: Data
    private var pos: Int

    init(_ data: Data) {
        self.data = data
        self.pos  = data.startIndex
    }

    var hasNext: Bool { pos < data.endIndex }

    // Returns (fieldNumber, wireType)
    func readTag() throws -> (Int, Int) {
        let raw = try readVarint64()
        return (Int(raw >> 3), Int(raw & 0x7))
    }

    func readVarint64() throws -> UInt64 {
        var result: UInt64 = 0
        var shift = 0
        while pos < data.endIndex {
            let byte = UInt64(data[pos]); pos += 1
            result |= (byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            guard shift < 64 else { throw BackupParseError.truncated }
        }
        throw BackupParseError.truncated
    }

    func readString() throws -> String {
        let raw = try readLengthDelimited()
        return String(data: raw, encoding: .utf8) ?? ""
    }

    func readLengthDelimited() throws -> Data {
        let length = Int(try readVarint64())
        guard pos + length <= data.endIndex else { throw BackupParseError.truncated }
        let slice = data[pos ..< pos + length]
        pos += length
        return slice
    }

    func readFixed32() throws -> UInt32 {
        guard pos + 4 <= data.endIndex else { throw BackupParseError.truncated }
        let v = data[pos ..< pos + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        pos += 4
        return v
    }

    func skip(wireType: Int) throws {
        switch wireType {
        case 0: _ = try readVarint64()
        case 1:
            guard pos + 8 <= data.endIndex else { throw BackupParseError.truncated }
            pos += 8
        case 2: _ = try readLengthDelimited()
        case 5:
            guard pos + 4 <= data.endIndex else { throw BackupParseError.truncated }
            pos += 4
        default: throw BackupParseError.truncated
        }
    }
}
