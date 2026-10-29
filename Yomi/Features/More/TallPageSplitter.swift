import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - TallPageSplitter

/// D12 (S163): cuts a very tall downloaded page (Asura via Keiyoushi = 900x16000) into parts the reader can draw as
/// ordinary pages, so an offline chapter never takes the 16000-px strip path (one 57 MB decode per page).
/// Rule ported from Mihon's `TallImageSplitCalculator` (Apache-2.0): split only when the page is more than 3× taller
/// than wide; equal parts, the last one takes the remainder. Mihon sizes parts at 2× the screen; Yomi caps them at the
/// reader's strip threshold (4096 px, `StripPageImage.strips`) so a part is never cut a second time in the reader.
///
/// An actor so pages are split one at a time: each split decodes the whole page once (~57 MB for 900x16000).
actor TallPageSplitter {

    static let shared = TallPageSplitter()

    nonisolated static let maxPartHeight = 4096

    /// The page's parts as HEIC data, or nil to keep the original bytes (not tall, animated, or not decodable).
    func parts(of data: Data) -> [Data]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              (props[kCGImagePropertyOrientation] as? Int ?? 1) == 1
        else { return nil }

        let rows = Self.partRows(width: width, height: height)
        guard rows.count > 1,
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }

        var out: [Data] = []
        for row in rows {
            guard let crop = image.cropping(to: CGRect(x: 0, y: row.lowerBound, width: image.width, height: row.count)),
                  let encoded = Self.encode(crop)
            else { return nil }   // all or nothing: a half-split page is worse than the original
            out.append(encoded)
        }
        return out
    }

    /// Pixel rows of each part; one range = don't split.
    nonisolated static func partRows(width: Int, height: Int) -> [Range<Int>] {
        guard width > 0, height > width * 3, height > maxPartHeight else { return [0..<height] }
        let count = (height - 1) / maxPartHeight + 1
        let step = height / count
        return (0..<count).map { i in
            i * step ..< (i == count - 1 ? height : (i + 1) * step)
        }
    }

    /// HEIC: on 12 real Asura pages (800x~14000 webp, 11.1 MB) HEIC 0.8 came to 0.93× the originals, JPEG 0.9 to 2.2×
    /// (S163). JPEG only if this device can't write HEIC.
    nonisolated private static func encode(_ image: CGImage) -> Data? {
        for type in [UTType.heic, .jpeg] {
            let data = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
            if CGImageDestinationFinalize(dest) { return data as Data }
        }
        return nil
    }
}

// MARK: - Page files

/// How a downloaded chapter's pages sit on disk: `<page>.dat` for a whole page, `<page>-<part>of<count>.dat` for the
/// parts of a split one. Progress is saved in source pages (`lastPageRead`), so it means the same page online, offline
/// and on another device; `sourcePages[i]` is the source page of local image `i`.
struct DownloadedPages {
    let urls: [URL]
    let sourcePages: [Int]

    /// Parses a folder. A whole `<page>.dat` wins over parts of the same page; a part set with a part missing (a split
    /// that stopped half-way) doesn't count — `incomplete` lists those files so a resumed download can clear them.
    /// Part sets are grouped by their count, so leftovers of an older split never decide the result by folder order
    /// (S195): the one complete set is the page; with none, or more than one, every part is cleared.
    nonisolated static func scan(_ dir: URL) -> (pages: [Int: [URL]], incomplete: [URL]) {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var whole: [Int: URL] = [:]
        var parts: [Int: [Int: [Int: URL]]] = [:]   // page → part count → part → file
        var incomplete: [URL] = []
        for file in files where file.pathExtension == "dat" {
            let name = file.deletingPathExtension().lastPathComponent
            if let page = Int(name) {
                whole[page] = file
                continue
            }
            let pieces = name.split(separator: "-")
            guard pieces.count == 2, let page = Int(pieces[0]) else { continue }
            let partOf = pieces[1].split(separator: "of")   // split(separator:) on a String: the whole "of"
            guard partOf.count == 2, let part = Int(partOf[0]), let count = Int(partOf[1]), part < count else {
                continue
            }
            parts[page, default: [:]][count, default: [:]][part] = file
        }
        var pages: [Int: [URL]] = whole.mapValues { [$0] }
        for (page, sets) in parts {
            let complete = sets.filter { $0.value.count == $0.key }
            if whole[page] == nil, complete.count == 1, let kept = complete.first {
                pages[page] = (0..<kept.key).compactMap { kept.value[$0] }
                for (count, files) in sets where count != kept.key { incomplete.append(contentsOf: files.values) }
            } else {
                for files in sets.values { incomplete.append(contentsOf: files.values) }
            }
        }
        return (pages, incomplete)
    }

    nonisolated init?(dir: URL) {
        let pages = Self.scan(dir).pages
        guard !pages.isEmpty else { return nil }
        var urls: [URL] = []
        var sourcePages: [Int] = []
        for page in pages.keys.sorted() {
            for url in pages[page]! {
                urls.append(url)
                sourcePages.append(page)
            }
        }
        self.urls = urls
        self.sourcePages = sourcePages
    }

    /// Before a (re)download: drops pages past the end (a chapter whose page list got shorter since the last try must
    /// not keep its old extra pages — the reader would show them at the end) and half-written part sets, then returns
    /// the source pages still missing. Pages already on disk are whole (every file is written atomically) and skipped.
    nonisolated static func prepareResume(_ dir: URL, pageCount: Int) -> [Int] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "dat" {
            // `<page>.dat` or a part `<page>-<part>of<count>.dat` (D12)
            let name = file.deletingPathExtension().lastPathComponent
            if let idx = Int(name.split(separator: "-").first ?? ""), idx >= pageCount {
                try? FileManager.default.removeItem(at: file)
            }
        }
        let onDisk = scan(dir)
        for file in onDisk.incomplete { try? FileManager.default.removeItem(at: file) }
        return (0..<max(0, pageCount)).filter { onDisk.pages[$0] == nil }
    }

    nonisolated static func fileName(page: Int, part: Int, of count: Int) -> String {
        count == 1 ? "\(page).dat" : "\(page)-\(part)of\(count).dat"
    }
}
