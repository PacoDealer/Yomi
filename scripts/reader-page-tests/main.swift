import Foundation

// F17 checks: PageBorders (port of image-decoder borders.cpp), PageSpreads, PageBackground (port of Mihon's
// chooseBackground). Run: ./run.sh

var failures = 0
var checks = 0

func expect(_ test: String, _ got: Any, _ want: Any) {
    checks += 1
    guard String(describing: got) != String(describing: want) else { return }
    failures += 1
    print("FAIL \(test): got \(got), want \(want)")
}

// MARK: - PageBorders

/// A w×h greyscale page filled with `margin`, with `content` drawn in the rect.
func page(_ w: Int, _ h: Int, margin: UInt8, content: UInt8, rect: (x: Int, y: Int, w: Int, h: Int)?) -> [UInt8] {
    var g = [UInt8](repeating: margin, count: w * h)
    if let r = rect {
        for y in r.y..<(r.y + r.h) { for x in r.x..<(r.x + r.w) { g[y * w + x] = content } }
    }
    return g
}
typealias R = PageBorders.Rect

expect("white margins", PageBorders.find(gray: page(100, 80, margin: 255, content: 0, rect: (10, 5, 80, 70)), width: 100, height: 80),
       R(x: 10, y: 5, width: 80, height: 70))
expect("black margins", PageBorders.find(gray: page(100, 80, margin: 0, content: 255, rect: (20, 8, 60, 50)), width: 100, height: 80),
       R(x: 20, y: 8, width: 60, height: 50))
expect("grey content inside white counts (< 191)", PageBorders.find(gray: page(100, 80, margin: 250, content: 150, rect: (3, 4, 90, 70)), width: 100, height: 80),
       R(x: 3, y: 4, width: 90, height: 70))
expect("light grey (>= 191) is still margin", PageBorders.find(gray: page(100, 80, margin: 255, content: 200, rect: (10, 10, 50, 50)), width: 100, height: 80),
       R(x: 0, y: 0, width: 100, height: 80))
expect("plain page: nothing to crop", PageBorders.find(gray: page(60, 60, margin: 255, content: 0, rect: nil), width: 60, height: 60),
       R(x: 0, y: 0, width: 60, height: 60))
expect("art to the edge: nothing to crop", PageBorders.find(gray: page(60, 60, margin: 0, content: 0, rect: nil), width: 60, height: 60),
       R(x: 0, y: 0, width: 60, height: 60))
// A top edge that is half black, half white is a picture running off the page: that edge stays.
var mixed = page(100, 80, margin: 255, content: 0, rect: (10, 10, 80, 60))
for x in 0..<50 { mixed[x] = 0 }
expect("mixed top edge kept", PageBorders.find(gray: mixed, width: 100, height: 80).y, 0)
expect("tiny image untouched", PageBorders.find(gray: [0, 0, 0, 0], width: 2, height: 2), R(x: 0, y: 0, width: 2, height: 2))

// MARK: - PageSpreads

func spreads(_ aspects: [Double?], cover: Bool = false) -> [[Int]] {
    PageSpreads.groups(count: aspects.count, aspect: { aspects[$0] }, coverAlone: cover)
}
let unknown6: [Double?] = Array(repeating: nil, count: 6)
expect("unknown shapes pair as before", spreads(unknown6), [[0, 1], [2, 3], [4, 5]])
expect("cover alone", spreads(unknown6, cover: true), [[0], [1, 2], [3, 4], [5]])
expect("odd count", spreads([0.7, 0.7, 0.7]), [[0, 1], [2]])
expect("wide page alone, pairing re-starts after it", spreads([0.7, 0.7, 1.4, 0.7, 0.7, 0.7]), [[0, 1], [2], [3, 4], [5]])
expect("wide second page leaves the first alone", spreads([0.7, 1.4, 0.7, 0.7]), [[0], [1], [2, 3]])
expect("shapes too different don't pair", spreads([0.7, 0.9, 0.9]), [[0], [1, 2]])
expect("within tolerance pairs", spreads([0.70, 0.75]), [[0, 1]])
expect("cover alone + wide", spreads([0.7, 1.5, 0.7, 0.7], cover: true), [[0], [1], [2, 3]])
expect("empty", spreads([]), [] as [[Int]])

// MARK: - PageBackground

typealias C = PageBackground.RGB
func bg(_ w: Int, _ h: Int, landscape: Bool = false, _ f: @escaping (Int, Int) -> C) -> PageBackground.Choice {
    PageBackground.choose(width: w, height: h, isLandscape: landscape, pixel: f)
}
let black = C(r: 0, g: 0, b: 0), white = C.white, navy = C(r: 20, g: 20, b: 60)
expect("white page", bg(200, 300) { _, _ in white }, PageBackground.Choice.solid(white))
expect("black page", bg(200, 300) { _, _ in black }, PageBackground.Choice.solid(black))
expect("coloured margins = that colour", bg(200, 300) { _, _ in navy }, PageBackground.Choice.solid(navy))
expect("black frame, white art", bg(200, 300) { x, y in (x < 12 || x > 188 || y < 12 || y > 288) ? black : white },
       PageBackground.Choice.solid(black))
expect("black top band", bg(200, 300) { _, y in y < 90 ? black : white }, PageBackground.Choice.split(top: black, bottom: white))
expect("black bottom band", bg(200, 300) { _, y in y > 210 ? black : white }, PageBackground.Choice.split(top: white, bottom: black))
expect("landscape never splits", bg(200, 300, landscape: true) { _, y in y < 90 ? black : white }, PageBackground.Choice.solid(white))
expect("white page with black art in the middle", bg(200, 300) { x, y in (x > 40 && x < 160 && y > 40 && y < 260) ? black : white },
       PageBackground.Choice.solid(white))
expect("too small = white", bg(40, 40) { _, _ in black }, PageBackground.Choice.solid(white))

print(failures == 0 ? "OK \(checks)/\(checks)" : "\(failures) of \(checks) FAILED")
exit(failures == 0 ? 0 : 1)
