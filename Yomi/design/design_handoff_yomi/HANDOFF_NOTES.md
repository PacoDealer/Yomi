# Handoff: YOMI — iOS reading app (v0.3, 16 screens)

## Overview
YOMI is an iOS app for reading manga, manhwa, and light novels pulled from any source
(plugin-based, à la a self-hosted library). The concept is a **"reading instrument /
living archive"** — editorial and warm, not a neon manga-reader. This bundle contains
high-fidelity HTML mockups of the full 16-screen suite plus the design tokens and the
two real app-icon assets.

## About the design files
The files in this bundle are **design references created in HTML** — prototypes that show
the intended look and behavior. They are **not production code to copy directly.** The task
is to **recreate these screens in the target codebase** (this app is native iOS — SwiftUI,
per the repo `PacoDealer/Yomi`) using its established patterns, tokens, and components.
Where this README and `Yomi/DESIGN_SYSTEM.md` / `Yomi/Core/DesignTokens.swift` disagree,
**the repo tokens win** — the HTML values below are transcribed from them and are the
reference, not a new source of truth.

The main prototype is a single "Design Component" HTML file that renders all 16 iPhone
screens side by side on a canvas. It uses a small custom template runtime (`support.js`)
and an iOS device-frame wrapper (`ios-frame.jsx`). **Neither of those is app code** — they
exist only to render the mockups in a browser. Read the screens for layout, spacing, color,
and copy; ignore the runtime plumbing.

## Fidelity
**High-fidelity.** Final colors, typography, spacing, copy, and interaction states are all
intentional and should be matched. Cover artwork is the one exception: covers are
**tinted placeholders** (flat color + ghost initials) standing in for real art — the color
comes from the cover, the chrome stays neutral. Swap in real cover art when available.

## Design language (read first)
1. **Content is the color; chrome is neutral.** Covers supply the color. Backgrounds, bars,
   and controls stay in the warm-neutral Ink palette.
2. **Canvas = flat Ink `#14110F`** (a warm near-black). **No glow, no red background
   gradients, no bloom.** The dark is flat and paper-like.
3. **Vermilion `#E5473A` is scarce and earned.** It appears ONLY on: unread badges, the
   reading-progress bar, the active category tab, the Resume/Continue button, score
   displays, selection rings, and destructive actions. One sanctioned wink: the index
   number of the hero ("Continue reading") item may be Vermilion. **Accent never lives in
   a background.**
4. **Type:** Space Grotesk for UI and titles; Space Mono for metadata/notation
   (chapter numbers, percentages, timestamps); Newsreader (serif) for novel body text and
   any in-app long-form. Never substitute a generic sans.
5. **Chrome is glass** — floating tab bars, nav buttons, and action bars use a blurred,
   saturated translucent fill derived from the current canvas (not hard-coded dark), so it
   stays legible on every theme (Ink / Midnight / Paper / Sepia).
6. **Legible on every theme.** All neutrals are theme variables, not fixed hex.

## Design tokens

### Core palette (Ink canvas — the default)
| Token            | Value                      | Use |
|------------------|----------------------------|-----|
| `--bg`  Ink      | `#14110F`                  | App canvas / page background |
| `--s1`  Surface1 | `#1E1A17`                  | Cards, rows, raised surfaces |
| `--s2`  Surface2 | `#2A2521`                  | Inset controls, segmented tracks |
| `--tx`  Text     | `#F4EFE7`                  | Primary text |
| `--tx2` Text-2   | `rgba(244,239,231,.60)`    | Secondary text |
| `--tx3` Text-3   | `rgba(244,239,231,.34)`    | Tertiary / disabled |
| `--hair` Hairline| `rgba(244,239,231,.10)`    | Dividers, 1px separators |
| `--accent`       | `#E5473A` Vermilion        | Accent (scarce — see rule 3) |
| `--on-accent`    | `#FFF8F5`                  | Text/icon on accent fills |

Manga reader uses a slightly deeper stage: page gutter `#080706`, chrome-free black
`#0A0807`.

### Alternate canvases (knob `canvas`)
- **Ink** (default) — `#14110F`
- **Midnight** — pure/cool near-black
- **Paper** — `#F3ECDD` (light, warm cream)
- **Sepia** — toasted light

When canvas changes, every neutral (`--bg/s1/s2/tx/tx2/tx3/hair`) and the glass chrome
recompute from that canvas. Accent stays Vermilion unless overridden.

### Reader themes (knob `readerTheme`, Novel Reader)
Four differentiated swatches: **Paper** (cream), **Sepia** (toasted), **Ink** (warm black),
**Midnight** (pure black). Each sets reader bg/fg (`--rbg`, `--rfg`, `--rfg2`).

### Typography scale (observed)
| Role | Font | Size / weight / spacing |
|------|------|--------------------------|
| Wordmark "YOMI." | Space Grotesk | 44px / 700 / +1px |
| Screen title | Space Grotesk | ~26–28px / 500 / -.4px |
| Section label | Space Mono | 11px / 700 / +.6px, uppercase |
| Body (UI) | Space Grotesk | 14–16px / 400–500 |
| Metadata / notation | Space Mono | 11–13px / 400, e.g. `CH. 042 · 68% · 12H 40M` |
| Novel body | Newsreader | 18px / 400 / line-height 1.6 / max-width 34em |
| Novel chapter head | Newsreader-adjacent | 26px / 500 / -.4px |

### Radius & shadow
- Rows/cards: 12–14px. Pills/segments/buttons: 100px (full). Dialogue bubbles: 16px with one
  4px corner. Primary CTA: 14px.
- Selection / active theme swatch: `2px solid var(--accent)` (or inset `0 0 0 1.5–2px`).
- Elevation is light: `0 1px 3px rgba(0,0,0,.15)` on floating serif chips; glass bars use
  `backdrop-filter: blur(22px) saturate(160%)` over a translucent canvas-derived fill.

### Accent ramp offered in Appearance (swatches only; Vermilion is default & canonical)
`#E5473A` (Vermilion, selected), `#FF6B6B`, `#FF9F43`, plus violet `#C56BFF`, teal
`#00D2A4`, and a custom conic wheel. Ship Vermilion; the others are user-selectable accents.

## Screens / views (16)
All screens render inside an iPhone frame at **402 × 874** (logical). Status bar is part of
the frame. Content scrolls; chrome floats.

1. **Library** — home. Flat Ink bg. Category tabs across the top; the active tab ("All")
   carries a **2pt Vermilion underline**. Three vertical sections, each a horizontal or grid
   run of covers with a **mono grey catalog index** per item:
   - **Up next** — titles already started; each shows a **progress bar anchored left**
     (= % read) and unread badges.
   - **Library** — all owned series (grid, `gridColumns` 2–4).
   - **Novels** — light-novel shelf.
   A **Continue-reading hero** sits up top (`showContinueHero`): cover + title +
   `CH. 042 · 68% · 12H 40M` (the 68% in Vermilion), and a Resume button. The hero item's
   index number may be Vermilion (the sanctioned wink). Floating **glass tab bar** at bottom.
   Unread badges (`showUnreadBadges`) are Vermilion pills.
2. **Manga Reader** — full-bleed page (representative art: screentone + kinetic lines +
   silhouette + dialogue bubbles) on a `#080706` gutter. Top chrome: back chevron `‹` (44pt)
   → title → list + settings, all light glass. Bottom chrome: `CH. 042 · 12/48` + a scrub
   slider + prev/next chapter nav. No stray "GO" button, no stray red thumbnail.
3. **Novel Reader** — the quality bar; **do not regress.** Sepia theme by default, Newsreader
   body, a typographic control panel (A / PT size, Serif / Sans / OpenDys, Line 1.6, Margin,
   justify, TTS), four differentiated theme swatches, notation `CH. 27 · 64%`, glass header.
4. **Appearance Studio** — live preview card at top, then Canvas theme picker, Accent ramp
   (see above), Interface font (Space Grotesk / System / Humanist), Reading font
   (Newsreader / Source Serif / Sans / Dys). Selected options carry the accent inset ring.
5. **Detail** — series page: cover header, title/metadata, Resume + actions, description,
   chapter list.
6. **Browse** — plugin/source catalog grid.
7. **Settings** — grouped list; includes an **"App icon"** section that toggles the real
   icon between **Ink** and **Paper** variants (knob `appIcon`). Glass back-nav.
8. **Onboarding** — centered: the **real app icon** (`assets/AppIcon-Ink.png` /
   `AppIcon-Paper.png`, NOT a drawn crescent), the "YOMI." wordmark, a one-line pitch, a
   3-dot pager (first dot Vermilion), a Vermilion primary CTA, and the plugin URL in mono.
9. **Empty state** — library with nothing added yet; guidance to add a source.
10. **More** — overflow/менu hub.
11. **Insights** — reading stats. Glass back-nav (same pattern as Settings/Detail).
12. **History** — recently read, reverse-chronological.
13. **Updates** — new chapters feed; unread badges.
14. **Downloads** — offline queue; glass back-nav.
15. **Library · Selection** — Library in multi-select mode: selection rings (Vermilion) +
    a bottom action bar.
16. **Browse · Search** — Browse with the search field active.

## Interactions & behavior
- **Tabs** (Library categories): tapping moves the 2pt Vermilion underline; content swaps.
- **Resume / Continue**: primary navigation into the last-read chapter of the hero title.
- **Progress bars**: left-anchored, width = % read, Vermilion fill on neutral track. Present
  on every "started" title.
- **Unread badges**: Vermilion count pills on cover corners.
- **Reader chrome**: tap to toggle show/hide; slider scrubs page/chapter.
- **Appearance / Settings pickers**: single-select segments; selected = accent inset ring.
- **Selection mode** (Library): long-press enters; items gain a Vermilion ring; a bottom
  action bar appears; tapping the bar's actions operates on the selection.
- **App-icon toggle**: switches the displayed icon and (in a real build) the alternate
  iOS icon between Ink and Paper.
- Motion should be quiet and editorial — short, eased fades/slides; no bounce, no glow.

## State (for the app)
- Current canvas theme; current accent; current reader theme; interface + reading font.
- Selected app-icon variant (Ink/Paper).
- Per-title: % read, current chapter, unread count, last-read timestamp, started/owned flags.
- Library selection set (selection mode).
- Grid column count (2–4).

## Knobs in the prototype (map to app settings / build flags, NOT UI to copy verbatim)
- `accent` (color), `canvas` (Ink/Midnight/Paper/Sepia), `appIcon` (Ink/Paper),
  `readerTheme` (Light/Sepia/Warm/Dark/AMOLED)
- `gridColumns` (2–4), `showContinueHero`, `showUnreadBadges`
- `presentationChrome` — prototype-only. When ON it draws a "YOMI." header and N.01/N.02
  labels around the screens for presentation; these are **annotations, not app UI**. Ignore
  them entirely when implementing.

## Assets
- `assets/AppIcon-Ink.png`, `assets/AppIcon-Paper.png` — the **real** app-icon art:
  monogram "Y." + a Vermilion dot, on Ink (`#14110F`) and Paper (`#F3ECDD`) grounds. Use
  these directly; they are final.
- Cover images are tinted placeholders — replace with real cover art from the source plugins.
- Fonts: Space Grotesk, Space Mono, Newsreader (Google Fonts). In the app, bundle equivalents
  or use the repo's chosen faces.

## Files in this bundle
- `README.md` — this document (self-sufficient).
- `YOMI Screens.dc.html` — the 16-screen prototype. Open in a browser to view. This is a
  design reference, not app source.
- `ios-frame.jsx`, `support.js` — browser-only rendering plumbing for the prototype. **Not
  app code.** Do not port these.
- `assets/AppIcon-Ink.png`, `assets/AppIcon-Paper.png` — final icon art.

## Canonical source of truth (in the repo)
`Yomi/DESIGN_SYSTEM.md` (v0.2, §9·A defines the screens; v0.3 §12–16 the additions) and
`Yomi/Core/DesignTokens.swift`. Read those before finalizing any color, type, or spacing —
they override anything transcribed here.
