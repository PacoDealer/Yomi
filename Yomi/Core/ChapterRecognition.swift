import Foundation

/// Chapter number from a chapter's name, for sources that don't give one — a port of Mihon's
/// `tachiyomi.domain.chapter.service.ChapterRecognition` (Apache-2.0, mihonapp/mihon), same rules and order.
///
/// Mihon runs this on every chapter a source returns; Yomi didn't (S144), so Keiyoushi extensions that report
/// -1 (Asura Scans among them) saved every chapter without a number. Yomi assumes chapters in ascending order
/// wherever it doesn't sort by number, so Continue and Next/Previous ran on the source's newest-first order.
nonisolated enum ChapterRecognition {

    private static let numberPattern = #"([0-9]+)(\.[0-9]+)?(\.?[a-z]+)?"#

    /// "Mokushiroku Alice Vol.1 Ch. 4: Misrepresentation" → 4
    private static let basic = try! NSRegularExpression(pattern: #"(?<=ch\.) *"# + numberPattern)

    /// "Bleach 567: Down With Snowwhite" → 567
    private static let number = try! NSRegularExpression(pattern: numberPattern)

    /// "Prison School 12 v.1 vol004 version1243 volume64" → "Prison School 12"
    private static let unwanted = try! NSRegularExpression(pattern: #"\b(?:v|ver|vol|version|volume|season|s)[^a-z]?[0-9]+"#)

    /// "One Piece 12 special" → "One Piece 12special"
    private static let unwantedWhiteSpace = try! NSRegularExpression(pattern: #"\s(?=extra|special|omake)"#)

    /// The number, or `chapterNumber ?? -1` when the name has none (Mihon's contract: < 0 = unknown).
    nonisolated static func parseChapterNumber(mangaTitle: String, chapterName: String,
                                               chapterNumber: Double? = nil) -> Double {
        // Known number: keep it.
        if let chapterNumber, chapterNumber == -2 || chapterNumber > -1 { return chapterNumber }

        var clean = chapterName.lowercased()
        let title = mangaTitle.lowercased()
        if !title.isEmpty { clean = clean.replacingOccurrences(of: title, with: "") }
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "-", with: ".")
        clean = replace(unwantedWhiteSpace, in: clean)

        let matches = number.matches(in: clean, range: NSRange(clean.startIndex..., in: clean))
        guard let first = matches.first else { return chapterNumber ?? -1 }
        if matches.count > 1 {
            let name = replace(unwanted, in: clean)
            let range = NSRange(name.startIndex..., in: name)
            if let m = basic.firstMatch(in: name, range: range) { return value(of: m, in: name) }
            // Need to find again: the first number might already be removed.
            if let m = number.firstMatch(in: name, range: range) { return value(of: m, in: name) }
        }
        return value(of: first, in: clean)
    }

    /// Mihon stores the parsed value only when it's known; Yomi's "unknown" is nil.
    nonisolated static func number(mangaTitle: String, chapterName: String, sourceNumber: Double?) -> Double? {
        let n = parseChapterNumber(mangaTitle: mangaTitle, chapterName: chapterName, chapterNumber: sourceNumber)
        return n < 0 ? nil : n
    }

    private nonisolated static func replace(_ regex: NSRegularExpression, in s: String) -> String {
        regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
    }

    private nonisolated static func group(_ i: Int, of m: NSTextCheckingResult, in s: String) -> String? {
        guard m.range(at: i).location != NSNotFound, let r = Range(m.range(at: i), in: s) else { return nil }
        return String(s[r])
    }

    private nonisolated static func value(of m: NSTextCheckingResult, in s: String) -> Double {
        let initial = Double(group(1, of: m, in: s) ?? "") ?? 0
        return initial + decimal(group(2, of: m, in: s), alpha: group(3, of: m, in: s))
    }

    private nonisolated static func decimal(_ decimal: String?, alpha: String?) -> Double {
        if let decimal, !decimal.isEmpty { return Double(decimal) ?? 0 }
        if let alpha, !alpha.isEmpty {
            if alpha.contains("extra") { return 0.99 }
            if alpha.contains("omake") { return 0.98 }
            if alpha.contains("special") { return 0.97 }
            let trimmed = alpha.drop { $0 == "." }
            if trimmed.count == 1, let c = trimmed.first { return alphaPostfix(c) }
        }
        return 0
    }

    /// x.a → x.1, x.b → x.2, …
    private nonisolated static func alphaPostfix(_ c: Character) -> Double {
        guard let code = c.asciiValue else { return 0 }
        let n = Int(code) - (Int(Character("a").asciiValue!) - 1)
        return n >= 10 ? 0 : Double(n) / 10
    }
}
