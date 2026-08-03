# YOMI app icon — assets

**Final direction (S79, 2026-07-18): "Y." monogram** — centered Space Grotesk `Y` + scarce Vermilion `#E5473A` dot, on a warm ground with subtle screentone. Two themes only.

## Canonical files (use these)
- `AppIcon-Ink-1024.png` — **default** icon (Ink `#14110F` ground, cream `Y`, vermilion dot).
- `AppIcon-Paper-1024.png` — **alternate** icon (Paper `#F3ECDD` ground, ink `Y`, vermilion dot).
- `Y-outlined.svg` — vector source of the glyph (Space Grotesk `Y`, outlined).
- `layers/` — Icon Composer inputs:
  - `Ink-bg.png` / `Ink-mark.png` / `Ink-white.png`
  - `Paper-bg.png` / `Paper-mark.png` / `Paper-white.png`
  - (`*-bg` = background+screentone, `*-mark` = Y+dot, `*-white` = pure-white mark for Tinted/Clear modes.)

## Icon Composer (Xcode 26) — quick assembly
1. New Icon Composer document.
2. Background layer ← `layers/Ink-bg.png`. Foreground ← `layers/Ink-mark.png`.
3. Set the pure-white / monochrome layer ← `layers/Ink-white.png` (keeps Tinted + Clear legible).
4. Export; add to the Xcode asset catalog as the app icon.
5. Repeat with the `Paper-*` layers as an **alternate icon** (wire via `setAlternateIconName` from the Appearance Studio).

**Quick path to ship now:** drop `AppIcon-Ink-1024.png` straight into the asset catalog (single-size 1024) — publishes fine without the layered treatment.

## Note
Older exploration PNGs (`icon_A1_principal.png`, `icon_A3_alt.png`, `icon_teal/lavender/paper.png`, `A1_layer_*.png`) are superseded drafts and can be deleted.
