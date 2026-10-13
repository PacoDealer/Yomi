import Foundation
import Unrar

// MARK: - ComicArchive
//
// S156: one way to read a comic archive, whichever container it is. ZIP (CBZ) goes through Yomi's own
// `ZipArchive`; RAR (CBR) through RARLAB's UnRAR source via the Unrar.swift package (RESEARCH §27 — the only
// free decoder that reads every RAR4 and RAR5 file). The kind is told by the file's first bytes, not its name:
// a ".cbr" that is really a ZIP, and the reverse, are both common.

nonisolated struct ComicArchive: Sendable {
    enum ArchiveError: LocalizedError {
        case encrypted, unreadable(String)
        var errorDescription: String? {
            switch self {
            case .encrypted: return "This archive is password-protected — Yomi can't open it."
            case .unreadable(let name): return "\"\(name)\" couldn't be read from the archive. The file may be damaged."
            }
        }
    }

    private enum Backing: Sendable {
        case zip(ZipArchive)
        case rar(Archive, [Entry])
    }

    private let backing: Backing

    /// Paths of the files inside (no folders), in archive order.
    let paths: [String]

    init(url: URL) throws {
        if Self.isRAR(url) {
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
        }
    }

    /// "Rar!\u{1A}\u{07}" opens both RAR4 and RAR5 files.
    static func isRAR(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 6)) == Data([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07])
    }
}
