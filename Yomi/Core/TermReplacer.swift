import Foundation

// MARK: - Term replacement (S177, ArcReader backlog)
//
// Renames a term everywhere in a novel's chapters — fixes names a machine or fan translation spells three ways
// ("Lin Fen" / "Lin Feng" / "Ling Feng"). Applied to chapter HTML when it is read (`NovelContent.html`), so the
// reader and read-aloud both get it and downloaded files stay as the source sent them.
//
// Rules:
// - Only text between tags changes; tags, attributes and <script>/<style> contents are left alone.
// - One pass over the text, longest term first: "Lin Feng" wins over "Lin", and a replacement is never replaced
//   again (A→B and B→C don't chain).
// - Whole words for scripts written with spaces: "Li" doesn't touch "Like". Terms that start or end in Chinese,
//   Japanese, Korean or Thai have no word edge there, so they match anywhere.
// - Not matched: a term split by a tag ("Lin <i>Feng</i>") or one whose characters the page wrote as entities.

nonisolated struct TermRule: Sendable, Equatable {
    var find: String
    var replace: String
    var matchCase: Bool
}

nonisolated enum TermReplacer {
    /// Rules usable as given, deduplicated (first one wins), longest term first.
    static func prepared(_ rules: [TermRule]) -> [TermRule] {
        var seen = Set<String>()
        var out: [TermRule] = []
        for rule in rules {
            let find = rule.find.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !find.isEmpty, seen.insert(find.lowercased()).inserted else { continue }
            out.append(TermRule(find: find, replace: rule.replace, matchCase: rule.matchCase))
        }
        return out.enumerated()
            .sorted { $0.element.find.count != $1.element.find.count ? $0.element.find.count > $1.element.find.count
                                                                      : $0.offset < $1.offset }
            .map(\.element)
    }

    static func apply(_ rules: [TermRule], toHTML html: String) -> String {
        let rules = prepared(rules)
        guard !rules.isEmpty, let regex = regex(for: rules) else { return html }
        var out = ""
        out.reserveCapacity(html.utf16.count)
        var text = ""
        var i = html.startIndex
        func flushText() {
            if !text.isEmpty { out += replace(in: text, regex: regex, rules: rules, escapeHTML: true); text = "" }
        }
        while i < html.endIndex {
            guard html[i] == "<" else { text.append(html[i]); i = html.index(after: i); continue }
            flushText()
            // A tag runs to the next ">"; <script> and <style> run to their closing tag.
            let tagEnd = html[i...].firstIndex(of: ">").map { html.index(after: $0) } ?? html.endIndex
            let tag = html[i..<tagEnd]
            var end = tagEnd
            let lower = tag.prefix(8).lowercased()
            for raw in ["script", "style"] where lower.hasPrefix("<\(raw)") {
                end = html.range(of: "</\(raw)", options: .caseInsensitive, range: tagEnd..<html.endIndex)
                    .map { html[$0.upperBound...].firstIndex(of: ">").map { html.index(after: $0) } ?? html.endIndex }
                    ?? html.endIndex
            }
            out += html[i..<end]
            i = end
        }
        flushText()
        return out
    }

    static func apply(_ rules: [TermRule], toText text: String) -> String {
        let rules = prepared(rules)
        guard !rules.isEmpty, let regex = regex(for: rules) else { return text }
        return replace(in: text, regex: regex, rules: rules, escapeHTML: false)
    }

    // MARK: Matching

    /// One alternation, a capture group per rule (same order as `rules`), case per rule.
    private static func regex(for rules: [TermRule]) -> NSRegularExpression? {
        let parts = rules.map { rule -> String in
            let body = NSRegularExpression.escapedPattern(for: rule.find)
            let lead = rule.find.first.map(hasWordEdge) == true ? "(?<![\\p{L}\\p{N}\\p{M}])" : ""
            let trail = rule.find.last.map(hasWordEdge) == true ? "(?![\\p{L}\\p{N}\\p{M}])" : ""
            return "(\(lead)(?\(rule.matchCase ? "-i" : "i"):\(body))\(trail))"
        }
        return try? NSRegularExpression(pattern: parts.joined(separator: "|"))
    }

    /// Letters and digits of scripts written with spaces between words.
    private static func hasWordEdge(_ c: Character) -> Bool {
        guard let scalar = c.unicodeScalars.first else { return false }
        if !(CharacterSet.alphanumerics.contains(scalar)) { return false }
        switch scalar.value {
        case 0x0E00...0x0EFF,                                   // Thai, Lao
             0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF, // Hangul (Korean uses spaces, but particles attach)
             0x3040...0x30FF, 0x31F0...0x31FF,                  // Hiragana, Katakana
             0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FFFF: // Han
            return false
        default:
            return true
        }
    }

    private static func replace(in text: String, regex: NSRegularExpression, rules: [TermRule], escapeHTML: Bool) -> String {
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }
        var out = ""
        var last = 0
        for m in matches {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let rule = (1...rules.count).first { m.range(at: $0).location != NSNotFound }.map { rules[$0 - 1] }
            let replacement = rule?.replace ?? ns.substring(with: m.range)
            out += escapeHTML ? escape(replacement) : replacement
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
