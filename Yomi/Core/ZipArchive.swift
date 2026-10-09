import Foundation
import Compression

// MARK: - ZipArchive
//
// S148: a minimal read-only ZIP reader for local CBZ/ZIP chapters and EPUB books. Both formats only use "stored"
// (0) and "deflate" (8) entries; deflate is raw RFC 1951, which Apple's Compression framework decodes as
// `COMPRESSION_ZLIB`. The file is memory-mapped, so a 200 MB CBZ isn't read into RAM. ZIP64 (archives > 4 GB or
// > 65,535 entries) and encrypted entries are refused with a clear error rather than misread.

nonisolated struct ZipArchive: Sendable {
    struct Entry: Sendable {
        let path: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
        let isEncrypted: Bool
        var isDirectory: Bool { path.hasSuffix("/") }
    }

    enum ZipError: LocalizedError {
        case notAZip, zip64, encrypted(String), unsupportedMethod(UInt16), corrupt(String)

        var errorDescription: String? {
            switch self {
            case .notAZip: return "This file isn't a ZIP archive."
            case .zip64: return "This archive is too large (ZIP64) — Yomi can't open it yet."
            case .encrypted(let name): return "\"\(name)\" is password-protected."
            case .unsupportedMethod(let m): return "This archive uses an unsupported compression method (\(m))."
            case .corrupt(let what): return "The archive is damaged (\(what))."
            }
        }
    }

    let url: URL
    let entries: [Entry]
    private let data: Data

    init(url: URL) throws {
        self.url = url
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        self.data = data
        self.entries = try Self.readCentralDirectory(data)
    }

    /// Entries that are files (not folders), in archive order.
    var files: [Entry] { entries.filter { !$0.isDirectory } }

    func entry(_ path: String) -> Entry? {
        entries.first { $0.path == path } ?? entries.first { $0.path.lowercased() == path.lowercased() }
    }

    func contents(of entry: Entry) throws -> Data {
        if entry.isEncrypted { throw ZipError.encrypted(entry.path) }
        let o = entry.localHeaderOffset
        guard o + 30 <= data.count, u32(data, o) == 0x04034b50 else { throw ZipError.corrupt("local header") }
        let start = o + 30 + Int(u16(data, o + 26)) + Int(u16(data, o + 28))
        guard start + entry.compressedSize <= data.count else { throw ZipError.corrupt("entry size") }
        let raw = data.subdata(in: start..<(start + entry.compressedSize))
        switch entry.method {
        case 0:
            return raw
        case 8:
            guard entry.uncompressedSize > 0 else { return Data() }
            var out = Data(count: entry.uncompressedSize)
            let written = out.withUnsafeMutableBytes { dst in
                raw.withUnsafeBytes { src in
                    compression_decode_buffer(
                        dst.bindMemory(to: UInt8.self).baseAddress!, entry.uncompressedSize,
                        src.bindMemory(to: UInt8.self).baseAddress!, raw.count,
                        nil, COMPRESSION_ZLIB)
                }
            }
            guard written == entry.uncompressedSize else { throw ZipError.corrupt("deflate") }
            return out
        default:
            throw ZipError.unsupportedMethod(entry.method)
        }
    }

    func contents(of path: String) throws -> Data? {
        guard let e = entry(path) else { return nil }
        return try contents(of: e)
    }

    // MARK: Parsing

    private static func readCentralDirectory(_ data: Data) throws -> [Entry] {
        // End of central directory: 22 bytes + up to 65,535 bytes of comment, at the very end.
        guard data.count >= 22 else { throw ZipError.notAZip }
        var eocd = -1
        var i = data.count - 22
        let floor = max(0, data.count - 22 - 65_535)
        while i >= floor {
            if u32(data, i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAZip }
        let count = Int(u16(data, eocd + 10))
        let size = Int(u32(data, eocd + 12))
        let offset = Int(u32(data, eocd + 16))
        if count == 0xFFFF || size == 0xFFFF_FFFF || offset == 0xFFFF_FFFF { throw ZipError.zip64 }
        guard offset + size <= data.count else { throw ZipError.corrupt("central directory") }

        var entries: [Entry] = []
        entries.reserveCapacity(count)
        var p = offset
        for _ in 0..<count {
            guard p + 46 <= data.count, u32(data, p) == 0x02014b50 else { throw ZipError.corrupt("directory entry") }
            let flags = u16(data, p + 8)
            let method = u16(data, p + 10)
            let csize = u32(data, p + 20)
            let usize = u32(data, p + 24)
            let nameLen = Int(u16(data, p + 28))
            let extraLen = Int(u16(data, p + 30))
            let commentLen = Int(u16(data, p + 32))
            let local = u32(data, p + 42)
            if csize == 0xFFFF_FFFF || usize == 0xFFFF_FFFF || local == 0xFFFF_FFFF { throw ZipError.zip64 }
            guard p + 46 + nameLen <= data.count else { throw ZipError.corrupt("entry name") }
            let nameData = data.subdata(in: (p + 46)..<(p + 46 + nameLen))
            // Bit 11 = UTF-8 names; older tools wrote CP437, where Latin-1 is the closest Foundation decoding.
            let name = (flags & 0x0800 != 0 ? String(data: nameData, encoding: .utf8) : nil)
                ?? String(data: nameData, encoding: .utf8)
                ?? String(data: nameData, encoding: .isoLatin1) ?? ""
            entries.append(Entry(path: name, method: method, compressedSize: Int(csize),
                                 uncompressedSize: Int(usize), localHeaderOffset: Int(local),
                                 isEncrypted: flags & 1 != 0))
            p += 46 + nameLen + extraLen + commentLen
        }
        return entries
    }
}

nonisolated private func u16(_ d: Data, _ o: Int) -> UInt16 {
    d.withUnsafeBytes { UInt16(littleEndian: $0.loadUnaligned(fromByteOffset: o, as: UInt16.self)) }
}

nonisolated private func u32(_ d: Data, _ o: Int) -> UInt32 {
    d.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: o, as: UInt32.self)) }
}
