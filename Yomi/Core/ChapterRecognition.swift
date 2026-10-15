import Foundation

/// Volume and chapter number from chapter names, for sources that don't give one — a port of Mihon's
/// `tachiyomi.domain.chapter.service.ChapterRecognition` (Apache-2.0, mihonapp/mihon @446f6df, v0.21), same rules
/// and order. Its tests are ported too (`scripts/chapter-recognition-tests`, run with `run.sh`).
///
/// Mihon runs this on every chapter a source returns; Yomi didn't (S144), so Keiyoushi extensions that report
/// -1 (Asura Scans among them) saved every chapter without a number. Yomi assumes chapters in ascending order
/// wherever it doesn't sort by number, so Continue and Next/Previous ran on the source's newest-first order.
///
/// v2 (S165): each name is read on its own (the volume or season is taken out, a part becomes the letter of a
/// sub-chapter, the number is the one after "ch." or else the first one left), then the whole list fills in what a
/// single name doesn't tell — see `parseChapterNumbers`.
nonisolated enum ChapterRecognition {

    /// The volume and chapter number recognized for a chapter, e.g. "10.5" or "19a", nil when there is none.
    struct Numbering: Equatable, CustomStringConvertible {
        let volume: String?
        let chapter: String?
        var description: String { "(\(volume ?? "nil"), \(chapter ?? "nil"))" }
    }

    /// A recognized number, with the letter of a sub-chapter like the a in 19a. Kept apart from the value so that
    /// chapters can still be compared and numbered after each other.
    private struct Recognized {
        var value: Double
        var letter: Character? = nil
        var text: String { format(value) + (letter.map(String.init) ?? "") }
    }

    /// A number with optional decimals and a trailing word or letter, e.g. 12, 12.5, 12a, 12.extra
    private static let numberPattern = #"([0-9]+)(\.[0-9]+)?(\.?[a-z]+)?"#

    /// "Mokushiroku Alice Vol.1 Ch. 4: Misrepresentation" → 4
    private static let basic = regex(#"(?<=ch\.) *"# + numberPattern)

    /// "Bleach 567: Down With Snowwhite" → 567
    private static let number = regex(numberPattern)

    /// "Onepunch-Man Punch Ver002 028" → "Onepunch-Man Punch 028"
    private static let unwanted = regex(#"\b(?:ver|version)[^a-z]?[0-9]+"#)

    /// "One Piece 12 special" → "One Piece 12special"
    private static let unwantedWhiteSpace = regex(#"\s(?=extra|special|omake)"#)

    /// A volume or season, the short forms only right before the number since "s" also ends words.
    /// "Mokushiroku Alice Vol.1 Ch. 4" → 1, "The Gamer S3 - Chapter 20" → 3
    private static let volume = regex(#"\b(?:(?:vol(?:ume)?|season)[^a-z0-9]? *|[vs]\.?)([0-9]+(?:\.[0-9]+)?)\b"#)

    /// "Chapter 1.5 Part II" → b
    private static let part = regex(#"\bpart\.? *([0-9]+|i{1,3}|iv|vi{0,3}|ix|x)\b"#)

    private static let romanNumerals = ["i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x"]

    /// "Group 2 Chapter 386" → "Group # Chapter #"
    private static let anyNumber = regex(#"[0-9]+(?:\.[0-9]+)?"#)

    /// A number after this is the chapter number, even when every similar name has the same one.
    /// "Oshi no Ko Chapter 5 Part 1" → 5a
    private static let chapterPrefix = regex(#"(?:\b(?:ch|chap|chapter|ep|episode)\.? *|#)$"#)

    /// "Bonus Chapter: Beach Episode"
    private static let bonus = regex(#"\b(?:extra|bonus|omake|special|side ?story|afterword|interlude)"#)

    /// "Prologue: The Beginning" → 0
    private static let prologue = regex(#"\b(?:prologue|one.?shot|pilot)\b"#)

    // MARK: - Single name

    /// The number, or `chapterNumber ?? -1` when the name has none (Mihon's contract: < 0 = unknown).
    nonisolated static func parseChapterNumber(mangaTitle: String, chapterName: String,
                                               chapterNumber: Double? = nil) -> Double {
        if let chapterNumber, isKnown(chapterNumber) { return chapterNumber }
        return parseName(cleanName(mangaTitle, chapterName)).map { toDouble($0.text) } ?? chapterNumber ?? -1
    }

    /// Mihon stores the parsed value only when it's known; Yomi's "unknown" is nil.
    nonisolated static func number(mangaTitle: String, chapterName: String, sourceNumber: Double?) -> Double? {
        let n = parseChapterNumber(mangaTitle: mangaTitle, chapterName: chapterName, chapterNumber: sourceNumber)
        return n < 0 ? nil : n
    }

    // MARK: - Whole list

    /// Yomi's numbers (nil = unknown) for a chapter list in EITHER order — Mihon's reading wants the newest first, so
    /// a list whose recognized numbers go up is read reversed and handed back in the order it came.
    nonisolated static func numbers(mangaTitle: String, names: [String], sourceNumbers: [Double?]) -> [Double?] {
        let singles = names.indices.map {
            number(mangaTitle: mangaTitle, chapterName: names[$0], sourceNumber: sourceNumbers[$0])
        }
        let known = singles.compactMap { $0 }
        let ascending = known.count > 1 && known.first! < known.last!
        let order = ascending ? Array(names.indices.reversed()) : Array(names.indices)
        let parsed = parseChapterNumbers(mangaTitle: mangaTitle, names: order.map { names[$0] },
                                         sourceNumbers: order.map { sourceNumbers[$0] })
        var result = [Double?](repeating: nil, count: names.count)
        for (i, original) in order.enumerated() {
            guard let chapter = parsed[i].chapter else { continue }
            let n = toDouble(chapter)
            result[original] = n < 0 ? nil : n
        }
        return result
    }

    /// Recognizes the numbers of chapters given from the most to the least recent, using the whole list for what a
    /// name alone doesn't tell: numbers every similar name shares aren't the chapter number, and chapters without a
    /// number are numbered after the chapters around them. Numbers the source gave (`sourceNumbers`) are kept.
    nonisolated static func parseChapterNumbers(mangaTitle: String, names chapterNames: [String],
                                                sourceNumbers: [Double?]) -> [Numbering] {
        let names = chapterNames.map { cleanName(mangaTitle, $0) }
        let known = sourceNumbers.map { $0.map(isKnown) ?? false }
        // Taken out before reading the names, so a number like the 2 in "Group 2 Chapter 386" can't be picked
        let sharedNumbers = findSharedNumbers(names, known: known)
        var chapterNumbers: [Recognized?] = names.indices.map { i in
            if known[i], let n = sourceNumbers[i] { return Recognized(value: n) }
            return parseName(removeRanges(sharedNumbers[i], from: names[i]))
        }
        // Only from the name: newer chapters may not be in a volume yet, so neighbours don't tell
        var volumes: [Double?] = names.map { name in
            firstMatch(volume, in: name).flatMap { group(1, of: $0, in: name) }.flatMap(Double.init)
        }

        fillChapterNumbers(names, &chapterNumbers, &volumes)
        return names.indices.map { Numbering(volume: volumes[$0].map(format), chapter: chapterNumbers[$0]?.text) }
    }

    /// `number`, a number of a `Numbering`, as a double. A letter only counts without decimals, from .1 for a up to
    /// .9 for i, e.g. 19a → 19.1 and 1.5a → 1.5.
    nonisolated static func toDouble(_ number: String) -> Double {
        let letter = number.last.flatMap { $0.isLetter ? $0 : nil }
        let value = Double(letter == nil ? number : String(number.dropLast())) ?? -1
        guard let letter, let code = letter.asciiValue else { return value }
        let tenths = Int(code) - Int(Character("a").asciiValue!) + 1
        return tenths < 10 && !number.contains(".") ? value + Double(tenths) / 10 : value
    }

    // MARK: - Mihon's helpers

    /// Whether the source gave a number: -1 and below mean it didn't, except -2 which some sources use on purpose.
    private static func isKnown(_ n: Double) -> Bool { n == -2 || n > -1 }

    private static func cleanName(_ mangaTitle: String, _ chapterName: String) -> String {
        let title = mangaTitle.lowercased()
        let name = chapterName.lowercased()
        return title.isEmpty ? name : name.replacingOccurrences(of: title, with: "")
    }

    /// Replaces `ranges` with spaces, from the last so the earlier ones stay where they are.
    private static func removeRanges(_ ranges: [NSRange], from name: String) -> String {
        let s = NSMutableString(string: name)
        for r in ranges.sorted(by: { $0.location > $1.location }) { s.replaceCharacters(in: r, with: " ") }
        return s as String
    }

    /// Finds the numbers that are the same in every name of a group of at least three names that only differ in
    /// their numbers, e.g. the 2 in "Group 2 Chapter 385". Chapters with a number from the source are left out.
    private static func findSharedNumbers(_ names: [String], known: [Bool]) -> [[NSRange]] {
        let matches = names.map { allMatches(anyNumber, in: $0).map(\.range) }
        func value(_ i: Int, _ slot: Int) -> String { (names[i] as NSString).substring(with: matches[i][slot]) }
        var shared = [[NSRange]](repeating: [], count: names.count)
        // Grouped by all but their numbers, so that the nth number of each name means the same thing
        let groups = Dictionary(grouping: names.indices.filter { !known[$0] }) { replace(anyNumber, in: names[$0], with: "#") }
        // Fewer names could share a number by chance
        for group in groups.values where group.count >= 3 {
            let first = group[0]
            let slots = matches[first].indices
            let sharedSlots = slots.filter { slot in group.allSatisfy { value($0, slot) == value(first, slot) } }
            // Something has to be left to tell the chapters apart
            guard sharedSlots.count < slots.count else { continue }
            // Parts of a chapter share its number, e.g. the 5 of "Chapter 5 Part 1" and "Chapter 5 Part 2"
            let removable = sharedSlots.filter { slot in
                let before = (names[first] as NSString).substring(to: matches[first][slot].location)
                return firstMatch(chapterPrefix, in: before) == nil
            }
            for i in group { shared[i] = removable.map { matches[i][$0] } }
        }
        return shared
    }

    /// Numbers runs of chapters without a number after the chapters around them, only within a volume since chapter
    /// numbers may start over in the next one:
    /// - between two chapters, the missing whole numbers when they fit, e.g. 2, ?, 4 → 3, or else 10, ?, 11 → 10.5
    /// - after the newest chapter, only bonus chapters, e.g. 100, Afterword → 100.5
    /// - before the oldest chapter, only a prologue, which gets 0, and volume 0 when the chapter after it has a volume
    private static func fillChapterNumbers(_ names: [String], _ numbers: inout [Recognized?], _ volumes: inout [Double?]) {
        for run in nullRuns(numbers) {
            // A -2 from the source says nothing about where a chapter is, so it can't be numbered after
            let newer = run.lowerBound > 0 ? numbers[run.lowerBound - 1].flatMap { $0.value >= 0 ? $0 : nil } : nil
            let olderIndex = run.upperBound   // first index after the run
            let older = olderIndex < numbers.count ? numbers[olderIndex].flatMap { $0.value >= 0 ? $0 : nil } : nil
            let olderVolume = olderIndex < volumes.count ? volumes[olderIndex] : nil
            let bonuses = run.filter { firstMatch(bonus, in: names[$0]) != nil }.count
            func isWithinVolume(_ v: Double?) -> Bool { run.allSatisfy { volumes[$0] == nil || volumes[$0] == v } }

            if let newer, let older {
                let isSameVolume = volumes[run.lowerBound - 1] == olderVolume && isWithinVolume(olderVolume)
                // Out of order chapters tell nothing about the ones between them
                guard newer.value > older.value, isSameVolume else { continue }
                let isWhole = [newer, older].allSatisfy { $0.letter == nil && $0.value.truncatingRemainder(dividingBy: 1) == 0 }
                // Bonus chapters aren't missing chapters even when they would fit, e.g. 2, Bonus, 4 → 2.5
                if bonuses == 0, isWhole, newer.value - older.value - 1 == Double(run.count) {
                    for i in run { numbers[i] = Recognized(value: older.value + Double(run.upperBound - i)) }
                } else {
                    // Never past the next whole number, which may still be a chapter to come
                    fillBetween(run, &numbers, lower: older.value, upper: min(newer.value, (older.value).rounded(.down) + 1))
                }
            } else if let older {
                // Newer chapters without a number may as well be announcements
                guard bonuses == run.count, isWithinVolume(olderVolume) else { continue }
                fillBetween(run, &numbers, lower: older.value, upper: older.value.rounded(.down) + 1)
            } else if let newer, newer.value > 0 {
                // When the first chapter is already 0, that's the prologue
                for i in run where firstMatch(prologue, in: names[i]) != nil {
                    numbers[i] = Recognized(value: 0)
                    if volumes[i] == nil, volumes[run.lowerBound - 1] != nil { volumes[i] = 0 }
                }
            }
        }
    }

    /// The ranges of consecutive chapters without a number.
    private static func nullRuns(_ numbers: [Recognized?]) -> [Range<Int>] {
        var runs: [Range<Int>] = []
        var start = 0
        while start < numbers.count {
            if numbers[start] != nil { start += 1; continue }
            let end = (start..<numbers.count).first { numbers[$0] != nil } ?? numbers.count
            runs.append(start..<end)
            start = end
        }
        return runs
    }

    /// Numbers `run` between `lower` and `upper`, the least recent getting the lowest: .5, .6 and so on after the
    /// whole number, e.g. 10, ?, ?, 11 → 10.5, 10.6, or evenly spread when those don't fit.
    private static func fillBetween(_ run: Range<Int>, _ numbers: inout [Recognized?], lower: Double, upper: Double) {
        let tenths = (5...9).map { lower.rounded(.down) + Double($0) / 10 }.filter { $0 > lower && $0 < upper }
        if tenths.count >= run.count {
            // Rounded since tenths can't be exact doubles, e.g. 10 + 0.6
            for (index, chapter) in run.reversed().enumerated() {
                numbers[chapter] = Recognized(value: (tenths[index] * 10).rounded() / 10)
            }
            return
        }
        // Tenths run out after e.g. a 2.9 or past five chapters, and the chapters still have to fit below upper
        let step = (upper - lower) / Double(run.count + 1)
        for i in run { numbers[i] = Recognized(value: ((lower + step * Double(run.upperBound - i)) * 1000).rounded() / 1000) }
    }

    /// The chapter number in `name`, a chapter name with the manga title removed, or nil if it has none. A part
    /// after the chapter number becomes its letter, e.g. Chapter 1.5 Part I → 1.5a.
    private static func parseName(_ name: String) -> Recognized? {
        // The volume can't also be the chapter number
        let withoutVolume = replace(volume, in: name, with: " ")
        if let partMatch = firstMatch(part, in: withoutVolume),
           let partText = group(1, of: partMatch, in: withoutVolume) {
            let n = Int(partText) ?? ((romanNumerals.firstIndex(of: partText) ?? -1) + 1)
            if (1...26).contains(n) {
                let rest = (withoutVolume as NSString).replacingCharacters(in: partMatch.range, with: "")
                if var number = parseNumber(rest) {
                    // A letter written in the number is what the source numbers the chapter by
                    if number.letter == nil { number.letter = Character(UnicodeScalar(UInt8(96 + n))) }
                    return number
                }
            }
        }
        // Without another number, e.g. "Part 3", the part is the chapter number
        return parseNumber(withoutVolume)
    }

    /// The number after "ch." or else the first one, leaving out version tags when there are several.
    private static func parseNumber(_ name: String) -> Recognized? {
        // Some sources write decimals and letters with these, e.g. 300,a and 122-a
        let clean = replace(unwantedWhiteSpace, in: name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "-", with: "."))
        let numbers = allMatches(number, in: clean)
        if numbers.count > 1 {
            let withoutTags = replace(unwanted, in: clean)
            if let m = firstMatch(basic, in: withoutTags) ?? firstMatch(number, in: withoutTags) {
                return recognized(m, in: withoutTags)
            }
        }
        return numbers.first.map { recognized($0, in: clean) }
    }

    /// 12.5 → 12.5, 12.extra → 12.99, 12.a → 12a
    private static func recognized(_ m: NSTextCheckingResult, in s: String) -> Recognized {
        let decimal = group(2, of: m, in: s) ?? ""
        let alpha = group(3, of: m, in: s) ?? ""
        let value = (Double(group(1, of: m, in: s) ?? "") ?? 0) + (Double(decimal) ?? 0)
        if decimal.isEmpty, alpha.contains("extra") { return Recognized(value: value + 0.99) }
        if decimal.isEmpty, alpha.contains("omake") { return Recognized(value: value + 0.98) }
        if decimal.isEmpty, alpha.contains("special") { return Recognized(value: value + 0.97) }
        // Only up to i, like the decimals they used to stand for, since others are rather words like 5v2
        let trimmed = alpha.drop { $0 == "." }
        let letter = trimmed.count == 1 ? trimmed.first.flatMap { ("a"..."i").contains($0) ? $0 : nil } : nil
        return Recognized(value: value, letter: letter)
    }

    /// Without trailing zeros, ASCII digits and a dot whatever the locale, at most 3 decimals: 10.5, 3, 24.005
    private static func format(_ value: Double) -> String {
        var s = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s == "-0" ? "0" : s
    }

    // MARK: - NSRegularExpression

    private static func regex(_ pattern: String) -> NSRegularExpression { try! NSRegularExpression(pattern: pattern) }

    private static func allMatches(_ r: NSRegularExpression, in s: String) -> [NSTextCheckingResult] {
        r.matches(in: s, range: NSRange(location: 0, length: (s as NSString).length))
    }

    private static func firstMatch(_ r: NSRegularExpression, in s: String) -> NSTextCheckingResult? {
        r.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length))
    }

    private static func replace(_ r: NSRegularExpression, in s: String, with template: String = "") -> String {
        r.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: template)
    }

    private static func group(_ i: Int, of m: NSTextCheckingResult, in s: String) -> String? {
        let r = m.range(at: i)
        guard r.location != NSNotFound else { return nil }
        return (s as NSString).substring(with: r)
    }
}
