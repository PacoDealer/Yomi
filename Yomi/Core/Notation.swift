import Foundation

// MARK: - Notation
//
// Catalog-style formatters for all machine/metadata text.
// All output is intended to be rendered in Space Mono (YomiTokens.Font.mono).
// Human-authored text (titles, author, synopsis) stays in Space Grotesk.
// See DESIGN_SYSTEM §6.

enum Notation {

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
}
