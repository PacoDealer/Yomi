import Foundation
import Unrar
import PLzmaSDK

// MARK: - ComicArchive
//
// S156: one way to read a comic archive, whichever container it is. ZIP (CBZ) goes through Yomi's own
// `ZipArchive`; RAR (CBR) through RARLAB's UnRAR source via the Unrar.swift package (RESEARCH §27 — the only
// free decoder that reads every RAR4 and RAR5 file). 7z (CB7, S175) through PLzmaSDK = Igor Pavlov's LZMA SDK (MIT +
// public domain): Copy, LZMA, LZMA2, PPMd and AES checked against py7zr-made archives; BZip2/Deflate inside a 7z are
// NOT in this build (rare — 7-Zip writes LZMA2). The kind is told by the file's first bytes, not its name: a ".cbr"
// that is really a ZIP, and the reverse, are both common.

nonisolated struct ComicArchive: Sendable {
    enum ArchiveError: LocalizedError {
        case encrypted, unreadable(String), unsupported7z
        var errorDescription: String? {
            switch self {
            case .encrypted: return "This archive is password-protected — Yomi can't open it."
            case .unreadable(let name): return "\"\(name)\" couldn't be read from the archive. The file may be damaged."
            case .unsupported7z:
                return "This 7z archive couldn't be read. It may be damaged, or packed with a method Yomi doesn't read "
                    + "(BZip2 or Deflate) — re-packing it with 7-Zip's default (LZMA2) or as a CBZ works."
            }
        }
    }

    private enum Backing: Sendable {
        case zip(ZipArchive)
        case rar(Archive, [Entry])
        case sevenZip(Decoder, [Item])
    }

    private let backing: Backing

    /// Paths of the files inside (no folders), in archive order.
    let paths: [String]

    init(url: URL) throws {
        if Self.is7z(url) {
            let decoder: Decoder
            do {
                decoder = try Decoder(stream: try InStream(path: try Path(url.path)), fileType: .sevenZ)
                guard try decoder.open() else { throw ArchiveError.unsupported7z }
            } catch let error as ArchiveError {
                throw error
            } catch {
                // With encrypted file names even the list can't be read without the password.
                throw Self.is7zHeaderEncrypted(url) ? ArchiveError.encrypted : ArchiveError.unsupported7z
            }
            let all = try decoder.items()
            var items: [Item] = []
            var names: [String] = []
            for i in 0..<all.count {
                let item = try all.item(at: i)
                guard !item.isDir else { continue }
                if item.encrypted { throw ArchiveError.encrypted }
                items.append(item)
                names.append(try item.path().description.replacingOccurrences(of: "\\", with: "/"))
            }
            backing = .sevenZip(decoder, items)
            paths = names
        } else if Self.isRAR(url) {
            let archive = try Archive(fileURL: url)
            if archive.isHeaderEncrypted { throw ArchiveError.encrypted }
            let entries = try archive.entries().filter { !$0.directory }
            backing = .rar(archive, entries)
            // RAR on Windows writes "\" between folders.
            paths = entries.map { $0.fileName.replacingOccurrences(of: "\\", with: "/") }
        } else {
            let zip = try ZipArchive(url: url)
            backing = .zip(zip)
            paths = zip.files.map(\.path)
        }
    }

    func contents(of path: String) throws -> Data {
        guard let index = paths.firstIndex(of: path) else { throw ArchiveError.unreadable(path) }
        switch backing {
        case .zip(let zip):
            return try zip.contents(of: zip.files[index])
        case .rar(let archive, let entries):
            if entries[index].encrypted { throw ArchiveError.encrypted }
            do { return try archive.extract(entries[index]) }
            catch { throw ArchiveError.unreadable((path as NSString).lastPathComponent) }
        case .sevenZip(let decoder, let items):
            do {
                let out = try OutStream()
                let pairs = try ItemOutStreamArray()
                try pairs.add(item: items[index], stream: out)
                guard try decoder.extract(itemsToStreams: pairs) else { throw ArchiveError.unsupported7z }
                return try out.copyContent()
            } catch {
                throw ArchiveError.unsupported7z
            }
        }
    }

    /// Writes several files at once. A "solid" 7z (the default) is one compressed stream, so reading page N alone
    /// decodes everything before it — page by page that is quadratic. One `extract` call decodes the stream once.
    /// ZIP and RAR just read each file.
    func write(_ files: [(path: String, to: URL)]) throws {
        guard case .sevenZip(let decoder, let items) = backing else {
            for file in files { try contents(of: file.path).write(to: file.to) }
            return
        }
        do {
            let pairs = try ItemOutStreamArray(capacity: Size(files.count))
            for file in files {
                guard let index = paths.firstIndex(of: file.path) else { throw ArchiveError.unreadable(file.path) }
                try pairs.add(item: items[index], stream: try OutStream(path: try Path(file.to.path)))
            }
            guard try decoder.extract(itemsToStreams: pairs) else { throw ArchiveError.unsupported7z }
        } catch let error as ArchiveError {
            throw error
        } catch {
            throw ArchiveError.unsupported7z
        }
    }

    /// "7z\u{BC}\u{AF}\u{27}\u{1C}".
    static func is7z(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 6)) == Data([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C])
    }

    /// A 7z with encrypted file names keeps its header packed with AES (coder id 06 F1 07 01). The 32-byte start
    /// header says where that header is: offset (bytes 12–19) and size (20–27), counted from byte 32.
    static func is7zHeaderEncrypted(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let start = try? handle.read(upToCount: 32), start.count == 32 else { return false }
        func uint64(_ at: Int) -> UInt64 { (0..<8).reduce(UInt64(0)) { $0 | UInt64(start[at + $1]) << (8 * UInt64($1)) } }
        let offset = uint64(12), size = uint64(20)
        guard size > 0, size < 1 << 20, (try? handle.seek(toOffset: 32 + offset)) != nil,
              let header = try? handle.read(upToCount: Int(size)), header.first == 0x17 else { return false }
        let aes: [UInt8] = [0x06, 0xF1, 0x07, 0x01]
        return header.indices.dropLast(3).contains { i in (0..<4).allSatisfy { header[i + $0] == aes[$0] } }
    }

    /// "Rar!\u{1A}\u{07}" opens both RAR4 and RAR5 files.
    static func isRAR(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 6)) == Data([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07])
    }
}
