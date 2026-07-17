import SwiftUI

// MARK: - YomiTokens
//
// Single source of truth for design values. Values are authoritative —
// lifted from NovelTheme, AppSettings, MangaCoverCell, and SettingsView.
// Adopt incrementally; nothing here replaces existing code unless you
// explicitly refactor to reference these constants.

enum YomiTokens {

    // MARK: - Accent

    enum Accent {
        /// Default brand coral — permanent, confirmed with design system.
        static let defaultHex = "#FF6B6B"
        static let `default`  = Color(hex: defaultHex)

        /// All accent presets shown in the swatch picker, in display order.
        /// First entry is the default. Matches accentSwatches in SettingsView.
        static let presets: [(name: String, hex: String)] = [
            ("Coral",      "#FF6B6B"),
            ("Orange",     "#FF9F43"),
            ("Yellow",     "#FECA57"),
            ("Sky",        "#48DBFB"),
            ("Teal",       "#0ABDE3"),
            ("Blue",       "#006BA6"),
            ("Indigo",     "#5F27CD"),
            ("Lavender",   "#C56BFF"),
            ("Pink",       "#FF6EB4"),
            ("Mint",       "#00D2A4"),
        ]

        static func color(for hex: String) -> Color { Color(hex: hex) }
    }

    // MARK: - Surfaces (dark-first)

    enum Surface {
        static let base     = Color(hex: "#000000")   // true black
        static let elevated = Color(hex: "#1C1C1E")   // iOS system dark / sheet bg
        static let raised   = Color(hex: "#2C2C2E")   // tertiary surface
        static let amoled   = Color(hex: "#0A0A0A")   // near-black, OLED jitter-safe
    }

    // MARK: - Text (Apple label opacities over dark)

    enum Text {
        static let primary   = Color.white
        static let secondary = Color.white.opacity(0.60)
        static let tertiary  = Color.white.opacity(0.30)
    }

    // MARK: - Reader themes
    //
    // Mirrors NovelTheme enum exactly. Sepia is the flagship.
    // If NovelTheme is ever refactored to read from here, delete the
    // duplicate switch statements in TextReaderView.

    struct ReaderTheme {
        let bg: String
        let fg: String
        let link: String
        let isDark: Bool

        var bgColor:   Color { Color(hex: bg) }
        var fgColor:   Color { Color(hex: fg) }
        var linkColor: Color { Color(hex: link) }
    }

    enum Reader {
        static let light = ReaderTheme(
            bg:     "#FFFFFF",
            fg:     "#1C1C1E",
            link:   "#0A6ADA",
            isDark: false
        )
        /// Flagship theme — Apple Books-standard warm cream.
        static let sepia = ReaderTheme(
            bg:     "#F8F1E3",
            fg:     "#2C2015",
            link:   "#0A6ADA",
            isDark: false
        )
        static let warm = ReaderTheme(
            bg:     "#1A1209",
            fg:     "#CDB38B",
            link:   "#5BA3F5",
            isDark: true
        )
        static let dark = ReaderTheme(
            bg:     "#1C1C1E",
            fg:     "#E8E8E8",
            link:   "#5BA3F5",
            isDark: true
        )
        static let amoled = ReaderTheme(
            bg:     "#0A0A0A",
            fg:     "#E0E0E0",
            link:   "#5BA3F5",
            isDark: true
        )

        static func theme(named name: String) -> ReaderTheme {
            switch name {
            case "Sepia":  return sepia
            case "Warm":   return warm
            case "Dark":   return dark
            case "AMOLED": return amoled
            default:       return light
            }
        }
    }

    // MARK: - Reader defaults

    enum ReaderDefaults {
        static let fontSize:           Double = 18.0
        static let lineSpacingNormal:  Double = 1.6
        static let lineSpacingTight:   Double = 1.3
        static let lineSpacingAiry:    Double = 2.0
        static let horizontalPadding:  Int    = 16
        static let fontFamily:         String = "Serif"
    }

    // MARK: - Radius

    enum Radius {
        static let badge:  CGFloat = 4    // status/unread badges
        static let thumb:  CGFloat = 6    // small thumbnails
        static let cover:  CGFloat = 8    // manga/novel cover images, selection ring
        static let button: CGFloat = 14   // buttons, banners, bottom sheets
        static let modal:  CGFloat = 20   // full modal sheets
        static let pill:   CGFloat = 100  // capsule / fully-rounded elements
    }

    // MARK: - Spacing (4-pt grid)

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs:  CGFloat = 8
        static let sm:  CGFloat = 12
        static let md:  CGFloat = 16
        static let lg:  CGFloat = 24
        static let xl:  CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: - Layout

    enum Layout {
        /// 2:3 portrait ratio for all cover images.
        static let coverAspectRatio: CGFloat = 2.0 / 3.0
        /// Minimum tap target (Apple HIG).
        static let minTapTarget:     CGFloat = 44
    }
}
