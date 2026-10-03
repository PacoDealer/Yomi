import Foundation

// MARK: - Notation
//
// Formatters for metadata text (chapters, progress, reading time, dates).
// S138 "calm" design: plain sentence-case text in the system font — no catalog
// caps ("CH. 042", "STATUS // ONGOING"); see RESEARCH §26.

nonisolated enum Notation {

    // MARK: - Chapter

    /// "Chapter 42" / "Chapter 42.5".
    static func chapter(_ number: Double) -> String {
        "Chapter \(number.formatted(.number.precision(.fractionLength(0...1))))"
    }

    /// A source's chapter name for display: bare "Ch. 31" / "31" / "chapter 31" become "Chapter 31"; real
    /// titles ("Chapter 702 - The Sect") are left as the source wrote them.
    static func chapterTitle(_ name: String, number: Double?) -> String {
        guard let number,
              name.trimmingCharacters(in: .whitespaces)
                .wholeMatch(of: /(?i)(ch(apter)?\.?\s*)?\d+(\.\d+)?/) != nil else { return name }
        return chapter(number)
    }

    /// Source text with the HTML entities some plugins leave in ("&lt;The Regressed…&gt;").
    static func plainText(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = text
        for (entity, char) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"),
                               ("&apos;", "'"), ("&nbsp;", " "), ("&amp;", "&")] {
            out = out.replacingOccurrences(of: entity, with: char)
        }
        return out.replacing(/&#(\d+);/) { match in
            UInt32(match.1).flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? String(match.0)
        }
    }

    /// "Chapter 42 · read to 68%" — in-progress chapter, for History rows.
    static func chapterReadTo(chapter: Double, fraction: Double) -> String {
        "\(Notation.chapter(chapter)) · read to \(Notation.progress(fraction))"
    }

    /// "Chapter 42" for a single chapter, "Chapters 42–44" for a span — used for Updates feed rows.
    static func chapterRange(low: Double, high: Double) -> String {
        guard low != high else { return Notation.chapter(low) }
        let f: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(0...1))) }
        return "Chapters \(f(low))–\(f(high))"
    }

    // MARK: - Progress

    /// "68%" — accent is applied at the call site, not here.
    static func progress(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    // MARK: - Reading time

    /// "12h 40m" for ≥60 min; "45m" for <60 min; "" for 0.
    static func readingTime(seconds: Int) -> String {
        guard seconds > 0 else { return "" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(max(1, minutes))m"
        }
    }

    /// Short form: "12h" only.
    static func readingTimeShort(seconds: Int) -> String {
        guard seconds > 0 else { return "" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours)h" : "\(max(1, minutes))m"
    }

    // MARK: - Chapter + progress compound (for Continue hero)

    /// "Chapter 42 · 68% · 12h 40m"
    static func chapterProgress(chapter: Double, fraction: Double, seconds: Int) -> String {
        var parts: [String] = [Notation.chapter(chapter), Notation.progress(fraction)]
        let time = Notation.readingTime(seconds: seconds)
        if !time.isEmpty { parts.append(time) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Page position (manga reader chrome)

    /// "Chapter 42 · 12/48"
    static func pagePosition(chapter: Double, page: Int, total: Int) -> String {
        "\(Notation.chapter(chapter)) · \(page)/\(total)"
    }

    // MARK: - Status

    /// "Ongoing" — capitalized status word.
    static func status(_ raw: String) -> String {
        raw.prefix(1).uppercased() + raw.dropFirst().lowercased()
    }

    // MARK: - History timestamp (adaptive)

    /// "14:20"/"2:20 PM" today, "Mon" within the last week, "Jul 28"/"28 Jul" otherwise — for
    /// History rows. `use24Hour`/`dayFirst` default to the app's original hardcoded format
    /// (24-hour clock, month-before-day) so existing callers are unaffected.
    static func historyTimestamp(_ date: Date, use24Hour: Bool = true, dayFirst: Bool = false) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let f = DateFormatter(); f.dateFormat = use24Hour ? "HH:mm" : "h:mm a"
            return f.string(from: date)
        }
        let days = cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: date),
            to: cal.startOfDay(for: Date())
        ).day ?? 0
        if days < 7 {
            let f = DateFormatter(); f.dateFormat = "EEE"
            return f.string(from: date)
        }
        let f = DateFormatter(); f.dateFormat = dayFirst ? "d MMM" : "MMM d"
        return f.string(from: date)
    }

    // MARK: - Date group label (History / Updates section headers)

    static let dateGroupOrder = ["Today", "Yesterday", "This week", "This month", "Earlier"]

    /// "Today" / "Yesterday" / "This week" / "This month" / "Earlier" bucket label.
    static func dateGroupLabel(for date: Date?, calendar: Calendar = .current, now: Date = Date()) -> String {
        guard let date else { return "Earlier" }
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        if days < 7  { return "This week" }
        if days < 30 { return "This month" }
        return "Earlier"
    }
}
