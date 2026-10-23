import Foundation

typealias I = ChapterCarryOver.Item
typealias M = ChapterCarryOver.Move
var checks = 0
var failures = 0

func expect(_ got: [M], _ want: [M], _ label: String) {
    checks += 1
    if got != want {
        failures += 1
        print("FAIL \(label)\n  got  \(got.map { "\($0.oldId)→\($0.newId)" })\n  want \(want.map { "\($0.oldId)→\($0.newId)" })")
    }
}

// 1. The #208 case: Madara switched every chapter from a full URL to slug + memo → every id is new.
let oldMadara = (1...5).map { I(id: "old\($0)", number: Double($0)) }
let newMadara = (1...5).map { I(id: "new\($0)", number: Double($0)) }
expect(ChapterCarryOver.moves(local: oldMadara, remote: newMadara),
       (1...5).map { M(oldId: "old\($0)", newId: "new\($0)") }, "whole list moved")

// 2. Same, plus one genuinely new chapter: 6 stays new.
expect(ChapterCarryOver.moves(local: oldMadara, remote: newMadara + [I(id: "new6", number: 6)]),
       (1...5).map { M(oldId: "old\($0)", newId: "new\($0)") }, "moved list + a real new chapter")

// 3. Normal refresh: nothing moved, one chapter added.
expect(ChapterCarryOver.moves(local: oldMadara, remote: oldMadara + [I(id: "x6", number: 6)]), [], "plain new chapter")

// 4. Identical lists → nothing.
expect(ChapterCarryOver.moves(local: oldMadara, remote: oldMadara), [], "no change")

// 5. Source dropped a chapter and added nothing → nothing to move (the old row just stays).
expect(ChapterCarryOver.moves(local: oldMadara, remote: Array(oldMadara.prefix(4))), [], "dropped only")

// 6. Unknown numbers never match.
expect(ChapterCarryOver.moves(local: [I(id: "a", number: nil), I(id: "b", number: -1)],
                              remote: [I(id: "c", number: nil), I(id: "d", number: -1)]), [], "unknown numbers")

// 7. Decimals: 10.5 matches 10.5, not 10.
expect(ChapterCarryOver.moves(local: [I(id: "a10", number: 10), I(id: "a105", number: 10.5)],
                              remote: [I(id: "b105", number: 10.5), I(id: "b10", number: 10)]),
       [M(oldId: "a10", newId: "b10"), M(oldId: "a105", newId: "b105")], "decimals")

// 8. Downloaded old chapter stays (files live under its id); the rest still move.
expect(ChapterCarryOver.moves(local: [I(id: "o1", number: 1, isDownloaded: true), I(id: "o2", number: 2)],
                              remote: [I(id: "n1", number: 1), I(id: "n2", number: 2)]),
       [M(oldId: "o2", newId: "n2")], "downloaded not moved")

// 9. Two groups with the same number on both sides → paired by group, case/space-insensitive.
expect(ChapterCarryOver.moves(
        local: [I(id: "oA", number: 7, scanlator: "Asura"), I(id: "oB", number: 7, scanlator: "Flame")],
        remote: [I(id: "nB", number: 7, scanlator: "flame "), I(id: "nA", number: 7, scanlator: "ASURA")]),
       [M(oldId: "oA", newId: "nA"), M(oldId: "oB", newId: "nB")], "paired by group")

// 10. Ambiguous: two old chapter 3s with no group, one new → left alone.
expect(ChapterCarryOver.moves(local: [I(id: "x", number: 3), I(id: "y", number: 3)],
                              remote: [I(id: "z", number: 3)]), [], "ambiguous old")

// 11. Ambiguous the other way: one old, two new without groups → left alone.
expect(ChapterCarryOver.moves(local: [I(id: "x", number: 3)],
                              remote: [I(id: "y", number: 3), I(id: "z", number: 3)]), [], "ambiguous new")

// 12. One old chapter 4 still listed + a new chapter 4 from another group: nothing moved (old is not gone).
expect(ChapterCarryOver.moves(local: [I(id: "keep4", number: 4, scanlator: "A")],
                              remote: [I(id: "keep4", number: 4, scanlator: "A"), I(id: "other4", number: 4, scanlator: "B")]),
       [], "old still listed")

// 13. Group renamed while URLs moved: single old + single new for that number still match (Mihon behaviour).
expect(ChapterCarryOver.moves(local: [I(id: "o", number: 9, scanlator: "Old Team")],
                              remote: [I(id: "n", number: 9, scanlator: "New Team")]),
       [M(oldId: "o", newId: "n")], "single pair ignores group")

// 14. Chapter 0 (prologue) is a known number.
expect(ChapterCarryOver.moves(local: [I(id: "p0", number: 0)], remote: [I(id: "q0", number: 0)]),
       [M(oldId: "p0", newId: "q0")], "chapter zero")

if failures > 0 { print("\(failures) of \(checks) checks failed"); exit(1) }
print("OK \(checks) checks")
