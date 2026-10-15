// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not
// distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Swift port of borders.cpp + borders.h from tachiyomiorg/image-decoder (MPL-2.0, @f11fbd3), the border finder behind
// Mihon's "Crop borders". Modified for Yomi (S169): one function per edge folded into `edge`, Swift types. This file
// alone is under the MPL; the rest of Yomi is not.

import Foundation

/// Finds the plain white or black margin around a page (F17 crop borders). Works on a greyscale copy, 1 byte per pixel.
nonisolated enum PageBorders {
    /// A line has content once 0.25 % of it is filled (every second pixel is sampled).
    static let filledRatioLimit = 0.0025
    /// Closer to 1 crops less: "black" is anything under 191, "white" anything over 63.
    static let threshold = 0.75
    static let blackBelow = UInt8(255.0 * threshold)
    static let whiteAbove = UInt8(255.0 - 255.0 * threshold)

    struct Rect: Equatable { var x, y, width, height: Int }

    /// The page without its margins, in pixels of `gray`. The whole image when there's nothing to crop.
    static func find(gray: [UInt8], width: Int, height: Int) -> Rect {
        guard width > 2, height > 2, gray.count >= width * height else { return Rect(x: 0, y: 0, width: width, height: height) }
        func px(_ x: Int, _ y: Int) -> UInt8 { gray[y * width + x] }
        let top = edge(lines: 0..<height, fromEnd: false, along: stride(from: 0, to: width, by: 2), limit: width) { px($1, $0) }
        let bottom = edge(lines: 0..<height, fromEnd: true, along: stride(from: 0, to: width, by: 2), limit: width) { px($1, $0) }
        let rows = stride(from: top, to: bottom, by: 2)
        let left = edge(lines: 0..<width, fromEnd: false, along: rows, limit: height) { px($0, $1) }
        let right = edge(lines: 0..<width, fromEnd: true, along: rows, limit: height) { px($0, $1) }
        return Rect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// Where the content starts, scanning `lines` inward from one side. The outermost line decides the margin's colour:
    /// mostly black → look for the first line with white in it, otherwise for the first with black; both → no crop.
    /// Returns the first content line (from the start) or one past it (from the end); the image's edge when no crop.
    private static func edge(lines: Range<Int>, fromEnd: Bool, along samples: StrideTo<Int>, limit size: Int,
                             pixel: (_ line: Int, _ sample: Int) -> UInt8) -> Int {
        let noCrop = fromEnd ? lines.upperBound : lines.lowerBound
        let filledLimit = Int((Double(size) * filledRatioLimit / 2).rounded())
        let outer = fromEnd ? lines.upperBound - 1 : lines.lowerBound
        var white = 0, black = 0
        for s in samples {
            let p = pixel(outer, s)
            if p < blackBelow { black += 1 } else if p > whiteAbove { white += 1 }
        }
        if white > filledLimit && black > filledLimit { return noCrop }   // mixed: a picture runs to the edge
        let lookForWhite = black > filledLimit
        let inward: [Int] = fromEnd ? Array(stride(from: lines.upperBound - 2, to: lines.lowerBound, by: -1))
                                    : Array((lines.lowerBound + 1)..<lines.upperBound)
        for line in inward {
            var filled = 0
            for s in samples {
                let p = pixel(line, s)
                if lookForWhite ? p > whiteAbove : p < blackBelow { filled += 1 }
            }
            if filled > filledLimit { return fromEnd ? line + 1 : line }
        }
        return noCrop
    }
}
