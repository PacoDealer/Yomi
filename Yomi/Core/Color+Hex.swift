import SwiftUI

extension Color {
    /// Initialize a Color from a CSS hex string: "#RRGGBB" or "#RRGGBBAA".
    /// Returns Color.accentColor if the string is malformed.
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 122, 255)
        }
        self.init(
            .sRGB,
            red:     Double(r) / 255,
            green:   Double(g) / 255,
            blue:    Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// Return the hex string "#RRGGBB" for this color (sRGB, ignores alpha).
    var hexString: String {
        let uic = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uic.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X",
                      Int(r * 255), Int(g * 255), Int(b * 255))
    }

    // MARK: - WCAG contrast
    //
    // Single source of truth for relative-luminance/contrast math — used by AppearanceStudioView's
    // contrast badge and by YomiTokens.Accent.foreground(for:on:) (picks legible text/icon color for an
    // accent fill). Previously duplicated privately inside AppearanceStudioView.

    /// WCAG 2.x relative luminance (0 = black, 1 = white).
    var relativeLuminance: Double {
        let uic = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uic.getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ v: CGFloat) -> Double {
            let d = Double(v)
            return d <= 0.04045 ? d / 12.92 : pow((d + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    /// WCAG contrast ratio between two colors (1:1 to 21:1).
    static func wcagContrast(_ c1: Color, _ c2: Color) -> Double {
        let hi = max(c1.relativeLuminance, c2.relativeLuminance)
        let lo = min(c1.relativeLuminance, c2.relativeLuminance)
        return (hi + 0.05) / (lo + 0.05)
    }

    /// Linearly interpolate this color's sRGB components toward `other` by `amount` (0 = self, 1 = other).
    func mix(with other: Color, amount: Double) -> Color {
        let t = min(max(amount, 0), 1)
        let uicA = UIColor(self), uicB = UIColor(other)
        var ra: CGFloat = 0, ga: CGFloat = 0, ba: CGFloat = 0, aa: CGFloat = 0
        var rb: CGFloat = 0, gb: CGFloat = 0, bb: CGFloat = 0, ab: CGFloat = 0
        uicA.getRed(&ra, green: &ga, blue: &ba, alpha: &aa)
        uicB.getRed(&rb, green: &gb, blue: &bb, alpha: &ab)
        return Color(
            .sRGB,
            red:     Double(ra) + (Double(rb) - Double(ra)) * t,
            green:   Double(ga) + (Double(gb) - Double(ga)) * t,
            blue:    Double(ba) + (Double(bb) - Double(ba)) * t,
            opacity: Double(aa) + (Double(ab) - Double(aa)) * t
        )
    }
}
