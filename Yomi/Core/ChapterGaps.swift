import Foundation

/// "N chapters missing" between neighbouring chapters in a title's list (A15 #32, S212) — Mihon's
/// `calculateChapterGap`: both numbers known (≥ 0), whole chapters only (12.5 counts as 12), so 10 → 13 is 2 missing
/// and 12 → 12.5 or two translations of 12 are none. Works in either list order.
nonisolated enum ChapterGaps {
    static func missing(between a: Double?, and b: Double?) -> Int {
        guard let a, let b, a >= 0, b >= 0, a.isFinite, b.isFinite else { return 0 }
        let higher = max(a, b).rounded(.down), lower = min(a, b).rounded(.down)
        return max(0, Int(higher - lower) - 1)
    }

    /// For each position in `numbers` (list order), the chapters missing before the next entry; positions with no gap
    /// are left out. Chapters without a number are skipped over, not counted as a gap or a bridge.
    static func after(_ numbers: [Double?]) -> [Int: Int] {
        var out: [Int: Int] = [:]
        var last: (index: Int, number: Double)?
        for (i, n) in numbers.enumerated() {
            guard let n, n >= 0 else { continue }
            if let last {
                let gap = missing(between: last.number, and: n)
                if gap > 0 { out[last.index] = gap }
            }
            last = (i, n)
        }
        return out
    }
}
