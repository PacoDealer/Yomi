import Foundation

// ChapterGaps (A15 #32, S212): Mihon's missing-chapter count. Run: ./run.sh
var failures = 0, checks = 0
func expect<T: Equatable>(_ test: String, _ got: T, _ want: T) {
    checks += 1
    if got != want { failures += 1; print("FAIL \(test): got \(got), want \(want)") }
}

expect("10 → 13", ChapterGaps.missing(between: 10, and: 13), 2)
expect("13 → 10 (descending)", ChapterGaps.missing(between: 13, and: 10), 2)
expect("next chapter", ChapterGaps.missing(between: 4, and: 5), 0)
expect("same chapter twice", ChapterGaps.missing(between: 12, and: 12), 0)
expect("half chapter", ChapterGaps.missing(between: 12, and: 12.5), 0)
expect("12.5 → 14", ChapterGaps.missing(between: 12.5, and: 14), 1)
expect("chapter 0 counts", ChapterGaps.missing(between: 0, and: 3), 2)
expect("unknown number", ChapterGaps.missing(between: -1, and: 7), 0)
expect("nil number", ChapterGaps.missing(between: nil, and: 7), 0)
expect("descending list", ChapterGaps.after([20, 19, 15, 14, 14, 10]), [1: 3, 4: 3])
expect("ascending list", ChapterGaps.after([1, 2, 5]), [1: 2])
expect("unnumbered skipped", ChapterGaps.after([1, nil, 3]), [0: 1])
expect("no gaps", ChapterGaps.after([3, 2.5, 2, 1]), [Int: Int]())
expect("empty", ChapterGaps.after([]), [Int: Int]())

print(failures == 0 ? "\(checks) checks passed" : "\(failures) of \(checks) checks failed")
exit(failures == 0 ? 0 : 1)
