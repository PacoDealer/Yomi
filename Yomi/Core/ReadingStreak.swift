import Foundation

// MARK: - Reading streak + repair (L4, RESEARCH §25.10 #9)
//
// The streak = days in a row with at least one chapter read, ending today (or yesterday, so it doesn't drop to 0
// before you've read today). Silverman & Barasch 2023 (J. Consumer Research 49(6)): people keep going after a broken
// streak far more often when they can repair it. So a short break can be repaired — quietly, from Insights, no
// notifications, no cost:
// - the break is 1 or 2 missed days, right before the current run (or right before today/yesterday),
// - the streak it broke was at least 2 days long,
// - one repair a week: none if a day was repaired in the 7 days before the break.
// Repaired days count as streak days (and show outlined in the heatmap). They're kept in `AppSettings
// .streakRepairedDays` as "yyyy-MM-dd" — device-only, not in backups or sync. Pure Foundation, tested on the Mac by
// `scripts/streak-tests/run.sh`.

nonisolated enum ReadingStreak {
    static let maxGap = 2
    static let minLostStreak = 2
    static let repairEvery = 7

    struct Offer: Equatable {
        /// Length of the streak the break ended (repaired days included).
        let lostStreak: Int
        /// The missed days a repair fills, newest first.
        let missedDays: [Date]
    }

    struct Result: Equatable {
        let streak: Int
        let offer: Offer?
    }

    static func key(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// `readDays` / `repairedDays` are `key(_:calendar:)` strings.
    static func compute(readDays: Set<String>, repairedDays: Set<String>, today: Date,
                        calendar: Calendar = .current) -> Result {
        let active = readDays.union(repairedDays)
        let todayStart = calendar.startOfDay(for: today)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: -offset, to: todayStart)! }
        func isActive(_ offset: Int) -> Bool { active.contains(key(day(offset), calendar: calendar)) }

        // Current run, ending today or (not read yet today) yesterday.
        let start = isActive(0) ? 0 : 1
        var streak = 0
        while isActive(start + streak) { streak += 1 }

        // The break just before it.
        var gap: [Int] = []
        var offset = start + streak
        while !isActive(offset) && gap.count <= maxGap {
            gap.append(offset)
            offset += 1
        }
        guard !gap.isEmpty, gap.count <= maxGap else { return Result(streak: streak, offer: nil) }

        var lost = 0
        while isActive(offset + lost) { lost += 1 }
        guard lost >= minLostStreak else { return Result(streak: streak, offer: nil) }

        // One repair a week.
        let breakStart = day(gap.last!)
        let recentRepair = repairedDays.contains { repaired in
            guard let date = date(fromKey: repaired, calendar: calendar) else { return false }
            let days = calendar.dateComponents([.day], from: date, to: breakStart).day ?? .max
            return days >= 0 && days <= repairEvery
        }
        guard !recentRepair else { return Result(streak: streak, offer: nil) }

        return Result(streak: streak, offer: Offer(lostStreak: lost, missedDays: gap.map(day)))
    }

    static func date(fromKey key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
