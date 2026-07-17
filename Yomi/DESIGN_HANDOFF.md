# YOMI — Design Session Handoff & Roadmap to Launch
**Session S79 · 2026‑07‑16 · Design track (no code shipped).**
_Self-contained handoff: you can resume in a brand-new chat from this file alone without losing anything._

---

## 0. TL;DR

- The app is **code-complete and polished** (last code session S78). The only things between YOMI and the App Store are **design (the app icon) + App Store Connect content** — not engineering.
- **S79 kicked off the design track**: full research + a documented, justified design system. No code touched.
- **Concept locked:** *YOMI = a reading instrument / living archive.* Derived from Andy's own design DNA (Prometheus) + research + references, and it structurally solves the "beautiful **and** deeply customizable" tension.
- **5 foundation decisions signed off** (see §2).
- **Deliverables (all now inside the repo, `Yomi/`):** `DESIGN_RESEARCH.md`, `DESIGN_SYSTEM.md` (v0.2), and this `DESIGN_HANDOFF.md`.
- **The tool for producing the visuals is Claude Design** (Anthropic Labs, web/desktop) — it reads this repo, applies the design system, and hands a bundle to Claude Code.

---

## 1. What S79 produced (the record)

1. **`DESIGN_RESEARCH.md`** — deep research: competitive landscape (Aidoku, Paperback, Tachimanga, Mihon, Apple Books, Kindle, Moon+ Reader, Webtoon…), what users love/hate, general UX/UI aesthetics, iOS 26 Liquid Glass (NN/g critique = our opportunity), reading typography science, personalization as strategy, Netflix/Spotify discovery, Duolingo gamification. Ends with a 7-pillar recommendation.
2. **Design DNA discovery** — read Andy's portfolio (`Creative/Portfolio/`) + Pinterest via Claude in Chrome. Findings that shaped everything: warm palette (reds/browns/tans), reactor-red accent used "scarce and load-bearing," Space Grotesk + Space Mono pairing, monospace catalog notation, and a love of ink/stipple illustration → the **ink & screentone** signature (which also *is* the material of manga).
3. **`DESIGN_SYSTEM.md` v0.2** — the justified system: concept, 6 principles, color + theming model (Ink/Midnight/Paper/Sepia/custom), typography (Grotesk+Mono, modular scale, research-locked reader specs), grid/spacing, the monospace **notation system**, iconography + app-icon direction, motion, **components** (cover cell, continue hero, tab bar, list row, buttons, badges, reader chrome, empty state), and the **three key screens** (Library, Manga Reader, Novel Reader). Every decision carries a **→ Reason**.

---

## 2. Confirmed decisions (signed off 2026‑07‑16)

1. **Accent default = Vermilion `#E5473A`** (Andy's red; user-themeable).
2. **Canvas default = Ink (warm near-black `#14110F`)**; true-black Midnight stays available.
3. **Ink & screentone = the signature texture** (icon, empty states, onboarding).
4. **Novel reader body = serif by default** (sans as an option) — per readability research.
5. **Grotesk + Mono = the standard type, user-swappable** via the Appearance Studio (Type is a 3rd customization axis alongside Canvas × Accent).

---

## 3. Roadmap to launch (phased)

Owner key: **[A]** = Andy · **[CD]** = Claude Design · **[CC]** = Claude Code · **[Me]** = this Cowork architect/strategy agent.

### Phase 1 — Design production (the visuals)
| Step | Owner | Status |
|------|-------|--------|
| Point Claude Design at the repo (ingest `DESIGN_SYSTEM.md` + `DesignTokens.swift`) | [A] | ⬜ |
| Produce v0.2 hero screens: Library, Manga Reader, Novel Reader | [CD] + [Me] brief | ⬜ |
| Write **v0.3 specs**: Browse, Detail, Settings + **Appearance Studio**, More, Onboarding, Insights, Updates, History, Downloads, empty states | [Me] | ⬜ |
| Produce v0.3 screens | [CD] | ⬜ |
| Ink & screentone illustration set (empty states, onboarding) | [CD]/[A] | ⬜ |

### Phase 2 — App icon (the actual blocker)
| Step | Owner | Status |
|------|-------|--------|
| Finalize icon concept (ink/screentone + mark + vermilion) — direction in `DESIGN_SYSTEM.md` §7 | [Me] draft / [A] decide | ⬜ |
| Produce 1024 layered art (fg / mid / bg) + **pure-white layer** for Tinted/Clear | [CD]/[A] | ⬜ |
| Assemble in **Icon Composer** (Xcode 26), export default/dark/tinted/clear | [A] | ⬜ |
| (Optional) alternate icons Dark/Minimal → drop PNGs + `CFBundleAlternateIcons` | [A] | ⬜ |

### Phase 3 — Implementation (apply the system in SwiftUI)
| Step | Owner | Status |
|------|-------|--------|
| Add Space Grotesk + Space Mono to bundle (`Fonts/` + Info.plist `UIAppFonts`) | [CC] | ⬜ |
| Update `DesignTokens.swift`: warm Ink surfaces, Vermilion default, canvas-preset + theming model | [CC] | ⬜ |
| Add a `Notation` helper (formatters: `CH.`, `%`, time, status) | [CC] | ⬜ |
| Build the **Appearance Studio** (Canvas × Accent × Type) | [CC] | ⬜ |
| Apply components + screens from the handoff bundle | [CC] | ⬜ |
| Build + verify on simulator (needs **iOS 26.5 runtime** downloaded first) | [CC] + [A] | ⬜ |

### Phase 4 — App Store Connect
| Step | Owner | Status |
|------|-------|--------|
| Upload app icon | [A] | ⬜ |
| Age rating 17+, description (drafted S46), keywords, support URL | [A] | ⬜ |
| Screenshots — from redesigned screens, **Appearance Studio as the hero** | [CD]/[Me] produce, [A] upload | ⬜ |
| Privacy: `PrivacyInfo.xcprivacy` ✅ (S22), privacy policy ✅ (yomi-plugins.web.app/privacy) | — | ✅ |
| Final build → TestFlight → submit for review | [A] + [CC] | ⬜ |

### Phase 5 — Pre-submit sanity (from `CLAUDE.md`)
- Binary ships zero `.js` plugins ✅ (Firebase hosts all 15). iCloud Documents Xcode capability step if iCloud stays on. Final DerivedData clean build.

---

## 4. What to send to Claude Design (ready brief)

1. Open **claude.ai/design** (or Claude Desktop sidebar).
2. **Connect / point it at the Yomi repo** so onboarding ingests the design system.
3. Paste this prompt:

> "Build the YOMI iOS app screens using the design system in `Yomi/DESIGN_SYSTEM.md` and the tokens in `Yomi/Core/DesignTokens.swift` as the single source of truth. Concept: a warm, editorial 'reading instrument / living archive.' Canvas = Ink (warm near-black), accent = Vermilion `#E5473A` used scarcely, type = Space Grotesk (UI) + Space Mono (metadata notation), covers provide the color. Start with three screens — **Library**, **Manga Reader**, **Novel Reader** — following §9·A exactly. Then let me tune with the knobs. Export a handoff bundle for Claude Code when approved."

4. Iterate with inline comments + knobs. When happy, **export the handoff bundle** → hand to Claude Code (Phase 3).

---

## 5. What's left to DESIGN (checklist)
- [ ] v0.3 screen specs (Browse, Detail, Settings/Appearance Studio, More, Onboarding, Insights, Updates, History, Downloads, empty states).
- [ ] The **Appearance Studio** screen (the differentiator) — full spec + design.
- [ ] The **app icon** (produce the layered art).
- [ ] Ink & screentone illustration set.
- [ ] App Store **screenshots**.
- [ ] Motion specs for the key transitions (page turn, chrome toggle, theme switch).

---

## 6. Next session — start here
1. Open `Yomi/DESIGN_SYSTEM.md`, skim, confirm you're happy with v0.2 (or note changes).
2. Tell me to write **v0.3** (remaining screens + the Appearance Studio + the icon direction in detail).
3. Open **Claude Design**, point it at the repo, run the brief in §4 → get the hero screens.
4. Hand the Claude Design bundle to **Claude Code** to implement (Phase 3).
5. In parallel, produce the **icon** (Phase 2) — it's the true App Store blocker.

---

## 7. Open questions for Andy
- Serif for the novel reader: *Newsreader* vs *Source Serif* — I'll pick if you don't mind.
- Icon motif: a stylized `読` / kitsune / crescent — any preference, or trust me to explore?
- Appearance Studio: include **per-cover ambient accent** (UI subtly tints from the current cover, Apple-Music-style)? Cool but optional.

---

## 8. Continuity / doc index
- **Design docs (in repo, `Yomi/`):** `DESIGN_RESEARCH.md`, `DESIGN_SYSTEM.md`, `DESIGN_HANDOFF.md` (this).
- **Convention docs updated for S79:** `CLAUDE.md` (design-track note + docs listed), `ROADMAP.md` (S79 state), `METODOLOGIA.md` (S79 session row).
- **⚠️ Not yet committed.** Per your session-close protocol, commit + push these so nothing is lost:
  `git add -A && git commit -m "S79: design track — research + design system + handoff" && git push`
