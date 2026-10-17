import Foundation

// Streak + repair cases. "Today" is Fri 2026-10-16; days are given as offsets back from today (0 = today).
var failures = 0
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "UTC")!
let today = cal.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 15))!
func keys(_ offsets: [Int]) -> Set<String> {
    Set(offsets.map { ReadingStreak.key(cal.date(byAdding: .day, value: -$0, to: today)!, calendar: cal) })
}
func run(_ name: String, read: [Int], repaired: [Int] = [], streak: Int, offer: (lost: Int, missed: [Int])?) {
    let r = ReadingStreak.compute(readDays: keys(read), repairedDays: keys(repaired), today: today, calendar: cal)
    let gotOffer = r.offer.map { o in
        (o.lostStreak, o.missedDays.map { cal.dateComponents([.day], from: $0, to: cal.startOfDay(for: today)).day! })
    }
    let ok = r.streak == streak && gotOffer?.0 == offer?.lost && gotOffer?.1 == offer?.missed
    if !ok { failures += 1 }
    print("\(ok ? "ok  " : "FAIL") \(name)" + (ok ? "" : "\n  got streak \(r.streak) offer \(String(describing: gotOffer))\n  want streak \(streak) offer \(String(describing: offer))"))
}

run("read today and the 4 days before", read: [0, 1, 2, 3, 4], streak: 5, offer: nil)
run("not read yet today: streak still counts from yesterday", read: [1, 2, 3], streak: 3, offer: nil)
run("nothing read", read: [], streak: 0, offer: nil)
run("missed yesterday, read today, 5-day streak before", read: [0, 2, 3, 4, 5, 6], streak: 1, offer: (5, [1]))
run("missed yesterday and the day before, not read today", read: [3, 4, 5], streak: 0, offer: (3, [1, 2]))
run("missed 2 days, back for 2 days", read: [0, 1, 4, 5, 6], streak: 2, offer: (3, [2, 3]))
run("3 missed days: too long to repair", read: [0, 4, 5, 6], streak: 1, offer: nil)
run("lost streak of 1 day: not worth repairing", read: [0, 2], streak: 1, offer: nil)
run("after the repair the streak spans the gap", read: [0, 2, 3, 4, 5, 6], repaired: [1], streak: 7, offer: nil)
run("one repair a week: repaired 5 days before this break", read: [0, 2, 3, 4, 5, 7, 8], repaired: [6], streak: 1, offer: nil)
run("one repair a week: last repair 9 days before this break", read: [0, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12], repaired: [10],
    streak: 1, offer: (11, [1]))
run("repaired days alone keep the streak going", read: [2, 3], repaired: [0, 1], streak: 4, offer: nil)

print(failures == 0 ? "\nall passed" : "\n\(failures) failed")
exit(failures == 0 ? 0 : 1)
