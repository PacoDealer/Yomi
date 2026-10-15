import Foundation

/// Which pages share the screen in two-page mode (F17). Before, pages were always paired [0,1] [2,3]…: a cover took half
/// of the first spread and every printed spread after it was split across two screens, and a page that is already a
/// spread was squeezed next to another. Rules from Mihon's experimental dual-page viewer (S158 research 1i,
/// `WebGpuViewer.kt`, Apache-2.0; re-written): a wide page stands alone, two pages pair only when their shapes match,
/// and each lone page re-starts the pairing after it instead of shifting every later spread.
nonisolated enum PageSpreads {
    /// Wider than this (width / height) = a page that is already a spread.
    static let wideAspect = 1.2
    /// Halves of one printed sheet scan alike: shapes further apart than this don't pair.
    static let pairTolerance = 0.1

    /// `aspect(i)` = width / height of page i, nil while unknown (an unknown page pairs as before).
    static func groups(count: Int, aspect: (Int) -> Double?, coverAlone: Bool) -> [[Int]] {
        var groups: [[Int]] = []
        var i = 0
        if coverAlone, count > 0 { groups.append([0]); i = 1 }
        func isWide(_ p: Int) -> Bool { (aspect(p) ?? 0) > wideAspect }
        while i < count {
            let next = i + 1
            if next >= count || isWide(i) || isWide(next) { groups.append([i]); i += 1; continue }
            if let a = aspect(i), let b = aspect(next), abs(a - b) > pairTolerance { groups.append([i]); i += 1; continue }
            groups.append([i, next])
            i += 2
        }
        return groups
    }
}

/// "Automatic" page background (F17): the colour of the page's own margins, so a page with a black frame sits on black
/// and a white page on white instead of a black box around it. Port of `ImageUtil.chooseBackground` from Mihon
/// (Apache-2.0, mihonapp/mihon @446f6df, core/common/.../ImageUtil.kt); modified: reads an RGBA buffer instead of a
/// Bitmap and returns colours instead of a Drawable.
nonisolated enum PageBackground {
    struct RGB: Equatable, Codable, Sendable {
        var r, g, b: UInt8
        static let white = RGB(r: 255, g: 255, b: 255)
        var isDark: Bool { r < 40 && g < 40 && b < 40 }   // Mihon also asks alpha > 200; pages are drawn opaque
        var isWhite: Bool { Int(r) + Int(g) + Int(b) > 740 }
        func isClose(to o: RGB) -> Bool { abs(Int(r) - Int(o.r)) < 30 && abs(Int(g) - Int(o.g)) < 30 && abs(Int(b) - Int(o.b)) < 30 }
    }

    /// One colour, or the top colour giving way to the bottom one through the middle of the screen.
    enum Choice: Equatable, Codable, Sendable {
        case solid(RGB)
        case split(top: RGB, bottom: RGB)
    }

    /// `pixel(x, y)` reads the page (any size; Yomi passes a small copy). `isLandscape` = the screen, not the page.
    static func choose(width: Int, height: Int, isLandscape: Bool, pixel: (Int, Int) -> RGB) -> Choice {
        let white = RGB.white
        guard width >= 50, height >= 50 else { return .solid(white) }

        let top = 5, bot = height - 5
        let left = Int(Double(width) * 0.0275), right = width - left
        let midX = width / 2, midY = height / 2
        let offsetX = Int(Double(width) * 0.01)
        let leftOffsetX = left - offsetX, rightOffsetX = right + offsetX
        // Mihon reads x = width - left, which is in range only because left > 0 there; keep every read inside.
        func at(_ x: Int, _ y: Int) -> RGB { pixel(min(max(x, 0), width - 1), min(max(y, 0), height - 1)) }

        let topLeft = at(left, top), topRight = at(right, top)
        let midLeft = at(left, midY), midRight = at(right, midY)
        let topCenter = at(midX, top), botLeft = at(left, bot), botCenter = at(midX, bot), botRight = at(right, bot)

        var darkBG = (topLeft.isDark && (botLeft.isDark || botRight.isDark || topRight.isDark || midLeft.isDark || topCenter.isDark))
            || (topRight.isDark && (botRight.isDark || botLeft.isDark || midRight.isDark || topCenter.isDark))

        let ring = [topLeft, topCenter, topRight, botRight, botCenter, botLeft]
        if ring.indices.allSatisfy({ !ring[$0].isWhite && ring[$0].isClose(to: ring[($0 + 1) % ring.count]) }) {
            return .solid(topLeft)
        }
        if [topLeft, topRight, botLeft, botRight].filter(\.isWhite).count > 2 { darkBG = false }

        var black: RGB = topLeft.isDark ? topLeft : topRight.isDark ? topRight : botLeft.isDark ? botLeft
            : botRight.isDark ? botRight : white

        var overallWhite = 0, overallBlack = 0
        var topBlackStreak = 0, topWhiteStreak = 0, botBlackStreak = 0, botWhiteStreak = 0
        let step = max(height / 25, 1)
        outer: for x in [left, right, leftOffsetX, rightOffsetX] {
            var whiteStreakLen = 0, whiteCount = 0, blackStreakLen = 0, blackCount = 0
            var blackStreak = false, whiteStreak = false
            let notOffset = x == left || x == right
            for (index, y) in stride(from: 0, to: height, by: step).enumerated() {
                let p = at(x, y)
                let off = at(x + (x < width / 2 ? -offsetX : offsetX), y)
                if p.isWhite {
                    whiteStreakLen += 1; whiteCount += 1
                    if notOffset { overallWhite += 1 }
                    if whiteStreakLen > 14 { whiteStreak = true }
                    if whiteStreakLen > 6 && whiteStreakLen >= index - 1 { topWhiteStreak = whiteStreakLen }
                } else {
                    whiteStreakLen = 0
                    if p.isDark && off.isDark {
                        blackCount += 1
                        if notOffset { overallBlack += 1 }
                        blackStreakLen += 1
                        if blackStreakLen >= 14 { blackStreak = true }
                        continue
                    }
                }
                if blackStreakLen > 6 && blackStreakLen >= index - 1 { topBlackStreak = blackStreakLen }
                blackStreakLen = 0
            }
            if blackStreakLen > 6 { botBlackStreak = blackStreakLen } else if whiteStreakLen > 6 { botWhiteStreak = whiteStreakLen }
            let rightSide = x == right || x == rightOffsetX
            if blackCount > 22 {
                if rightSide { black = topRight.isDark ? topRight : botRight.isDark ? botRight : black }
                darkBG = true
                overallWhite = 0
                break outer
            } else if blackStreak {
                darkBG = true
                if rightSide { black = topRight.isDark ? topRight : botRight.isDark ? botRight : black }
                if blackCount > 18 { overallWhite = 0; break outer }
            } else if whiteStreak || whiteCount > 22 {
                darkBG = false
            }
        }

        let topIsBlackStreak = topBlackStreak > topWhiteStreak
        let bottomIsBlackStreak = botBlackStreak > botWhiteStreak
        if overallWhite > 9 && overallWhite > overallBlack { darkBG = false }
        if topIsBlackStreak && bottomIsBlackStreak { darkBG = true }

        if isLandscape { return .solid(darkBG ? black : white) }

        let botCornersWhite = botLeft.isWhite && botRight.isWhite
        let topCornersWhite = topLeft.isWhite && topRight.isWhite
        let topCornersDark = topLeft.isDark && topRight.isDark
        let botCornersDark = botLeft.isDark && botRight.isDark
        let topOffsetDark = at(leftOffsetX, top).isDark && at(rightOffsetX, top).isDark
        let botOffsetDark = at(leftOffsetX, bot).isDark && at(rightOffsetX, bot).isDark

        if darkBG && botCornersWhite { return .split(top: black, bottom: white) }
        if darkBG && topCornersWhite { return .split(top: white, bottom: black) }
        if darkBG { return .solid(black) }
        if topIsBlackStreak || (topCornersDark && topOffsetDark && (topCenter.isDark || overallBlack > 9)) {
            return .split(top: black, bottom: white)
        }
        if bottomIsBlackStreak || (botCornersDark && botOffsetDark && (botCenter.isDark || overallBlack > 9)) {
            return .split(top: white, bottom: black)
        }
        return .solid(white)
    }
}
