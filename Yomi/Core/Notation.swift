import Foundation

// MARK: - Notation
//
// Catalog-style formatters for all machine/metadata text.
// All output is intended to be rendered in Space Mono (YomiTokens.Font.mono).
// Human-authored text (titles, author, synopsis) stays in Space Grotesk.
// See DESIGN_SYSTEM §6.

nonisolated enum Notation {

    // MARK: - Chapter

    /// "CH. 042" — zero-padded to 3 digits.
    static func chapter(_ number: Double) -> String {
        let isWhole = number.truncatingRemainder(dividingBy: 1) == 0
        if isWhole {
            return String(format: "CH. %03d", Int(number))
        } else {
            return String(format: "CH. %05.1f", number)
        }
    }

    /// "VOL. 03 / CH. 027"
    static func volumeChapter(volume: Int, chapter: Double) -> String {
        "VOL. \(String(format: "%02d", volume)) / \(Notation.chapter(chapter))"
    }

    /// "CH. 042 · read to 68%" — in-progress chapter, for History rows.
    static func chapterReadTo(chapter: Double, fraction: Double) -> String {
        "\(Notation.chapter(chapter)) · read to \(Notation.progress(fraction))"
    }

    /// "CH. 042" for a single chapter, "CH. 042–044" for a span — used for Updates feed rows.
    static func chapterRange(low: Double, high: Double) -> String {
        guard low != high else { return Notation.chapter(low) }
        let highIsWhole = high.truncatingRemainder(dividingBy: 1) == 0
        let highStr = highIsWhole ? String(format: "%03d", Int(high)) : String(format: "%05.1f", high)
        return "\(Notation.chapter(low))–\(highStr)"
    }

    // MARK: - Progress

    /// "68%" — accent is applied at the call site, not here.
    static func progress(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    // MARK: - Reading time

    /// "◷ 12H 40M" for ≥60 min; "◷ 45M" for <60 min; "" for 0.
    static func readingTime(seconds: Int) -> String {
        guard seconds > 0 else { return "" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return String(format: "◷ %dH %02dM", hours, minutes)
        } else {
            return String(format: "◷ %dM", max(1, minutes))
        }
    }

    /// Short form: "12H" only, for Continue hero card.
    static func readingTimeShort(seconds: Int) -> String {
        guard seconds > 0 else { return "" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return String(format: "◷ %dH", hours)
        } else {
            return String(format: "◷ %dM", max(1, minutes))
        }
    }

    // MARK: - Chapter + progress compound (for Continue hero)

    /// "CH. 042 · 68% · ◷ 12H 40M"
    static func chapterProgress(chapter: Double, fraction: Double, seconds: Int) -> String {
        var parts: [String] = [Notation.chapter(chapter), Notation.progress(fraction)]
        let time = Notation.readingTime(seconds: seconds)
        if !time.isEmpty { parts.append(time) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Page position (manga reader chrome)

    /// "CH. 042 · 12/48"
    static func pagePosition(chapter: Double, page: Int, total: Int) -> String {
        "\(Notation.chapter(chapter)) · \(page)/\(total)"
    }

    // MARK: - Status

    /// "STATUS // ONGOING" — uppercase, monospace catalog label.
    static func status(_ raw: String) -> String {
        "STATUS // \(raw.uppercased())"
    }

    // MARK: - Catalog index

    /// "N.07" — novel catalog index.
    static func novelIndex(_ n: Int) -> String {
        String(format: "N.%02d", n)
    }

    /// "07" — manga catalog index (plain zero-padded number).
    static func catalogIndex(_ n: Int) -> String {
        String(format: "%02d", n)
    }

    // MARK: - Chapter + page footer (novel reader)

    /// "CH. 027 · 64%"
    static func novelFooter(chapter: Double, fraction: Double) -> String {
        "\(Notation.chapter(chapter)) · \(Notation.progress(fraction))"
    }

    // MARK: - History timestamp (adaptive)

    /// "14:20" today, "MON" within the last week, "JUL 28" otherwise — for History rows.
    static func historyTimestamp(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            return f.string(from: date)
        }
        let days = cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: date),
            to: cal.startOfDay(for: Date())
        ).day ?? 0
        if days < 7 {
            let f = DateFormatter(); f.dateFormat = "EEE"
            return f.string(from: date).uppercased()
        }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: date).uppercased()
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
