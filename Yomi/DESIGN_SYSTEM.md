# YOMI — Design System
**Status: v0.2 — foundations CONFIRMED (2026‑07‑16), components & screens added.** Still a living draft; keep flagging anything to change.

> How to read this doc: every decision is followed by **→ Reason**. If a Reason doesn't convince you, that decision is wrong and we change it. This is the contract you asked for — no arbitrary choices.
>
> Grounded in: your own design DNA (Prometheus, Velvet Moon, your Pinterest), the reading-app + UX research (`DESIGN_RESEARCH.md`), Apple HIG / iOS 26, and typographic science. v0.1 foundations are **confirmed** (you signed off on the 5 decisions — see §11); v0.2 adds components and the three key screens.

---

## 0. Concept

**YOMI is a reading instrument — a living archive of what you read.**

Not "another dark manga grid." A precise, editorial, warm-but-technical system where the covers and the reader's own accent are the only color, metadata reads like catalog notation, and the app's craft lives in typography, grid, texture and restraint.

→ **Reason.** Research finding #1: you don't win by out-coloring competitors (they're already loud). You win where nobody is — a premium, ownable identity — plus deep personalization and a great reader. The "instrument/archive" concept is pulled directly from your best work (Prometheus' engineering-document register) and is the closest cousin to the most premium reference we found (the sleek.design monospace weather *instrument*). It also structurally solves your customization tension: a neutral, systematic canvas is a frame that makes *any* user theme + *any* covers look intentional.

---

## 1. Principles (the six rules everything obeys)

1. **Content is the color.** Chrome stays neutral; color comes from covers + the user's accent.
   → Reason: lets heavy customization never break the look (Apple Books / Things ethos); covers stay the hero.
2. **Warm, not sterile.** The neutral canvas is chromatically *warm* (ink/paper), never blue-cold.
   → Reason: your Pinterest + Velvet Moon + Prometheus palettes are warm (reds, browns, tans, leather). A cold blue-black would fight your taste and feel clinical.
3. **The accent is scarce and load-bearing.** Accent appears only where it *does* something (active state, progress, primary action, catalog index). Never decoration.
   → Reason: your literal Prometheus rule — "red is scarce and load-bearing, never decoration." Scarcity is what makes it read as intentional.
4. **Notation over noise.** Metadata (chapters, %, time, status) is set as monospace notation, not chatty labels.
   → Reason: it's distinctive, it fits an *archive/catalog*, and it's your Prometheus voice (`REV.02`, coded index).
5. **Ink & screentone is our texture.** Illustration/empty-states/onboarding/icon use an ink + dot-screen (stipple) language.
   → Reason: manga is physically made of ink + screentone dots; your Pinterest shows you love stipple/ink illustration. One idea unites the medium and your taste — and no competitor owns it.
6. **Legible and stable beats shiny.** High contrast always; floating "glass" only on chrome, never over text; controls don't move or morph.
   → Reason: NN/g documented iOS 26 Liquid Glass failing at 1.5:1 contrast, text-over-text, and unpredictable morphing controls. Doing the opposite reads as quality — a free differentiator.

---

## 2. Brand

**Wordmark:** `YOMI` set in Space Grotesk, 700, tracking +2–3px, with a single accent mark (the `.` / tick) as the *only* colored element.
→ Reason: a confident geometric grotesk gives brand character (principle: identity lives in type, not a logo blob); the lone accent mark applies principle #3 at the smallest scale.

**Naming / voice:** catalog-like, sentence case, terse. Sections read like an index ("Continue", "Up next", "Library"), metadata like notation.
→ Reason: reinforces the archive concept and matches CDS/Apple copy norms (sentence case, verb-first, no fluff).

**Signature graphic language — Ink & Screentone.** A halftone dot-screen + brush-ink motif used in: empty states, onboarding, loading shimmer, the app icon, section dividers.
→ Reason: principle #5. This is the ownable visual hook. Kept out of dense UI (only expressive moments) so it never hurts legibility.

---

## 3. Color & theming model

**Three independent axes: Canvas (theme) × Accent × Type.** The user sets each separately.
→ Reason: this *is* the "Appearance Studio" differentiator (research §6). Separating the axes means every canvas × accent × font combo is valid and pre-harmonized — deep customization without ugly results. Type is an axis because you asked that users be able to change the fonts (see §4).

### 3.1 Canvas presets (fully themeable — background included, per your ask)

| Preset | bg | surface-1 | surface-2 | text-primary | text-secondary | hairline |
|--------|----|-----------|-----------|--------------|----------------|----------|
| **Ink** (default) | `#14110F` | `#1E1A17` | `#2A2521` | `#F4EFE7` | `rgba(244,239,231,.60)` | `rgba(244,239,231,.10)` |
| **Midnight** (OLED) | `#000000` | `#111111` | `#1C1C1E` | `#FFFFFF` | `rgba(255,255,255,.60)` | `rgba(255,255,255,.10)` |
| **Paper** | `#F7F1E6` | `#FFFFFF` | `#EEE7D8` | `#1A1512` | `rgba(26,21,18,.58)` | `rgba(26,21,18,.10)` |
| **Sepia** | `#F3E7D2` | `#FBF3E2` | `#EADBC0` | `#3A2C18` | `rgba(58,44,24,.62)` | `rgba(58,44,24,.15)` |
| **Custom** | user-picked bg → surfaces/text auto-derived | | | | | |

→ Reason: **Ink** (warm near-black) is the default over pure black because of principle #2 — it's your warmth, and warm-black is easier on the eyes than #000 in normal light while still near-OLED. **Midnight** keeps true-black for OLED lovers (existing `pureBlack` users). **Paper/Sepia** deliver the black→white range you explicitly asked for; Sepia values come from your `DesignTokens.swift` reader theme. Text hierarchy uses 3 steps (100/60/34%) → Reason: matches Apple label opacities and gives clear hierarchy with one color.

### 3.2 Accent

**Default accent — "Vermilion" `#E5473A`.** Full preset set keeps your existing 10 swatches (`Coral #FF6B6B`, `Orange`, `Yellow`, `Sky`, `Teal`, `Blue`, `Indigo`, `Lavender`, `Pink`, `Mint`) + Vermilion.
→ Reason: your signature color across Velvet Moon (blood red), Prometheus (reactor red `#D11E1E`), and your Pinterest is a warm red. Vermilion is that red pulled slightly warmer/softer than `#D11E1E` so it reads *premium* rather than *alarm/error*. Still 100% user-changeable — Vermilion is just a stronger, more "you" default than the current Coral.

**Accent usage rules (where it may appear):** active tab/underline, progress fills, unread badge, catalog index number, the primary action of a screen, the wordmark mark. **Never:** body text, large fills, decorative backgrounds, more than ~3 spots per viewport.
→ Reason: principle #3. A hard cap is what enforces "scarce and load-bearing."

**Contrast:** every accent must pass WCAG AA (≥4.5:1 for text, ≥3:1 for UI) on both the lightest and darkest canvas. Accent-on-fill uses the darkest stop of that hue for text.
→ Reason: principle #6; guarantees legibility across all themes so customization never produces an unreadable combo.

### 3.3 Reader themes (separate from app chrome)
Keep the five reader themes already in `DesignTokens.swift` (Light, **Sepia** flagship, Warm, Dark, AMOLED) — retuned so "Dark" = Ink-warm.
→ Reason: the reading surface has different needs than chrome (long-form comfort); research §7 says Sepia/warm are the comfort winners. Keeping the user's separate reader-theme choice is a retention feature.

---

## 4. Typography

**Families**
- **Space Grotesk** — display, titles, all UI text.
- **Space Mono** — metadata / notation / catalog indices / folios.
- **Reader body (novels): a warm serif** (e.g. *Newsreader* / *Source Serif*), user-switchable to sans.
→ Reason: Grotesk+Mono is *your* pairing (Prometheus) and gives warm-technical character no manga app has. For the novel reader, science says a serif aids long-form reading; keeping Grotesk for UI and a serif for prose separates "interface voice" from "reading voice" (Apple Books does exactly this).

**Fonts are the standard, not a cage.** Grotesk + Mono ship as the default identity, but the Appearance Studio lets users swap the UI font and the reading font from a *curated* shortlist (system, a humanist sans, a couple of serifs, and dyslexia-friendly OpenDyslexic).
→ Reason: your call on decision #5 — Grotesk+Mono is the standard, but users can change it. Curated rather than a free font-picker so every swap still looks intentional and stays legible.

**Type scale — base 16, ratio 1.25 (Major Third).**

| Token | Size / Line | Font | Use |
|-------|------|------|-----|
| display | 32 / 1.1 | Grotesk 700 | wordmark, hero title |
| title-1 | 26 / 1.15 | Grotesk 500 | screen titles ("Library") |
| title-2 | 22 / 1.2 | Grotesk 500 | section headers, detail title |
| headline | 20 / 1.25 | Grotesk 500 | card title, list primary |
| body | 16 / 1.5 | Grotesk 400 | default UI text |
| callout | 15 / 1.4 | Grotesk 400 | secondary UI |
| footnote | 13 / 1.4 | Grotesk 400 | captions |
| notation | 12–13 / 1.5 | **Mono** 400/700 | CH./%/time/status/index |

→ Reason: a modular scale gives predictable harmony (research: modular scale). Ratio 1.25 (moderate, not dramatic 1.618) because content/library apps want *calm* hierarchy, not marketing-poster contrast. Two weights only (400/500, 700 for wordmark) per CDS.

**Reader (novel) typography — research-locked defaults**
- Size 18pt (range 14–28) · line-height 1.6 · **measure 50–75 characters** (enforce max-width + margin on iPad/landscape) · paragraph spacing ≈ 1× font-size · generous side margins.
→ Reason: directly from the science in `DESIGN_RESEARCH.md` §7 (66 CPL sweet spot; ≥1.4 line-height; margins cut fatigue). Your current 18/1.6 is already right; the new part is **exposing measure/margin control** and font choice — that's what puts YOMI at Moon+ Reader level.

**Rules:** sentence case everywhere; never ALL CAPS except Mono notation labels (`STATUS`, `VOL.`) where small-caps-style uppercase is the catalog convention.
→ Reason: sentence case = Apple/CDS norm; the one uppercase exception is the notation system earning its distinct voice.

---

## 5. Grid & spacing

- **8pt grid, 4pt sub-grid.** Spacing scale: `4 · 8 · 12 · 16 · 24 · 32 · 48` (unchanged from `DesignTokens.swift`).
- **Screen margin:** 16pt. **Cover grid:** 2:3 ratio, 12pt gutter, user-set column count (2–4).
- **Radii:** badge 4 · thumb 6 · **cover 10** · button 14 · modal 20 · pill 100.
- **Tap targets:** ≥44×44pt, ≥8pt apart.

→ Reason: 8pt grid is the iOS standard and already in your tokens (keep what works). Cover radius bumped 8→10 → Reason: slightly softer corners catch light better and read more premium (echoes the iOS 26 icon guidance that rounded corners scatter light more naturally); still crisp. Tap-target rule is Apple HIG and a direct rebuke of the iOS 26 crowding NN/g flagged (principle #6).

---

## 6. Notation system (signature)

Metadata is rendered in Space Mono using fixed formats:

| Thing | Format | Example |
|-------|--------|---------|
| Chapter | `CH. 042` | zero-padded to 3 |
| Volume + chapter | `VOL. 03 / CH. 27` | |
| Progress | `68%` (accent) | accent only on the number |
| Reading time | `12H 40M` or `◷ 12H` | |
| Status | `STATUS // ONGOING` | uppercase label |
| Catalog index | `N.07` / `07` | accent, structural |
| Unread count | badge `12` (mono, accent fill) | |

Human-authored text (titles, author, synopsis) stays in **Grotesk**; machine/catalog facts go in **Mono**.
→ Reason: the Grotesk↔Mono split gives an instant read of "content vs. metadata," makes the library feel like a precise catalog, and is the most ownable, distinctive detail in the whole system — lifted straight from your Prometheus notation.

---

## 7. Iconography & app icon

**UI icons:** SF Symbols only, weight matched to text.
→ Reason: native consistency, dynamic-type + accessibility for free, zero maintenance.

**App icon (the App Store blocker) — direction:** a single, simple mark built in the **Ink & Screentone** language — proposal: a stylized `読`/kitsune-or-crescent silhouette in ink, over a warm ground, with a screentone-dot texture and a scarce Vermilion accent. Built as **layered** art (background / mid / foreground) for **Icon Composer** (Xcode 26); specify a **pure-white layer** so Tinted/Clear modes stay legible; rounded corners; concept expressible in ≤3 words.
→ Reason: iOS 26 layered-icon guidance (research: foreground/mid/background, pure-white layer, simplicity, rounded corners for light) + principle #5 makes the icon carry the brand texture. This unblocks App Store while being unmistakably YOMI. (Detailed icon exploration = its own task once the system is signed off.)

---

## 8. Motion

- **Purposeful only.** Animate to communicate state (page turn, chrome toggle, selection), never for spectacle. Durations: `fast .15s` (state), `base .2s` (transitions), `slow .3s` (page/hero). Easing: `easeInOut`.
- **Liquid Glass:** allowed *only* on floating chrome (tab bar, reader overlay) via `.glassEffect()`, **never** over text/content; keep controls fixed in place.
→ Reason: NN/g found iOS 26's "motion without meaning" distracting/nauseating and its morphing controls unlearnable. Restrained, stable motion is principle #6 in action and reads as premium calm.

---

## 9. Components

Every component below lists anatomy, exact spacing, and the reason. All values resolve to §5 tokens.

### 9.1 Cover cell (library grid)
Cover image 2:3, radius 10, clipped. Overlays:
- **Catalog index** — top-left, 8pt inset. Mono 700 · 15px · accent.
  → Reason: your portfolio's `01 / 02` numbering; accent used as *structure* (an allowed load-bearing role), giving the grid a catalog feel no competitor has.
- **Unread badge** — top-right, 6pt inset. Mono 700 · 11px · on-accent text · accent-fill pill.
  → Reason: scarce accent doing real work (count), not decoration.
- **Last-read strip** — bottom, full width, only if progress > 0. Mono · 11px · white on `rgba(0,0,0,.55)` scrim · 1 line, truncate middle.
  → Reason: notation over noise; carries the exact resume point (fixes the #1 "where was I" complaint).
- **Progress hairline** — bottom edge, 3pt, accent fill to % width (only if 0 < p < 1).
- **Title** — below image, 6pt gap. Grotesk · footnote 13 · text-primary · 2 lines.
- **Source** — Grotesk · caption 12 · text-secondary · 1 line (optional).
- **Selection** — accent ring 2.5pt + checkmark top-left.

### 9.2 Continue hero
Card radius 16, background = ambient tint sampled from the cover, padding 14.
- Cover thumb left, 74×104, radius 10.
- Right column: label `CONTINUE READING` (Mono 11, uppercase, tracking .4, tint-secondary) → title (Grotesk title-2 22, on-tint) → notation (`CH. 042 · 68% · 12H 40M`, Mono 12) → action row: **Resume** (accent pill, on-accent, Grotesk 500 13, ▷ icon) + progress hairline.
→ Reason: editorial hero + discovery (research §8, Netflix/Spotify); ambient color = principle #1 (content is the color); exactly one primary action.

### 9.3 Tab bar
5 tabs (Library · Browse · History · Updates · More) on a floating `.glassEffect()` bar, 0.5pt top hairline. Active = accent icon (20) + Grotesk footnote 11/500 accent; inactive = text-secondary.
→ Reason: glass only on chrome, never over content (principle #6); one unambiguous active state.

### 9.4 List row
Thumb 48×68 r6 · title Grotesk body 16 · subtitle (author/source) footnote secondary · unread `N unread` Mono footnote accent · chevron tertiary. Vertical padding 8; divider inset left 76.

### 9.5 Buttons
- **Primary** — accent fill · on-accent text · height 44 · radius 14 (pill for Resume) · Grotesk 500. **One per view.**
- **Secondary** — transparent · 0.5pt hairline border · text-primary.
- **Ghost** — text only.
→ Reason: CDS "one accent per view" + 44pt HIG target.

### 9.6 Badges
Unread (Mono, accent fill) · Status (Mono uppercase, surface-2, text-secondary — `ONGOING`, `COMPLETED`) · Format (`MANGA` / `NOVEL`, Mono, muted).
→ Reason: unifies all metadata into the one notation voice.

### 9.7 Section header
Grotesk title-2 left + optional `See all` (footnote, secondary) or trailing SF Symbols right. 16 margins, 8 below.

### 9.8 Reader chrome (both readers)
Immersive. `@State showChrome` toggled by center tap.
- **Top bar** — back 44×44 (chevron) · center title Grotesk callout 15, truncated · right actions (list, settings) 44pt each.
- **Bottom bar** — notation `CH. 042 · 12/48` (Mono, left) · chapter prev/next · page slider (manga) / typography button (novel).
- Both on `.glassEffect()`, `.opacity + .easeInOut(.2)` toggle, `.statusBarHidden(!showChrome)`, tab bar hidden.
→ Reason: your existing immersive pattern + glass-on-chrome; 44pt back button fixes the tiny-target issue (your S58 fix, HIG, and a direct answer to NN/g's crowding critique).

### 9.9 Empty state
Centered: **ink/screentone illustration** (~120pt) · Grotesk title-2 · footnote secondary body · primary button.
→ Reason: the signature texture (principle #5) lives in expressive moments like this; copy is an invitation, not an apology (CDS).

---

## 9·A. Screens (layout + position + reason)

### A. Library (home)
1. **Category tab bar** — `safeAreaInset(.top)`. Underline tabs (`All` · categories · `+`), horizontal scroll, hairline bottom. Active: Grotesk subheadline 500, accent, 2pt accent underline; inactive text-secondary.
   → Reason: Tachiyomi-style, already in your app; accent underline = scarce accent as navigation state.
2. **Nav** — large title `Library` (title-1). Toolbar trailing: grid/list toggle · shuffle · filter (SF Symbols, secondary). Searchable "Search library".
3. **Scroll content** (16 side margins):
   a. **Continue hero** (if a recently-read item exists) — full width.
   b. **"Up next" shelf** — section header + horizontal cover row (peek ~3.5), optional.
   c. **Library** — section header + cover grid (`LazyVGrid`, user column count, gutter 12) **or** list (user toggle).
   d. **Novels** — same, under a `Novels` header, when present.
4. **Tab bar** bottom.
5. **Selection mode** — nav title `N selected`; bottom action bar (Mark read · Download · Remove); accent rings on selected.
→ Reason: editorial home + shelves for discovery (research §8) **with the grid/list toggle as the "simple library" escape hatch** power users want (research: Mihon crowd). Everything derives from tokens; nothing is placed by feel.

### B. Manga reader
Full-bleed pages. Modes: **RTL · LTR · Webtoon (vertical continuous)**. Pinch-zoom + pan; center tap toggles chrome; side taps page-turn (user-set tap zones); light haptic on turn. Chrome overlay (9.8) shows `CH. 042 · 12/48`, page slider, chapter nav, discuss/settings.
→ Reason: research — multiple reading modes + gesture control are the most-loved manga-reader features; reliable resume (`lastPageRead`) answers the #1 complaint (broken "continue").

### C. Novel reader
Serif body 18/1.6, **measure clamped to 50–75 CPL** (max-width + side margins, critical on iPad/landscape). Theme = reader theme (Sepia flagship / warm Ink / Paper). Optional justify. Chrome overlay adds a **typography row**: size · font (serif/sans/OpenDyslexic) · line-height · margin · theme · justify · TTS. Footer notation `CH. 27 · 64%`. Scroll-position save + chapter-finished banner.
→ Reason: research §7 typography science, delivered as Moon+ Reader-level control — the exact differentiator that makes readers stay for years. Keeps every feature you already built.

### D. Browse & Detail
Same components (cover cells, notation, hero, list rows). Full layout in **v0.3** to keep this review focused on the three screens you prioritized.

---

## 10. Implementation mapping (SwiftUI)
- Extends the existing `Yomi/Core/DesignTokens.swift` (keep spacing/radius/layout; **change**: warm-Ink surfaces, Vermilion default accent, add canvas-preset + theming model).
- Add **Space Grotesk + Space Mono** to the bundle (`Fonts/` + Info.plist `UIAppFonts`).
- Add a `Notation` helper (formatters for `CH.`, `%`, time, status).
- Feeds Claude Design: point Claude Design at this repo so it ingests this doc + `DesignTokens.swift` as the source of truth, then produces the v0.2 screens.

---

## 11. Confirmed decisions (signed off 2026‑07‑16)
1. **Default accent = Vermilion `#E5473A`.** ✅
2. **Default canvas = Ink (warm black); true-black Midnight stays available.** ✅
3. **Ink & screentone = the signature texture.** ✅ (tentative yes — we prove it in the icon + empty states; easy to dial back if it doesn't sing)
4. **Novel reader body = serif by default, sans as an option.** ✅ (per the readability research)
5. **Grotesk + Mono = the standard, user-swappable** via the Appearance Studio. ✅

_— v0.2 delivered. Next: v0.3 (Browse + Detail) and/or hand this repo to Claude Design to produce the visuals._
