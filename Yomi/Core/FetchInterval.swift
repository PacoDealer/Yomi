import Foundation

/// When a library title is next expected to get a chapter — a port of Mihon's `FetchInterval`, `ReleaseSchedule` and
/// `ReleasePattern` (`tachiyomi.domain.manga.interactor`, Apache-2.0, mihonapp/mihon @446f6df, v0.21), same rules,
/// numbers and order. Its tests are ported too (`scripts/fetch-interval-tests`, run with `run.sh`).
///
/// The schedule is read from the most recent distinct release days (upload dates when the source gives at least
/// three, else the days a refresh first saw chapters): the interval is the median gap (1…28 days, 7 when there's too
/// little to go on), and a calendar pattern is used when one fits — a few fixed weekdays, a day or weekday of the
/// month, or releases in batches. Checks spread out during a hiatus. A refresh can then skip titles not expected to
/// update yet (Settings → Update Rules, S166). Pure Foundation so the test harness compiles it on macOS.
nonisolated enum FetchInterval {

    static let maxInterval = 28
    private static let gracePeriodDays = 1

    /// What the schedule reads from one chapter: when the source says it was uploaded, and when a refresh first saw it.
    struct ChapterDates {
        let uploaded: Date?
        let fetched: Date?
    }

    /// A title's stored schedule after a check.
    struct Update: Equatable {
        let nextUpdate: Date
        /// Days between releases; negative = set by the user and kept as is.
        let fetchInterval: Int
    }

    /// Mihon's `withFetchInterval`: the title's fetch interval and the next day to check it.
    /// - Parameters:
    ///   - fetchInterval: the stored one (0 = never worked out, negative = the user's own).
    ///   - lastUpdate: when the title's chapter list last changed — the anchor of a user-set interval.
    ///   - foundRelease: whether the check that led here found new chapters.
    static func update(fetchInterval: Int, nextUpdate: Date?, lastUpdate: Date?, chapters: [ChapterDates],
                       now: Date, calendar: Calendar, window: ClosedRange<Date>? = nil,
                       foundRelease: Bool = false) -> Update {
        let today = Day(now, calendar)
        let currentWindow = window ?? Self.window(today: today, calendar: calendar)
        let schedule: ReleaseSchedule
        if fetchInterval < 0 {
            // The check that found a release is the title's last update
            let last = foundRelease ? today : lastUpdate.map { Day($0, calendar) }
            schedule = .fixed(interval: -fetchInterval, lastRelease: last ?? today)
        } else {
            schedule = .estimate(chapters, calendar: calendar, today: today)
        }

        // A release on or after the expected day means the next one is counted from it instead
        let isAwaitingRelease = nextUpdate.map { expected in
            expected >= currentWindow.lowerBound && expected <= currentWindow.upperBound.addingTimeInterval(0.001)
                && (schedule.lastRelease.map { $0 < Day(expected, calendar) } ?? true)
        } ?? false
        let next: Date = if foundRelease {
            schedule.nextCheckAfterRelease(today: today).start(calendar)
        } else if isAwaitingRelease, let nextUpdate {
            nextUpdate
        } else {
            schedule.nextCheck(today: today).start(calendar)
        }
        return Update(nextUpdate: next, fetchInterval: fetchInterval < 0 ? fetchInterval : schedule.interval)
    }

    /// Mihon's `getWindow`: yesterday 00:00 to tomorrow 00:00. A title expected after its end isn't checked when
    /// "not expected to update" titles are skipped.
    static func window(today: Day, calendar: Calendar) -> ClosedRange<Date> {
        today.plus(-gracePeriodDays).start(calendar)...today.plus(gracePeriodDays).start(calendar)
    }

    static func window(now: Date, calendar: Calendar) -> ClosedRange<Date> {
        window(today: Day(now, calendar), calendar: calendar)
    }
}

// MARK: - Day

/// A calendar day with no time or time zone (kotlinx `LocalDate`), counted from 1970-01-01 (proleptic Gregorian).
nonisolated struct Day: Comparable, Hashable, CustomStringConvertible {
    let n: Int

    init(_ n: Int) { self.n = n }

    /// Howard Hinnant's `days_from_civil`.
    init(year: Int, month: Int, day: Int) {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        n = era * 146097 + doe - 719468
    }

    /// The day `date` falls on in `calendar`'s time zone.
    init(_ date: Date, _ calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// "2020-01-21".
    init?(_ iso: String) {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    /// Howard Hinnant's `civil_from_days`.
    var ymd: (year: Int, month: Int, day: Int) {
        let z = n + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
    }
    var day: Int { ymd.day }
    /// ISO day of the week, Monday = 1 … Sunday = 7 (1970-01-01 was a Thursday).
    var weekday: Int { floorMod(n + 3, 7) + 1 }
    var firstOfMonth: Day { let d = ymd; return Day(year: d.year, month: d.month, day: 1) }
    var lastOfMonth: Day { firstOfMonth.plusMonths(1).plus(-1) }

    func plus(_ days: Int) -> Day { Day(n + days) }
    func plusMonths(_ months: Int) -> Day {
        let d = ymd
        let total = d.year * 12 + (d.month - 1) + months
        return Day(year: floorDiv(total, 12), month: floorMod(total, 12) + 1, day: min(d.day, 28))
    }
    func daysUntil(_ other: Day) -> Int { other.n - n }
    /// 00:00 of this day in `calendar`'s time zone.
    func start(_ calendar: Calendar) -> Date {
        let d = ymd
        return calendar.date(from: DateComponents(year: d.year, month: d.month, day: d.day)) ?? Date(timeIntervalSince1970: 0)
    }

    static func < (a: Day, b: Day) -> Bool { a.n < b.n }
    var description: String { let d = ymd; return String(format: "%04d-%02d-%02d", d.year, d.month, d.day) }
}

/// Kotlin's `floorDiv` / `mod` (round toward negative infinity; Swift's `/` and `%` round toward zero).
nonisolated private func floorDiv(_ a: Int, _ b: Int) -> Int {
    let q = a / b
    return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
}
nonisolated private func floorMod(_ a: Int, _ b: Int) -> Int { a - floorDiv(a, b) * b }
nonisolated private func median(_ values: [Int]) -> Int { values.sorted()[(values.count - 1) / 2] }

// MARK: - ReleaseSchedule

/// How often a title releases, and so when to check it for the next release (Mihon's `ReleaseSchedule`).
nonisolated struct ReleaseSchedule {
    /// Days between releases, which is what the fetch interval shows.
    let interval: Int
    /// The most recent release day, which the next ones are counted from.
    let lastRelease: Day?
    let pattern: ReleasePattern
    /// Days past the expected day a release can still come, from how late recent ones were.
    var lateness = 0
    /// Whether checks spread out once releases stop coming, which a schedule set by the user doesn't.
    var backsOff = true
    /// Lengths in days of earlier breaks in releases, which a break like a season's end is expected to last again.
    var pastBreaks: [Int] = []

    private static let defaultInterval = 7
    private static let hiatusCycles = 4
    private static let minReleases = 3
    private static let fewChapters = 8
    private static let fewChaptersReleases = 3
    private static let recentReleases = 10
    private static let phaseReleases = 5

    /// The next day to check for a release, as of `today`. Today counts, so a due release keeps being checked for.
    func nextCheck(today: Day) -> Day {
        let anchor = lastRelease ?? today
        let daysSinceRelease = anchor.daysUntil(today)
        let isOnBreak = backsOff && daysSinceRelease > interval * Self.hiatusCycles
        // Around when earlier breaks ended, this one likely ends too, so the schedule is followed again
        if isOnBreak && !pastBreaks.contains(where: { ($0 - interval...$0 + interval).contains(daysSinceRelease) }) {
            // Past a few missed releases the schedule no longer holds, so checks spread out until it resumes
            let backedOff = backOff(daysSinceRelease)
            let next = anchor.plus(-floorDiv(-daysSinceRelease, backedOff) * backedOff)
            let breakEnd = pastBreaks.map { anchor.plus($0 - interval) }.filter { $0 > today }.min()
            return min(next, breakEnd ?? next)
        }

        let due = pattern.nextAfter(pattern.nearest(anchor))
        if today >= due && today <= due.plus(lateness) { return today }
        return capped(first(from: due) { $0 >= today }, from: today)
    }

    /// The next day to check after a check `today` found a release.
    ///
    /// The release is dated by its newest chapter, since a check can turn up one that came out on an earlier day. It
    /// stands in for the expected day nearest to it, so an early, late or extra release leaves the schedule in place.
    func nextCheckAfterRelease(today: Day) -> Day {
        let release = lastRelease.map { min($0, today) } ?? today
        // What was found is out already, so checking again today would only find it again
        let next = pattern.nextAfter(pattern.nearest(release))
        return capped(first(from: next) { $0 > today }, from: today)
    }

    /// The first expected day from `start` on (Kotlin's `generateSequence(start, nextAfter).first`).
    private func first(from start: Day, where accept: (Day) -> Bool) -> Day {
        var day = start
        while !accept(day) { day = pattern.nextAfter(day) }
        return day
    }

    // Months and batches can be further apart than a check should ever wait
    private func capped(_ day: Day, from today: Day) -> Day { min(day, today.plus(FetchInterval.maxInterval)) }

    private func backOff(_ daysSinceRelease: Int) -> Int {
        var backedOff = interval
        while backedOff < FetchInterval.maxInterval && daysSinceRelease > backedOff * Self.hiatusCycles {
            backedOff *= 2
        }
        return min(backedOff, FetchInterval.maxInterval)
    }

    /// A schedule the user set to every `interval` days, counted from `lastRelease`.
    static func fixed(interval: Int, lastRelease: Day) -> ReleaseSchedule {
        ReleaseSchedule(interval: interval, lastRelease: lastRelease,
                        pattern: .everyDays(interval, onSchedule: lastRelease), backsOff: false)
    }

    /// Estimates the schedule from the recent release days of `chapters`, by upload date or else fetch date.
    static func estimate(_ chapters: [FetchInterval.ChapterDates], calendar: Calendar, today: Day) -> ReleaseSchedule {
        let recent = chapters.count <= fewChapters ? fewChaptersReleases : recentReleases
        // Sources that date chapters ahead of their release would otherwise pull the schedule into the future
        let latestPlausibleDay = today.plus(1)
        func releaseDays(_ dates: [Date]) -> [Day] {
            Set(dates.map { Day($0, calendar) }.filter { $0 <= latestPlausibleDay }).sorted(by: >)
        }

        let uploadDays = releaseDays(chapters.compactMap(\.uploaded))
        let fetchDays = releaseDays(chapters.compactMap(\.fetched))
        let history: [Day]
        if uploadDays.count >= minReleases {
            history = uploadDays
        } else if fetchDays.count >= minReleases {
            history = fetchDays
        } else {
            let lastRelease = uploadDays.first ?? fetchDays.first
            return ReleaseSchedule(interval: defaultInterval, lastRelease: lastRelease,
                                   pattern: .everyDays(defaultInterval, onSchedule: lastRelease ?? today))
        }
        let days = Array(history.prefix(recent))

        let gaps = zip(days, days.dropFirst()).map { newer, older in older.daysUntil(newer) }.sorted()
        let medianGap = gaps[(gaps.count - 1) / 2]
        let detected = ReleasePattern.detect(days: days, history: history, medianGap: medianGap)
        // Within a batch releases are a day apart, but it's the batches that come every so often
        let batchEvery: Int? = if case .batches(let every, _, _) = detected { every } else { nil }
        let interval = min(max(batchEvery ?? medianGap, 1), FetchInterval.maxInterval)
        return ReleaseSchedule(
            interval: interval,
            lastRelease: days.first,
            pattern: detected
                ?? .everyDays(interval, onSchedule: medianPhase(Array(days.prefix(phaseReleases)), interval: interval)),
            lateness: min(max(gaps.last! - interval, 0), interval / 2),
            pastBreaks: zip(history, history.dropFirst()).map { newer, older in older.daysUntil(newer) }
                .filter { $0 > interval * hiatusCycles })
    }

    /// The release in `days`, newest first, that the others land closest to in step with `interval`, so one early
    /// or late release doesn't shift the schedule. Ties go to the newest, which follows a schedule that moved.
    private static func medianPhase(_ days: [Day], interval: Int) -> Day {
        func offset(_ from: Day, _ to: Day) -> Int {
            let m = floorMod(from.daysUntil(to), interval)
            return min(m, interval - m)
        }
        var phase = days[0], best = Int.max
        for candidate in days {
            let total = days.reduce(0) { $0 + offset(candidate, $1) }
            if total < best { best = total; phase = candidate }
        }
        let onPhase = days.filter { offset(phase, $0) == 0 }.count
        return onPhase * 5 >= days.count * 3 ? phase : days[0]
    }
}

// MARK: - ReleasePattern

/// The days a title is expected to release on (Mihon's `ReleasePattern`). Weekdays are ISO numbers, Monday = 1.
nonisolated enum ReleasePattern: Equatable {
    /// Releases every `days` days, in step with `onSchedule`.
    case everyDays(Int, onSchedule: Day)
    case weekdays(Set<Int>)
    /// Releases for `length` days in a row, every `every` days in step with `onSchedule`.
    case batches(every: Int, onSchedule: Day, length: Int)
    /// Releases on these days of every month, or a month's last day for those past it.
    case daysOfMonth(Set<Int>)
    /// Releases on `dayOfWeek` of the `week`th week of every month, or its last week for `lastWeek`.
    case weekdayOfMonth(week: Int, dayOfWeek: Int)

    static let lastWeek = -1

    /// The first expected release day after `date`.
    func nextAfter(_ date: Day) -> Day {
        switch self {
        case .everyDays(let days, let onSchedule):
            return date.plus(days - floorMod(onSchedule.daysUntil(date), days))
        case .weekdays(let set):
            var d = date.plus(1)
            while !set.contains(d.weekday) { d = d.plus(1) }
            return d
        case .batches(let every, let onSchedule, let length):
            let offset = floorMod(onSchedule.daysUntil(date), every)
            return date.plus(offset + 1 < length ? 1 : every - offset)
        case .daysOfMonth, .weekdayOfMonth:
            var month = date.firstOfMonth
            while true {
                if let d = daysIn(month).sorted().first(where: { $0 > date }) { return d }
                month = month.plusMonths(1)
            }
        }
    }

    /// The last expected release day before `date`.
    func previousBefore(_ date: Day) -> Day {
        switch self {
        case .everyDays(let days, let onSchedule):
            return date.plus(-(floorMod(onSchedule.daysUntil(date) - 1, days) + 1))
        case .weekdays(let set):
            var d = date.plus(-1)
            while !set.contains(d.weekday) { d = d.plus(-1) }
            return d
        case .batches(let every, let onSchedule, let length):
            let dayBefore = date.plus(-1)
            let offset = floorMod(onSchedule.daysUntil(dayBefore), every)
            return dayBefore.plus(-max(offset - length + 1, 0))
        case .daysOfMonth, .weekdayOfMonth:
            var month = date.firstOfMonth
            while true {
                if let d = daysIn(month).sorted(by: >).first(where: { $0 < date }) { return d }
                month = month.plusMonths(-1)
            }
        }
    }

    /// The expected release day closest to `date`, which a release on `date` stands in for.
    func nearest(_ date: Day) -> Day {
        // Release days are a day or two apart, so a release between them is more likely an extra than an early one
        if case .weekdays = self { return date }
        let before = previousBefore(date.plus(1))
        let after = nextAfter(date.plus(-1))
        // A release halfway between is taken as late, so the next check comes sooner
        return before.daysUntil(date) <= date.daysUntil(after) ? before : after
    }

    /// The release days of a monthly pattern in the month starting on `firstOfMonth`.
    private func daysIn(_ firstOfMonth: Day) -> [Day] {
        switch self {
        case .daysOfMonth(let days):
            let lastDay = firstOfMonth.lastOfMonth.day
            return Array(Set(days.map { firstOfMonth.plus(min($0, lastDay) - 1) }))
        case .weekdayOfMonth(let week, let dayOfWeek):
            if week == Self.lastWeek {
                let lastOfMonth = firstOfMonth.lastOfMonth
                return [lastOfMonth.plus(-floorMod(lastOfMonth.weekday - dayOfWeek, 7))]
            }
            let daysAhead = floorMod(dayOfWeek - firstOfMonth.weekday, 7)
            return [firstOfMonth.plus(daysAhead + (week - 1) * 7)]
        default:
            return []
        }
    }

    private static let minReleases = 4
    private static let maxWeekdays = 3
    private static let coverage = 0.8
    private static let dayOfMonthTolerance = 3
    private static let monthlyGaps = 26...35
    private static let twiceMonthlyGaps = 12...18
    private static let batchHistory = 40
    private static let batchGap = 2
    private static let batchCount = 6
    private static let minBatches = 3

    /// Finds a calendar pattern a plain day interval can't follow in `days`, newest first: a few fixed weekdays, days
    /// or a weekday of the month, or releases in batches, which can take longer than `days` to show up in `history`.
    /// They all need a few releases to be told apart from chance.
    static func detect(days: [Day], history: [Day], medianGap: Int) -> ReleasePattern? {
        guard days.count >= minReleases else { return nil }
        // Batches come first, since their days can look like a few weekdays or a monthly schedule
        if let batches = batches(history) { return batches }
        if monthlyGaps.contains(medianGap) { return monthly(days) }
        if twiceMonthlyGaps.contains(medianGap) { return twiceMonthly(days) }
        return weekdays(days, medianGap: medianGap)
    }

    private static func monthly(_ days: [Day]) -> ReleasePattern? {
        let daysOfMonth = days.map(\.day)
        if daysOfMonth.max()! - daysOfMonth.min()! <= dayOfMonthTolerance { return .daysOfMonth([median(daysOfMonth)]) }
        // The last day of the month moves between the 28th and the 31st
        if daysOfMonth.allSatisfy({ $0 >= 28 }) { return .daysOfMonth([31]) }
        return weekdayOfMonth(days)
    }

    private static func weekdayOfMonth(_ days: [Day]) -> ReleasePattern? {
        guard let dayOfWeek = mostCommon(days, \.weekday) else { return nil }
        // A fifth week isn't in every month, so those days only count as the last week
        if let week = mostCommon(days, { ($0.day - 1) / 7 + 1 }), week < 5 {
            return .weekdayOfMonth(week: week, dayOfWeek: dayOfWeek)
        }
        let isLastWeek = Double(days.filter { $0.day + 7 > $0.lastOfMonth.day }.count) >= Double(days.count) * coverage
        return isLastWeek ? .weekdayOfMonth(week: lastWeek, dayOfWeek: dayOfWeek) : nil
    }

    private static func twiceMonthly(_ days: [Day]) -> ReleasePattern? {
        let daysOfMonth = days.map(\.day).sorted()
        var split = 1
        for i in 1..<daysOfMonth.count where daysOfMonth[i] - daysOfMonth[i - 1] > daysOfMonth[split] - daysOfMonth[split - 1] {
            split = i
        }
        let halves = [Array(daysOfMonth[..<split]), Array(daysOfMonth[split...])]
        if halves.contains(where: { $0.count < 2 || $0.last! - $0.first! > dayOfMonthTolerance }) { return nil }
        return .daysOfMonth(Set(halves.map(median)))
    }

    private static func weekdays(_ days: [Day], medianGap: Int) -> ReleasePattern? {
        // Kotlin's groupingBy keeps first-seen order and sortedByDescending is stable, so ties stay in that order
        var order: [Int] = [], counts: [Int: Int] = [:]
        for day in days {
            if counts[day.weekday] == nil { order.append(day.weekday) }
            counts[day.weekday, default: 0] += 1
        }
        let byFrequency = order.enumerated()
            .sorted { a, b in counts[a.element]! != counts[b.element]! ? counts[a.element]! > counts[b.element]! : a.offset < b.offset }
            .map(\.element)
        var weekdays = Set<Int>()
        var covered = 0
        let needed = Double(days.count) * coverage
        for dayOfWeek in byFrequency {
            if Double(covered) >= needed { break }
            weekdays.insert(dayOfWeek)
            covered += counts[dayOfWeek]!
        }
        // One weekday is a weekly interval, and an irregular schedule spreads over most of the week
        if !(2...maxWeekdays).contains(weekdays.count) || Double(covered) < needed { return nil }
        // Releasing on several weekdays means more than one release a week
        if medianGap > 7 / weekdays.count + 1 { return nil }
        return .weekdays(weekdays)
    }

    /// Runs of releases a day or two apart, starting at a steady interval and mostly longer than a day.
    private static func batches(_ history: [Day]) -> ReleasePattern? {
        var runs: [[Day]] = []
        for day in history.prefix(batchHistory).reversed() {
            if let last = runs.last?.last, last.daysUntil(day) <= batchGap {
                runs[runs.count - 1].append(day)
            } else {
                runs.append([day])
            }
        }
        let recent = Array(runs.suffix(batchCount))
        if recent.count < minBatches || recent.filter({ $0.count > 1 }).count * 2 < recent.count { return nil }

        let gaps = zip(recent, recent.dropFirst()).map { older, newer in older[0].daysUntil(newer[0]) }
        let every = median(gaps)
        let length = median(recent.map { $0[0].daysUntil($0[$0.count - 1]) + 1 })
        if every < length * 2 || gaps.contains(where: { abs($0 - every) > every / 4 }) { return nil }
        return .batches(every: every, onSchedule: recent[recent.count - 1][0], length: length)
    }

    /// The most common key of `selector`, if at least `coverage` of the days share it. Ties go to the first seen
    /// (Kotlin's `maxBy` over a `groupingBy` map).
    private static func mostCommon(_ days: [Day], _ selector: (Day) -> Int) -> Int? {
        var order: [Int] = [], counts: [Int: Int] = [:]
        for day in days {
            let key = selector(day)
            if counts[key] == nil { order.append(key) }
            counts[key, default: 0] += 1
        }
        var best = order[0]
        for key in order where counts[key]! > counts[best]! { best = key }
        return Double(counts[best]!) >= Double(days.count) * coverage ? best : nil
    }
}
