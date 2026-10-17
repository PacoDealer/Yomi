import Foundation
import CoreGraphics
import ImageIO

typealias R = PageTextRecognizer
var failures = 0

func check(_ name: String, _ got: [String], _ want: [String]) {
    if got == want {
        print("ok   \(name)")
    } else {
        failures += 1
        print("FAIL \(name)\n  got:  \(got)\n  want: \(want)")
    }
}

/// Lines from Vision's normalized boxes (x, y from the top, w, h) on a page of `size` pixels.
func lines(_ size: CGSize, _ boxes: [(Double, Double, Double, Double, String)]) -> [R.Line] {
    boxes.map { x, y, w, h, text in
        R.Line(text: text, rect: CGRect(x: x * size.width, y: y * size.height, width: w * size.width, height: h * size.height))
    }
}

// One Piece vol. 1 p. 4 (Japanese raw, 760 × 1200): what Vision returned on 2026-10-16 (S173). Vertical bubbles,
// a horizontal caption, the page header and sound effects.
let onePieceSize = CGSize(width: 760, height: 1200)
let onePiece = lines(onePieceSize, [
    (0.905, 0.121, 0.039, 0.123, "お前なんかが"), (0.852, 0.120, 0.053, 0.170, "海賊になれるか！"),
    (0.069, 0.071, 0.217, 0.021, "ONE PIECE1"), (0.335, 0.092, 0.465, 0.053, "っはっはっはは、"),
    (0.150, 0.124, 0.066, 0.119, "カナッチは"), (0.105, 0.123, 0.049, 0.142, "海賊にとって"),
    (0.046, 0.123, 0.049, 0.154, "致命的だぜ！！："),
    (0.349, 0.371, 0.030, 0.094, "カナッチでも"), (0.312, 0.371, 0.039, 0.077, "船から落ち"),
    (0.283, 0.371, 0.030, 0.077, "なきゃいい"), (0.257, 0.370, 0.031, 0.093, "じゃないか！！"),
    (0.161, 0.375, 0.033, 0.056, "それに"), (0.122, 0.375, 0.036, 0.077, "戦っても"),
    (0.089, 0.377, 0.030, 0.054, "おれは"), (0.046, 0.375, 0.039, 0.075, "強いんだ"),
    (0.740, 0.531, 0.095, 0.029, "湽賊鎖"), (0.740, 0.556, 0.109, 0.031, "\"赤髪の"),
    (0.753, 0.588, 0.152, 0.023, "シャンクス、"),
    (0.391, 0.687, 0.257, 0.215, "ど"),
    (0.310, 0.689, 0.035, 0.064, "ちゃんと"), (0.283, 0.677, 0.030, 0.060, "きたえて"),
    (0.257, 0.677, 0.026, 0.046, "るから"),
    (0.145, 0.667, 0.033, 0.104, "おれのパンチは"), (0.105, 0.667, 0.030, 0.087, "銃のように"),
    (0.053, 0.665, 0.046, 0.096, "強いんだ！！："),
    (0.000, 0.923, 0.319, 0.075, "DONN"),
])
check("japanese vertical bubbles, right to left",
      R.blocks(onePiece, in: onePieceSize, rightToLeft: true).map(\.text),
      ["ONE PIECE1", "っはっはっはは、",
       "お前なんかが海賊になれるか！", "カナッチは海賊にとって致命的だぜ！！：",
       "カナッチでも船から落ちなきゃいいじゃないか！！", "それに戦ってもおれは強いんだ",
       "湽賊鎖\"赤髪のシャンクス、",
       "ど", "ちゃんときたえてるから", "おれのパンチは銃のように強いんだ！！：",
       "DONN"])
check("automatic reads kana pages right to left", [String(R.readsRightToLeft(onePiece, language: "auto"))], ["true"])

// One Piece vol. 1 p. 5, middle row: a bubble whose columns Vision boxed 17 and 30 px wide (same glyph size), and
// furigana "なにこと" beside 何事も.
let row = lines(onePieceSize, [
    (0.6763, 0.3017, 0.0263, 0.0600, "楽しく"), (0.6684, 0.3042, 0.0250, 0.0558, "いこうぜ"),
    (0.6553, 0.3017, 0.0132, 0.0292, "なにこと"), (0.6316, 0.3017, 0.0224, 0.0567, "何事も！"),
    (0.5461, 0.3017, 0.0224, 0.0467, "そう！"), (0.5066, 0.3017, 0.0395, 0.0467, "海賊は"),
    (0.4697, 0.3017, 0.0395, 0.0733, "楽しいぜょ"),
])
check("columns of different box widths stay one bubble, furigana dropped",
      R.blocks(row, in: onePieceSize, rightToLeft: true).map(\.text),
      ["楽しくいこうぜ何事も！", "そう！海賊は楽しいぜょ"])

// English webtoon slice (900 px wide): two bubbles side by side, then one below; lines stacked inside each.
let webtoonSize = CGSize(width: 900, height: 1350)
let english = lines(webtoonSize, [
    (0.55, 0.100, 0.35, 0.030, "WHAT ARE YOU"), (0.58, 0.134, 0.30, 0.030, "DOING HERE?"),
    (0.08, 0.110, 0.32, 0.030, "I CAME TO"), (0.10, 0.144, 0.28, 0.030, "SEE YOU."),
    (0.25, 0.600, 0.50, 0.030, "THE SWORD IMMORTAL"), (0.28, 0.634, 0.44, 0.030, "DIVIDED HIS REMNANT..."),
])
check("english bubbles, left to right",
      R.blocks(english, in: webtoonSize, rightToLeft: false).map(\.text),
      ["I CAME TO SEE YOU.", "WHAT ARE YOU DOING HERE?", "THE SWORD IMMORTAL DIVIDED HIS REMNANT..."])
check("automatic keeps english left to right", [String(R.readsRightToLeft(english, language: "auto"))], ["false"])

// Korean manhwa: horizontal lines, words separated by spaces — joined with a space, left to right.
let korean = lines(webtoonSize, [
    (0.30, 0.200, 0.40, 0.030, "여기서 뭐 하는"), (0.33, 0.234, 0.34, 0.030, "거야?"),
])
check("korean lines keep a space", R.blocks(korean, in: webtoonSize, rightToLeft: false).map(\.text), ["여기서 뭐 하는 거야?"])
check("automatic keeps korean left to right", [String(R.readsRightToLeft(korean, language: "auto"))], ["false"])

// Artwork read as text in another script is dropped; Latin stays on a Japanese page.
let artJunk = lines(onePieceSize, [
    (0.80, 0.10, 0.04, 0.12, "お前なんかが"), (0.75, 0.10, 0.04, 0.15, "海賊になれるか！"),
    (0.10, 0.50, 0.20, 0.03, "วัด"), (0.40, 0.70, 0.20, 0.03, "요"), (0.00, 0.92, 0.30, 0.07, "DON"),
    (0.90, 0.95, 0.03, 0.01, "12"),
])
check("other scripts dropped on a japanese page",
      R.blocks(artJunk, in: onePieceSize, rightToLeft: true).map(\.text), ["お前なんかが海賊になれるか！", "DON", "12"])
let englishJunk = english + lines(webtoonSize, [(0.1, 0.9, 0.1, 0.02, "١١,٨ ١"), (0.5, 0.95, 0.1, 0.02, "쾅站")])
check("other scripts dropped on an english page",
      R.blocks(englishJunk, in: webtoonSize, rightToLeft: false).map(\.text),
      ["I CAME TO SEE YOU.", "WHAT ARE YOU DOING HERE?", "THE SWORD IMMORTAL DIVIDED HIS REMNANT..."])

// Tall pages: slices cover the page, overlap, and their cores don't overlap.
let tiles = R.tiles(width: 900, height: 16000)
let covered = tiles.last!.rect.maxY == 16000 && tiles.first!.rect.minY == 0
let coresDisjoint = zip(tiles, tiles.dropFirst()).allSatisfy { $0.core.upperBound <= $1.core.lowerBound + 0.001 }
check("tall page slices", ["\(covered)", "\(coresDisjoint)"], ["true", "true"])

// Real images given on the command line: path [language]
var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let path = args.removeFirst()
    let language = args.first.map { !$0.contains("/") && ($0.contains("-") || $0 == "auto") } == true ? args.removeFirst() : "auto"
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { print("can't read \(path)"); continue }
    let blocks = try await R.recognize(image, language: language)
    print("\n\(path) (\(language), \(image.width)×\(image.height)): \(blocks.count) blocks")
    for (i, b) in blocks.enumerated() { print("  \(i + 1). \(b.text)") }
}

print(failures == 0 ? "\nall passed" : "\n\(failures) failed")
exit(failures == 0 ? 0 : 1)
