import Foundation
import CoreGraphics
import Vision

// MARK: - Text on Page: recognition + layout (L3d)
//
// No UIKit here, so `scripts/page-text-tests/run.sh` runs the same code on the Mac against real pages
// (`PageText.swift` has the sheet). Vision reads the page; the lines it returns are joined into blocks (≈ one speech
// bubble or caption) and the blocks are put in reading order. Pure functions, so `nonisolated` (the project
// defaults to MainActor).
//
// All geometry is in PIXELS. (S173: the first version compared normalized widths with normalized heights — on a
// 760 × 1200 page those units differ by 1.6×, so vertical Japanese columns weren't seen as columns and whole rows of
// bubbles, sound effects and the page header became one block read backwards.)

nonisolated enum PageTextRecognizer {
    /// Languages offered in the sheet's menu ("auto" = Vision detects). Vision supports more; these are the ones
    /// sources publish in.
    static let languages: [(code: String, name: String)] = [
        ("auto", "Automatic"), ("en-US", "English"), ("ja-JP", "Japanese"), ("ko-KR", "Korean"),
        ("zh-Hans", "Chinese (Simplified)"), ("zh-Hant", "Chinese (Traditional)"), ("es-ES", "Spanish"),
        ("pt-BR", "Portuguese"), ("fr-FR", "French"), ("de-DE", "German"), ("it-IT", "Italian"),
        ("ru-RU", "Russian"), ("vi-VT", "Vietnamese"), ("th-TH", "Thai"), ("id-ID", "Indonesian"),
    ]

    struct Line {
        let text: String
        let rect: CGRect   // pixels, origin top-left

        /// Tategaki column: clearly taller than wide (pixels).
        var isVertical: Bool { rect.height > rect.width * 1.3 }
        var isHorizontal: Bool { rect.width > rect.height * 1.3 }
        /// Glyph size: a column's height per character, a line's height. (Not a column's width — Vision's boxes hug the
        /// glyphs, so columns of the same bubble measured 17 and 30 px wide on One Piece p. 5; per character both were 18.)
        var glyphSize: CGFloat {
            isVertical ? rect.height / CGFloat(max(text.filter { !$0.isWhitespace }.count, 1)) : rect.height
        }
        var isKanaOnly: Bool { text.unicodeScalars.allSatisfy { $0.isKana || $0.properties.isWhitespace } }
    }

    /// One bubble / caption: joined lines and the box around them (normalized 0…1, origin top-left).
    struct Block: Hashable {
        let text: String
        let box: CGRect
    }

    static func recognize(_ cgImage: CGImage, language: String) async throws -> [Block] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        if language == "auto" {
            request.automaticallyDetectsLanguage = true
        } else {
            request.automaticallyDetectsLanguage = false
            request.recognitionLanguages = [Locale.Language(identifier: language)]
        }
        var lines: [Line] = []
        for tile in tiles(width: cgImage.width, height: cgImage.height) {
            guard let slice = cgImage.cropping(to: tile.rect) else { continue }
            for obs in try await request.perform(on: slice) {
                guard let text = obs.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty else { continue }
                let r = obs.boundingBox.cgRect   // normalized to the slice, origin bottom-left
                let rect = CGRect(x: r.minX * tile.rect.width,
                                  y: tile.rect.minY + (1 - r.maxY) * tile.rect.height,
                                  width: r.width * tile.rect.width,
                                  height: r.height * tile.rect.height)
                // A line in the overlap is read by both slices: keep it only in the slice whose core holds its middle.
                guard tile.core.contains(rect.midY) else { continue }
                lines.append(Line(text: text, rect: rect))
            }
        }
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        return blocks(lines, in: size, rightToLeft: readsRightToLeft(lines, language: language))
    }

    /// Vision scales the whole image to its working size, so on a webtoon page (900 × 16,000 px) the text ends up a
    /// few pixels tall and nothing is found. Tall pages are read in slices 1.5× as tall as they are wide, overlapping by
    /// a fifth so a line cut by one slice is whole in the next.
    static func tiles(width: Int, height: Int) -> [(rect: CGRect, core: Range<CGFloat>)] {
        let w = CGFloat(width), h = CGFloat(height)
        let tileHeight = max(w * 1.5, 1)
        guard h > tileHeight * 1.2 else { return [(CGRect(x: 0, y: 0, width: w, height: h), 0..<h + 1)] }
        let overlap = tileHeight * 0.2
        var result: [(rect: CGRect, core: Range<CGFloat>)] = []
        var y: CGFloat = 0
        while true {
            let bottom = min(y + tileHeight, h)
            let isFirst = y == 0, isLast = bottom >= h
            let core = (isFirst ? 0 : y + overlap / 2)..<(isLast ? h + 1 : bottom - overlap / 2)
            result.append((CGRect(x: 0, y: y, width: w, height: bottom - y).integral, core))
            if isLast { break }
            y = bottom - overlap
        }
        return result
    }

    /// Two lines belong to the same bubble when they run the same way, have about the same glyph size and sit next to
    /// each other: columns side by side (gap < one column width) overlapping in height, or lines stacked (gap < one
    /// line height) overlapping in width. Sound effects and page headers (other size or direction) stay apart.
    static func belongTogether(_ a: Line, _ b: Line) -> Bool {
        let ratio = max(a.glyphSize, b.glyphSize) / max(min(a.glyphSize, b.glyphSize), 1)
        guard ratio < 1.6 else { return false }
        let size = max(a.glyphSize, b.glyphSize)
        if a.isVertical && b.isVertical {
            let gap = max(a.rect.minX, b.rect.minX) - min(a.rect.maxX, b.rect.maxX)
            let overlap = min(a.rect.maxY, b.rect.maxY) - max(a.rect.minY, b.rect.minY)
            return gap < size * 0.8 && overlap > min(a.rect.height, b.rect.height) * 0.3
        }
        if !a.isVertical && !b.isVertical {
            let gap = max(a.rect.minY, b.rect.minY) - min(a.rect.maxY, b.rect.maxY)
            let overlap = min(a.rect.maxX, b.rect.maxX) - max(a.rect.minX, b.rect.minX)
            return gap < size * 0.9 && overlap > 0
        }
        return false
    }

    static func blocks(_ lines: [Line], in size: CGSize, rightToLeft: Bool) -> [Block] {
        var lines = inMainScript(lines)
        if rightToLeft { lines = withoutFurigana(lines) }
        guard !lines.isEmpty, size.width > 0, size.height > 0 else { return [] }
        var parent = Array(lines.indices)
        func find(_ i: Int) -> Int { var i = i; while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }; return i }
        for i in lines.indices {
            for j in lines.indices where j > i && belongTogether(lines[i], lines[j]) {
                parent[find(i)] = find(j)
            }
        }
        var groups: [Int: [Int]] = [:]
        for i in lines.indices { groups[find(i), default: []].append(i) }

        struct Made { let text: String; let rect: CGRect }
        let made: [Made] = groups.values.map { members in
            let rect = members.map { lines[$0].rect }.reduce(CGRect.null) { $0.union($1) }
            // Columns read right to left (tategaki is always right to left); lines top to bottom.
            let vertical = members.allSatisfy { lines[$0].isVertical } && members.count > 1
            let ordered = members.sorted { a, b in
                let ra = lines[a].rect, rb = lines[b].rect
                if vertical { return ra.midX > rb.midX }
                return ra.midY != rb.midY ? ra.midY < rb.midY : ra.minX < rb.minX
            }
            let texts = ordered.map { lines[$0].text }
            // Japanese/Chinese have no spaces between words; Korean and Latin scripts do.
            let joiner = texts.contains { $0.unicodeScalars.contains { $0.isKana || $0.isHan } } ? "" : " "
            return Made(text: texts.joined(separator: joiner), rect: rect)
        }

        // Reading order: rows top to bottom. A block joins the current row when its top is within half a block height
        // of the row's first block; inside a row, right to left (Japanese) or left to right.
        var rows: [[Made]] = []
        for block in made.sorted(by: { $0.rect.minY < $1.rect.minY }) {
            if let first = rows.last?.first,
               block.rect.minY < first.rect.minY + min(first.rect.height, block.rect.height) * 0.5 {
                rows[rows.count - 1].append(block)
            } else {
                rows.append([block])
            }
        }
        return rows.flatMap { row in
            row.sorted { rightToLeft ? $0.rect.midX > $1.rect.midX : $0.rect.midX < $1.rect.midX }
        }.map { block in
            Block(text: block.text, box: CGRect(x: block.rect.minX / size.width, y: block.rect.minY / size.height,
                                                width: block.rect.width / size.width,
                                                height: block.rect.height / size.height))
        }
    }

    /// Japanese pages: furigana (the small kana beside kanji) come back as their own short columns — "なにこと" beside
    /// 何事も. Kana-only vertical lines under three quarters of the page's usual glyph size are dropped.
    static func withoutFurigana(_ lines: [Line]) -> [Line] {
        let sizes = lines.filter(\.isVertical).map(\.glyphSize).sorted()
        guard sizes.count >= 3 else { return lines }
        let usual = sizes[sizes.count / 2]
        return lines.filter { !($0.isVertical && $0.isKanaOnly && $0.glyphSize < usual * 0.75) }
    }

    enum Script { case latin, japaneseChinese, hangul, other }

    /// Artwork read as text usually comes out in a script the page isn't in: Thai and Hangul on a Japanese page,
    /// Arabic digits and Hangul on an English one (S173). Lines with no letter of the page's main script are dropped;
    /// Latin always stays on Japanese/Chinese pages (headers, "DON"), plain digits and punctuation count as any script.
    /// Junk in the page's own script can't be told apart (Vision's confidence is only 0.3 / 0.5 / 1, real lines get 0.3).
    static func inMainScript(_ lines: [Line]) -> [Line] {
        var counts: [Script: Int] = [:]
        for line in lines { for scalar in line.text.unicodeScalars { if let s = script(of: scalar) { counts[s, default: 0] += 1 } } }
        guard let main = counts.max(by: { $0.value < $1.value })?.key else { return lines }
        return lines.filter { line in
            let scripts = Set(line.text.unicodeScalars.compactMap(script(of:)))
            return scripts.isEmpty || scripts.contains(main) || (main == .japaneseChinese && scripts.contains(.latin))
        }
    }

    /// nil = fits any page (ASCII digits, punctuation, symbols, spaces).
    static func script(of scalar: Unicode.Scalar) -> Script? {
        if scalar.isKana || scalar.isHan { return .japaneseChinese }
        if scalar.isHangul { return .hangul }
        if scalar.properties.isAlphabetic || scalar.properties.numericType != nil {
            if scalar.isASCII { return scalar.properties.numericType != nil ? nil : .latin }
            return (0x00C0...0x024F).contains(scalar.value) ? .latin : .other
        }
        return nil
    }

    /// Japanese manga read right to left. "Automatic": when kana make up a good share of the text, or most CJK text
    /// sits in vertical columns (traditional Chinese editions of manga). Korean and webtoon-style pages: left to right.
    static func readsRightToLeft(_ lines: [Line], language: String) -> Bool {
        if language.hasPrefix("ja") { return true }
        guard language == "auto" else { return false }
        let scalars = lines.flatMap { $0.text.unicodeScalars }
        guard !scalars.isEmpty else { return false }
        let kana = scalars.filter(\.isKana).count
        if Double(kana) / Double(scalars.count) > 0.2 { return true }
        let cjkLines = lines.filter { $0.text.unicodeScalars.contains(where: \.isHan) }
        let vertical = cjkLines.filter(\.isVertical).count
        return !cjkLines.isEmpty && vertical * 2 > cjkLines.count
    }
}

nonisolated extension Unicode.Scalar {
    var isKana: Bool { (0x3040...0x30FF).contains(value) }
    var isHan: Bool { (0x4E00...0x9FFF).contains(value) || (0x3400...0x4DBF).contains(value) }
    var isHangul: Bool { (0xAC00...0xD7AF).contains(value) || (0x1100...0x11FF).contains(value) || (0x3130...0x318F).contains(value) }
    var isCJK: Bool { isKana || isHan || isHangul }
}
