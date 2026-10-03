import SwiftUI

// MARK: - YomiTokens
//
// Single source of truth for design values.
// S138 "calm" design (RESEARCH §26): Apple Music-style — SF Pro everywhere, system
// neutrals, colour comes from covers, one accent. Axes: Canvas (theme) × Accent.

enum YomiTokens {

    // MARK: - Typography

    enum Font {
        // S138: both helpers return SF Pro. The names are kept so the ~200 call sites
        // don't churn; screens move to semantic styles (.headline, .subheadline…) as
        // they are redesigned. "mono" keeps tabular digits for counts and progress.
        static func grotesk(_ size: CGFloat) -> SwiftUI.Font {
            .system(size: size)
        }
        static func grotesk(_ size: CGFloat, weight: SwiftUI.Font.Weight) -> SwiftUI.Font {
            .system(size: size, weight: weight)
        }
        static func mono(_ size: CGFloat, bold: Bool = false) -> SwiftUI.Font {
            .system(size: size, weight: bold ? .semibold : .regular).monospacedDigit()
        }
    }

    // MARK: - Type scale (base 16, Major Third 1.25)

    enum TypeScale {
        static let display:  CGFloat = 32   // wordmark, hero title     — Grotesk 700
        static let title1:   CGFloat = 26   // screen title "Library"   — Grotesk 500
        static let title2:   CGFloat = 22   // section header, detail   — Grotesk 500
        static let headline: CGFloat = 20   // card title, list primary — Grotesk 500
        static let body:     CGFloat = 16   // default UI text          — Grotesk 400
        static let callout:  CGFloat = 15   // secondary UI             — Grotesk 400
        static let footnote: CGFloat = 13   // captions                 — Grotesk 400
        static let notation: CGFloat = 12   // CH./% /time/status       — Mono 400/700
    }

    // MARK: - Canvas presets

    // Canvas is the full app chrome theme (background, surfaces, text hierarchy).
    // Each preset gives 5 semantic colors; accent and type are separate axes.

    struct CanvasColors {
        let name:         String
        let bg:           Color   // root background
        let surface1:     Color   // cards, sheets, elevated surfaces
        let surface2:     Color   // secondary surfaces, selected chips
        let textPrimary:  Color   // primary label (~100%)
        let textSecondary: Color  // secondary label (~60%)
        let hairline:     Color   // dividers, borders (~10%)
    }

    enum Canvas {
        // S138: Ink (the dark default) = Apple's system dark palette — black canvas,
        // #1C1C1E/#2C2C2E surfaces, white label + 60 % secondary (was warm brown #14110F).
        static let ink = CanvasColors(
            name:          "Ink",
            bg:            Color(hex: "#000000"),
            surface1:      Color(hex: "#1C1C1E"),
            surface2:      Color(hex: "#2C2C2E"),
            textPrimary:   Color.white,
            textSecondary: Color(hex: "#EBEBF5").opacity(0.60),
            hairline:      Color(hex: "#545458").opacity(0.60)
        )

        static let midnight = CanvasColors(
            name:          "Midnight",
            bg:            Color(hex: "#000000"),
            surface1:      Color(hex: "#111111"),
            surface2:      Color(hex: "#1C1C1E"),
            textPrimary:   Color.white,
            textSecondary: Color.white.opacity(0.60),
            hairline:      Color.white.opacity(0.10)
        )

        // S138: Paper (the light default) = Apple's system light palette (was cream #F7F1E6;
        // the warm look stays available as Sepia).
        static let paper = CanvasColors(
            name:          "Paper",
            bg:            Color(hex: "#FFFFFF"),
            surface1:      Color(hex: "#F2F2F7"),
            surface2:      Color(hex: "#E5E5EA"),
            textPrimary:   Color.black,
            textSecondary: Color(hex: "#3C3C43").opacity(0.60),
            hairline:      Color(hex: "#3C3C43").opacity(0.29)
        )

        static let sepia = CanvasColors(
            name:          "Sepia",
            bg:            Color(hex: "#F3E7D2"),
            surface1:      Color(hex: "#FBF3E2"),
            surface2:      Color(hex: "#EADBC0"),
            textPrimary:   Color(hex: "#3A2C18"),
            textSecondary: Color(hex: "#3A2C18").opacity(0.62),
            hairline:      Color(hex: "#3A2C18").opacity(0.15)
        )

        static let all: [CanvasColors] = [ink, midnight, paper, sepia]

        static func named(_ name: String) -> CanvasColors {
            all.first { $0.name == name } ?? ink
        }
    }

    // MARK: - Accent

    enum Accent {
        // Default: Vermilion — warm premium red, the YOMI signature.
        // CLAUDE.md §confirmed: Vermilion replaces old Coral default.
        static let defaultHex = "#E5473A"
        static let `default`  = Color(hex: defaultHex)

        // Full preset set (Vermilion first = default position).
        static let presets: [(name: String, hex: String)] = [
            ("Vermilion", "#E5473A"),
            ("Coral",     "#FF6B6B"),
            ("Orange",    "#FF9F43"),
            ("Yellow",    "#FECA57"),
            ("Sky",       "#48DBFB"),
            ("Teal",      "#0ABDE3"),
            ("Blue",      "#006BA6"),
            ("Indigo",    "#5F27CD"),
            ("Lavender",  "#C56BFF"),
            ("Pink",      "#FF6EB4"),
            ("Mint",      "#00D2A4"),
        ]

        static func color(for hex: String) -> Color { Color(hex: hex) }

        /// Legible label/icon color for content rendered on a fill of this accent — several
        /// presets (Yellow, Sky, Mint, …) are bright enough that the canvas's own ink color is
        /// close to unreadable on them (WCAG contrast well under 2:1), even though the same
        /// accent reads perfectly well as an icon/progress-bar color directly on the canvas
        /// background. Keeps `canvasTextPrimary` (the color every other label on that canvas
        /// already uses — near-white ink on Ink/Midnight, near-black on Paper/Sepia) whenever it
        /// clears a pragmatic 3:1 against the accent; only for accents where that genuinely fails
        /// does it flip to the opposite pole. A blanket "always pick whichever of white/black
        /// wins" was tried first and rejected — it flipped even passable defaults (e.g. Vermilion
        /// on Ink, ~4:1) to black, breaking the all-one-ink-color convention for no real
        /// legibility gain on the one case anyone actually looks at.
        static func foreground(for hex: String, on canvasTextPrimary: Color) -> Color {
            let bg = Color(hex: hex)
            if Color.wcagContrast(canvasTextPrimary, bg) >= 3.0 {
                return canvasTextPrimary
            }
            return canvasTextPrimary.relativeLuminance > 0.5 ? .black : .white
        }
    }

    // MARK: - Reader themes (separate axis from chrome canvas)
    //
    // The reading surface has different needs than chrome (long-form comfort).
    // "Dark" reader is retuned to Ink-warm (#1A1209 → retains warmth).

    struct ReaderTheme {
        let name:   String
        let bg:     String
        let fg:     String
        let link:   String
        let isDark: Bool

        var bgColor:   Color { Color(hex: bg) }
        var fgColor:   Color { Color(hex: fg) }
        var linkColor: Color { Color(hex: link) }
    }

    enum Reader {
        static let light = ReaderTheme(
            name:   "Light",
            bg:     "#FFFFFF",
            fg:     "#1C1C1E",
            link:   "#0A6ADA",
            isDark: false
        )
        // Flagship — warm cream, research-backed for long-form reading.
        static let sepia = ReaderTheme(
            name:   "Sepia",
            bg:     "#F8F1E3",
            fg:     "#2C2015",
            link:   "#0A6ADA",
            isDark: false
        )
        // Ink-warm: matches the default app canvas for continuity.
        static let warm = ReaderTheme(
            name:   "Warm",
            bg:     "#1A1209",
            fg:     "#CDB38B",
            link:   "#5BA3F5",
            isDark: true
        )
        static let dark = ReaderTheme(
            name:   "Dark",
            bg:     "#1C1C1E",
            fg:     "#E8E8E8",
            link:   "#5BA3F5",
            isDark: true
        )
        static let amoled = ReaderTheme(
            name:   "AMOLED",
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

    // MARK: - Reader defaults (research-locked — DESIGN_SYSTEM §4)

    enum ReaderDefaults {
        static let fontSize:          Double = 18.0
        static let lineSpacingNormal: Double = 1.6
        static let lineSpacingTight:  Double = 1.3
        static let lineSpacingAiry:   Double = 2.0
        static let horizontalPadding: Int    = 16
        static let fontFamily:        String = "georgia"   // a ReaderFont.id (S136)
        static let paragraphSpacing:  Double = 1.0         // em
    }

    // MARK: - Radius (DESIGN_SYSTEM §5)

    enum Radius {
        static let badge:  CGFloat = 4    // status/unread badges
        static let thumb:  CGFloat = 6    // small thumbnails
        static let cover:  CGFloat = 6    // manga/novel cover images (S138: Apple Music artwork ≈6)
        static let button: CGFloat = 14   // buttons, banners, bottom sheets
        static let modal:  CGFloat = 20   // full modal sheets
        static let pill:   CGFloat = 100  // capsule / fully-rounded elements
    }

    // MARK: - Spacing (8pt grid, 4pt sub-grid)

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
        static let coverAspectRatio: CGFloat = 2.0 / 3.0  // 2:3 portrait ratio
        static let minTapTarget:     CGFloat = 44          // Apple HIG minimum
        static let screenMargin:     CGFloat = 20          // standard side margin (S138: Apple Music 20)
        static let coverGutter:      CGFloat = 12          // between cover cells
    }

    // MARK: - Motion (DESIGN_SYSTEM §8)

    enum Motion {
        static let fast:   Double = 0.15   // state feedback (tab select, toggle)
        static let base:   Double = 0.20   // chrome toggle, opacity transitions
        static let slow:   Double = 0.30   // page turn, hero transitions
    }
}
