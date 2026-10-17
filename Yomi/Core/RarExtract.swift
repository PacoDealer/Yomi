import Foundation
import Cunrar

// MARK: - RarExtract
//
// S179: unpacks many RAR entries in ONE walk through the archive. Unrar.swift's `extract(_:)` reopens the archive and
// skips to the entry for every call — in a "solid" RAR (one compressed stream) skipping still decodes, so reading a
// 150-page chapter page by page decoded ~11,000 pages' worth (same quadratic cost S175 found in solid 7z). Here each
// wanted entry streams to its file through UnRAR's data callback as the walk passes it.
// Tested on the Mac with the same file: scripts/rar-extract-tests/run.sh.

nonisolated enum RarExtract {
    enum Failure: Error, Equatable {
        case open, encrypted, read(String), incomplete(String)
    }

    /// Box handed to the C callback: the open file and how many bytes it got.
    private final class Sink {
        let handle: FileHandle
        var written: UInt64 = 0
        var failed = false
        init(_ handle: FileHandle) { self.handle = handle }
    }

    /// Writes each `name` in the archive to its URL. Names are as stored (RAR on Windows writes "\" between folders —
    /// pass them that way). Entries not asked for are skipped (decoded only when the archive is solid).
    static func write(archive url: URL, files: [String: URL]) throws {
        var open = RAROpenArchiveDataEx()
        open.OpenMode = UInt32(RAR_OM_EXTRACT)
        let handle: UnsafeMutableRawPointer? = url.path.utf8CString.withUnsafeBufferPointer { path in
            open.ArcName = UnsafeMutablePointer(mutating: path.baseAddress)
            return UnsafeMutableRawPointer(RAROpenArchiveEx(&open))
        }
        guard let handle, open.OpenResult == ERAR_SUCCESS else {
            if let handle { RARCloseArchive(handle) }
            throw Failure.open
        }
        defer { RARCloseArchive(handle) }

        let callback: UNRARCALLBACK = { msg, userData, p1, p2 in
            guard msg == UCM_PROCESSDATA.rawValue, let box = UnsafeRawPointer(bitPattern: userData),
                  let bytes = UnsafeRawPointer(bitPattern: p1) else {
                // A password request means an encrypted entry: stop (Yomi has no password UI).
                return (msg == UCM_NEEDPASSWORD.rawValue || msg == UCM_NEEDPASSWORDW.rawValue) ? -1 : 0
            }
            let sink = Unmanaged<Sink>.fromOpaque(box).takeUnretainedValue()
            do {
                try sink.handle.write(contentsOf: Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: bytes), count: p2,
                                                       deallocator: .none))
                sink.written += UInt64(p2)
                return 0
            } catch {
                sink.failed = true
                return -1
            }
        }

        var remaining = files
        var header = RARHeaderDataEx()
        while !remaining.isEmpty {
            let read = RARReadHeaderEx(handle, &header)
            if read == ERAR_END_ARCHIVE { break }
            guard read == ERAR_SUCCESS else { throw Failure.read("header") }
            // Same field and decoding as Unrar.swift's `Entry.fileName`, so names match `ComicArchive.paths`' source.
            let name = withUnsafePointer(to: &header.FileName.0) { String(cString: $0) }
            guard let target = remaining.removeValue(forKey: name) else {
                guard RARProcessFile(handle, RAR_SKIP, nil, nil) == ERAR_SUCCESS else { throw Failure.read(name) }
                continue
            }
            if header.Flags & UInt32(RHDF_ENCRYPTED) != 0 { throw Failure.encrypted }
            FileManager.default.createFile(atPath: target.path, contents: nil)
            let file = try FileHandle(forWritingTo: target)
            let sink = Sink(file)
            let box = Unmanaged.passRetained(sink)
            RARSetCallback(handle, callback, Int(bitPattern: box.toOpaque()))
            let result = RARProcessFile(handle, RAR_TEST, nil, nil)   // TEST = decode, data goes to the callback
            RARSetCallback(handle, nil, 0)
            box.release()
            try? file.close()
            let expected = UInt64(header.UnpSizeHigh) << 32 | UInt64(header.UnpSize)
            guard result == ERAR_SUCCESS, !sink.failed else {
                throw result == ERAR_MISSING_PASSWORD || result == ERAR_BAD_PASSWORD ? Failure.encrypted : Failure.read(name)
            }
            guard sink.written == expected else { throw Failure.incomplete(name) }
        }
        if let missing = remaining.keys.first { throw Failure.read(missing) }
    }
}
