import Foundation

// Port of Mihon's FetchIntervalTest.kt (Apache-2.0, mihonapp/mihon @446f6df, v0.21), every case in its order, plus
// Yomi's own cases at the end. Run: ./run.sh

typealias C = FetchInterval.ChapterDates
var failures = 0
var checks = 0

func expect(_ test: String, _ got: Any, _ want: Any) {
    checks += 1
    guard String(describing: got) != String(describing: want) else { return }
    failures += 1
    print("FAIL \(test): got \(got), want \(want)")
}

var utc = Calendar(identifier: .gregorian)
utc.timeZone = TimeZone(identifier: "UTC")!
let testTime = ISO8601DateFormatter().date(from: "2020-01-01T00:00:00Z")!
let hour: TimeInterval = 3600
let day: TimeInterval = 86400
func d(_ s: String) -> Day { Day(s)! }

/// Mihon's `chapterWithTime`: fetched and uploaded at testTime + duration.
func chapterWithTime(_ duration: TimeInterval) -> C {
    let t = testTime.addingTimeInterval(duration)
    return C(uploaded: t, fetched: t)
}
func withoutUploadDate(_ chapters: [C]) -> [C] { chapters.map { C(uploaded: nil, fetched: $0.fetched) } }
func lastUploadDate(_ chapters: [C]) -> TimeInterval { chapters.last!.uploaded!.timeIntervalSince(testTime) }
func interval(_ chapters: [C]) -> Int {
    ReleaseSchedule.estimate(chapters, calendar: utc, today: Day(Date(), utc)).interval
}
/// Chapters released at noon on each of `days`, `perDay` of them.
func chaptersOn(_ days: [Day], perDay: Int = 1) -> [C] {
    days.flatMap { day in
        let time = day.start(utc).addingTimeInterval(12 * hour)
        return Array(repeating: C(uploaded: time, fetched: time), count: perDay)
    }
}
func every(days: Int, from: String, to: String) -> [Day] {
    stride(from: d(from).n, through: d(to).n, by: days).map(Day.init)
}
func weekly(from: String, to: String) -> [Day] { every(days: 7, from: from, to: to) }
func afterGaps(_ from: String, _ gaps: Int...) -> [Day] {
    gaps.reduce([d(from)]) { $0 + [$0.last!.plus($1)] }
}
/// Mihon's `nextUpdate` helper: checked at 10:00 on `today`, the title expecting `expecting` (its stored next update).
func nextUpdate(today: String, _ chapters: [C], expecting: String? = nil, fetchInterval: Int = 0,
                foundRelease: Bool = false) -> Day {
    let date = d(today)
    let update = FetchInterval.update(
        fetchInterval: fetchInterval, nextUpdate: expecting.map { d($0).start(utc) }, lastUpdate: nil,
        chapters: chapters, now: date.start(utc).addingTimeInterval(10 * hour), calendar: utc,
        window: FetchInterval.window(today: date, calendar: utc), foundRelease: foundRelease)
    return Day(update.nextUpdate, utc)
}

do { // returns default interval of 7 days when not enough distinct days
    let withUpload = (1...50).map { _ in chapterWithTime(1 * day) }
    expect("default 7 when not enough distinct days", interval(withUpload), 7)
    expect("default 7 when not enough distinct days (no upload date)", interval(withoutUploadDate(withUpload)), 7)
}
do { // returns interval based on more recent chapters
    let old = (1...5).map { chapterWithTime(Double($0 * 7) * day) }   // would have interval of 7 days
    let new = (1...10).map { chapterWithTime(lastUploadDate(old) + Double($0) * day) }
    expect("interval from the more recent chapters", interval(old + new), 1)
}
do { // returns interval based on smaller subset of recent chapters if very few chapters
    let old = (1...3).map { chapterWithTime(Double($0 * 7) * day) }
    // Significant gap between chapters
    let new = (1...3).map { chapterWithTime(lastUploadDate(old) + 365 * day + Double($0 * 7) * day) }
    expect("smaller window when very few chapters", interval(old + new), 7)
}
expect("7 when multiple chapters in 1 day", interval((1...10).map { _ in chapterWithTime(10 * hour) }), 7)
expect("7 when multiple chapters in 2 days",
       interval((1...2).map { _ in chapterWithTime(1 * day) } + (1...5).map { _ in chapterWithTime(2 * day) }), 7)
expect("1 when released every day", interval((1...20).map { chapterWithTime(Double($0) * day) }), 1)
expect("1 when delta is less than 1 day", interval((1...20).map { chapterWithTime(Double(15 * $0) * hour) }), 1)
expect("2 when released every 2 days", interval((1...20).map { chapterWithTime(Double(2 * $0) * day) }), 2)
do { // returns interval with floored value when interval is decimal
    let withUpload = (1...5).map { chapterWithTime(Double(25 * $0) * hour) }
    expect("floored when decimal", interval(withUpload), 1)
    expect("floored when decimal (no upload date)", interval(withoutUploadDate(withUpload)), 1)
}
expect("2 when released just below every 2 days", interval((1...20).map { chapterWithTime(Double(43 * $0) * hour) }), 2)

do { // follows releases on a few fixed weekdays
    let mondaysAndThursdays = (d("2019-12-02").n...d("2020-01-20").n).map(Day.init)
        .filter { $0.weekday == 1 || $0.weekday == 4 }
    let chapters = chaptersOn(mondaysAndThursdays)
    expect("weekdays: pattern", ReleaseSchedule.estimate(chapters, calendar: utc, today: d("2020-01-21")).pattern
           == .weekdays([1, 4]), true)
    expect("weekdays: next", nextUpdate(today: "2020-01-21", chapters), d("2020-01-23"))
}
expect("day of the month", nextUpdate(today: "2020-01-20", chaptersOn(
    ["2019-09-15", "2019-10-15", "2019-11-14", "2019-12-15", "2020-01-16"].map(d), perDay: 2)), d("2020-02-15"))
expect("last day of the month", nextUpdate(today: "2020-02-05", chaptersOn(
    ["2019-09-30", "2019-10-31", "2019-11-30", "2019-12-31", "2020-01-31"].map(d), perDay: 2)), d("2020-02-29"))
do { // follows releases on two days of the month
    let days = ["2019-10-01", "2019-10-15", "2019-11-01", "2019-11-16", "2019-12-01", "2019-12-15", "2020-01-01"]
    let chapters = chaptersOn((days + ["2020-01-15"]).map(d), perDay: 2)
    expect("two days of the month: pattern",
           ReleaseSchedule.estimate(chapters, calendar: utc, today: d("2020-01-20")).pattern == .daysOfMonth([1, 15]), true)
    expect("two days of the month: next", nextUpdate(today: "2020-01-20", chapters), d("2020-02-01"))
}
expect("weekday of the month", nextUpdate(today: "2020-01-10", chaptersOn(
    ["2019-09-07", "2019-10-05", "2019-11-02", "2019-12-07", "2020-01-04"].map(d), perDay: 2)), d("2020-02-01"))
expect("weekday of the last week", nextUpdate(today: "2020-02-03", chaptersOn(
    ["2019-09-27", "2019-10-25", "2019-11-29", "2019-12-27", "2020-01-31"].map(d), perDay: 2)), d("2020-02-28"))
do { // follows releases in batches: three days of releases every three weeks
    let batches = every(days: 21, from: "2019-09-02", to: "2019-12-16").flatMap { start in (0...2).map { start.plus($0) } }
    expect("batches: next day inside a batch",
           nextUpdate(today: "2019-12-17", chaptersOn(batches.filter { $0 <= d("2019-12-17") }), foundRelease: true),
           d("2019-12-18"))
    expect("batches: next batch", nextUpdate(today: "2019-12-18", chaptersOn(batches), foundRelease: true), d("2020-01-06"))
}
do { // checks again around when an earlier break ended: a season, a 98 day break, another season
    let chapters = chaptersOn(weekly(from: "2019-01-02", to: "2019-03-27") + weekly(from: "2019-07-03", to: "2019-09-25"))
    expect("earlier break: before", nextUpdate(today: "2019-12-20", chapters), d("2019-12-25"))
    expect("earlier break: after", nextUpdate(today: "2019-12-26", chapters), d("2020-01-01"))
}
expect("never waits more than 28 days", nextUpdate(today: "2020-01-31", chaptersOn(
    ["2019-09-30", "2019-10-31", "2019-11-30", "2019-12-31", "2020-01-31"].map(d), perDay: 2), foundRelease: true),
       d("2020-02-28"))
expect("keeps checking on the expected day",
       nextUpdate(today: "2020-01-01", chaptersOn(weekly(from: "2019-12-04", to: "2019-12-25"))), d("2020-01-01"))
expect("keeps a next update in the window while nothing new came out",
       nextUpdate(today: "2020-01-02", chaptersOn(weekly(from: "2019-12-04", to: "2019-12-25")), expecting: "2020-01-01"),
       d("2020-01-01"))
expect("counts from a release on the expected day",
       nextUpdate(today: "2020-01-01", chaptersOn(weekly(from: "2019-12-04", to: "2020-01-01")), expecting: "2020-01-01"),
       d("2020-01-08"))
expect("release uploaded the day before it was found", nextUpdate(
    today: "2020-01-01", chaptersOn(weekly(from: "2019-10-02", to: "2019-12-25") + [d("2019-12-31")]),
    expecting: "2020-01-01", foundRelease: true), d("2020-01-08"))
expect("release shortly before the expected day", nextUpdate(
    today: "2019-12-30", chaptersOn(weekly(from: "2019-10-02", to: "2019-12-25") + [d("2019-12-30")]),
    expecting: "2020-01-01", foundRelease: true), d("2020-01-08"))
expect("late release", nextUpdate(
    today: "2020-01-03", chaptersOn(weekly(from: "2019-12-04", to: "2019-12-25") + [d("2020-01-03")]),
    expecting: "2020-01-01", foundRelease: true), d("2020-01-08"))
expect("extra release well before the expected one", nextUpdate(
    today: "2020-01-02", chaptersOn(weekly(from: "2019-10-02", to: "2020-01-01") + [d("2020-01-02")]),
    expecting: "2020-01-08", foundRelease: true), d("2020-01-08"))
expect("schedule again after a hiatus", nextUpdate(
    today: "2020-01-01", chaptersOn(weekly(from: "2019-09-11", to: "2019-10-02") + [d("2020-01-01")]),
    expecting: "2020-01-22", foundRelease: true), d("2020-01-08"))
do { // follows the schedule once releases keep coming early
    let history = every(days: 5, from: "2019-10-01", to: "2019-12-15")
    let chapters = chaptersOn(history + every(days: 5, from: "2019-12-19", to: "2019-12-29"))
    expect("releases keep coming early",
           nextUpdate(today: "2019-12-29", chapters, expecting: "2019-12-30", foundRelease: true), d("2020-01-03"))
}
// Due on the 18th from a median gap of 6, and gaps have run to 8
expect("overdue while recent ones came that late", nextUpdate(
    today: "2019-12-20", chaptersOn(afterGaps("2019-10-18", 6, 5, 8, 6, 5, 6, 8, 6, 5)), expecting: "2019-12-18"),
       d("2019-12-20"))
expect("custom interval counts from an early release",
       nextUpdate(today: "2019-12-31", [], expecting: "2020-01-01", fetchInterval: -7, foundRelease: true),
       d("2020-01-07"))
expect("spreads out checks during a hiatus",
       nextUpdate(today: "2020-01-01", chaptersOn(weekly(from: "2019-09-11", to: "2019-10-02"))), d("2020-01-22"))
expect("ignores chapters dated in the future", nextUpdate(
    today: "2020-01-01", chaptersOn(weekly(from: "2019-12-04", to: "2019-12-25") + [d("2020-06-01")])), d("2020-01-01"))

// MARK: - Yomi

expect("Yomi: no dates at all → 7", interval((1...30).map { _ in C(uploaded: nil, fetched: nil) }), 7)
expect("Yomi: capped at 28", interval((1...5).map { chapterWithTime(Double(60 * $0) * day) }), 28)
expect("Yomi: chapters in any order", interval((1...20).reversed().map { chapterWithTime(Double(3 * $0) * day) }), 3)
expect("Yomi: fetch dates when upload dates are missing",
       interval((1...10).map { C(uploaded: nil, fetched: testTime.addingTimeInterval(Double(4 * $0) * day)) }), 4)
// Mihon's cases pass with the upper median or a 9-day window too; these two don't (mutation-checked, S166).
expect("Yomi: even count of gaps takes the lower median (gaps 6, 2 → 2)",
       interval([0, 2, 8].map { chapterWithTime(Double($0) * day) }), 2)
do { // newest-first gaps 1,1,1,1 then 5s: 10 release days → 9 gaps, median 5 (9 days → 8 gaps would give 1)
    let gaps = [1, 1, 1, 1, 5, 5, 5, 5, 5, 5, 5]
    var t = 200
    let days = [t] + gaps.map { t -= $0; return t }
    expect("Yomi: 10 release days for longer lists", interval(days.map { chapterWithTime(Double($0) * day) }), 5)
}
// Three rules no Mihon case pins (each survived a mutation, S166); expectations worked out by hand from the Kotlin.
// 30 quiet days on a weekly schedule is past 4 cycles: back off to every 14 days → 3 × 14 after the last release.
expect("Yomi: a break starts after 4 missed cycles",
       nextUpdate(today: "2019-11-01", chaptersOn(weekly(from: "2019-09-11", to: "2019-10-02"))), d("2019-11-13"))
// Every 6 days, then an extra release exactly halfway (12-28): taken as late for 12-25, so the next is 12-31.
expect("Yomi: a release halfway between is taken as late", nextUpdate(
    today: "2019-12-28", chaptersOn(every(days: 6, from: "2019-11-01", to: "2019-12-25") + [d("2019-12-28")]),
    foundRelease: true), d("2019-12-31"))
// Mondays and Thursdays plus a Sunday extra: the Sunday stays itself (not Monday's early release) → next is Monday.
expect("Yomi: weekday releases aren't moved to the nearest weekday", nextUpdate(
    today: "2020-01-26", chaptersOn((d("2019-12-02").n...d("2020-01-23").n).map(Day.init)
        .filter { $0.weekday == 1 || $0.weekday == 4 } + [d("2020-01-26")]), foundRelease: true), d("2020-01-27"))
// Day arithmetic the port leans on instead of kotlinx-datetime.
expect("Yomi: Day round trip", d("2020-02-29").description, "2020-02-29")
expect("Yomi: Day weekday (2020-01-01 was a Wednesday)", d("2020-01-01").weekday, 3)
expect("Yomi: last of February in a leap year", d("2020-02-10").lastOfMonth, d("2020-02-29"))
expect("Yomi: month back across a year", d("2020-01-01").plusMonths(-1), d("2019-12-01"))
expect("Yomi: Day from a Date in another zone", Day(testTime, { var c = utc; c.timeZone = TimeZone(identifier: "America/Argentina/Buenos_Aires")!; return c }()), d("2019-12-31"))
// The window is yesterday 00:00 … tomorrow 00:00, both included.
let w = FetchInterval.window(today: d("2020-01-01"), calendar: utc)
expect("Yomi: window", "\(Day(w.lowerBound, utc))…\(Day(w.upperBound, utc))", "2019-12-31…2020-01-02")
expect("Yomi: never checked keeps a weekly title due a week after its last release",
       nextUpdate(today: "2019-12-27", chaptersOn(weekly(from: "2019-11-06", to: "2019-12-25"))), d("2020-01-01"))

print(failures == 0 ? "OK \(checks) checks" : "\(failures) of \(checks) checks FAILED")
exit(failures == 0 ? 0 : 1)
