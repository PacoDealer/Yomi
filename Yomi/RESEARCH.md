# Yomi — Master Research Document
**Last updated:** 2026-09-29 (S132 §25 audits §4, §5 and design/DESIGN_RESEARCH.md against primary sources — read §25 before trusting any number in §4; S122 §22 corrects §7b and §19) | **Do not re-research topics marked with ✅ RESEARCHED**

This file is the single source of truth for all Yomi research. It replaces all prior per-session research notes. Update only when new research is conducted or when a section becomes stale.

---

## Table of Contents
1. [Competitive Landscape](#1-competitive-landscape)
2. [Community Sentiment & User Needs](#2-community-sentiment--user-needs)
3. [Source Sites & Scraping](#3-source-sites--scraping)
4. [UX & Reading Science](#4-ux--reading-science)
5. [App Store Regulations (2026)](#5-app-store-regulations-2026)
6. [iOS 26 App Icon System](#6-ios-26-app-icon-system)
7. [App Customization — Competitor Comparison](#7-app-customization--competitor-comparison)
8. [Plugin Ecosystem — Platform Compatibility](#8-plugin-ecosystem--platform-compatibility)
9. [Architecture Audit — Plugin Execution Runtimes](#9-architecture-audit--plugin-execution-runtimes)
10. [Claude Code Workflow & MCP Stack](#10-claude-code-workflow--mcp-stack)
11. [Strategic Roadmap — Ranked Recommendations](#11-strategic-roadmap--ranked-recommendations)
12. [Suwayomi / Tachidesk Deep Dive](#12-suwayomi--tachidesk-deep-dive)
13. [LNReader Plugin Ecosystem — Full Picture](#13-lnreader-plugin-ecosystem--full-picture)
14. [Full iOS Manga/Novel Reader Landscape (2026)](#14-full-ios-mangannovel-reader-landscape-2026)
15. [App Store Strategy for Plugin-Based Apps](#15-app-store-strategy-for-plugin-based-apps)
20. [Competitor Deep-Dive & Architecture Comparison (S114, 2026-08-18)](#20-competitor-deep-dive--architecture-comparison-s114-2026-08-18)
22. [Direction Reset — Sources, Hosting, Performance, Design, New Competitors (S122, 2026-09-23)](#22-direction-reset--sources-hosting-performance-design-new-competitors-s122-2026-09-23)
23. [S128 audit + research — reader feel and app smoothness (2026-09-25)](#23-s128-audit--research--reader-feel-and-app-smoothness-2026-09-25)
24. [Discord community research — Mihon, LNReader, Tachimanga (S130, 2026-09-26/28)](#24-discord-community-research--mihon-lnreader-tachimanga-s130-2026-092628)
25. [S132 — Research audit + evidence review: reading science, UX/UI, community, App Store (2026-09-29)](#25-s132--research-audit--evidence-review-reading-science-uxui-community-app-store-2026-09-29)

---

## 1. Competitive Landscape
✅ RESEARCHED (S23 + S32 + S35 + S39 audit, 2026-04-07 through 2026-04-19)

### iOS Manga Readers

**Tachimanga** — Current best iOS manga reader
- No light novels — manga only. This is Yomi's primary differentiator.
- No extension/plugin system — fixed set of sources only, maintained by one dev.
- Paywall on basic features (Face ID lock, passcode = $1.99/month or $24.99 lifetime) — users are angry.
- Supports: ZIP, CBZ, EPUB natively; Komga self-hosted; iCloud backup; MAL/AniList sync.
- Reader: multiple reading modes, color filters, per-series filter options, bulk operations.
- Customization: custom app icons, iOS 18 adaptive icons, custom themes (premium), pure black OLED mode, tab bar reordering.
- Complaints: duplicate chapters, fewer sources than Android, no extensions.

**Paperback** — Closest to Tachiyomi on iOS
- Free, no paywalls. TypeScript/JavaScript extension system.
- Supports MAL, AniList, Komga, offline downloads. No light novels.
- ~100+ community TypeScript extensions available.
- Yomi already has a Paperback adapter shim in JSBridge.swift (S24).

**Aidoku** — Free, open source
- Free, open-source. Reading statistics, background download, iCloud sync, built-in Kavita source.
- No light novels. Smaller community than Paperback.
- WASM-based source system (Rust SDK, .aix packages).

**Mangayomi** — New cross-platform competitor (2025–2026)
- Flutter-based: iOS, Android, Windows, macOS, Linux. Open-source.
- Dual extension system: JavaScript plugins for manga, Dart plugins for anime (with video player).
- Covers manga + novels + anime — more complete than Yomi or any iOS app.
- Extension format: custom JS API with `client.get()`/`client.post()` HTTP calls. Not compatible with Yomi Format A or LNReader Format B without a shim.
- Growing community; available on App Store as of late 2025.
- **Implication for Yomi:** Yomi's manga+novel positioning is no longer unique if Mangayomi gains iOS traction. Yomi's competitive moat must shift to better iOS-native UX, performance, and App Store presence.

**Others** — Suwatte, Panels, Manga Storm
- None have light novels. All fragmented.

### Android Manga Readers

**Mihon** (successor to Tachiyomi, best Android manga reader)
- 19.9k GitHub stars, 1.1k forks. Tachiyomi shut down 2024 (legal pressure).
- Extension system: Kotlin `.jar` files loaded at runtime. JVM-based, NOT TypeScript.
- Community extensions: keiyoushi/extensions repo.
- No light novels — users must use LNReader separately. This is the Android equivalent of Yomi's gap.
- Forks: TachiyomiSY (QoL), TachiyomiJ2K (tablet double-page), Neko, Komikku.

**LNReader** (Android light novel reader)
- Android-only. No iOS equivalent exists. This is Yomi's market opportunity.
- Plugin system: TypeScript/JavaScript — each plugin = one content source.
- Plugin repo: lnreader/lnreader-plugins
- Yomi implements the LNReader Format B with Promise auto-resolution adapter.

### Yomi's Strategic Position
**Market gap:** No iOS app combines manga + light novels with an extension system. Yomi is first.

**Competitive moat:**
- iOS-native (not Android port)
- Unified library for all formats
- Plugin/extension system (unlike Tachimanga)
- No paywall on core features (unlike Tachimanga)
- Novel-specific UX (unlike Paperback/Aidoku)

**Risks:**
- App Store rejection if plugin system looks like downloading executable code → mitigated by JavaScriptCore (Apple-approved JS runtime)
- DMCA on sources → mitigated by plugin system (app ≠ sources)
- Source maintenance burden → mitigated by community-driven plugin repo

---

## 2. Community Sentiment & User Needs
✅ RESEARCHED (S23, 2026-04-07)
Sources: App Store reviews, Reddit r/manga, r/manhwa, r/lightnovels, GitHub issue trackers across all major apps.

### Why users switch apps
1. Favorite source removed or blocked
2. Paywall on basic features (Face ID, offline, search)
3. Library lost during migration (Tachiyomi death)
4. Missing feature competitors have
5. Performance (crashes, laggy library)
6. Tracker sync broken

### Most requested features (cross-app consensus)
1. **Offline download reliability** — must work on planes/subways
2. **Library sync across devices** — iCloud is strong iOS selling point
3. **Tracker integration** — MAL/AniList auto-update is essential
4. **Fast source updates** — stale chapters = app abandonment
5. **Zero bloat** — no ads, no paywalls for core features
6. **Light novel support on iOS** — biggest iOS-specific gap

### From UX app analysis (Tachiyomi, Paperback, Aidoku, MangaPlus, Webtoon, INKR, Azuki, Moon+ Reader, ReadEra, Shosetsu)
What users universally want:
1. **Bulk download** — #1 feature request on Paperback GitHub, Tachiyomi issues, Reddit threads
2. **Unread count badge** on library covers — visual scan without opening each title
3. **Continue reading → direct to reader** — extra tap to detail view is friction everyone notices
4. **Storage size indicator** — "how much space are my downloads using?"
5. **LTR mode** — manhwa/manhua audience is large and vocal

### Status of user wants in Yomi
| Feature | Status |
|---------|--------|
| Bulk download | ✅ Implemented S23 |
| Unread badge | ✅ Implemented S23 |
| Continue reading direct | ✅ Implemented S23 |
| Storage size indicator | ✅ Implemented S23 |
| LTR reading mode | ✅ Implemented S23 |
| Library categories | ✅ Implemented S10 |
| Reading status filter | ✅ Implemented S25 + S33 |
| MAL/AniList tracking | ✅ Implemented S8 |
| Offline downloads | ✅ Implemented S12 |
| Pure black OLED mode | ✅ Implemented S36 |
| App Lock (FaceID/Passcode) | ✅ Implemented S42 — FREE (Tachimanga charges premium) |
| Manga notes | ✅ Implemented S42 — FREE (Tachimanga charges premium) |
| TTS for novels | ✅ Implemented S42 — exclusive (no iOS competitor has this) |
| Global search across all sources | ✅ Implemented S42 |
| Tachiyomi backup import | ✅ Implemented S43 (.tachibk protobuf) |
| Tab reordering | ✅ Implemented S43 (iOS 26 TabViewCustomization) |
| Cloudflare auto-bypass | ✅ Implemented S45 (CFBypassManager + CFBypassView) |
| 500+ novel sources via LNReader repo | ✅ Compatible S44+ (Format B native, repo URL one-tap add) |
| 195+ manga sources via Mangayomi | ✅ Format D shim S44 |
| Suwayomi (1000+ keiyoushi sources) | ✅ Integrated S41 |
| Custom manga covers | ✅ Implemented S39 |
| Scanlator filter | ✅ Implemented S39 |
| iCloud sync | ❌ Not yet (future) |
| Home screen widget | ❌ Not yet (future) |
| Volume button page-turn | ❌ Not yet (future) — ⚠️ *S132: drop it; Guideline 2.5.9 rejects apps that alter the volume buttons (§25.13)* |
| OPDS client (Kavita/Komga) | ❌ Not yet (future) |

---

## 3. Source Sites & Scraping
✅ RESEARCHED (S23 + S32 + S39 audit, 2026-04-19)

| Site | Type | API | Scraping | Status in Yomi | Notes |
|------|------|-----|----------|----------------|-------|
| MangaDex | Aggregator | ✅ Official free API | N/A | ✅ Working (mangadex.js) | Lost 7k series in May 2025 DMCA wave. Rate limited but generous. |
| ComicK | Aggregator | Partial | Needed | ❌ Removed (Cloudflare 403) | api.comick.dev returns 403 from non-browser clients. Site-level block. |
| Asura Scans | Publisher | JSON API | N/A | ✅ Working (asurascans.js) | api.asurascans.com JSON API — reliable. |
| AquaManga | Aggregator | None | HTML | ✅ Working (aquamanga.js) | aquareader.net domain. |
| Royal Road | Platform | None | Possible | ✅ Working (royalroad.js) | Web serials/LitRPG. Anti-scraping but accessible. |
| ScribbleHub | Platform | None | Possible | ✅ Working (scribblehub.js) | Web serials. AJAX POST TOC. |
| NovelFire | Aggregator | None | HTML | ✅ Working (novelfire.js restored S36) | Was temporarily removed (S35) due to site security attack. Restored when site recovered. |
| FreeWebNovel | Aggregator | None | HTML | ✅ Working (freewebnovel.js) | Fixed S34. |
| NovelBin | Aggregator | None | HTML | ✅ Working (novelbin.js) | Uses text slugs not numeric IDs. Fixed S34. |
| LightNovelWorld | Aggregator | None | HTML | ❌ Removed (site dead) | Permanently down. Removed from catalog S34. |
| Bato.to | Aggregator | None | HTML | ❌ No plugin, site dead | Permanently shut down January 2026 by CODA (Chinese government takedown). Do not plan plugins for this source. |
| LightNovelPub | Aggregator | None | Cloudflare | ❌ Removed (Cloudflare 403) | Removed from catalog S34. |
| WuxiaWorld | Niche | None | Cloudflare | ❌ No plugin | Cloudflare — very hard to scrape. |
| WebNovel | Platform | None | Cloudflare | ❌ No plugin | Licensed content. Cloudflare blocks. |
| Webtoon | Platform | None | Hard | ❌ No plugin | Aggressive anti-scraping. |
| MangaPlus | Official | None | Hard | ❌ No plugin | Shueisha only, anti-scraping. |

**Key insight:** Cloudflare is the main blocker for novel sources. Prioritize Royal Road, ScribbleHub, NovelBin, FreeWebNovel for new plugins. MangaDex API is safest long-term for manga.

**DMCA trend:** Publishers increasingly targeting free sources. Plugin system is the survival strategy — app survives even if individual plugins are removed.

---

## 4. UX & Reading Science
✅ RESEARCHED (S19–S24, 2026-04-14) — ⚠️ **audited S132: several numbers here are unsourced or misread (letter spacing, sepia radiance, #121212). See §25.1 before using this section.**

### Typography Optima (WCAG-confirmed)

| Metric | Optimal Range | Yomi Implementation |
|--------|---------------|---------------------|
| Font size | 16–18px default | 18pt default, range 14–28pt ✅ |
| Line height | 1.4–1.6× font size | 1.5–1.6× ✅ |
| Characters per line | 50–75 (66 ideal) | Enforced by horizontal margins |
| Dark text color | #E8E8E8 | ✅ Used |
| Dark background | #1C1C1E | ✅ Used |
| Sepia text | #2C1810 on #FFF8F0 | ✅ Used |
| Light mode | #1C1C1E on white | ✅ Used |

### Background Color Research
- **Sepia wins for long sessions**: ~25% lower effective radiance than white, reduces eye strain
- **AMOLED**: Dark gray (#121212) wins over pure black (#000000) for readability; pure black wins for battery savings
- **Best practice**: Offer both "True Black" and "Dark Gray" as separate options (Yomi currently only has Dark Gray)

### Recommended Theme Presets
1. **Light** — white bg, black text (day reading) ✅ Implemented
2. **Sepia** — #FFF8F0 bg, #2C1810 text (default for long sessions) ✅ Implemented  
3. **Dark Gray** — #1C1C1E bg, #E8E8E8 text (night) ✅ Implemented
4. **Pure Black / AMOLED** — #000000 bg (battery saving, OLED users) ✅ **Implemented S36**

### Novel-Specific UX (distinct from manga)
- Font size/family/weight/spacing/margin controls — critical differentiator ✅ Font size implemented
- Sepia mode as default (not dark) ✅
- Text justification options (left, full justify) ❌ Not yet
- Continuous scroll OR paginated — user toggle ❌ Not yet
- Estimated reading time per chapter ❌ Not yet
- Chapter bookmarks within text ❌ Not yet

### Text-to-Speech (TTS) — Future Feature
- 50M+ users use TTS apps (Speechify alone) — not just accessibility, also commuters/multitaskers
- v1 approach: integrate with Apple's built-in Spoken Content (zero implementation cost)
- v2 approach: custom speed controls, voice selection, highlight sync

### Library & Navigation UX Patterns
- **Grid** = default for manga (visual) ✅
- **List** = preferred for novels (text-heavy, F-pattern scanning) — currently novels use grid too
- Sort options: alphabetical, last read, last updated, unread count ✅ All implemented

### Backup & Sync
- **v1 (S32)**: JSON export/import implemented ✅ (manga + novels)
- **v2**: iCloud CloudKit real-time sync — requires CloudKit setup in App Store Connect, higher effort
- Format: `.yomibk` (gzip JSON) — future improvement to current format

### What NOT to Paywall (Tachimanga lesson)
- Face ID / passcode lock → FREE ✅
- Offline reading → FREE ✅
- Search → FREE ✅
- Basic sync → FREE ✅
- Core themes → FREE ✅

Optional premium (acceptable): advanced color filters, exclusive themes, early beta access, donation tier.

---

## 5. App Store Regulations (2026)
✅ RESEARCHED (S23 + S32, updated 2026-04-14; 2.5.2/5.2.2/precedent claims corrected S104 2026-08-07
against the live current guideline text — see below)

### Age Rating System — UPDATED 2026
- **OLD system**: 4+, 9+, 12+, 17+
- **NEW system (2026)**: 4+, 9+, 13+, 16+, **18+** (replaces 17+)
- Deadline was January 31, 2026 — must update before submission
- **Yomi must declare 18+** because it supports NSFW plugins via user installation

### NSFW/Mature Content Rules
- NSFW content from third-party web sources is allowed if:
  - Hidden by default ✅ (NSFW toggle off by default)
  - User explicitly opts in via settings ✅
  - App description clearly states this ✅ (in S33 draft)
- Yomi's NSFW toggle + isNSFW extension flag is compliant.

### Plugin/Extension System (Guideline 2.5.2) — corrected S104 — ⚠️ re-corrected S132: the "primary purpose" test is in the DPLA §3.3.1(B), not 2.5.2; Guideline 4.7 now covers JS plug-ins (§25.7)
- Apple does NOT allow third-party plugins that download additional native code.
- **The old "JavaScriptCore/WebKit named exemption" is stale.** Apple rewrote 2.5.2 engine-agnostic in
  2017 — the current text (fetched live from developer.apple.com, S104) has no named-engine carve-out:
  "may not download, install, or execute code which introduces or changes features or functionality of
  the app." The real test is whether downloaded code changes the app's **primary purpose**. Yomi still
  clears this (reading from sources IS the primary purpose, so JS plugins adding sources are consistent
  with it) — but cite the primary-purpose test, not a named JS/WebKit exemption, in any review notes.
- **Legal precedent, corrected**: Aidoku is **not distributed via the App Store at all**
  (TestFlight/AltStore/IPA sideload only, confirmed via WebSearch S104) — it is not an App Store review
  precedent in either direction. Paperback is live on the App Store but has faced a real DMCA complaint
  over this exact content model (Comeso GmbH, referenced 2021 and again 2024) — "tolerated so far,"
  not "cleared." Treat this whole category as an accepted risk, not a solved compliance question.
- Do NOT market as "extensible with third-party plugins" — frame as "sources + community scripts."

### Third-Party Content (Guideline 5.2.2) — new section, S104
- The guideline that actually governs Yomi's source model is **5.2.2**, not 2.5.2: "If your app uses,
  accesses, monetizes access to, or displays content from a third-party service, ensure that you are
  specifically permitted to do so under the service's terms of use. Authorization must be provided upon
  request." (Fetched verbatim from developer.apple.com, S104.)
- **Live fresh-user audit (S104)**: Yomi's own first-party Plugins catalog (`yomi-plugins.web.app/index.json`,
  fetched automatically, no user action needed — and directly pointed at from onboarding page 2/3) lists
  15 sources; ~12 (AquaManga, Asura Scans, BabelNovel, BoxNovel, FreeWebNovel, LightNovelPub, MTLNovel,
  NovelBin, NovelFire, NovelFull, NovelHall, ReadWN) are unlicensed scanlation/scrape aggregators with
  no documented permission — the exact case 5.2.2 addresses. Only MangaDex (public API under its own
  terms) and arguably Royal Road/Scribble Hub (host only originally-authored fan content) are clearly
  outside that category.
- **Mitigated S104** (Martin's call, matching the friction S96 already applied to the LNReader repo):
  the 12 non-allowlisted catalog entries now require an explicit Copy URL + manual add instead of
  one-tap Install. See `PluginsView.swift`'s `instantInstallSourceIDs` and `ROADMAP.md`'s S104 entry.
  This reduces how turnkey the app looks to a reviewer; it does not obtain actual permission from those
  sites and does not eliminate the underlying legal exposure (same category as Tachiyomi/Paperback).

### Common Rejection Reasons for Reader Apps
1. Privacy policy missing or broken link (40% of rejections) ✅ Fixed (yomi-plugins.web.app/privacy)
2. Missing/incorrect age rating questionnaire ❌ **Still needed**
3. SDK compliance (Firebase, analytics must have privacy disclosures) ✅ PrivacyInfo.xcprivacy added S22
4. App crashes during review
5. Subscription transparency (Yomi has no subscriptions — not applicable)
6. Misleading metadata

### Screenshot Requirements
- **Required sizes**: 6.9-inch iPhone AND 13-inch iPad
- Max 10 screenshots, min 1. Formats: .jpeg, .jpg, .png
- Screenshots must be appropriate for 4+ even if app rated higher (no explicit content in previews)
- Simulator screenshots are accepted
- Primary category: Books. Secondary: Entertainment or Reference.

### App Store Submission Checklist

| Item | Status | Action Required |
|------|--------|-----------------|
| App icon (1024×1024 PNG) | ❌ **BLOCKER** | User designing |
| Age rating 18+ | ❌ **BLOCKER** | App Store Connect → App Information |
| App description | ❌ **BLOCKER** | Drafted S33 — paste into App Store Connect |
| Screenshots (6.9" + 6.1") | ❌ **BLOCKER** | Take on iPhone 17 Pro simulator |
| Support URL | ❌ **BLOCKER** | GitHub repo URL |
| PrivacyInfo.xcprivacy | ✅ Done S22 | — |
| Privacy policy URL | ✅ Done S25 | yomi-plugins.web.app/privacy |
| MAL token → Keychain | ✅ Done S24 | — |
| Zero .js in binary | ✅ Done S19 | Plugins on Firebase only |

---

## 6. iOS 26 App Icon System
✅ RESEARCHED (S35, 2026-04-15)

### Liquid Glass Icon Architecture (WWDC 2025)
iOS 26 introduces a major icon overhaul. Icons now require:

**3 layers** (all transparent PNGs, 1024×1024):
1. **Background** — base solid shape or gradient
2. **Midground** — primary logo or graphic
3. **Foreground** — optional highlights or badges

**6 required modes:**
- Default, Dark, Clear Light, Clear Dark, Tinted Light, Tinted Dark

The system composites layers with real-time lighting/depth effects (Liquid Glass aesthetic).

### Tooling
- **Icon Composer** — new tool bundled with Xcode 26. Import layer PNGs → preview glass effects → export assets for all platforms.
- Simply recompiling with Xcode 26 SDK gets automatic Liquid Glass adaptation.
- New SwiftUI API: `glassEffect(_:in:isEnabled:)` for custom glass effects within the app.

### Alternate Icons — API Unchanged
```swift
// Same API as before, no breaking changes
UIApplication.shared.setAlternateIconName("DarkIcon") { error in
    // handle
}
UIApplication.shared.setAlternateIconName(nil) // reset to default
```

**Asset setup:** Add alternate icon sets to `Assets.xcassets`. Each set supports all 3 layers + 6 modes. Register in `Info.plist`:
```xml
<key>CFBundleAlternateIcons</key>
<dict>
    <key>DarkIcon</key>
    <dict>
        <key>CFBundleIconFiles</key>
        <array><string>IconSet_Dark</string></array>
    </dict>
</dict>
```

### App Icon Design Notes (from S23 research)
- Mascot characters build brand recall (Tachiyomi octopus example)
- Warm gradients (coral, amber, teal) outperform flat blue in App Store search grid
- "Yomi" (読み) = reading in Japanese; references Yomi-no-kuni (underworld mythology)
- Research suggested: coral-to-amber gradient background + 読 kanji midground + glow foreground
- Minimum viable: 1024×1024 PNG, no alpha, coral-to-amber gradient, 読 kanji

---

## 7. App Customization — Competitor Comparison
✅ RESEARCHED (S35 + S39 visual audit, 2026-04-19)

| Feature | Tachimanga | Aidoku | Paperback | **Yomi** |
|---------|-----------|--------|-----------|---------|
| Alternate app icons | ✅ Multiple sets | ❌ | ❌ | ✅ Infrastructure S36 (awaiting user PNGs) |
| iOS 26 adaptive icons | ✅ v4.2 | ❓ | ❓ | ⚠️ Awaiting app icon design |
| Custom themes (dark/sepia/light) | ✅ Premium | ✅ | ✅ | ✅ (reader only) |
| Pure black OLED mode | ✅ Premium | ❓ | ❓ | ✅ **S36 (free)** |
| Color blend level slider | ✅ | ❌ | ❌ | ❌ future |
| Named color theme presets | ✅ Default/Green Apple/Lavender | ❌ | ❌ | ❌ future (Yomi has hex picker) |
| Per-source custom colors | ❌ | ❌ | ❌ | N/A |
| Tab bar customization | ✅ Premium v4.13 | ❓ | ❓ | ✅ **S43 (free, iOS 26 TabViewCustomization)** |
| Home screen widget | ❓ | ❓ | ❓ | ❌ future |
| App-wide themes (not just reader) | ✅ | ❓ | ❓ | ❌ future |
| Cloudflare bypass | ✅ Advanced settings | ❌ | ❌ | ✅ **S45 (auto + manual CFBypassView)** |
| Multiple extension repositories | ✅ by GitHub slug or URL | ❌ | ❌ | ✅ **S40 (Plugin Repositories in Settings, multi-URL)** |
| Tachiyomi backup import | ✅ | ❌ | ❌ | ✅ **S43 (.tachibk protobuf3 + gzip)** |
| Date format options | ✅ 7 formats | ❌ | ❌ | ❌ future |
| Library list/descriptive view | ✅ | ❌ | ❌ | ✅ **S41 (grid/list toggle, libraryDisplayMode)** |
| Tap zone layouts | ✅ 5 (L-Shaped/Edge/Right&Left/Kindle-ish/Disabled) | ❌ | ❌ | ✅ **S39** 3 (Default/Sides/Disabled) |
| Auto-refresh when viewing title | ✅ | ❌ | ❌ | ✅ (loadChapters on appear, unlabeled) |
| App Lock (Face ID / passcode) | ✅ **Premium** | ❌ | ❌ | ✅ **S42 (free)** |
| Manga/novel notes | ✅ **Premium** | ❌ | ❌ | ✅ **S42 (free)** |
| TTS for novels | ❌ | ❌ | ❌ | ✅ **S42 (exclusive)** |

### Visual Audit Findings (S39 screenshots — 2026-04-19)
Direct side-by-side comparison of Yomi simulator vs Tachimanga real device:

**Browse**: Yomi flat list; Tachimanga groups into "Last used / Pinned / English" sections. Tachimanga shows 100+ sources vs Yomi's 8.

**Settings depth**: Tachimanga has a full **Advanced** screen (Data usage / Network / Troubleshoot / Logs). Key items: "Bypassing Cloudflare automatically" toggle (WKWebView cookie bridge), "User Agent" selector, "Receive timeout interval", "Repair Database", "Enable/Export log". Yomi has none of these — gap.

**Tachimanga Backup & Restore**: Own format + Tachiyomi-compatible format + iCloud Drive automated backups (premium). Yomi has manual JSON export only.

**Extension repos**: Tachimanga accepts `username/repo` (auto-resolves to GitHub raw keiyoushi URL) or full URL ending in `index.min.json`. Field is the same as Yomi's `pluginCatalogURL` but supports multiple entries.

**Tachimanga More screen**: Incognito toggle visible directly on the main More page (not buried in Settings). Premium banner at top. Account email + "Sync now" status visible inline.

---

## 7b. Tachimanga Architecture Deep Dive
> ⚠️ **SUPERSEDED S122 (2026-09-23) — see §22.1.** Evidence shows Tachimanga runs an on-device fork of Suwayomi-Server (JVM) that downloads Keiyoushi `.jar` builds — not a DEX interpreter. The diagram below is kept for history only.

✅ RESEARCHED (S39 audit + web search + S44 DEX research, 2026-04-20)

### How Tachimanga gets 100+ sources on iOS — CORRECTED

Tachimanga is a **Flutter app** with a **DEX bytecode interpreter** embedded as a native C library inside the binary. It runs real Keiyoushi Kotlin APK extensions on iOS without a full JVM.

```
[Tachimanga iOS app]
    Flutter UI (Tachidesk-Sorayomi fork)
    ↕ function calls
    Native DEX interpreter (C library, AOT-compiled into the binary)
    ↕ interprets bytecode instruction-by-instruction (NO JIT — App Store compliant)
    Tachiyomi/Mihon Kotlin APK extensions (keiyoushi repo, downloaded at runtime)
    ↕ Android API stubs (OkHttp → URLSession bridge, JSoup HTML parsing)
    Source websites
```

**Why no JIT?** Apple forbids third-party JIT compilation on iOS (only Safari's JS engine gets this). The DEX interpreter runs bytecode in **interpreted mode only** — similar to how Pythonista runs Python scripts on iOS. This is explicitly allowed.

**Why this is App Store compliant:**
- Interpreted code (like Python/Lua/JS interpreters) is allowed — it's not "downloading and running native code"
- The interpreter itself is native C code compiled into the binary at submission time
- Downloaded extensions are bytecode data, not native code
- Analogous to JavaScriptCore (Yomi's approach) — both are sanctioned interpreter patterns

**What extensions are:** When the user adds `keiyoushi/extensions` as a repo, Tachimanga downloads `.apk` files, extracts DEX bytecode, and runs it through the interpreter. HTTP calls in extensions use OkHttp API stubs that forward to `URLSession` underneath.

**The previous claim ("embedded JVM/Suwayomi-Server") was wrong.** A full JVM would be ~200MB+ and Tachimanga is much smaller. The Suwayomi-Server approach (which Sorayomi uses for external server connections) is different from Tachimanga's embedded approach.

**Implication for Yomi:** This approach is architecturally opposite to Yomi:
- Tachimanga: 100+ sources, any Kotlin extension works, requires bundled JVM (~100MB+)
- Yomi: JS plugins, native Swift, runs offline with no server required

**Bundling a JVM is not necessary.** Yomi's path to comparable source count:
1. Add Mangayomi JS format → 195+ sources (small shim, no JVM)
2. Complete Paperback shim → 100+ manga sources
3. LNReader repos → 500+ novel sources (already compatible, users just need the URL)
4. Suwayomi integration (S41) → hundreds of keiyoushi sources for power users

**Yomi's competitive advantages over Tachimanga:**
1. iOS-native SwiftUI vs Flutter (better performance, animations, iOS system integration)
2. Light novels — Tachimanga has ZERO novel support
3. Free features vs Tachimanga's premium paywall (App Lock, Notes, etc.)
4. No mandatory server — works offline with JS plugins
5. Community-driven plugin ecosystem rather than one dev's sources

### How Tachimanga's Cloudflare bypass works
From the Advanced settings "Bypassing Cloudflare automatically" toggle:
- Opens a hidden `WKWebView` pointing to the blocked URL
- WKWebView completes the Cloudflare JS challenge (browser fingerprint is authentic)
- Extracts `cf_clearance` cookie + matched User-Agent string
- Injects both into `URLSession` requests for subsequent fetches on that domain
- Result: Comick, Webtoons.com, and other CF-blocked sources work

**This IS replicable in Yomi** without a JVM. Implementation sketch:
```swift
// CFBypassManager.swift
// 1. On 403 from SOURCE.fetch, open hidden WKWebView to domain
// 2. WKNavigationDelegate.didFinish: extract cookies via WKWebView.configuration.websiteDataStore
// 3. Store cf_clearance + User-Agent per domain in memory
// 4. Inject into JSBridge SOURCE.fetch headers for that domain
```
This would restore Comick and unlock ~5+ more sources currently blocked by Cloudflare.

### Keiyoushi repo format (for reference, not for direct use)
Tachimanga accepts repos as `username/repo` (e.g., `keiyoushi/extensions`) which it converts to:
`https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json`

The keiyoushi extensions themselves are Android Kotlin APKs — **Yomi cannot run them**. But the repo URL pattern is worth adopting for Yomi's own plugin catalog multi-repo feature, using the same `index.min.json` naming convention for community repos.

---

## 8. Plugin Ecosystem — Platform Compatibility
✅ RESEARCHED (S23 + S32 + S35 + **S44 deep audit**, 2026-04-20)

### The Correct Mental Model
Yomi does not need to choose one plugin format. JSBridge already detects multiple formats at eval time. The strategy is **multi-format compatibility** — run plugins from every ecosystem by adding thin detection + shim layers. No architecture rebuild required.

### Total available sources by format (April 2026)

| Format | Ecosystem | Available Sources | Yomi Support | Status |
|--------|-----------|-------------------|--------------|--------|
| **Format A** | Hand-written Yomi | 15 (Firebase catalog) | ✅ Native | Live |
| **Format B** | LNReader/lnreader-plugins | **500+ novel sources**, 18+ languages | ✅ Native | Live. Users add repo URL in Plugin Repositories settings. JSBridge shims complete as of S47 (FormData, isAbsoluteUrl, all @libs/* modules). |
| **Format C** | Paperback 0.8 (TypeScript) | ~100+ manga sources | ⚠️ Partial shim (S24) | JSBridge shim exists. `__pbSourceId` flag. requestManager pattern mostly wired. Some sources may need further testing. |
| **Format D** | Mangayomi JS extensions | **195+ manga+novel sources** | ✅ **Implemented S44** | `injectMangayomiShims` + `injectMangayomiAdapter`. `__mangayomiSource` flag. Catalog parser added to PluginCatalogService. |
| **Suwayomi** | keiyoushi/Mihon extensions | **500–1000+** manga sources | ✅ **Integrated S41** | `SuwayomiService.swift`. User self-hosts Suwayomi-Server (JVM). Yomi connects via REST. |
| **OPDS** | Kavita / Komga servers | User's local library | ❌ Not yet | Future session |

**Realistic source count if all formats unlocked: 800+ sources across manga and novels, across 20+ languages.** No other iOS app achieves this.

### Format D: Mangayomi JS — HIGHEST NEW LEVERAGE
Mangayomi JS plugins use a class-based API very close to Format B. Delta from current JSBridge is small:

```javascript
// Mangayomi plugin structure (class, not global)
class MProvider {
  async getPopular(page) { return { list: [...], hasNextPage: bool } }
  async getLatest(page)  { return { list: [...], hasNextPage: bool } }
  async search(query, page, filters) { return { list: [...], hasNextPage: bool } }
  async getDetail(url)   { return { title, author, genre, status, chapters: [...] } }
  async getPageList(chapterUrl) { return [...urls] }
}

// HTTP client (async, not DispatchSemaphore)
const client = new Client();
const res = await client.get(url, headers);
const res = await client.post(url, headers, body);
// res.body is a string
```

Config fields: `name`, `baseUrl`, `lang`, `id`, `iconUrl`, `version`, `isManga` (bool), `isNsfw` (bool)

**To support Mangayomi plugins in Yomi:**
1. Detect `new Client()` pattern at eval time or check `plugin.getDetail` vs `global.getMangaList`
2. Inject a `Client` class shim that wraps `SOURCE._fetchSync` with async wrapper
3. Map `getDetail → getMangaDetail`, `getPageList → getPageList`, `getPopular → getMangaList`
4. Mangayomi extension repos expose an `index.json` with entries → add to PluginCatalogService

Community extension repos for Mangayomi:
- Official: `github.com/kodjodevf/mangayomi-extensions` (195+ sources)
- Community: multiple repos tagged `mangayomi-extensions` on GitHub
- Index URL pattern: `raw.githubusercontent.com/{user}/{repo}/main/index.json`

### LNReader (Format B) — Already Working, 500+ sources available
- Official repo: `github.com/LNReader/lnreader-plugins` — 285 stars, 242 forks, 500+ plugins
- Also: `github.com/CD-Z/lnreader-sources` (alternative community repo)
- Sources: Royal Road ✅, ScribbleHub ✅, NovelFire ✅, FreeWebNovel ✅, NovelBin ✅ + 495 more
- Languages: English, Chinese, Russian, Spanish, Portuguese, French, Turkish, Vietnamese, Japanese, Korean, Arabic, Thai, Indonesian, Ukrainian, Polish, and more
- **Key gap**: Yomi only deploys 12 of these 500+ to Firebase. We should let users add the LNReader repo URL directly in Plugin Repositories settings.
- LNReader catalog index: `raw.githubusercontent.com/LNReader/lnreader-plugins/master/dist/plugins.min.json`

### Paperback (Format C) — Partial shim, ~100+ sources
- App: Paperback 0.8.11 (updated April 1, 2026) — active, on App Store (id1626613373)
- Official community repo: `github.com/TheNetsky/community-extensions` 
- Many community repos tagged `paperback-source` on GitHub
- Extensions: generic MangaStream, MangaReader, MangaBox, Madara CMS types → covers many scanlation sites
- Yomi S24 shim: `require('paperback-extensions-common')` + `injectPaperbackAdapter()` post-eval
- **Remaining gap**: `requestManager.schedule()` args not fully wired for all source patterns

### Suwayomi/Tachidesk — Already Integrated (S41), Hundreds of keiyoushi sources
- Detailed in Section 12 below

### Aidoku (WASM) — Not viable for Yomi
- `.aix` packages require Rust/WASM runtime — full rewrite of all plugins
- Aidoku v0.8 on App Store with iOS 26 support, active community
- Not worth porting — different runtime entirely

### Tachiyomi/Mihon Kotlin APKs — Two viable paths exist (neither is urgent)
1. **Suwayomi bridge** (already integrated, S41) — user self-hosts, Yomi connects via REST. Zero engineering cost. Power-user path.
2. **DEX interpreter** (Tachimanga's approach) — embed a C DEX interpreter in Yomi binary, run Keiyoushi APKs natively. Estimated 2–4 months of hard work. App Store compliant (interpreted code is allowed). The "correct" long-term path if Yomi wants to compete head-to-head with Tachimanga without requiring a server. Not urgent while Suwayomi covers this use case.

### App Store compliance across all formats
All JS-based formats (A, B, C, D) run in JavaScriptCore — explicitly approved by Apple. 
Precedent: Paperback (TypeScript/JS extensions) and Tachimanga (embedded JVM) are both on App Store.
Key framing: "community source scripts" not "plugins that download executable code".

---

## 12. Suwayomi / Tachidesk Deep Dive
✅ RESEARCHED (S41 integration + S44 deep audit, 2026-04-20)

### Name history
- **Tachidesk** = old name of the project (abandoned ~2023)
- **Suwayomi-Server** = current name (rebranded for clarity). "Suwayomi" = short for "suwariyomi" (seated reading in Japanese)
- The Suwayomi GitHub org maintains both server and clients: `github.com/Suwayomi`

### What Suwayomi-Server is
A free, open-source manga reader **server** (not an app) that runs Tachiyomi/Mihon Kotlin extensions on a JVM. Any platform that runs Java 21+ can run it. ~6,800 GitHub stars, last updated April 19, 2026. Actively maintained.

```
[Any HTTP client — browser, iOS app, Android app]
          ↕ GraphQL / REST / OPDS
    [Suwayomi-Server (Java 21, Javalin)]
          ↕ AndroidCompat JVM layer
    [Tachiyomi/Mihon Kotlin APK extensions]
          ↕
    [Any manga source: MangaDex, Webtoon, etc.]
```

### Architecture layers
1. **AndroidCompat** — emulates Android APIs (Context, SharedPreferences, OkHttp) in JVM
2. **Server Core** — Javalin-based HTTP server
3. **Extension System** — converts APK→JAR, patches bytecode to run on JVM
4. **Storage** — H2 (default) or PostgreSQL + filesystem
5. **APIs** — GraphQL (primary), REST (deprecated), OPDS 1.2

### API endpoints
- `POST /api/graphql` — primary API, full schema (queries + mutations + subscriptions)
- `GET /api/graphql` — GraphiQL IDE for interactive exploration
- `/api/v1` — REST (deprecated, still works)
- `/api/opds/v1.2` — OPDS feed for any e-reader/manga app

### Clients that connect to Suwayomi
| Client | Platform | Distribution | Notes |
|--------|----------|--------------|-------|
| Suwayomi-WebUI | Web | Bundled with server | React, default UI |
| Tachidesk-Sorayomi | iOS/Android/macOS/Windows/Linux | IPA via AltStore (v0.6.3, Feb 2025), **NOT on App Store** | Flutter, free |
| Suwayomi-JUI | Desktop | GitHub | Compose Multiplatform |
| **Tachimanga** (commercial fork) | iOS | App Store | Flutter + embedded JVM. Paid features. |
| **Yomi** | iOS | App Store (planned) | Swift/SwiftUI, S41 integrated |
| Any OPDS reader | Multiple | — | Panels (iOS), KedaReader (iOS), etc. |

### Key insight: Tachidesk-Sorayomi vs Tachimanga
- **Sorayomi** (open-source, Suwayomi org): requires external server, IPA sideload only
- **Tachimanga** (commercial, `tachimanga/Tachidesk-Sorayomi` fork): bundles embedded JVM server inside the iOS app → App Store compliant. This is the "trick" — the server is embedded, not remote.

### What Yomi's Suwayomi integration already does (S41)
- `SuwayomiService.swift` connects to a user-provided URL (`AppSettings.suwayomiURL`)
- Fetches sources, popular, search, manga detail, chapters, page URLs via REST
- Sources appear in BrowseView under "Suwayomi Server" section
- Reader works end-to-end for Suwayomi-sourced manga

### What Suwayomi integration could become
Users who self-host Suwayomi (on Mac, NAS, homelab, VPS) get access to ALL keiyoushi extensions. This is a power-user feature. The right approach is:
1. Make Suwayomi setup frictionless in Yomi (URL + test connection already done)
2. Promote it as "Connect to your own Suwayomi server for 1000+ sources"
3. Link to a setup guide from within the app or GitHub wiki
4. Optionally: show Suwayomi sources alongside native JS plugin sources in Browse

### Extension count
Keiyoushi (`github.com/keiyoushi/extensions`) maintains "hundreds" of APK extensions organized by language (`en`, `zh`, `es`, `pt-BR`, `ja`, `fr`, `vi`, etc.). Each extension can expose multiple sources. Total source count accessible via Suwayomi: 500–1000+ (varies as sites go down/up).

---

## 13. LNReader Plugin Ecosystem — Full Picture
✅ RESEARCHED (S44 deep audit, 2026-04-20)

### What LNReader is
Android-only light novel reader. Closest Android equivalent to what Yomi is for iOS — and **no iOS equivalent exists**. This is Yomi's blue ocean: 0 competitors on iOS.

### Official plugin repo: `github.com/LNReader/lnreader-plugins`
- **285 stars, 242 forks** — healthy community
- **500+ plugins** across 18+ languages (confirmed from `lnreader.app/plugins` listing)
- TypeScript-based, 94.8% of codebase
- Active: 438 open issues, 10 PRs, 737 commits
- Automated GitHub Actions for publishing — plugins are built and hosted as JS bundles
- Secondary community repo: `github.com/CD-Z/lnreader-sources`

### Plugin catalog format
Published at: `raw.githubusercontent.com/LNReader/lnreader-plugins/master/dist/plugins.min.json`

Each entry: `{ id, name, version, url, lang, icon }` — nearly identical to Yomi's catalog entry format.

### Notable sources (Format B, Yomi-compatible today)
Royal Road, ScribbleHub, NovelFull, ReadNovelFull, FreeWebNovel, NovelBin, NovelFire, RanobeLib (Russian), WuxiaWorld (some CF), multiple Chinese/Korean/Vietnamese sources.

### Current gap
Yomi deploys 12 of these 500+ plugins to Firebase. **The fix is simple: add the LNReader repo URL to Yomi's Plugin Repositories settings.** Users can then install any of the 500+ plugins directly. Yomi already supports Format B natively — zero code changes needed.

### App Store compliance for LNReader plugins in Yomi
LNReader plugins are TypeScript → transpiled JS bundles. They run in Yomi's existing JSContext. Same compliance story as Format A plugins. ✅

---

## 14. Full iOS Manga/Novel Reader Landscape (2026)
✅ RESEARCHED (S44 deep audit, 2026-04-20)

### iOS readers with plugin/extension systems

| App | On App Store | Format | Source Count | Novels | Open Source | Notes |
|-----|-------------|--------|--------------|--------|-------------|-------|
| **Tachimanga** | ✅ | Embedded JVM (keiyoushi APKs) | 100+ | ❌ | ❌ (forks are) | Premium paywall. Flutter. |
| **Paperback** | ✅ | TypeScript/JS | ~100+ | ❌ | ✅ | Active (0.8.11 Apr 2026). |
| **Aidoku** | ✅ | WASM/Rust `.aix` | ~100+ | ❌ | ✅ | v0.8 with iOS 26 UI updates. |
| **Sora** | ✅ | JS modules | ~50+ | ❌ | — | Less community data. |
| **Suwatte** | ✅ | JS (v6/v7) | ~50+ | ❌ | — | Less community data. |
| **Mangayomi** | ❌ Not on App Store | JS (`new Client()`) | 195+ | ✅ | ✅ | Flutter, sideload only. |
| **Yomi** | ❌ Not yet | JS (Formats A/B/C) | 15 deployed (500+ compatible) | ✅ | ❌ | Swift/SwiftUI, best iOS UX |

### Key competitive gap: novel support
**Zero iOS apps on the App Store support light novels with a plugin system.** LNReader (Android) has 500+ plugins. Yomi is the only iOS app in this space. This is the primary positioning that no competitor can copy quickly.

### Community discussion findings (2025–2026)
- Reddit + tech articles consistently list: Tachimanga → Paperback → Aidoku as the iOS manga reader hierarchy
- "All Light Novel" app removed from App Store March 30, 2026 — confirms iOS novel reader gap widening
- Mangayomi not on App Store (iOS app doesn't work reliably) — Flutter limitations
- Users repeatedly ask: "Is there a Tachiyomi for iOS?" — Yomi answers this better than anything else if source count increases

### Self-hosted library servers (local content)
| Server | API | OPDS | iOS clients today |
|--------|-----|------|------------------|
| **Kavita** | REST + rich API | ✅ | Panels, KedaReader, Tachimanga (Komga only) |
| **Komga** | REST + rich API | ✅ | Paperback (official extension), Panels, KedaReader |
| **Suwayomi** | GraphQL + REST + OPDS | ✅ | Sorayomi (sideload), Yomi (S41), OPDS readers |

**Opportunity:** Adding OPDS support to Yomi lets users read from Kavita or Komga local libraries. This covers the offline/local collection use case and appeals to power users who already self-host.

---

## 15. App Store Strategy for Plugin-Based Apps
✅ RESEARCHED (S44 deep audit, 2026-04-20)

### What is allowed (confirmed by approved apps)
- **JavaScriptCore** for running JS scripts: ✅ Apple-approved. Paperback (TypeScript→JS), Yomi use this.
- **WASM runtime** for running `.aix` packages: ✅ Aidoku is on App Store.
- **Embedded JVM** running Kotlin extensions: ✅ Tachimanga is on App Store.
- **Downloading JS scripts at runtime** from user-provided URLs: ✅ Paperback, Yomi do this.

**Guideline 2.5.2** ("Apps should not download, install, or execute code which introduces or changes features or functionality of the app") has a JS/WebKit exemption. ⚠️ *S132: outdated — no such exemption in current 2.5.2; see §25.7 (DPLA §3.3.1(B) + Guideline 4.7).* The key: scripts must not change the app's **primary purpose** — in Yomi's case the primary purpose IS reading from sources, so adding sources via scripts is consistent with the purpose.

### How approved apps frame it (language to copy)
- **Paperback**: "Supports an extensive scripting API using TypeScript/JavaScript to extend app functionality" + "Set up and choose what repos or extensions you'd prefer"
- **Aidoku**: "Modular architecture with WebAssembly-based sources"
- **Tachimanga**: Never explicitly mentions "plugin" — says "supports reading from hundreds of sources"

### Recommended Yomi App Store framing
- ✅ "Extensible manga and novel reader with community source scripts"
- ✅ "Install community-maintained sources from GitHub repositories"
- ✅ "Supports Royal Road, ScribbleHub, MangaDex, and hundreds more via community sources"
- ❌ Never say "download and execute third-party plugins" or "extension system"
- ❌ Never show piracy-adjacent content in screenshots

### GitHub as the community hub (standard practice)
All major iOS manga readers (Paperback, Aidoku, Suwatte) use GitHub as their community + documentation hub:
- Extension repos tagged with `paperback-source`, `aidoku-source`, etc.
- Official documentation wiki linked from App Store support URL
- No app review issues from GitHub links

**For Yomi:** GitHub wiki should explain how to add plugin repos. App Store listing support URL = GitHub repo. This is industry-standard and Apple-accepted.

---

## 9. Architecture Audit — Plugin Execution Runtimes
✅ RESEARCHED (S35, 2026-04-15)

### Current: JSContext + Cheerio Shim

```
Plugin JS file → JavaScriptCore JSContext → cheerio shim → SOURCE.fetch (URLSession) → Swift
```

**Performance:** JSContext runs in same process as host app → iOS sandbox **disables JIT compilation**. Result: 12–15x slower than WKWebView for JS execution. For HTML parsing tasks, this is acceptable.

### Alternative Analysis

| Criterion | **JSContext (current)** | WKWebView JS | WASM |
|-----------|------------------------|-------------|------|
| Plugin author DX | ✅ Plain JS | ✅ Plain JS | ❌ Rust/C |
| Sync bridge model | ✅ | ❌ Async only | ⚠️ Varies |
| iOS performance | ⚠️ No JIT | ✅ JIT (+12–15x) | ✅ AOT |
| Background execution | ✅ | ❌ Suspends off-screen | ✅ |
| Existing plugins reuse | ✅ | ✅ | ❌ Full rewrite |
| Binary size impact | ✅ None | ✅ None | ❌ +~1MB |
| Memory sandboxing | ❌ | ❌ | ✅ |

**WKWebView limitation:** Suspends when not on screen — makes it unusable for background update checks. JSContext's synchronous DispatchSemaphore model is an architectural advantage.

**Targeted WKWebView improvement (S36):** NovelFire and some sources have JS-rendered synopsis/status fields. Adding a `requiresWebView: true` flag in Format B metadata triggers a targeted WKWebView load for the detail page only — without changing the general execution model.

**Verdict: Stay the course with JSContext.** One targeted improvement: `requiresWebView` flag for JS-rendered pages.

---

## 10. Claude Code Workflow & MCP Stack
✅ RESEARCHED (S22 + S35, 2026-04-15)

### Current MCP Stack Assessment

| Server | Tools | Status | Assessment |
|--------|-------|--------|------------|
| **XcodeBuildMCP** (getsentry) | 59 tools (build, test, simulator, LLDB, UI automation) | ✅ Connected | Best-in-class. Keep. |
| **context7** | Live library docs (GRDB, SwiftUI, etc.) | ✅ Connected | Essential — prevents training-data drift. Always use `use context7`. |
| **apple-docs** | developer.apple.com + WWDC search | ✅ Connected | iOS 26 API reference. Keep. |
| **github** | PR/issue management | ✅ Connected | Use for tracking issues. Keep. |
| **mobile-mcp** | iOS Simulator UI automation | ✅ Connected | Visual verification after builds. Keep. |
| **swift-lsp** | Real-time Swift diagnostics | ✅ Installed | ⚠️ SourceKit errors are noise (cross-file types not resolved). Only trust xcodebuild errors. |

### New Option: Apple's Native Xcode MCP (Xcode 26.3)
Apple shipped a native MCP server via `xcrun mcpbridge` in Xcode 26.3.

**20 tools in 5 categories:**
- File ops: XcodeRead, XcodeWrite, XcodeUpdate, XcodeGlob, XcodeGrep, XcodeLS, XcodeMakeDir, XcodeRM, XcodeMV
- Build & Test: BuildProject, GetBuildLog, RunAllTests, RunSomeTests, GetTestList
- Additional: Swift REPL, SwiftUI Previews, Symbol navigation

**Key difference from XcodeBuildMCP:** Apple's runs inside Xcode via XPC — sees SwiftUI previews and live diagnostics. XcodeBuildMCP runs headless via xcodebuild CLI — no Xcode GUI needed. They complement each other.

**Setup (add to project `.mcp.json`):**
```json
{
  "mcpServers": {
    "xcode-native": {
      "command": "xcrun",
      "args": ["mcpbridge"]
    }
  }
}
```

**Recommendation:** Add as optional supplemental MCP for SwiftUI preview rendering.

### Workflow Rules (Claude Code-first, established S22)
- Claude Code reads target file before every edit. Always.
- One file at a time, compile after each new file.
- Diagnose before prescribing: (1) read file, (2) find exact failure point, (3) write one targeted fix.
- All code, commits, docs in English (from S15 onward).
- Session close: update ROADMAP + METODOLOGIA + ARQUITECTURA + CLAUDE.md → commit + push.

### Plugin System Evaluation
Available Claude Code plugin types: Skills (slash commands), Agents (subagents), Hooks, MCP servers, LSP servers.

**Official LSP plugins available:**
- `pyright-lsp` — Python
- `typescript-lsp` — TypeScript
- `rust-lsp` — Rust
- `swift-lsp@claude-plugins-official` — ✅ **Already installed** (produces SourceKit noise — expected)

**Assessment:** Current setup is optimal. No new MCP servers needed. Consider Apple's native Xcode MCP for SwiftUI previews.

---

## 11. Strategic Roadmap — Ranked Recommendations
✅ UPDATED (S47 audit, 2026-04-25)

### The goal
**Make Yomi the most source-diverse iOS manga+novel reader by unlocking every existing JS plugin ecosystem.** Goal achieved at architectural level as of S47 — all four JS formats (A/B/C/D) plus Suwayomi are live. Focus now shifts to App Store submission + growth.

### ✅ COMPLETED: Source ecosystem unlocking
| # | Action | Status |
|---|--------|--------|
| 1 | LNReader Format B + full @libs/* shim coverage | ✅ Done S45/S47. 500+ novels, all require() modules shimmed. |
| 2 | Mangayomi Format D shim | ✅ Done S44. 195+ sources. |
| 3 | Paperback Format C shim | ✅ Done S24. ~100 manga sources. |
| 4 | Suwayomi REST bridge | ✅ Done S41. 500–1000+ sources. |
| 5 | Multi-repo catalog + LNReader/Mangayomi format parsing | ✅ Done S40/S44. |
| 6 | Cloudflare auto-bypass | ✅ Done S45. |
| 7 | FormData shim for Madara/WordPress plugins | ✅ Done S47. Unblocks 52+ LNReader sources. |

### Priority 1 — App Store submission ❌ BLOCKING
| # | Action | Status |
|---|--------|--------|
| 1 | App icon 1024×1024 PNG | ❌ Blocking. User designing (3-layer iOS 26 Liquid Glass format). |
| 2 | Age rating 18+ in App Store Connect | ❌ Blocking. New 2026 system (replaces 17+). |
| 3 | App description (drafted S33) | ❌ Blocking. Paste into App Store Connect. |
| 4 | Screenshots 6.9" iPhone | ❌ Blocking. Take on iPhone 17 Pro simulator. |
| 5 | Support URL = GitHub repo | ❌ Blocking. |

### Priority 2 — Power-user backends
| # | Feature | Value | Effort |
|---|---------|-------|--------|
| 1 | OPDS client (Kavita + Komga) | Local library readers | Medium |
| 2 | Suwayomi onboarding UX | Power users: 1000+ keiyoushi sources | Low (integration exists, need UX) |
| 3 | Complete Paperback shim testing | ~100 manga sources | Low |

### Priority 3 — Growth features
| # | Feature | Value | Effort |
|---|---------|-------|--------|
| 1 | WidgetKit ContinueReading widget | Acquisition/retention | High |
| 2 | iCloud CloudKit sync | Cross-device | Very High |
| 3 | AniList tracking | Complements MAL | Medium |
| 4 | Volume button page-turn | Reader polish | Low |

### What NOT to prioritize
- **WASM runtime**: Overkill. Revisit if 10k+ users.
- **Bundling JVM/Suwayomi-Server**: Tachimanga does this; Yomi can connect to existing installs instead.
- **Writing more hand-crafted plugins**: Community ecosystem has 800+ — all three plugin repos are now accessible.
- **Keiyoushi direct (DEX interpreter)**: 2–4 months of work. Suwayomi covers this use case adequately.

---

---

## 16. Mihon Forks Landscape
✅ RESEARCHED (S44, 2026-04-20)

These are Android forks of Mihon (itself the Tachiyomi successor). All use the same **Keiyoushi APK extension system**. None have iOS versions. None open new source compatibility paths for Yomi — the only way to access their sources from iOS remains Suwayomi.

| Fork | Repo | Stars | Key feature vs Mihon | Useful for Yomi? |
|------|------|-------|----------------------|-----------------|
| **TachiyomiJ2K** | `Jays2Kings/tachiyomiJ2K` | ~5.2k | Tablet dual-page reader, modernized toolbar | UX inspiration: dual-page layout for iPad |
| **TachiyomiSY** | `jobobby04/TachiyomiSY` | ~3.8k | Merges J2K + enhanced tracking, per-source settings, enhanced metadata | Per-source settings pattern worth studying |
| **TachiyomiAZ** | `az4521/TachiyomiAZ` | Low | Old Tachiyomi hamburger menu design | No — design is legacy |
| **Yōkai** | `null2264/yokai` | ~1.7k | Best-of J2K + infrastructure modernization | No practical value for Yomi |
| **Komikku** | `komikku-app/komikku` | ~3.7k | Auto webtoon detection, dynamic theme colors, features from SY | Auto webtoon detection (Yomi S38 already has this) |

**Key finding:** All forks share the same Keiyoushi extension ecosystem. Source count differences between forks are zero — they all have access to the same 1000+ sources. Differences are purely UX/feature-level.

**What Yomi can take from this research:**
- J2K dual-page reader for iPad → worth adding when iPad support is prioritized
- SY's per-source settings (custom headers, login, filters per source) → advanced power-user feature worth noting for a future session
- Komikku's dynamic theme colors (extracts accent from cover art) → attractive UX feature

**What NOT to do:** Fork any of these or try to run their extension system directly. All paths lead to the same Keiyoushi APKs, accessible via Suwayomi today.

---

## 17. Plugin Catalog Format: Multi-Format Support
✅ RESEARCHED + FIXED (S44, 2026-04-20)

### The problem
`PluginCatalogService` expected a single JSON format (Yomi native). When users added the LNReader catalog URL, the Extensions tab in Browse showed "Failed to load: The data couldn't be read because it is missing." This was a `JSONDecoder` failure — LNReader uses different field names.

### Format differences

| Field | Yomi native | LNReader (`plugins.min.json`) |
|-------|-------------|-------------------------------|
| Language | `language` | `lang` |
| Plugin file URL | `fileURL` | `url` |
| Icon URL | `iconURL` | `iconUrl` |
| Description | `description` (required) | absent |
| NSFW flag | `isNSFW` (required) | absent (default `false`) |
| Site name | absent | `site` (optional) |

### Fix (shipped S44)
- `PluginCatalogEntry.description` made optional (`String?`)
- Added `LNReaderEntry` private struct that decodes LNReader format and maps to `PluginCatalogEntry`
- `parseEntries(from:)` tries Yomi format first, falls back to LNReader format
- **Per-URL errors are now silent** — if one catalog URL fails (wrong format, network error), other catalogs still load. Only shows error if ALL catalogs fail.
- `LNReaderEntry.toEntry()` and `parseEntries` marked `nonisolated` to avoid Swift 6 actor isolation warnings

### Impact
Adding the LNReader catalog URL (`raw.githubusercontent.com/LNReader/lnreader-plugins/master/dist/plugins.min.json`) now works correctly and shows 500+ novel plugins in the catalog.

---

## 18. Three-Repo Strategy for New Users
✅ DECIDED (S44, 2026-04-20)

Yomi presents users with three clear source choices:

| Repo | Content | Access method |
|------|---------|--------------|
| **Yomi Catalog** | Curated manga + novels (best sources, hand-picked quality) | Pre-installed |
| **LNReader Novels** | 500+ novel sources, 18 languages | One-tap "Add" in PluginsView or paste URL |
| **Keiyoushi** | 1000+ manga (via Suwayomi server) | Settings → Suwayomi Server URL |

**Why this structure:** Yomi Catalog = curated zero-friction entry. LNReader = the massive novel catalog unlock (Yomi's core differentiator). Keiyoushi = power-user path requiring a server, presented separately because it's not a plugin catalog URL.

**In the app (shipped S44):**
- PluginsView empty state shows LNReader as a one-tap featured repo
- AddRepoSheet (toolbar `+` → "Add Repository") shows LNReader with checkmark when already added
- Keiyoushi is mentioned in README and SettingsView Suwayomi section — not as a catalog URL
- GitHub README (`github.com/PacoDealer/Yomi`) has the comparison table and step-by-step guide

**Suwayomi self-hosting removed from user-facing docs** per usability research — the setup instructions were too technical for most users. Brief mention remains with a link to the Suwayomi GitHub.

---

---

## 19. JSBridge Shim Coverage — Full LNReader Audit (S47, 2026-04-25)
✅ RESEARCHED (S47 — full scan of 131 English LNReader v3 plugins)

### require() module frequency across all 131 English LNReader v3 plugins
| Module | Plugin count | Shimmed? |
|--------|-------------|----------|
| `@libs/fetch` | 131 | ✅ S45 |
| `cheerio` | 122 | ✅ S6 |
| `@libs/novelStatus` | 110 | ✅ S45 |
| `@libs/defaultCover` | 79 | ✅ S45 |
| `@libs/storage` | 72 | ✅ S45 |
| `dayjs` | 59 | ✅ S45 |
| `htmlparser2` | 33 | ✅ S45 |
| `@libs/filterInputs` | 27 | ✅ S45 |
| `@/types/constants` | 1 (NovelFire) | ✅ S47 (returns `{}`) |
| `@libs/isAbsoluteUrl` | 1 (RoyalRoad) | ✅ S47 |
| `@libs/aes` | 1 (WTR-LAB) | ✅ S47 (returns `{}`) |

### Global constructors (not require() — Web API globals)
| Global | Plugin count | Status |
|--------|-------------|--------|
| `FormData` | 52+ (entire Madara/WordPress multisrc family) | ✅ S47 |
| `URL` | All | ✅ S44 |
| `URLSearchParams` | Many | ✅ S44 |
| `Promise` | All | ✅ S45 (SyncPromise) |

### Madara/WordPress plugins using FormData
Scribble Hub, DaoNovel, MTL-Novel, Novel Updates, WuxiaWorld.Site, Moonquill, Chrysanthemum Garden, Wuxia Blog, Pandanovel, Luminous Scans, and 42+ more. All POST to `wp-admin/admin-ajax.php` with `action=something&postid=X` as FormData. Fixed in S47 by detecting `rawBody._entries` and serializing as URL-encoded.

### Conclusion
> ⚠️ **WRONG — corrected S122 (§22.4).** This audit only checked module *names*. Running Yomi's cheerio shim under `jsc` showed `.remove()/.contents()/.get()` throw and `.a.b`/`:nth-child`/`:contains` return wrong nodes; 147 of 280 current plugins call `.remove()`.

As of S47, all 131 English LNReader v3 plugins should work in Yomi at the JSBridge level. Remaining failures (if any) are source-specific (site structure changes, Cloudflare blocks, dead sites) — not JSBridge gaps.

---

## 20. Competitor Deep-Dive & Architecture Comparison (S114, 2026-08-18)
✅ RESEARCHED (S114 — general research conversation, not a Yomi coding session; no code touched, findings compiled and committed here per Martin's explicit close-out ask so the research isn't lost)

Found via a targeted GitHub search for Swift-language manga/novel readers, then real clone-and-read investigation (not marketing claims) of the closest new entrants to Yomi's niche, plus a from-scratch build of Aidoku and Nyora to verify claims hands-on.

### Ito (itoapp/Ito) — closest positioning match to Yomi
"Anime, manga, and novels in one native iOS app," Swift 6.2, MPL 2.0, WASM plugin system (`.ito` plugins). Very early — 2 stars, ~100 commits. Validates Yomi's "unified iOS manga+novel with a plugin system" market thesis rather than threatening it at this size.
- **The WASM plugin runtime itself is closed-source** — `ito-runner`/`wasmkit` are private sibling repos; the public repo only has commit-hash pointer files. Can't verify sandboxing claims from code, and **currently cannot even be built** — the private dependency isn't published anywhere, no TestFlight/`.ipa` release either.
- **Worth stealing the shape of, if Yomi ever adds "import from Aidoku/Paperback"**: `AidokuImporter`/`SourceMatcher`/`JaroWinkler` uses a confidence-tiered fuzzy matcher to remap a foreign backup's plugin IDs onto local ones — exact match auto-confirms, ≥0.80 Jaro-Winkler similarity requires confirmation, and a margin-check against the second-best candidate (<0.08 apart) forces confirmation even on an apparent exact hit, avoiding false auto-matches between similarly-named plugins.
- Unified `LibraryItem` table (opaque JSON payload per manga/anime/novel) vs. Yomi's typed Manga/Novel tables is a real architectural fork — trades away SQL-level queryability for one shared schema. Not worth Yomi revisiting: no anime ambitions, dual-table model is mature and already wired into `CloudSyncManager`.

### Nyora (Nyora-Manga/nyora-ios) — Aidoku fork, adds cross-platform cloud sync
Manga/manhwa/manhua only (no novels), sideload-only `.ipa` (v2.7.3, unsigned, AltStore/SideStore, iOS 15+), ~1,386 commits, actively developed. Built on Aidoku's stock WASM runtime (kept intact), layers its own sync/parser additions alongside it.
- **Sync is NOT CloudKit** — a self-hosted Supabase backend: OAuth2 password grant + JWT, a Postgres-backed Edge Function doing last-write-wins upsert. A genuine alternative to CloudKit's Apple-Dev-Program blocker (Known Issue #47) — but it trades a $99/yr fee for owning/paying for/maintaining a backend, auth, and a signup UI. Not a drop-in win; a real tradeoff only worth taking if CloudKit enrollment stays blocked long-term.
- Parser engine (`kotatsu-parsers`, AOT-compiled via GraalVM Native Image to arm64, ~960 sources) is real per the client-side C ABI header, but the actual engine source and compiled binary live in separate non-public repos — not a realistic adoption path for Yomi (would need a whole separate Kotlin/GraalVM iOS cross-compile pipeline for a source catalog Yomi has no claim to).
- **Actionable, low-effort, unrelated to the sync question**: `NyoraCloudflareSolver.swift` reuses the same Safari-derived UA that earned `cf_clearance` on retry — same bug class as Yomi's own S89/S100 Kingfisher/Cloudflare UA-mismatch fixes (Known Issues #9/#34). Worth a targeted look at that one file if Yomi's Cloudflare handling ever regresses again.
- **Built from source and confirmed a real Simulator blocker, definitively**: `vendor/nyora-engine/NyoraEngine.xcframework`'s `Info.plist` declares only a `LibraryIdentifier: ios-arm64` (device) slice — no `ios-arm64-simulator` variant (a real 69MB `.dylib`, fetched via `git lfs pull`, not a pointer file). Confirmed by resolving the package graph and asking Xcode directly: `xcodebuild -destination` for the "Nyora (iOS)" scheme returns **zero concrete Simulator devices**, only "Any iOS Simulator Device" (a placeholder that never resolves) plus real connected iOS devices. Nyora cannot run on Simulator on any Mac — a genuine constraint baked into the project, not a one-off build issue.

### Plugin architecture — WASM (Aidoku/Wasm3) vs. JSCore (Yomi/JSBridge), settled with real code
Direct comparison of Yomi's real `JSBridge.swift`/`CFBypassManager` against Aidoku's public `Source.swift`/`WasmNet.swift`/`CloudflareHandler.swift` — the only publicly-readable WASM implementation among the three competitors above, and the one Nyora reuses verbatim.
- **Startup cost**: architecturally identical — both parse/instantiate once then cache (`JSBridge.init` evaluates JS once; Aidoku's `Source.init` loads WASM once via **Wasm3**, an *interpreter*, not a JIT/AOT compiler — confirmed via `Package.resolved`). WASM's "precompiled bytecode" framing doesn't translate into a real speed edge since Wasm3 interprets that bytecode too.
- **Per-request execution**: both bridge networking to native Swift synchronously (`URLSession` + `DispatchSemaphore`) and both are network-latency-bound, not CPU-bound — plugin code is trivial HTML/JSON parsing next to a real HTTP round trip.
- **Sandboxing**: same shape, different mechanism — both expose only an explicit host-function-import allowlist (Yomi: what `JSBridge` injects into the `JSContext`; Aidoku: Wasm3's `linkFunction` imports). No meaningful attack-surface gap either direction.
- **Verdict**: Aidoku's WASM choice is a developer-ergonomics/typed-language preference (Rust SDK vs. Yomi's plain JS), not a user-perceptible performance or reliability win. **Not worth chasing WASM for Yomi.**
- **Real, actionable gap found in Yomi's own code, independent of Aidoku's tech choice**: Aidoku auto-retries every Cloudflare-blocked request transparently, wired into its shared network layer everywhere. Yomi's own `CFBypassManager.autoBypass` (off-screen WKWebView solver, same underlying trick as Aidoku/Nyora — solve, copy `cf_clearance`+cookies to `HTTPCookieStorage.shared`, match UA) **is only wired into `BrowseView.swift`** — `MangaDetailView.swift`/`NovelDetailView.swift` (opening a manga / reading a chapter) fall straight to the manual "Bypass Cloudflare" button with no auto-attempt first. **Not fixed this session** — a candidate fix for a future session.

### Yuedu-reader's "Legado-format" source system — hypothesis tested and disproven
Investigated whether Legado's declarative rule-based source format might carry meaningfully lower App Store review risk than Yomi's/Aidoku's executable JS/WASM plugins (relevant to the current 5.2.2/2.5.2 compliance framing in §5 above). **It doesn't — the hybrid nature of the format undercuts the whole premise:**
- Yuedu's `RuleEngine` has a real CSS/XPath/JSON-path/regex selector layer, but also a full JavaScriptCore engine (`JSCoreEngine.swift`, 1,331 lines) + `LegadoJSBridge.swift` (1,675 lines) polyfilling Legado's Android/Rhino `java.*` API — network access, DOM parsing via SwiftSoup, cookie access, and **JS-triggered interactive WebView popups** (`startBrowser`/`startBrowserAwait`, for login/Cloudflare flows) that Yomi's own JSBridge doesn't even expose to plugin code. `<js>...</js>`/`@js:...` segments embed inline inside otherwise-declarative rule strings, auto-detected and routed to this engine.
- Real sources mix both freely — Yomi's simpler API-based sources (MangaDex) would map cleanly to pure selector rules, but anything needing pagination loops, auth, or Cloudflare handling (AsuraScans, AquaManga, the novel sites — i.e. most of Yomi's actual plugin logic) would end up in the `<js>` escape hatch anyway, running through an equivalent JSCore bridge. **Not a review-risk or complexity win** — arguably a larger capability surface than Yomi's own model.
- Side finding: Yuedu renders novel text via native CoreText (plus Readium's `ReadiumShared` for EPUB), prompting the follow-up below.

### Yomi's `TextReaderView.swift` (WKWebView-based novel reader) re-examined — confirmed correct, not a gap
Checked whether Yomi should follow Yuedu's native-CoreText approach instead.
- `TextReaderView.swift` injects a full HTML doc with a live CSS `<style>` block built from `AppSettings` (font/size/line-height/justify/padding/theme colors); settings changes re-inject just that block via a JS `outerHTML` swap — no reload, no lost scroll position. Reimplementing this in native TextKit would mean building an `NSAttributedString`/paragraph-style pipeline from scratch for zero user-facing gain. Zero WKWebView-related bugs anywhere in Yomi's 71-row Known Issues history.
- **Bonus, de-risks the backlogged Yomitan-style dictionary-lookup feature idea**: Yomitan itself is built entirely on DOM Range/Selection APIs (`caretRangeFromPoint`, `Selection.modify`) — exactly what a WKWebView content script does natively. Adding tap-to-lookup-word would be one more JS listener through the *same* `userContentController` message-handler bridge already wired up for scroll-position/read-complete tracking (see the hands-on Aidoku finding below for a real, shipped reference implementation of this feature — though for image-based manga pages via OCR, a different mechanism than the DOM-based approach that fits Yomi's novel reader).
- **One real gap, low priority**: no chapter-preload equivalent to the manga reader's S109-111 boundary-crossing feature — each chapter nav fully remounts the WKWebView.

### Keiyoushi-via-Suwayomi (S89/S90) vs. alternatives — re-confirmed with real current numbers
Martin asked directly whether Keiyoushi (the chosen strategy per §12/§16 and the live-verified Suwayomi-Server bridge, S89/S90) is really the best call, and to check alternatives. Checked two real candidates:

| Catalog | Size (2026-08-18) | Contributors | Format fit for Yomi | Server needed |
|---|---|---|---|---|
| **Keiyoushi** (via Suwayomi bridge) | 1,368+ | large, mature | zero — server executes, Yomi just calls REST | yes (already built, S89/S90) |
| **Aidoku-Community/sources** | 133 | 30 | poor — Rust→WASM, would need Yomi to build+maintain a full host-API shim matching Aidoku's evolving ABI (their SDK repos are actively changing) | no |
| **inkdex/extensions** (Paperback successor) | 71 | 2 | closest paradigm (JS-ish, Yomi has a partial adapter shim already) but tiny catalog + thin bus factor | no |

**Verdict: Keiyoushi via the existing bridge wins clearly** — ~10x Aidoku-Community's catalog, ~19x Inkdex's, zero new maintenance burden since the bridge is already built and live-verified (S89). The only real argument for either alternative is avoiding server-hosting/legal exposure entirely — but that trade buys an order-of-magnitude smaller catalog, plus for Aidoku specifically a genuinely new, ongoing Rust/WASM host-shim maintenance commitment that doesn't even lower Yomi's own community-contribution bar (Yomi's model is plain-JS plugins; Rust is a much higher bar). Martin's original assessment was correct — no action needed beyond eventually deploying the existing bridge (`~/Desktop/Projects/Yomi/SuwayomiServer-Deploy/DEPLOY.md`).

### Hands-on: built Aidoku and Nyora from source, drove the running app directly
Confirmed the Nyora Simulator blocker above by attempting a real build. Aidoku built and ran clean on Simulator (`-skipPackagePluginValidation` needed to bypass SwiftLint's interactive plugin-trust prompt in a headless build — otherwise zero issues, pure Swift/WASM, no native binary dependency). Martin then drove the running Aidoku build directly and found:
- **A shipped, production OCR-based dictionary-lookup feature** (Settings → Dictionaries): OCR runs on manga page *images* (not DOM text — Aidoku's manga pages are images, unlike Yomi's novel reader's HTML), results matched against imported Yomitan dictionaries, single-tap lookup gesture, optional "OCR Text Overlay" showing what was recognized, "Restrict OCR Languages" to scope which chapters get processed. Separate from a plain iOS "Live Text" toggle. **This is the concrete reference design if Yomi ever builds OCR-based dictionary lookup for the manga reader** (as opposed to the DOM-based approach that fits the novel reader, assessed above — two different mechanisms for two different content types).
- **Suwayomi is a first-class built-in source inside Aidoku itself** (Add Source → Built-in Sources, alongside Komga/Kavita), described in-app as running "extensions built for Mihon (Tachiyomi)." Independently validates Yomi's own S89/S90 bridge strategy — a major competitor uses the identical pattern as a core feature, not a workaround.
- **Aidoku's own CloudKit sync is still "Experimental... may trigger data loss"** — comparable maturity to Yomi's own CKSyncEngine work (S102-105), just not blocked on Dev Program enrollment the way Yomi's is.
- **Real feature gap confirmed, but overstated — corrected S115**: Aidoku has native tracker sync for 5 services (AniList, MyAnimeList, MangaBaka, Shikimori, Bangumi) — "Update After Reading"/"Automatically Sync History" toggles. ~~Yomi has zero tracker integration today.~~ **Wrong** — Yomi already had real, working MAL sync (`MALService.swift`, wired into `ChapterReaderView.swift`) at the time this line was written; this session never checked Yomi's own code before making the comparison. See §21 — S115 generalized this into a shared protocol and added AniList/Shikimori/Bangumi, closing the real gap (3 of Aidoku's other 4 services; MangaBaka skipped, deferred).
- Minor ideas, not adopted: custom library grid layout (configurable portrait/landscape row counts), an experimental native Text Reader mode alongside the image-based readers. Aidoku's Insights streak+stats screen closely parallels what Yomi already shipped in S94 — confirms parity, nothing new there.

---

## 21. Tracker API Shapes — AniList, Shikimori, Bangumi (S115, 2026-08-19)
✅ RESEARCHED + IMPLEMENTED — verified live against each service's own current docs (not training data),
then built directly against these findings same session. Full implementation in `Features/More/`
(`MangaTracker.swift` protocol, `AniListTrackerService.swift`, `ShikimoriService.swift`,
`BangumiService.swift`); see CLAUDE.md's S115 current-state entry for the fuller narrative.

**AniList** (docs.anilist.co) — the only one of the three with a client_secret-free flow: **Implicit
Grant** (`response_type=token` on `https://anilist.co/api/v2/oauth/authorize`), token returned in the
redirect URL's *fragment* (not query), long-lived (~1yr), no refresh token. GraphQL at
`graphql.anilist.co` — `Page { media(search:, type: MANGA) { id } }` for search, `SaveMediaListEntry`
mutation for progress, `Viewer { id name }` for the logged-in user.

**Shikimori** (shikimori.io — `.one` now permanently redirects here, don't hardcode the old domain) —
Authorization Code Grant, **requires client_secret** (no PKCE alternative in this API). Tokens expire in
1 day. Every request needs a descriptive `User-Agent` or Shikimori may ban the IP (5 req/s / 90 req/min
limits). Search: `GET /api/mangas?search=`. Progress: v1 `/api/user_rates` is deprecated — use v2
(`POST`/`PATCH /api/v2/user_rates`), body needs both `user_id` and `target_id`, fetched via
`GET /api/users/whoami`.

**Bangumi** (bgm.tv for OAuth, **api.bgm.tv** for REST — different hosts, easy to get wrong) —
Authorization Code Grant, **requires client_secret**, no PKCE either. Search:
`POST /v0/search/subjects` with `filter.type: [1]` (1 = Book, which covers manga/novels — first-class
in the schema, just thinner in community tooling). Progress: `PATCH /v0/users/-/collections/{subject_id}`
with `type`/`ep_status`, or per-chapter via `.../episodes`. Needs a descriptive `User-Agent` too.

**Security tradeoff, flagged to Martin directly rather than decided unilaterally**: Shikimori and Bangumi
both force embedding a `client_secret` in client-side app code (extractable via static analysis — no
first-party workaround exists in either API's design). Martin's call: embed it anyway, same as every
other open-source tracker client (Tachiyomi, Aidoku) does for these same two services — the practical
risk is limited to abuse of the app's own OAuth identity/rate-limit bucket, not any user's account or
data, since each user still authenticates directly with the real service.

---


---

## 22. Direction Reset — Sources, Hosting, Performance, Design, New Competitors (S122, 2026-09-23)
✅ RESEARCHED (S122 — research-only session, no code changes; every claim below was checked live on 2026-09-23 unless marked UNVERIFIED)

**Why this session happened.** Martin's brief (voice-memo transcript): finish Yomi no matter what. Tachimanga
feels smoother and hand-crafted; Yomi stutters/freezes and he never actually uses it. Space Grotesk made the
app look AI-generated. **Top priority: Keiyoushi (and LNReader) sources must work exactly like in
Tachimanga — add the repo URL and be done, never maintain a source himself — so library imports from
Mihon/Tachimanga resolve.** He doesn't want to host a server unless truly necessary. He reads light novels in
Safari today. Working rules for this phase: don't implement, don't assume, dig deeper, ask.

### 22.1 Tachimanga — how it really runs Keiyoushi (supersedes §7b and the S89 "server bridge" claim)

Three conflicting stories existed in our docs: §7b ("native C DEX interpreter"), S89 in CLAUDE.md/memory
("same self-hosted-server bridge as Yomi"), and the April research ("no extension system"). **Evidence
found S122:**
- Tachimanga publishes a fork of Suwayomi-Server: `github.com/tachimanga/Tachidesk-Server` (MPL-2.0, last
  push 2026-07-15, version tags `v4.x buildNNN`). It contains `libs/sqlite-jdbc-ios-3.41.0.0.jar` and
  `server/src/main/kotlin/okhttp3/*` files commented "On iOS, URLSession natively handles…" → **the Suwayomi
  server (Kotlin/JVM) runs INSIDE the iPhone app**, with networking bridged to URLSession. No external server.
- `github.com/trxlezi/tachimanga-repo` (third-party compat repo) states the iOS client downloads the
  extension's **`.jar`** (`jarUrl`), not the `.apk`; a `.jar` = the APK with `classes.dex` converted to JVM
  classes (dex2jar) and the binary manifest converted to text XML. Renaming an APK fails with
  "Content is not allowed in prolog".
- ⇒ Tachimanga executes **JVM bytecode on-device**, so it embeds some JVM interpreter. **Which engine is
  UNVERIFIED** (the Flutter app + native glue are closed source). §7b's "DEX interpreter" claim is therefore
  most likely wrong (DEX ≠ jar), and S89's "server bridge" claim is definitely wrong.
- Martin's own Tachimanga uses repo URL `https://github.com/keiyoushi/extensions/raw/repo/index.pb` →
  Tachimanga reads Keiyoushi's new protobuf index natively.
- App Store: Tachimanga v5.0 (2026-09-06), 218 MB, 4.76★ from 5,385 ratings, seller Tekbrio LLC, min iOS 15.

### 22.2 Keiyoushi changed format on 2026-08-13

- `keiyoushi/extensions` branch `repo` was "Reinitialize[d] as release-based extensions repo" on 2026-08-13.
- **Repo URL now:** `https://github.com/keiyoushi/extensions/raw/repo/index.pb` — gzip-compressed protobuf.
  `repo.json` = `{"index_v2": ".../index.pb", "meta": {"name":"Keiyoushi", "signingKeyFingerprint":"9add655a…4da2"}}`.
- The old `raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json` now returns **one stub
  extension named "Outdated App"** (pkg `eu.kanade.tachiyomi.extension.all.keiyoushi`) — old JSON clients
  see an empty/obsolete list.
- **1,397 extensions**, each published as BOTH `.apk` and a pre-built **`.jar`** in GitHub Releases
  (`release-assets.json` lists name + sha256 for both). The `.jar` exists for JVM hosts (Suwayomi, Tachimanga, …).
- keiyoushi.github.io: officially supports only **Mihon, TachiyomiSY, Komikku**; "anything else isn't
  supported so if it doesn't work, you are on your own".
- How to decode it (reusable): `curl -sL <index.pb> | gunzip | strings` shows names/pkgs/apk/jar URLs; proper
  parsing needs the proto schema (Suwayomi: `ExtensionStoreService.kt`, kotlinx `ProtoBuf`).
- **Suwayomi reads `index_v2` since 2026-06-27** (commit "Extension API 1.6 (#2120)"), included in stable
  v2.3.2243 (2026-07-13); latest preview v2.3.2363 (2026-09-23). Relevant open Suwayomi issues: #2298
  (APK→JAR conversion emits invalid bytecode for Kotlin 2.x extensions — Keiyoushi's pre-built jars sidestep
  it), #2347/#2357 (WebView glue for new `runWebView` client-hint helpers), #2364 (updates fail when
  versionName + JAR filename unchanged).

### 22.3 On-device Keiyoushi for Yomi — the open-source stack that already exists

Martin asked "is it really that complicated? It's free and the app works better." Answer after digging:
**feasible, the hard parts exist as licensed open source; still the biggest single job on Yomi's list.**

| Piece | What | Licence | Size | Notes |
|---|---|---|---|---|
| JVM | **Official OpenJDK Mobile port** (`github.com/openjdk/mobile` + `openjdk-mobile/ios-tools`), Zero interpreter, no JIT, min iOS 13 | GPLv2 + Classpath Exception (standard OpenJDK — **verify exact files before shipping**) | Prebuilt at `github.com/1Selxo/Mangatan` release `embedded-openjdk-ios13-v16` (2026-08-25): `OpenJDK.xcframework.zip` 6 MB + `java_bundle-device.zip` 9 MB, with `SOURCE_MANIFEST.txt` (commit `fc10224…`, 3 patches: zero-jni-env-lifetime, ios-libjava-global-symbols, ios-zero-runtime; libffi) | Physical devices only (Dartotsu ships a simulator stub) |
| Extension host | **M-Extension-Server** `github.com/kodjodevf/M-Extension-Server` — headless Mihon/Aniyomi extension runner with small HTTP API; built with `-PiosRuntime=true` for iOS (drops KCEF/JCEF/JOGL, swaps logging) | **MPL-2.0** (AndroidCompat from TachiWeb, Apache-2.0) | `ios-runtime-v7` `MExtensionServer-ios.jar` = **46 MB** | **Trap:** bundles NewPipe Extractor (`org/schabi`, 485 entries, **GPLv3**, used only for anime/YouTube) → build our own variant without it. Also bundles ICU4J (`com/ibm`, 6,135 entries) — size candidate to trim |
| Alternative host | Tachimanga's Suwayomi fork (§22.1) | MPL-2.0 | full server | heavier; Yomi already has a Suwayomi REST client (`SuwayomiService.swift`) |
| Reference integration | `github.com/kodjodevf/m_extension_server` (Flutter plugin used by **Mangayomi**: "iOS device: in-process OpenJDK Zero interpreter, loaded lazily without JIT"; server pauses in background) | **NO licence file** ("TODO: Add your license here") → read for understanding, **do not copy** | — | `ios/Classes/MihonEmbeddedBridge.mm`, `ios/PrepareEmbeddedRuntime.sh` (checksum-pinned downloads) |
| Reference integration 2 | `github.com/aayush2622/DartotsuExtensionBridge` (Flutter) — same OpenJDK artifacts reused verbatim; `ios/.../EmbeddedJvm.mm` | UPL (GPLv3-based) → **don't reuse code** unless Yomi goes GPL | — | runs Aniyomi/CloudStream/Tsundoku/Kotatsu backends on iOS via embedded JVM |
| Research-grade | `github.com/taizaki69/Kami` — pure-Swift DEX interpreter for Mihon APKs | none | — | 0★, experimental; not usable |
| Other JVMs looked at | `digitalgust/miniJVM` (414★, minimal JVM, Java subset — unlikely to run Kotlin/okhttp/jsoup extensions); thebaselab Code App (reported OpenJDK 8 on App Store — article NOT read) | — | — | not pursued |

**Precedent:** Mangayomi (Apache-2.0, 3.8k★, iOS **sideload only** via AltStore/SideStore — not App Store)
does exactly this stack. App Store apps running Mihon extensions on-device: **Tachimanga** and **Madomi**
(§22.7). Apple guideline 2.5.2 risk remains — precedent, not guarantee.

**Real remaining work for Yomi:** Swift ↔ JVM glue written ourselves; our own iOS host build without NewPipe;
WebView/Cloudflare glue for extensions that need a WebView (→ WKWebView); lazy JVM start + background pause;
index.pb parsing + jar install/update/signature check; device-only testing (no simulator); app size
+~60–100 MB (rough). **UNMEASURED:** JVM startup time, memory, per-request speed on Martin's phone.

**Proposed first step (awaiting Martin's answer):** a throwaway proof of concept on Martin's iPhone — embed
the OpenJDK runtime + host jar, install ONE Keiyoushi extension, load Popular + one chapter, measure launch
time / memory / app size. This removes the need for the S90 hosted server (`SuwayomiServer-Deploy/`) and its
legal exposure; Yomi's Suwayomi client stays for self-hosters.

**Server options kept for the record (if on-device fails):** A) hosted Suwayomi per S90 (Oracle Always Free
or ~$5–10/mo) — Martin's IP fetches for all users, dies if unpaid, Oracle reclaims idle VMs; C) port
extensions to our own format — rejected (Martin won't maintain sources).

### 22.4 LNReader in Yomi — measured, not assumed (supersedes §19's conclusion)

§19 (S47) concluded "all 131 English plugins should work at the JSBridge level". It only checked that each
`require()`d module name exists. **S122 tested behaviour:**
- Plugin set: `LNReader/lnreader-plugins` branch `plugins/v3.0.0` (the URL Yomi uses:
  `.../plugins/v3.0.0/.dist/plugins.min.json`), last publish 2026-09-22 — **280 plugins** (154 English).
- Module coverage (all 280): `@libs/fetch` 280, `cheerio` 242, `@libs/novelStatus` 239, `@libs/defaultCover`
  182, `@libs/storage` 127, `dayjs` 113, `@libs/filterInputs` 71, `htmlparser2` 55, `@/types/constants` 2,
  `@libs/aes` 1, `@libs/isAbsoluteUrl` 1. Only `@libs/aes` (1 plugin) is unshimmed. `fetchApi` 274,
  `imageRequestInit` 30 (cover request headers — check Yomi honours it), `fetchText` 7, `fetchProto` 1.
- **The failure point is Yomi's hand-written cheerio** (`JSBridge.injectCheerio`, ~350 lines: own HTML parser +
  selector engine; one class and one attribute per token, `>` and descendant combinators only). Runtime test —
  extracted the shim JS and ran it under macOS `jsc`
  (`/System/Library/Frameworks/JavaScriptCore.framework/Versions/Current/Helpers/jsc`):
  - `.remove()`, `.contents()`, `.get()` → **TypeError: not a function** (throws, kills that plugin call)
  - `$('.x.y')` → matches `.x` only (returned 2, expected 1) — **silently wrong**
  - `p:nth-child(2)`, `p:contains(World)` → pseudo ignored, returns all `p` — **silently wrong**
  - Methods present: attr, children, each, eq, filter, find, first, hasClass, html, is, last, map, next,
    parent, prev, text, toArray, load.
- Static scan of the 280 plugins: **147 call `.remove()`** (typically chapter-text cleanup, e.g. Madara
  `e(".manga-title-badges").remove()`), 82 `.contents()`, plus `.replaceWith/.slice/.clone/.closest/:has/
  :nth-child/:contains/[attr^=]`… — 219/251 cheerio users hit ≥1 unsupported feature (heuristic; `.append`
  may be FormData, so treat as upper bound; `.remove()` count is solid).
- `dayjs` is also a stub ("supports subtract/add/format use").
- **Fix direction (no server needed):** bundle the real libraries LNReader itself ships (cheerio,
  htmlparser2, dayjs; LNReader runs them in Hermes, all pure JS) instead of shims.
- **Upstream health:** lnreader-plugins has **545 open issues** (first page labels: 22 bug, 15 "severity:
  can't load novels"), but 65 commits to master since 2026-08-01 — actively maintained. Even with perfect
  compatibility some sources will be broken at any moment; that's upstream's job, not Martin's.
- Reusable harness (recreate in scratchpad):
  ```
  python3: slice JSBridge.swift between '#"""' and '"""#' after 'injectCheerio' → cheerio_shim.js
  t.js: load('cheerio_shim.js'); var $=cheerio.load('<div id="c"><p class="x y">Hello</p>…'); try each call
  run: <jsc path above> t.js
  ```

### 22.5 Why Yomi stutters — root causes found by reading code (NOT yet measured in Instruments)

1. **Images decoded full-size on the main thread.** Kingfisher 8.9.0: `backgroundDecode` defaults to `false`
   (`KingfisherOptionsInfo.swift` line 418); Yomi's only global option is `.requestModifier` (`YomiApp.swift:173`).
   No `DownsamplingImageProcessor`, no `ImagePrefetcher` anywhere. Tall webtoon strips and covers decode on
   main at first draw → hitches + memory pressure.
2. **Webtoon reader layout jumps** (`ChapterReaderView.swift` ~855-965): SwiftUI `LazyVStack` of `KFImage`s with
   a 2:3 placeholder that snaps to the real (very tall) height on load; `ForEach(... id: \.offset)`; two-way
   `visibleId`/`currentPage` sync with `withAnimation { proxy.scrollTo }`.
3. **Novel reader relayouts while scrolling** (`TextReaderView.swift`): `lastKnownScrollPercent` is `@State`
   read in `body` (line 238), set every ~400 ms scroll tick (line 210) → `updateUIView` (line 576) re-injects
   the whole `<style>` element via `evaluateJavaScript` → WebKit style recalc + relayout of the chapter.
4. **`UIImage.averageColor()`** (`Core/UIImage+AverageColor.swift`) creates a new `CIContext` per call, run
   `@MainActor` from `ContinueReadingRow.sampleAmbient` on a full-res cover.
5. **Library reload model** (`LibraryViewModel.loadLibrary`): full reload + `isLoading = true` on every
   `onAppear`, writes widget data each time; mutations are `Task.detached { write }` followed by a separate
   `Task { loadLibrary() }` that can run before the write lands. No GRDB `ValueObservation` anywhere.
6. **Zero automated tests** in the repo (no XCTest/Swift Testing target) across ~25,600 Swift lines; biggest
   files JSBridge 2,032, MangaDetailView 1,558, ChapterReaderView 1,409, BrowseView 1,152, TextReaderView 1,090.
   384 commits, 97 with "fix" in the subject. This is the structural reason "every audit fixes one thing and
   breaks another".
- JSBridge itself is fine threading-wise: all JS runs `nonisolated` off the main actor (sync `DispatchSemaphore`
  fetch on background threads).
- **Next step when implementing:** profile on Martin's real iPhone with Instruments (Time Profiler + Hangs +
  Allocations) before and after, not just code reading.

### 22.6 Design — Martin's call, research pending

Martin: Space Grotesk experiment made the app worse / AI-looking; Tachimanga started as an Android port but
improves; Yomi can win on graphic design + less clutter. S122 observation (not yet a decision): Space Grotesk
+ Space Mono "catalog notation" labels is a widely recognised template look; Tachimanga, Aidoku and Apple Books
use the system font. Candidate direction: SF Pro for chrome (Dynamic Type), keep a serif for novel body. **To
decide together from screenshots**, re-using `Yomi/design/DESIGN_RESEARCH.md` + §4 rather than re-researching.
Reddit confirms the audience punishes AI-looking apps (see 22.7).

### 22.7 New competitors / apps Martin found (r/mangapiracy posts, read via Firefox — Reddit blocks curl/WebFetch)

- **ArcReader** — `arcreaders.app`, App Store id6762717697, seller Thien Le, v1.2.3 (2026-09-20), 4.92★/37,
  released 2026-04-29, iOS + Android, **closed source** (dev confirmed in thread; website GitHub icon linked to
  nothing — "leftover from the site template"). Novels only (no manga), 200+ **dev-maintained built-in sources**
  (not plugins; users request sources in threads), paste-a-link import, offline downloads, on-device neural TTS
  (Kokoro 59 voices + Supertonic, 15+ languages, voice preview, lock-screen controls, sleep timer), BYO-API-key
  chapter translation (Gemini/OpenAI-compatible), EPUB (multi) / TXT / MOBI / DOCX import, tap-to-define +
  flashcards, highlights, stats/streaks, optional account sync, Pro subscription, auto-download-ahead (Premium),
  search across 20 sources in parallel, polite rate-limiting (slow downloads on some sources). Excludes AO3 on
  purpose. Thread `r/mangapiracy/comments/1wm7nue` top comments: "No point using if not FOSS", "Vibecoding final
  boss", "Just don't try to monetize it… DMCA'd pretty quickly", worry about App Store survival.
  **Take:** paste-link import, on-device TTS, tap-to-define, highlights, doc import, download-ahead + clear-read.
  **Leave:** closed source, accounts, subscriptions, dev-maintained sources, AI look.
- **Bunori** — `github.com/bunoriapp/bunori`, GPL-3.0, Kotlin, **Android only** (v2.0.2 2026-09-23, created
  2026-08-05, 34★). Own `.bext` extensions written in Rust → WASM (`bunoriapp/extensions`), concurrent
  downloads with retry/pause/resume, compressed storage, custom CSS/scripting in reader, export. Dev says he
  didn't adopt lnreader-plugins because "most were broken"; may add LNReader support later. Thread `1wna9m1`.
- **Madomi** — `pawakalabs.com/products/madomi/`, App Store id6748589728 "Madomi: Read & Translate Manga",
  seller Pawaka Empire, v1.1.18 (2026-09-17), **423 MB**, 3.41★/22, min iOS 15.5, iOS + Android. Started as a
  Chrome manga-translation extension (formerly "Fakey"). **Runs Mihon/Tachiyomi extension repos on iOS**
  (paste `index.pb` or `index.min.json`), imports Mihon `.tachibk` **and Tachimanga `.tmb`** backups,
  Komikku-style recommendations + library sync, AI page translation. How it runs extensions: **UNVERIFIED**
  (their blog doesn't say; size suggests embedded JVM + ML models). Thread `1w80c0c`.
  **Take:** Tachimanga-backup import — directly serves Martin's "import my library and it resolves" goal.
- **Aidoku** (GPL-3.0, Swift, 4.6k★): v0.9 (2026-09-03) added Yomitan-compatible OCR dictionary lookup and a
  built-in **Suwayomi** source; v0.8.2 added an experimental paged text reader for text-only chapters; v0.8.4
  (2026-07-03) fixed iOS 27 settings freezes and made backup restore take seconds. Best open-source reference
  for a hand-built UIKit reader.
- **LNReader** (MIT, 2.8k★): still **no iOS app** (issue "Add iOS support" open since 2023-12).
- **Mangayomi** (Apache-2.0, 3.8k★): iOS sideload only; manga/novel/anime; Mihon extensions on iOS via
  embedded OpenJDK (§22.3).

### 22.8 Hosting — only relevant if on-device fails

- **Firebase** (firebase.google.com/pricing): Spark (free) = Hosting 10 GB storage + 360 MB/day transfer (what
  the plugin catalog uses now); **no Cloud Functions, no App Hosting on Spark**. Blaze no-cost quotas: Functions
  2M invocations/mo + 400K GB-s + 200K CPU-s; Firestore 50K reads/20K writes per day; App Hosting 10 GiB/mo
  cached egress. Firebase cannot run Suwayomi; only Cloud Run could (JVM cold starts, persistent state
  problems) — not recommended.
- **Martin's Google account = Google Workspace**. **Workspace includes no Google Cloud
  credit.** Credits exist only for Google AI Pro ($10/mo) / Ultra ($100/mo) consumer plans (announced
  2026-01-27, claimed via Google Developer Program) or Workspace + a separate legacy GDP Premium subscription
  (new standalone Premium sign-ups closed).
- **Railway** (railway.com/pricing): Free $0 with $1/mo usage; Hobby $5/mo incl. $5 usage; RAM $10/GB-mo,
  vCPU $20/mo, volume $0.15/GB, egress $0.05/GB → Suwayomi ≈ $5–10/mo.
- **Oracle Always Free** (docs.oracle.com FreeTier): A1 = 1,500 OCPU-h + 9,000 GB-h/mo ≈ **2 OCPU / 12 GB**
  (was 4/24 when S90 was designed); idle reclaim if over 7 days CPU p95 <20% AND network <20% AND memory <20%.
- Current known recurring costs: Apple Developer Program $99/yr (Martin will pay). No server needed if
  on-device works.

### 22.9 Open questions for Martin (asked end of S122 — answers go here next session)

1. **Proof of concept first, or stutter fixes first?** Proposed: on-device Keiyoushi PoC on his iPhone
   (§22.3) as the first implementation step; alternative is the performance fixes (§22.5) first since they
   touch every screen.
2. **Which iPhone model does Martin have?** (Interpreter-only JVM speed depends on it.)
- **Answered S123 (2026-09-24):** (1) **on-device Keiyoushi proof of concept first**; (2) **iPhone 17, iOS 26.6.1**
  (A19-class chip; enough RAM for Kokoro voices too).
- Answered this session: Tachimanga repo URL = `index.pb` (Keiyoushi direct); Google account = Workspace (no
  credits); Reddit posts = §22.7.

### 22.10 Not yet researched / explicitly UNVERIFIED (don't assume next session)

- Which JVM Tachimanga and Madomi embed; Madomi's architecture in general.
- ~~M-Extension-Server's HTTP API / whether current Keiyoushi extensions run~~ → answered S123 (§22.12): API
  documented; Asura + MangaFire run after 2 fixes (on a Mac java.base-only JVM — **not yet on the phone**).
  WebView-dependent paths (MangaFire captcha) are still unhandled.
- OpenJDK Mobile licence files for the iOS build (assumed standard GPLv2+CPE).
- Real on-device numbers: JVM start time, RAM, app-size delta, battery → **KEIYOUSHI_POC.md Phase 1** (next session).
- Tachimanga `.tmb` backup format (for import).
- Whether Yomi honours LNReader `imageRequestInit`; which LNReader plugins work once real cheerio is bundled
  (needs a runtime harness against live sites).
- thebaselab "OpenJDK 8 on the App Store" article (not read).
- App Review outcome for Yomi with an embedded JVM.

### 22.11 ArcReader deep-dive — how it actually works (S123, 2026-09-24)

Method: App Store lookup API + public review RSS, `arcreaders.app` legal/support/licences pages, and the public
Android APK (`cdn.arcreaders.app/apk/arcreader-latest.apk`, 210 MB universal) unzipped + `strings` on the Dart
AOT binary `libapp.so`. Only public CDN files fetched; the authenticated API was **not** called.

**Stack (verified from the APK):** Flutter/Dart; Drift (SQLite); Riverpod; Dio; Dart `html` parser; Supabase
project `edqosjdoeoehzqeudtyv` (auth/rest/realtime/storage/functions) for accounts + sync; own REST API at
`api-arcreader.novelworlds.org` and `api(3).allnovelreader.org` behind Cloudflare; CDN `cdn.allnovelreader.org`;
RevenueCat; AdMob (rewarded video); Sentry; pdfium; **sherpa-onnx + onnxruntime** (on-device TTS). Firebase
Analytics/measurement SDK `.properties` are in the APK although the privacy policy says the app runs no Google
Analytics — SDK presence ≠ active use (UNVERIFIED). iOS build 142 MB, min iOS 15.6, 17+.

**Sources — NOT plugins, a hybrid "recipe" system** (class names in the binary: `RecipeEngine`,
`RecipeManifest`, `RecipePageFetcher`, `RecipeChapterResolver`, `RecipeHostThrottle`, `RecipeDebugScreen`;
Remote Config flag `recipe_first_enabled`):
- Server ships **declarative recipes** (per-host CSS-selector JSON via `/chapters/recipes`, `/recipes/manifest.json`)
  that the phone executes itself — fetch page on device, apply selectors. No executable code downloaded →
  sidesteps App Store 2.5.2. Sources are fixed server-side "weekly" without an app update (support FAQ).
- Fallback = **server resolver**: `/novels/resolve`, `/novels/parse-meta`, `/novels/check-updates`.
  Search is split: `/novels/search/plan` (server says what to fetch) → device fetches → `/novels/search/parse`
  (server parses) → `/novels/search/stream`. Keeps parsing logic on the server, traffic from the user's IP.
- Almost no source domains are hard-coded (only Royal Road/ScribbleHub helpers + WTR-Lab login/unlock checks via
  injected `document.querySelector` JS in a WebView — gated sources use an in-app browser).
- DMCA page: takedowns "block the source at our resolver". Central control = central liability; also what lets
  him ship "200+ sources" with zero user setup.

**TTS** — public catalog `cdn.allnovelreader.org/tts/catalog-v4.json` (v10, 2026-09-18): **140 downloadable voice
models**: Piper 82 (6–104 MB, 20 locales incl. es-AR, min RAM 256 MB+), Kokoro 47 (327 MB, **min RAM 3 GB**, 8
locales), Supertonic-3 int8 10 (119 MB, 31 languages, 2 GB), Matcha 1 (70 MB). Each entry has sha256, sample mp3,
min_ram, `requires_espeak_data`; espeak-ng data ships in the app. Plus TTS **pronunciation/filter rules**,
per-novel text replacement rules, shareable as `.arcrules` "rule packs" (import previews + one-tap undo), and
ambience loops (rain/fireplace/forest/cave/wind). The public licences page (dated v1.0, 2026-04-23) still claims
`flutter_tts`/AVSpeechSynthesizer and "cloud AI voices" — stale.

**Translation:** BYO key for OpenAI / Groq / DeepSeek / OpenRouter / Gemini / any OpenAI-compatible server,
plus the unofficial Google `translate_a/single` endpoint (free path). Dictionary = `freedictionaryapi.com`.

**Monetization:** coins. Batch download = 1 coin/chapter, max 30/batch free; daily coins + rewarded ads + referral
codes; Pro (monthly/yearly/lifetime) removes coins, 100/batch, auto-download-ahead. Opening a chapter caches it
free. Guest coins are device-local.

**UX details worth noting:** onboarding is a 4-chapter bundled "Welcome to ArcReader" *novel* that teaches the app
by using it; paste-link + share-sheet + in-app browser as the three add paths; smart prefetch N+1..N+4; "read now"
at 10% of a batch; local notification when a batch finishes; sentence highlight during TTS; JSON export (chapter
bodies referenced by URL); public-domain catalogs (Gutenberg, Standard Ebooks, ManyBooks, Global Grey); per-novel
comments (`/novel/:key/comments`).

**Trust/quality signals:** homepage "unedited" store reviews are dated Feb–Apr 2026 "v1.0" — before the
2026-04-29 release. App Store reviewer (v1.0.26): "Super clean **Claude code UI** 🤣"; another: "Tachimanga but for
Novels". Website = Newsreader + Geist + JetBrains Mono with mono "Document · 04 · Credits" labels — the same
template look §22.6 wants Yomi to leave. Community (§22.7): closed source is the main objection.

**What this means for Yomi (candidates, not decisions):**
- Martin's rule "no maintaining sources" rules out ArcReader's model (it needs a dev who fixes recipes weekly + a
  server). Yomi keeps LNReader/Keiyoushi repos. Borrowable idea: a *generic* on-device extractor for "paste any
  link" when no installed plugin matches (readability-style, no per-site upkeep).
- TTS is his strongest feature and it's replicable on-device: sherpa-onnx has iOS support (licence + iOS
  packaging UNVERIFIED), Piper voices are small (6–60 MB), Kokoro needs ≥3 GB RAM. Voices as optional downloads,
  not bundled. AVSpeechSynthesizer remains the zero-download default.
- Free translation on iOS: Apple's on-device Translation framework (UNVERIFIED which iOS version/API shape fits)
  instead of an unofficial Google endpoint.
- Cheap wins: tutorial-as-a-book onboarding, share-sheet import, prefetch-ahead + read-while-downloading,
  batch-done notification, per-novel text replacement rules (kill "translator note"/watermark junk), sentence
  highlight in TTS, sleep timer.
- Avoid: coins/ads/accounts, fake testimonials, the Geist/mono template look.

### 22.12 Keiyoushi on-device PoC — Phase 0 (Mac) verified (S123, 2026-09-24)

Plan + results live in **`Yomi/KEIYOUSHI_POC.md`**; scripts in `scripts/keiyoushi-poc/`. Verified facts:

- **M-Extension-Server** (`kodjodevf/M-Extension-Server`, MPL-2.0, pinned `6685bdc`): one HTTP endpoint
  `POST /dalvik` with `{method, data: base64 APK | extensionId, page, search, mangaData, chapterData, lang, …}`;
  methods `getPopularManga/getLatestManga/getSearchManga/getDetailsManga/getChapterList/getPageList/…`; returns
  `X-Mangayomi-Extension-Id` handle; images served via its own `/image/<uuid>` proxy. iOS entry =
  `mextensionserver.EmbeddedBridge.start(port, appDir)` (loopback only), `pause()`, `stop()`, `isRunning()`.
  Loader converts APK→JAR with dex2jar on every load (in-memory cache only). Forwards the caller's
  `User-Agent` and `Cookie` headers into extension requests.
- **OpenJDK Mobile iOS runtime** (`1Selxo/Mangatan` release `embedded-openjdk-ios13-v16`, 2026-08-25, built from
  `openjdk/mobile` `fc10224`): `libdevice.a` (arm64 device only, **no simulator slice**) + a Java home whose
  `release` says **`MODULES="java.base"`**; `sun/security/ec` is inside `java.base`; libffi is inside the archive.
  Links into a dylib needing only libz/libc++/Foundation/CoreFoundation/Security. Mangayomi ships exactly this
  runtime + the `ios-runtime-v7` jar.
- **`jdeps` of the server jar**: besides `java.base` it references `java.desktop` (AndroidCompat graphics/text,
  TwelveMonkeys ImageIO), `java.xml` (jsoup helper, android.sax), `java.logging` (NanoHTTPD, OkHttp, protobuf, dx),
  `java.sql` (Jackson ext, android.database) — code paths touching these fail on the phone. `java.logging` is
  hit on every start → our shim. QuickJS runs via `quickjs4j` on the **Chicory pure-Java WASM** runtime (no JIT
  needed).
- **Keiyoushi (2026-09-24)**: Asura Scans `en.asurascans` v1.6.69 and MangaFire `all.mangafire` v1.6.34 both exist
  as `.apk` + `.jar`. New shared base `keiyoushi.source.KeiSource` adds `CompressionInterceptor(Brotli, Gzip, Zstd)`
  and zstd-compresses its filter cache on disk → requires `com.squareup.zstd` (JNI) from the host. Asura unscrambles
  "tiles" pages with `android.graphics` (AWT-backed in AndroidCompat); MangaFire signs requests in pure Kotlin
  (`VrfSigner`) but solves its shape-captcha in an Android WebView (`runWebViewBlocking`).
- **Result:** with our `java.logging` stand-in + `NoZstdInterceptor` patch, both sources work end to end on a
  java.base-only, interpreter-only JVM (table in KEIYOUSHI_POC.md). **MangaFire returns duplicate translations**
  (Devil Butler: 1,516 English chapters, 592 numbers twice — `official` + `unofficial`), so the "clones" problem
  Martin saw on MangaDex is Keiyoushi-wide → Yomi needs a per-title "one translation per chapter" dedupe.
- **aircompressor** (both 2.0.2 and v3 3.3) depends on `jdk.unsupported` (`sun.misc.Unsafe`) → not usable as a
  pure-Java zstd on the phone.
- Device facts: Martin's iPhone 17 (iPhone18,3, iOS 26.6.1) is paired, Developer Mode on; the only signing team is
  the free Personal Team `F9R33MN82P`; Yomi's entitlements (push, iCloud/CloudKit) can't be signed by it → PoC in a
  separate lab app.

### 22.13 Keiyoushi on-device PoC — Phase 1 (iPhone) PASSED (S124, 2026-09-24)

Real Keiyoushi extensions ran **on Martin's iPhone 17 (iOS 26.6.1), inside a free-Personal-Team-signed app, no
server**: `Labs/YomiBridgeLab` = our clean-room ObjC++ host (`JVMHost.mm`: one VM on a dedicated 16 MiB-stack
`NSThread`, `JNI_CreateJavaVM` → `EmbeddedBridge.start`) + a SwiftUI driver. Asura Scans and MangaFire both passed
popular → search → details → chapters → pages → first image (decoded), cold and warm, no crash. JVM create 45 ms,
bridge start 366 ms, first extension call 4.3–7.4 s (incl. dex2jar), later calls mostly network-bound; footprint
62 MB after start, peak 164 MB. Full table + the four things that broke: `KEIYOUSHI_POC.md` Phase 1.
Key new fact: **on iOS HotSpot ignores `-Djava.home`** and uses `<dir of JVM binary>/lib` — an embedding app must
put the Java home there (verified in `openjdk/mobile` `fc10224` `os_bsd.cpp` + ios-tools' sample app layout).
The only runtime error seen was the already-known zstd filter-cache JNI failure (`com.squareup.zstd.JniZstdKt`:
"Unsupported OS: darwin"), harmless to requests. Zero's speed is **not** the bottleneck at this scale.

### 22.14 "Keiyoushi for novels" — which novel repos exist, and the fix for LNReader (S125, 2026-09-24)

Martin's question: is there a Keiyoushi-style repo for novels, or should Yomi make one? Measured via GitHub/GitLab
APIs + the repos' published indexes, same day:

| Ecosystem | Sources | Format | Licence | Last push | Runs in Yomi? |
|---|---|---|---|---|---|
| **LNReader plugins** (`lnreader/lnreader-plugins`) | **280** (154 en) | JS/TS | MIT | 2026-09-24 | Yes — JSCore, but the cheerio shim breaks ~half (§22.4) |
| IReader (`IReaderorg/IReader-extensions`, branch `repov2`) | 143 (98 en) | Kotlin, IReader's own source API | MPL-2.0 | 2026-09-14 | No — not Mihon's API, the Keiyoushi runtime can't load it as-is |
| Shosetsu (`gitlab.com/shosetsuorg/extensions`) | 58 (40 en) | Lua | — | 2026-09-23 | No — needs a Lua runtime |
| Mangayomi (`m2k3a/mangayomi-extensions`, original `kodjodevf` archived 2025-10) | 9 novel | Dart/JS | Apache-2.0 | 2026-09-03 | Not worth it |
| ArcReader | "200+" | server-side recipes, closed | — | — | No — its developer maintains them (§22.11) |

**Tsundoku** (`tsundoku-otaku/tsundoku`, Apache-2.0, ★98, pushed 2026-09-13) is a Mihon fork for novels on Android.
Its novels come from **LNReader plugins** run in QuickJS (`app/.../jsplugin/`: `JsPluginManager`, `JsSource`,
`JSLibraryProvider` 2,525 lines), plus a GPLv3 compat extension for Shosetsu/IReader (`wasu-code/novel-compat-shosetsu`).
Its own `tsundoku-otaku/extensions` repo is 404. So the Android novel ecosystem converged on the same repo Yomi
already uses: **LNReader is the Keiyoushi of novels.** Making a Yomi repo would mean maintaining sources — ruled out.

**The fix, verified:** Tsundoku ships a real cheerio bundle (`app/src/main/assets/js/vendor/cheerio.bundle.js`,
343 KB, exposes `globalThis.__realCheerio.load`; experimental behind a pref, default is a Jsoup-backed wrapper).
Loaded into macOS `jsc` (the JavaScriptCore Yomi uses), it passed every case the Yomi shim fails: `.x.y` → 1,
`p:nth-child(2)` → "World", `.remove()` works, `.contents()` 2, `.get()` 2, `[class^=x]` 2, `.closest('div')` → c.
→ Replacing `JSBridge.injectCheerio` with a real cheerio bundle is feasible in JSCore, no new engine needed.
Build our own bundle from npm `cheerio` with the repo's existing esbuild setup (known version and provenance, MIT)
rather than copying Tsundoku's minified file. Same for `dayjs` (stub today). Then measure: run every LNReader
plugin's popular + one chapter parse in-app and count passes, instead of assuming.

**Result (same session, S125):** shipped the bundle — measured English LNReader plugins working end to end
(popular → novel → chapter) went from **7/157 to 67/157**. The shim was only part of it: Yomi's URL/URLSearchParams
dropped query strings, fetchApi faked `status: 200` with no `url`, and paged chapter lists (`parsePage`) were never
called. Of the remaining 90, ~43 are upstream plugins whose site changed layout (200 page, 0 items parsed), ~21 are
Cloudflare/captcha (need the in-app bypass), ~13 unreachable. Details in CLAUDE.md "Current state" item 5.

Other things worth borrowing from Tsundoku later: LNReader backup import (`LNReaderBackupImporter.kt`), NovelUpdates
tracker, a per-plugin site resolver.


## 23. S128 audit + research — reader feel and app smoothness (2026-09-25)

Trigger: Martin's field report (ROADMAP "S128"). Rule: **no fixes until this is done; then one batched pass.**
Clean build: succeeds, **0 compiler warnings**. 93 Swift files, ~27,900 lines, **still zero tests**. 404 commits,
122 with "fix" in the subject.

### 23.1 Novel reader bugs — causes found in code

- **Next chapter does nothing** (suspected, not yet reproduced): `ReaderWebView.updateUIView` re-injects only the
  `<style>` element and never loads new body HTML. A new chapter appears only if SwiftUI tears the web view down,
  which happens when `isLoading` renders `true` in between. A preload-cache hit (`loadContent` returns the cached
  chapter immediately) can skip that render, leaving the old chapter on screen. Quit + reopen builds a fresh view,
  which matches the symptom. Verify before fixing.
- **Short scroll opens the menu** (confirmed by reading): a native `UITapGestureRecognizer` on the web view with
  `shouldRecognizeSimultaneouslyWith → true`. A small drag within the tap slop, or a touch that stops a fling,
  counts as a tap. LNReader avoids this by using the DOM `click` event (WebKit does not send `click` after a
  touch that scrolled) plus `ignoreClickUntil` after any move >8 px (`assets/reader/js/core.js` ~L818-906).
- **Style re-injected on every scroll tick** (S122 §22.5 #3, still true): `lastKnownScrollPercent` is read in
  `body`, so each ~400 ms scroll update re-runs `updateUIView` → replaces `<style>` → WebKit style recalc of the
  whole chapter mid-scroll. A likely direct cause of the reader not feeling smooth.

### 23.2 "Not smooth" — Browse, opening titles, everywhere (code-read; NOT yet measured on device)

Ranked by likely impact:
1. **Opening a manga/novel waits on the network before showing anything.** `MangaDetailView.loadChapters` and
   `NovelDetailView.loadChapters` show a spinner until the plugin fetches the *entire* chapter list from the site,
   even for library titles whose chapters are already in the DB. Mihon/Tachimanga show the saved list at once and
   refresh behind it. Biggest perceived-speed problem.
2. **Every cover cell runs 4 DB queries on appear** (`MangaCoverCell` `.task`: unread, downloaded count,
   `fetchAll` chapters = every chapter row just to compute progress, `fetchOne` manga), then sets 7 `@State`
   values → several re-renders per cell while scrolling Library and Browse grids. `NovelCoverCell` does 1 query.
   Fix direction: one aggregate query per screen (GROUP BY mangaId) passed into cells.
3. **Covers decode at full size.** No `DownsamplingImageProcessor` anywhere (S122 #1). Correction to S122: turning on
   `backgroundDecode` is **not** a proven fix in SwiftUI — Kingfisher #2058 (open) reports it still decoding on main in
   `KFImage`, and in #1917 the maintainer's `backgroundDecode` + drop-`.fade` suggestion didn't remove LazyVGrid
   hitches. Downsampling to cell size cuts the decode cost wherever it runs, so do that first and measure.
   `.fade(0.2)` per cover also adds a transaction per image while scrolling.
4. **Plugin engine built on the main thread.** `JSBridge(scriptURL:)` evaluates the 450 KB `yomi-js-libs.js` (S125)
   in every new context. Called on main from `SourceBrowseView.loadContent`, `MangaDetailView.loadChapters`,
   `NovelDetailView.loadChapters`, `ContinueReadingRow`, `LibraryView` bulk download, and `UpdatesView` (explicit
   `MainActor.run`, once per title during an update check). Measured: 12–23 ms per eval in macOS `jsc` (with and
   without JIT). Costs a frame or two per open; small alone, not the main freeze. Cache one bridge per source.
5. **Library reload model** (S122 #5, still true): full reload + `isLoading = true` on every `onAppear`.
6. **`averageColor()` builds a new `CIContext` per call** on main (S122 #4, still true).
7. **Browse source list**: `duplicateNames` rebuilds `allItems` and does an O(n²) scan *per row* → O(n³) per
   render; `mangaItems`/`novelItems` re-sort with localized compare each render. Only hurts with many sources.
8. Detail screens start 5–7 independent `.task`s (AniList score, categories, storage size…), each landing as a
   separate state change → several re-layouts of a long `List` right as it opens.

**Measure before and after** (Martin's iPhone 17, Release/personal build): Instruments *Animation Hitches* + *Time
Profiler* on (a) scrolling Browse → a source grid, (b) opening a library manga and a library novel, (c) Library
scroll. CLI: `xcrun xctrace record --template 'Animation Hitches' --device <udid> --attach Yomi`. Add
`os_signpost` intervals for "tap title → chapters visible" so the fix shows as a number.

### 23.3 Reader architecture decision — keep WKWebView, restructure it

Question: infinite scroll, swipe, tap zones, pages mode, TTS highlight and translation all depend on how the chapter
is rendered. Options were a web view (today), native TextKit, or a native list of paragraphs.

- **Native text is the worse fit.** Converting HTML to `NSAttributedString` must run on the main thread and is meant
  for simple markup. TextKit 2 has reported large-document scrolling stutter (Apple forums 729491, fix = fall back
  to TextKit 1) and image-attachment lag (775509). A list of paragraph cells breaks text selection across paragraphs,
  and with it the system Look Up/Translate/Share menu a web view gives for free.
- **Precedents stay on the web.** LNReader (the plugin ecosystem Yomi runs) renders chapters in a WebView and
  implements tap zones, swipe, a paged mode (CSS/transform pages) and TTS text-node walking in one JS file. Apple
  Books renders EPUB with WebKit.
- **Infinite scroll = one document, appended chapters**, not stacked web views. Riffle (Android, Readium-based) stacked
  one WebView per chapter and hit GPU texture limits (raster stopped at 16,384 px) and tile-memory blanks; the fix
  was capping each view to 3 viewports and sliding it (PR #1100). One WKWebView with `<section
  data-chapter=…>` blocks avoids that class of problem: append the next chapter near the end, drop sections more
  than ~2 chapters behind with scroll-offset compensation, and report the visible chapter + per-chapter % with
  `IntersectionObserver`. Unverified on iOS: memory with ~3 long chapters loaded, and that offset compensation
  doesn't jump. Test with a real 5k-word WeTried chapter before committing to it.
- **Move gestures into JS** (one reader controller script, LNReader-style): center `click` toggles the menu (option:
  1 tap / 2 taps); optional top/bottom tap zones scroll a page; swipe = horizontal distance > 2× vertical and
  > ~180 px, next from the right half / previous from the left half; `ignoreClickUntil` after any move. Keep swipes
  away from the left screen edge, which iOS uses for "back".
- Data model changes infinite scroll forces: read/progress per section instead of per screen; "current chapter"
  (history, last read, tracker) updates when a boundary is crossed; the 90 % `readComplete` becomes per section.
  The index-based `NovelChapter.id` (`<novelId>-ch-<index>`) shifts when a source inserts a chapter — fix or at
  least guard before more features key off it.

### 23.4 Testing (the structural cause of regressions)

Add a test target first, before the fix pass: Swift Testing unit tests for pure logic (chapter ordering, id
mapping, progress merge, the new gesture thresholds), plus 2–3 XCUITests for the reader (open chapter → Next →
new text; short drag doesn't open the menu). Each bug in §23.1 gets a test that fails first.

### 23.6 Baseline measured on device (S129, 2026-09-25)

Martin's iPhone 17 (iOS 26.6.1), **Release** personal build (`scripts/build-personal.sh --release`), Time Profiler +
Hitches + Points of Interest, 45–60 s per run with Martin driving. Signposts: `Core/Perf/Perf.swift`. Tools:
`scripts/perf/record.sh <name>` (attaches to the open app) → `scripts/perf/summarize.py`. Traces in `perf-traces/`
(gitignored). **These are the numbers step 6 must beat.**

| Run | Hitches (total / worst) | Hangs | Intervals |
|---|---|---|---|
| 1 Library scroll | 19 / 221 ms / 17 ms | 0 | LoadLibrary 3–6 ms |
| 2 Browse, Keiyoushi sources | 14 / 171 ms / 17 ms | 0 | KeiyoushiPage 0.75 / 1.4 / 1.5 / 1.9 / 2.0 / 5.8 / 17.3 s (+1 unfinished) |
| 3 Open library titles | 33 / 592 ms / 83 ms | 801, 722, 326 ms | OpenManga 467, 473 ms · OpenNovel 1.70, 2.08 s · NovelChapter 807 ms |
| 4 Novel reader + Next | 20 / 538 ms / 142 ms | 589, 541, 263, 262 ms | NovelChapter 2 ms, 677 ms · OpenNovel 1.65 s |

What the samples say (corrects/extends §23.2's code-read ranking):
- **Scrolling is fine.** Library and Browse grids hitch only at the one-frame level (≤17 ms) in Release. Cover cell
  queries (§23.2 #2) and full-size decode (#3) are not a visible problem at this library size — ImageIO/AppleJPEG was
  ~2.4 s of *background* CPU in run 2, never on main. Lower their priority.
- **Browse is slow because of the JVM, not the network or SwiftUI.** During Keiyoushi page loads one JVM thread sat at
  ~100 % of a core for ~42 s straight (`BytecodeInterpreter::run` / `ZeroInterpreter::main_loop` in
  OpenJDKRuntime — Zero, no JIT on iOS), then dropped to idle when loads ended. Plus ~4 s in libz. New item:
  measure what the extension does per page under Zero (Jsoup parse? OkHttp gzip? class loading on first use) —
  first-page vs later-page times suggest warm-up matters; consider keeping the JVM warm / caching parsed pages.
- **Opening a novel hangs 800 ms on main**: `ExtensionManager.bridge(for:)` → `JSBridge.init` → `injectCheerio`
  on the main thread (§23.2 #4 confirmed — worse than the 12–23 ms `jsc` estimate: a whole new context + 450 KB
  libs). It happens again when a chapter opens (reader builds its own bridge).
- **New: `NovelDetailView` renders all ~880 chapter rows eagerly and keeps re-rendering them while the reader is open
  on top.** `chaptersSection` + a per-row `onLongPressGesture` = 414 main samples (0.4 s) in run 4 and the 262–326
  ms hangs. Something the detail view observes (download manager progress / reader state) invalidates its body.
- **Opening the reader: `WKWebView.init` on main** inside a 541 ms hang (plus the bridge build above).
- **Two hangs are blocked, not busy** (589 ms and 801 ms with 1–2 main samples): the main thread was waiting.
  Time Profiler can't show on what — a System Trace (thread states) is needed if they survive the fixes.
- **Bug #1 reproduced on device** (Martin: Next left the old chapter on screen at least once). The run shows one
  NovelChapter load of **2 ms** (downloaded chapter) — consistent with §23.1's cause: a fast local load never renders
  `isLoading = true`, so the web view isn't rebuilt.
- Style re-inject on scroll (§23.1 #3): not visible in Yomi's main-thread frames; its cost, if any, lands in the
  WebContent process. Unconfirmed — still remove it in step 4, but don't count it as a measured win.

Revised fix priority for the batched pass: (1) bridge off main + cached per source, (2) novel detail: lazy chapter
list + stop invalidating it from the reader, (3) detail screens DB-first, (4) reader controller (fixes #1 #3 #4 #2),
(5) Keiyoushi page cost under Zero, (6) the rest of §23.2.

**Step 5 result (S134, 2026-10-01): the Keiyoushi Browse cost was covers, not pages.** Method: Java thread dumps
from the phone (`devicectl device process signal --signal SIGQUIT` → the JVM prints every thread with `cpu=` to the
`--console` stream — works in the embedded Zero VM and doesn't kill the app), then a diagnostic OkHttp network
interceptor (`WireStatsInterceptor`, server patch, off unless `-Dyomi.wireStats=true`) logging bytes per request.
- The thread `OkHttp api.asurascans.com` (HTTP/2 reader) burned **4.6 s CPU for the first page and ~7 s per page
  after**; every sample was AES-GCM (`GHASH.blockMult`, `AES_Crypt.implEncryptBlock`) — Java TLS with no hardware
  crypto, interpreted. Same 4 pages on Mac `-Xint`: 139 ms on that thread.
- The API pages themselves are ~19 KB br each (0.17–0.8 s). The bytes were **covers**: M-Extension-Server rewrites
  every `thumbnail_url` to its own image proxy (`MihonImageProxy.registerPoster`), so Kingfisher pulled each cover
  through the JVM — Asura covers are 0.15–5.4 MB, ~25 MB for 3 pages, up to **8.2 s per cover**. The proxy URLs
  also carry a per-launch port + token, so Kingfisher's disk cache never hit across launches, and library entries
  saved with one died at the next launch.
- Fix: server patch keeps `thumbnail_url` original and adds `thumbnail_proxy_url`; Yomi (`KeiyoushiCovers`) loads
  covers natively with the source's own headers (`headersManga`: Referer/Origin, persisted per cover host) and uses
  the proxy only as a Kingfisher `alternativeSources` fallback. `MangaDetailView` replaces stale proxy covers.
  **After: same 3-page Asura run, the connection thread used 61 ms CPU (was 26.9 s), no cover went through the JVM.**
- Not fixed, same cause: **manga reader pages from Keiyoushi sources still go through the proxy** (`fetchPage`) and
  are decrypted in Java — expect seconds per page image. Unlike covers they can't simply go native: some extensions
  descramble pages in an OkHttp interceptor. Measure in step 6; candidate fix = native fetch when the extension
  registers no image interceptor, or route the JVM's HTTPS through URLSession.
- Smaller, measured on Mac `-Xint`: Keiyoushi's `parseAs` reads JSON with `decodeFromBufferedSource`
  (code-point-at-a-time over okio, ~30 % of warm-call samples); `decodeFromString(source.readUtf8())` is 1.6× faster
  (38 → 24 ms for 64 KB). Not done — small next to the above.

**Step 6 (S134, in progress).** Same phone, Release, `perf-traces/s134-*.trace`.
| Run | Hitches (total / worst) | Hangs | Notes |
|---|---|---|---|
| 1 Library scroll | 7 / 67 ms / 13 ms (was 19 / 221 / 17) | 0 | |
| 2 Browse MangaFire + Asura (after step 5) | 78 / 1296 ms / 100 ms (was 14 / 171 / 17) | 338, 288 ms | KeiyoushiPage 418 ms |
Run 2 is worse because covers now actually arrive (before, most never finished through the JVM) — at full size. Both
hangs: main mostly blocked, the rest decoding **PNG** in `CA::Render::prepare_image` ← `_SwiftUIProxyImage`:
Kingfisher stores WebP covers in its disk cache as PNG and returns an undecoded image, so a multi-megapixel decode
landed on main at render time (§23.2 #3, now measured). Fix (`coverSized()` in `Core/CoverImage.swift`):
`DownsamplingImageProcessor` 180×270 pt at display scale + `backgroundDecode()` on every cover `KFImage`.
**Not yet re-measured** — next: redo run 2, then 3 (open library titles), 4 (novel reader + Next), and new 5
(Keiyoushi manga reader pages — still through the JVM proxy).
Tooling notes (also in `scripts/perf/record.sh`): xctrace needs a live CoreDevice tunnel or it fails "Timed out waiting
for device to boot" — hold one with `devicectl device notification observe --name x --session-timeout 7200 &`
(`--timeout` alone exits at 300 s); it resolves `--attach` by pid or by name inconsistently, so the script tries both
and warns when a trace has < 200 samples (idle/background app — one S134 run recorded 13).

### 23.5 Sources

LNReader reader JS: github.com/lnreader/lnreader `assets/reader/js/core.js`; infinite-scroll requests lnreader
#1776, #49. Riffle continuous mode PR github.com/pkmetski/riffle/pull/1100. Readium swift-toolkit #684 (no
cross-chapter continuous scroll). Kingfisher #2058, #1917, Cheat-Sheet wiki (downsampling). Apple Developer Forums
threads 729491, 775509. Sarunw "display HTML in UILabel/UITextView" (HTML importer main-thread note).


## 24. Discord community research — Mihon, LNReader, Tachimanga (S130, 2026-09-26/28)

Source: exports of the three Discord servers (2025-09-26 → 2026-09-26; Mihon `chat` and Tachimanga `chat` only the last
6 months). **Local only, never commit them** — they are other people's messages. Raw JSON, a compact text copy
and a full-text index live in `~/discord-exports/` (see its `README.md` for how to search). 185,731 messages: Mihon
146,859 · LNReader 35,791 · Tachimanga 3,081. Everything below is what people *said* on Discord, not verified elsewhere.
The export got the Discord account disabled; **do not re-run it** — missing channels are pasted by hand (§24.7).

### 24.1 Competitors doing what Yomi does

- **TachiyomiAZ iOS** (fork maintainer az4521, mostly AI-written): Aidoku's UI + Suwayomi compat layer + an
  interpreter-only JVM running Mihon `.jar` extensions on iOS — the same approach as Yomi's Keiyoushi runtime. GitHub
  release `ios-nightly` 2026-09-19 (`az4521/TachiyomiAZ`). He says the Mihon team endorses it; iOS 15+. He also says
  Aidoku's extension runner is not FOSS, so no fork can reuse Aidoku extensions.
- **Mihon for iOS (long-term).** Admin Antsy is making the code Kotlin Multiplatform and removing okhttp/injekt from
  the extension lib ("WebView passed by the context"). Asked whether Mihon iOS will run the `.jar` extensions:
  "potentially not… I'll have to see if wasm comes first or I finish the app first" (2026-08-15). Patreon post
  "AntsyLetter #2: Designers and iOS groundwork" 2026-08-03 (S131 correction: 2026-09-18 is only when a user asked about
  it); moderators insist it is very long-term. **Risk for Yomi:** the `.jar` format may not be the
  future extension format — keep Yomi's extension layer swappable.
- **LNReader will not ship iOS.** Its devs own no Apple devices; an old half-working iOS build was never maintained
  (2025-10 → 2026-04). The iOS slot for an LNReader-plugin novel reader is open. ⚠️ *S132: no longer — Lipex (App Store,
  2026-07) and Buny (TestFlight) now run LNReader-style repos on iOS; see §25.13.*

### 24.2 How Tachimanga works (from its release notes and owner replies)

- Its runtime imitates Android APIs one at a time: build449 added `Bitmap.setPixels`, `Rect.set`, the Protobuf
  singleton and fixed `VerifyError`/`NoClassDefFoundError`; build506 fixed missing `url` in `WebViewClient`
  callbacks and custom User-Agents in WebView. Supports extension lib 1.6 (`getMangaUpdate`, one call for manga +
  chapters). Expect Yomi's runtime to need the same kind of per-API patching.
- Pushes fixes without an App Store update ("wait a minute for the patch to download and apply").
- iPad lag (ProMotion, iPad mini A17 Pro) was Flutter's Metal layer — fixed with a Labs toggle + an FPS monitor.
- Discord automod deletes the word "extension" (staff: to cut down source-support requests).
- **Backup format:** `.tmb` is a zip containing a plain, unencrypted SQLite `tachimanga.db` (owner, 2026-07-21). It
  also exports Tachiyomi-format backups. → A "switch from Tachimanga" importer in Yomi is feasible (Madomi has one).
- **2026 roadmap** (`app-dev`, posted 2026-02-18; the owner says it is a vision, not a promise). Done: bulk migration,
  Liquid Glass, wide-page detection in double-page layout, auto read mode, "smarter updates". Planned: previous chapter
  when scrolling up, a modern reader UI, **AI reader features** (copy text from pages, in-page translation, AI image
  upscaling), two-way tracking + auto-bind + importing titles from trackers, better Komga/Kavita/Suwayomi support,
  background auto-updates, a redesigned updates page, daily/monthly reading stats.
- Owner (2025-10-28): iOS 26 background downloads stopped on all his devices until he reset the phone — worth
  remembering if Yomi's background downloads fail on iOS 26.
- Monetization: Premium subscription/lifetime + ads for free users; TestFlight slots only for sponsors/translators or
  a monthly 100-slot drop.

### 24.3 Tachimanga pain points (517 support/suggestion threads, by title)

| Theme | ~Threads | Notes |
|---|---|---|
| Cloudflare / blocked / HTTP errors | 94 | Staff answer: "not an app issue, use a VPN or change the User-Agent" |
| Premium, purchases, ads | 80 | 18+ ads, ads after paying, restore purchase failing, Premium-gated features |
| Reader / UI | 52 | iPad lag, wide pages, tap zones |
| Sync / backup / data loss | 42 | "Sync stuck at 20%", "90% of my library is gone" |
| Tracking | 24 | AniList outages |
| Downloads | 23 | "Cannot alloc memory" on iOS 26 |

### 24.4 What iOS users ask for most (Tachimanga `app-suggestions`, by reactions)

1. Hidden / locked categories (90)
2. One library entry merged across several sources or scanlation groups (68)
3. MangaBaka tracker (open API) (48)
4. Updates list grouped by title (38)
5. Library grouping beyond manual categories (35)
6. Real positional bookmarks (31)
7. End-to-end encrypted sync (26)
8. Exclude a broken source from library updates (25)

Smaller: child mode, keep last N chapters when auto-deleting, scanlator filters, per-title notifications, custom
User-Agent, other cloud backup targets, border crop, paper-colour whites.

### 24.5 Novel readers (LNReader)

- Pain points: TTS (voices, chunking, repeated paragraphs), backup/restore and v1→v2 migration crashes, **infinite
  scroll** (several threads — same as Martin's S128 ask), WTR-Lab / NovelUpdates breaking (login or captcha),
  crashes when offline.
- Cloudflare advice from contributors: use the WebView's own User-Agent, re-solve the challenge in the WebView, then
  restart. Some sites (WTR-Lab) expire cookies in ~3 min.
- Plugins use both cheerio and htmlparser2 directly; contributors say most plugin time is spent in cheerio.
  **Yomi check:** already bundles real cheerio 1.2.0 + htmlparser2 + dayjs (`Resources/yomi-js-libs.js`), so the
  §22 fake-cheerio concern is resolved.
- A contributor's Mihon-based novel fork (`mrissaoussama/mihonnovel`) lists what novel users want: translation
  (LibreTranslate / AI APIs, auto-translate downloads), a JSON selector-based custom source builder, EPUB
  import/export, auto-scroll, infinite scroll, TTS, alternative titles, bulk URL import.

### 24.6 Mihon (mostly Android users)

Most-discussed support topics: downloads (2,619 hits), Cloudflare (1,398), crashes (1,320), backup/restore (863),
storage (780), extension repos (709). Mostly Android-specific (storage access, WebView version), so Tachimanga is the
better proxy for iOS users. Mihon support will not help with Tachimanga or Aidoku backups.

**Extension API timeline** (from `mihon-updates`, pasted S131):
- 2024-02: every repo must ship `repo.json` (`meta.name`, `shortName`, `website`, `signingKeyFingerprint` = SHA-256 of
  the signing cert, lowercase, no colons). Repos without one are not recognised.
- 2025-02: the team dropped extensions-lib 1.6 in favour of "MihonX" — not backward compatible, but 1.4 extensions stay
  supported through a bridge "for a long while".
- 2026-06-28: **tachiyomix 1.6** released (`mihonapp/tachiyomix`): the source API goes "full coroutines", plus the
  **tachiyomix index**, a new extension *store* index format (spec: `tachiyomix/tree/1.6.0/index`). **Verified S131:** Keiyoushi's `index.pb`
  (gunzipped, 696 KB) decodes as this schema's `Index` message: name "Keiyoushi", badgeLabel "KEI", signingKey
  `9add655a…4da2`, contact website `keiyoushi.github.io`. The schema §22.2 said was missing is
  `mihonapp/tachiyomix/index/index.proto` (proto3; the spec says hosts must also accept its JSON form, gzip optional). Yomi's Keiyoushi runtime must read this index and host 1.6
  (suspend-function) sources, not only 1.4.
- Mihon fetches the chapter list even for manga marked "licensed" (2024-09); an extension that wants to block it must
  throw.
- Small idea from `programming` (2026-09-15): Mihon's local source now takes chapter dates from the CBZ's
  `ComicInfo.xml` (Year/Month/Day) instead of the file's modified date. Yomi's local import could do the same.

### 24.7 Gaps — channels not exported (paste by hand if needed)

| Server | Channel | Why |
|---|---|---|
| Mihon | Mihon / mihon-updates | Pasted by hand S131 → `~/discord-exports/pasted/` (full history, 2024-02 → 2026-08) |
| Mihon | Mihon / programming | In the index, plus a 2026-09-12→15 paste in `pasted/` |
| Mihon | Development / dev-app, dev-ext-api, dev-design, dev-image-decoder, dev-website | Forbidden (role-gated) |
| Mihon | Info / faq, Info / extension-recommendations | Token invalidated when the account was disabled |
| Mihon | Archive / dev-mihonx, Archive / dev-random | Token invalidated |
| Tachimanga | app-suggestions | Partial: 319 threads found, export crashed at thread "Monthly , weekly insights" (474 msgs indexed) |

Most useful left to paste: **Info / faq**. Tachimanga `app-dev` IS exported, but it only has 4 owner posts after
2025-09-26; older posts (2023–2025) were outside the export window.

---

## 25. S132 — Research audit + evidence review: reading science, UX/UI, community, App Store (2026-09-29)

Martin's ask (overnight, S132): go through all Yomi research, check whether it was actually applied, re-verify every
claim against real sources (twice, not once; ask who wrote it and why), and extend it with new UX/UI research for
novels, manga, manhwa and manhua. **Research only — no code changed.** Raw notes (with every URL and quote) were kept
in the session scratchpad; everything that mattered is here.

**How claims were checked.** Primary source first (the paper, Apple's own page, the App Store API, GitHub's API).
A claim that only appears in blogs, content farms, or AI-written "statistics" pages is marked UNSOURCED even if many
pages repeat it. Every source gets its interest noted where it has one (vendor stats, lobby-hosted PDFs, company
blogs about their own features). Verdicts: ✅ verified · ⚠️ partly true / needs nuance · ❌ wrong, misattributed, or
unsourced.

### 25.1 Claims audit — what the older docs said vs. what the sources say

| Claim (where) | Verdict | What the source actually says |
|---|---|---|
| Font size 16–18 px optimal; Yomi 18 pt ✅ (§4, DESIGN_RESEARCH §7) | ⚠️ | Rello, Pielot & Marcos, CHI 2016 (n=104, eye-tracking): readability and comprehension rise up to 18 pt, best at 18–26 pt — but on a **17-inch desktop monitor** reading Wikipedia; the authors say phones need their own studies. Apple HIG: iOS body default **17 pt**, minimum 11 pt, "for custom and system fonts". 18 pt is a sensible default; the real gap is that it doesn't follow the user's Dynamic Type (§25.2). |
| 50–75 characters per line, "66 ideal" (§4, DS §4) | ⚠️ | Ranges come from typographers (Bringhurst, Ruder 50–60), not experiments. Experiments disagree: Dyson & Kipping 1998 — 100 CPL read **faster** than 25 CPL; Dyson & Haselgrove 2001 — 55 CPL gave **better comprehension** than 100; Bernard 2002 — 45/76/132 no difference; people *prefer* shorter lines (Dyson 2004 review, *Behaviour & IT*). Honest rule: keep lines ≤ ~75–80 CPL for comfort and comprehension; WCAG 1.4.8 (AAA) says ≤ 80. On a phone Yomi's lines are ~40 CPL (fine); on iPad/landscape they are ~130–150 CPL (too long). |
| "Lines > 80 chars skipped 41 % more" (DESIGN_RESEARCH §7, attributed to Baymard) | ❌ | Baymard's article (Edward Scott, 2022-05-10) contains no "41 %" — checked the page text. Misattributed, likely AI-generated. Baymard's own 50–75 rests on Emil Ruder + qualitative e-commerce testing, and Baymard sells paid research. |
| "Good typography = +20 % accuracy, −30 % fatigue" (DESIGN_RESEARCH §7) | ❌ | Only found in blogs citing an unnamed "university research". Unsourced. |
| Line height 1.4–1.6× "WCAG-confirmed" (§4) | ⚠️ | WCAG 1.4.12 (AA) is a **tolerance** rule: content must survive a user forcing line 1.5×, paragraph 2×, letter 0.12×, word 0.16×. It is not a design target. WCAG 1.4.8 (AAA): "a mechanism is available" for line spacing ≥ 1.5 and paragraph spacing ≥ 1.5× line spacing. Rello 2016: 0.8 and 1.8 marginally worse, 1.0/1.4 fine. Yomi's 1.6 is fine. |
| "Letter spacing ≥ 0.12× optimal" (§4 table) | ❌ | Misread of WCAG 1.4.12 (see above). The real evidence for letter spacing is Zorzi et al. 2012 *PNAS* (94 dyslexic children, +2.5 pt spacing → faster, more accurate) — a reason to offer a spacing control, not to set it by default. |
| Sepia "~25 % lower radiance, reduces eye strain" (§4) | ❌ | No primary source found. Sepia is a comfort/preference theme, not a proven eye-health measure. |
| "#121212 beats pure black for readability" (§4) | ⚠️ | It's Material Design's convention (elevation + avoiding OLED black smear), not a readability study. OLED smear on true black is real (visible on iPhone OLEDs while scrolling). Yomi's AMOLED reader theme is `#0A0A0A` (near-black) — a sensible compromise already. |
| Dark mode reduces eye strain / saves battery | ⚠️ | Reading performance is **better with dark text on light** (Piepenbrock, Mayr & Buchner 2013/2014, *Ergonomics* / *Human Factors*: better proofreading and acuity, especially at small sizes; replicated in VR by Luzsa & Mayr 2025). Fatigue studies are small and mixed (Sengsoon 2025, n=30: no difference in visual fatigue). Battery: Purdue, MobiSys 2021 — dark mode saves 39–47 % display power at 100 % brightness but only **3–9 %** at typical indoor brightness. Offer dark themes for comfort and night, don't claim health or battery benefits. |
| Warm/yellow tones help at night | ⚠️ | Fan et al. 2024 *Sensors*: under dark backgrounds, yellow text caused the least fatigue, red the most. But Nagare et al. 2019 (*Lighting Res. & Tech.*): iPad Night Shift **did not** reduce melatonin suppression — brightness matters, colour alone doesn't. Chang et al. 2015 *PNAS* (n=12, full-brightness iPad, 4 h/night) showed e-readers delay sleep vs print. A warm theme is comfort; dimming is what reduces light. |
| Serif helps long-form reading (DS §4) | ⚠️ | No reliable serif-vs-sans effect on screens. Wallace et al. 2022 *ACM TOCHI* (16 fonts, hundreds of readers): each person's fastest vs slowest font differed by **35 % in reading speed with no comprehension loss**, and the best font differs per person. Supports **font choice**, not a specific serif. |
| OpenDyslexic as an accessibility font (DS §4) | ❌ as evidence / ✅ as preference | Wery & Diliberto 2017 (*Annals of Dyslexia*), Kuster et al. 2018 (n=170), Rello & Baeza-Yates 2013: no speed/accuracy benefit. Spacing is what helps. Offer it only because some readers prefer it. |
| Liquid Glass fails at "1.5:1 contrast" (DESIGN_RESEARCH §5, attributed to NN/g) | ❌ number / ✅ gist | NN/g "Liquid Glass Is Cracked, and Usability Suffers in iOS 26" (Raluca Budiu, 2025-10-10) — confirmed: low contrast over images, smaller/crowded targets, controls that move and collapse, tiring animation. **The page contains no "1.5:1".** Apple itself added Settings → Display & Brightness → Liquid Glass **Clear / Tinted** in iOS 26.1 (Nov 2025) for more opacity and contrast. |
| "70 % expect personalization, 89 % of marketers…" (DESIGN_RESEARCH §6) | ❌ as used | McKinsey 2021 "71 % expect personalized interactions" is about **marketing** (tailored offers, recommendations) — not reader customization. McKinsey sells personalization consulting; the 89 % stat is from a marketing vendor. The case for deep reader customization stands on better evidence: Wallace 2022 (per-person best font), and competitors adding it under demand (Tachimanga v5.0 added custom reading backgrounds). |
| Streaks +60 %, leaderboards +40 %, badges +30 % (DESIGN_RESEARCH §9) | ❌ | Traced to loyalty-software vendor blogs; no primary data. Real evidence: Duolingo's own blog (company interest, correlational: 7-day streak users 3.6× more likely to finish a course; Streak Wager A/B +14 % day-7 retention) and **Silverman & Barasch 2023, *J. Consumer Research* 49(6)** (7 studies): showing an intact streak increases continued use vs a broken one; the drop after a break is **smaller when people can repair the streak**. |
| Netflix: 80 % of viewing comes from recommendations (DESIGN_RESEARCH §8) | ✅ but weak analogy | Gomez-Uribe & Hunt 2015 *ACM TMIS* — true. But Netflix has a catalogue and ML on millions of users; Yomi has neither. It doesn't justify an editorial home by itself. |
| App Store 2.5.2 has a "primary purpose" test (§5, S104) | ❌ corrected | Live Guidelines (updated **June 8, 2026**): 2.5.2 says apps may not "download, install, or execute code which introduces or changes features or functionality of the app" — no primary-purpose wording. The primary-purpose test is in the **Developer Program License Agreement §3.3.1(B)**: interpreted code may be downloaded if it (a) doesn't change the primary purpose, (b) doesn't bypass signing/sandbox/security, (c) doesn't create a storefront for other apps. And Guideline **4.7** now explicitly covers "HTML5 and JavaScript … plug-ins" with duties 4.7.1–4.7.5 (see §25.7). |
| Tachimanga 4.8★ ~4.9k reviews (DESIGN_RESEARCH §1) | ✅ updated | App Store API 2026-09-29: 4.76★ / 5,396 (US), v5.0 (2026-09-06). |
| Novel reader uses Newsreader serif (CLAUDE.md design summary) | ❌ doc vs code | `TextReaderView.fontFamilyCSS` uses **Georgia** ("Serif") or `-apple-system`. Newsreader is not bundled. |

### 25.2 Was it applied? — research recommendations vs. the code (checked 2026-09-29, HEAD `ec13d2b`)

| Recommendation (source doc) | In the code? | Where / note |
|---|---|---|
| Novel defaults 18 pt / 1.6 line height / Sepia flagship / left-aligned | ✅ | `AppSettings` defaults, `DesignTokens.ReaderDefaults`, `TextReaderView.styledHTML` |
| Enforce measure (≤ 75–80 CPL) on iPad/landscape (DS §4, DESIGN_RESEARCH §7) | ❌ | `body` has no `max-width`; only 8/16/24 pt side padding. iPad landscape ≈ 130–160 CPL (estimate: ~1,340 pt of text at ~8.5 pt per Georgia character). |
| Paragraph spacing ≈ 1× font size (DS §4) | ⚠️ | `p { margin: 0 0 0.75em }` |
| Font choice beyond serif/sans, incl. dyslexia font (DS §4, ArcReader backlog) | ❌ | Georgia vs system only |
| Letter/word spacing control | ❌ | none (ArcReader backlog item) |
| Justify option | ✅ but | `novelJustifyText` exists; **no `hyphens:auto`** → justified ~40-CPL phone lines get large word gaps (the one case where justification is known to read worse). |
| Dynamic Type / Bold Text support (Apple HIG) | ❌ | Zero `dynamicTypeSize`/`UIFontMetrics`/`@ScaledMetric` in the app. 197 `YomiTokens.Font.grotesk(size)` + 38 `.system(size:)` fixed sizes; reader px ignores the system text size. 189 places use text styles (those scale). |
| Avoid light font weights (HIG) | ⚠️ | `YomiTokens.Font.groteskPS = "SpaceGrotesk-Light"` default instance (only used when `useSystemFont` is off; default is on since S122). |
| Reduce Motion | ❌ | no `accessibilityReduceMotion` checks; 59 `withAnimation` calls |
| True black + dark grey themes (§4) | ✅ | Reader: Dark `#1C1C1E`, AMOLED `#0A0A0A`; chrome: Midnight `#000` |
| Reader contrast ≥ 7:1 (HIG dark-mode page) | ✅ | Computed: Light 17.0, Sepia 14.1, Warm 9.2, Dark 13.9, AMOLED 15.0 |
| Liquid Glass only on floating chrome, never over text (DESIGN_RESEARCH §5) | ⚠️ | Reader overlay uses glass; the S129 a11y bug (invisible overlay still in the VoiceOver tree) is open. Check under iOS 26.1 **Tinted**, Reduce Transparency, Increase Contrast. |
| Pages mode for novels (§4 "scroll or paginated") | ❌ | not built (ArcReader backlog) |
| Estimated time left per chapter (§4) | ❌ | not built |
| TTS with highlight (§4) | ⚠️ | one utterance per chapter, no highlight (backlog) |
| Streaks / Insights, gentle (DESIGN_RESEARCH §9) | ✅ | `InsightsView` computes from the local DB (works offline — the Kindle failure mode doesn't apply). No streak repair/freeze. |
| Reduce first-plugin friction / guided onboarding (DESIGN_RESEARCH §10.6) | ❌ + bug | `OnboardingView` is a 3-card deck that says **"Go to More → Plugins"** — stale since S125 moved Extensions to Browse. No one-tap setup. |
| Novels as list layout (§4 "List preferred for novels") | ⚠️ | global grid/list toggle, not per type |
| iCloud sync | ⚠️ | built S103, blocked on paid Developer Program (Known Issue #47) |
| Volume-button page turn (§2 table) | ❌ | not found |
| Tachimanga/Tachiyomi import | ⚠️ | `.tachibk` import+export ✅; Tachimanga `.tmb` (zip + SQLite, §24.2) ❌ |
| Local CBZ/EPUB import | ❌ | OPDS/Komga only |

### 25.3 Reading science for the novel reader — what the evidence supports

1. **Size:** default 18 pt is fine (Apple 17 pt body; Rello 2016 ≥ 18 pt on desktop). Better: start from the
   user's Dynamic Type body size and scale the reader font with it, so people who set large text system-wide get it
   in Yomi on first open. Keep the range wide (Apple asks for ≥ 200 % enlargement).
2. **Line length:** cap the text column (`max-width` ≈ 34–38em, centered) so iPad/landscape lines stay ≤ ~75 CPL;
   phones are already fine. WCAG 1.4.8 accepts it as a setting, but a sane default cap costs nothing.
3. **Leading and paragraphs:** 1.4–1.6 is safe; extremes (≤ 1.0, ≥ 1.8) read worse. Offer the spacing presets that
   exist, add paragraph spacing and letter/word spacing (spacing is the one typographic change with dyslexia evidence).
4. **Fonts:** no universal best font; individual differences are large (35 %). Offer a curated set (system SF,
   **New York** — Apple's own serif, reachable in the web view as CSS `ui-serif` — Georgia, a humanist sans, a slab or Literata-style book face,
   plus OpenDyslexic/Atkinson Hyperlegible for preference) and let users import a font (LNReader #1626 asks for it).
5. **Justification:** default left-aligned (WCAG 1.4.8); if justified, turn on hyphenation (`hyphens:auto` + the
   right `lang`), otherwise rivers on narrow phone lines.
6. **Themes:** keep light/sepia/dark/near-black; add custom colours (Tachimanga v5 did). Light themes read best in lit
   rooms; dark for night comfort. Don't market any theme as eye-health or battery.
7. **Scroll vs pages:** a 2026 network meta-analysis (Clinton-Lisell & Litzinger, *Educ. Inf. Technol.*, 56 studies)
   found paper beats screens **only when scrolling was needed** (g 0.35–0.48); without scrolling, no reliable
   difference (g 0.03–0.12). Sanchez & Wiley 2009: scrolling hurts comprehension of complex text, mostly for lower
   working-memory readers. But for **narrative** text (novels) screen reading shows no deficit at all (Schwabe et al.
   2022, *Media Psychology*, 32 studies; Delgado et al. 2018: narrative g ≈ 0.01). → Infinite scroll is fine for
   web novels; **Pages mode is still worth building as an option** (it's the evidence-backed choice for dense text).
8. **Listening:** reading and listening give the same comprehension overall (Clinton-Lisell 2022 *Review of Educ.
   Research*, 46 studies, g = 0.07; Rogowsky et al. 2016). TTS is a real way to read fiction, not only an
   accessibility add-on — sentence highlighting (reading-while-listening) and auto-advance matter.
9. **Night:** offer auto-switch to a dark theme at night and a brightness/dim control; don't claim sleep benefits.

### 25.4 Manga / manhwa / manhua reader — what the evidence and users say

- **Page vs guided vs single-panel:** Chen, Chen & Zheng 2026 (*SAGE Open*, survey n=84 + experiment n=24): guided
  view helped readers with **low** visual-language fluency; **fluent** comic readers preferred full pages; single-frame
  was easiest but least beautiful. Yomi's audience is fluent → full page default is right; panel view is an
  optional extra at most (Panels.app users complain it's unreliable; a Medium critic calls guided view destructive to
  page composition — opinion).
- **Reading order:** Cohn 2013 / Cohn & Campbell 2015 (*Applied Cognitive Psychology*) and Kirtley 2023 (eye-tracking):
  readers follow a Z-path (mirrored in manga) but layout (blockage, gaps, overlaps) changes the order — automatic panel
  slicing easily gets it wrong.
- **Long strip (manhwa/manhua):** avoid 1-px seams between stitched images when zooming (Readest #6484); on iPad don't
  blow small images up to full width (blurry) — offer a max-width / original-size option (older Tachimanga iPad
  complaint); respect the safe area (WEBTOON 1★: content under the notch).
- **What readers ask for (GitHub 👍, 2026-09-29):** Mihon — cross-device sync (52), double page (30), multiple sources
  for one title (15), two-way tracker sync (14), and a **performance regression** issue (13: "update negatively
  impacted the reader's fluidity"). Komikku — MangaBaka tracker (16), merged series (14), smarter duplicate-chapter
  skipping across scanlators (13), web-page-like navigation in long strip (10), e-reader mode without animations (8).
  Paperback — scroll into next chapter (9), ProMotion 120 Hz (3). Aidoku — iCloud sync status icon (10), automatic
  backups (8), auto-download new chapters (7). Tachimanga Discord (§24.4) — hidden/locked categories (90), one entry
  across sources (68), MangaBaka (48).
- **Tachimanga v5.0 (2026-09-06)** shipped: MangaUpdates/Bangumi/MangaBaka trackers, Komga/Kavita/Suwayomi tracking,
  custom reading backgrounds, **separate tap zones for paged vs webtoon**, press-and-hold scroll with swipe speed
  control. That's the current bar on iOS.

### 25.5 What people love and hate — across apps (App Store reviews, GitHub, Reddit, Discord §24)

Review mining: Apple's public review feed, "most helpful", ≤ 200 per app, US only — a biased sample (loud users,
one country), useful for themes, not percentages.

**Five cross-app laws** (each seen in 3+ unrelated apps):
1. **Don't churn the UI.** The most-upvoted Kindle review (367/385 helpful) is about a forced redesign; MANGA Plus
   ("Please change back the Browse screen"), WEBTOON ("New UI is not the move", "App overhaul 👎"), Apple Books ("GIVE US
   THE OLD VERSION BACK"), Panels ("continuously making unnecessary changes"). Yomi has changed Browse/design several
   times — before 1.0 that's fine; after release, move things rarely and keep old habits working.
2. **Never paywall what used to be free.** Tachimanga (10 downloads/day, auto-delete behind Premium, confirm on every
   delete), Panels ("continue to next comic" moved to paid), Royal Road (downloads paywalled + noisy ads).
3. **Never lose the library.** Apple Books' top complaint is items vanishing with sync (70/116 helpful); Panels
   "downloads broke with 75 GB"; Tachimanga Discord "90 % of my library is gone". Automatic local backups + clear sync
   status (Aidoku #510) are trust features.
4. **Slowness after updates kills goodwill.** Tachimanga v4.4 and v4.20 reviews ("pages take 30 s", "used to be the
   best, now it's slow"), Mihon #3017, Royal Road "slower than a snail". Same as Martin's S128 report.
5. **Empty-shell setup is where extension readers lose people.** Paperback (4.29★): "setup instructions terrible",
   "requires Discord for instructions", "repos don't work". Tachimanga 5★ reviews still say "after setup" and "looked
   up a tutorial on YT". Eclipse users: "every repo I tried says unavailable".

**What gets praised:** a reader that "just works" after setup, offline downloads, trackers, collections/categories,
smooth transitions ("the transition and the vibe is really clean and seamless" — Eclipse thread), no intrusive ads
(ads only at launch), free sync. Novel readers: paste-a-link import ("adding novels I've had open in my browser has
been pretty breezy" — ArcReader thread), clean chapter text (garbled HTML is a top complaint), voices beyond US English,
choosing translation groups, removing sources. Kindle: a reading streak lost after a day offline earns a 1★.

### 25.6 Competitor updates (App Store lookup API, 2026-09-29)

- **Novel readers — see §25.13:** Lipex (App Store, LNReader repos) and Buny (TestFlight) launched July 2026.
- **Eclipse – Manga Reader** — **new, not in earlier docs.** App Store id6779430885, seller Vratislav Vacula, released
  2026-06-18, v3.1 (2026-09-17), 4.45★/11, **93 MB**, iOS 16.4+, free + one-time "Pro" support purchase. Reddit launch
  post r/mangapiracy `1v4sucd` (301 votes/200 comments): runs "Tachiyomi/Mihon repos", free iCloud sync, Komga/OPDS/local,
  stats, backups to/from Android readers, "not vibe coded… 8 months" (dev says AI helped). Complaints: Keiyoushi
  sources fail Cloudflare where Tachimanga works; first-time users confused adding repos; crash importing a Tachimanga
  backup. **How it runs Mihon extensions is UNVERIFIED** (93 MB suggests no embedded JVM). Its App Store description never
  mentions sources — only local files, Komga, backups, sync.
- **Tachimanga** v5.0, 4.76★/5,396, 229 MB; App Store description also mentions only ZIP/CBZ/EPUB + Komga.
- **Readest** (open-source e-reader) is on iOS: 4.52★/180. **Moon+ Reader** appeared on iOS (2026-08, 2 ratings).
- **Paperback** App Store build last updated 2025-02-28 (19 months stale), 4.29★/636.
- ArcReader v1.2.4 (2026-09-29), 4.9★/40; Madomi 444 MB, 3.41★/22.
- Official apps for context: WEBTOON 4.77★/511k, Shonen Jump 4.89★/260k, MANGA Plus **3.81★** (slow, redesigns, can't
  see which titles have new chapters).

### 25.7 App Store — corrected reading of the rules (live text, 2026-09-29)

- Cite **DPLA §3.3.1(B)** (interpreted code: same primary purpose, no security bypass, no storefront) and **Guideline
  4.7** (JavaScript plug-ins allowed, developer responsible) — not a "primary purpose" clause in 2.5.2, which doesn't
  exist in the current text.
- **4.7 duties** if Yomi "offers" plug-ins: 4.7.1 privacy + a way to filter/report objectionable content; 4.7.2 no
  exposing native platform APIs to the plug-in without Apple's permission (JSBridge exposes fetch/cookies/WebView —
  arguably not "native platform APIs", but note it); 4.7.3 no sharing data/permissions without per-use consent; 4.7.4 an
  index of the software with universal links; 4.7.5 identify software above the app's age rating + age gate (NSFW
  sources). Whether user-added repos count as "offered in your app" is unclear; Yomi's own first-party catalog clearly
  does.
- **4.2.3(ii):** if the app must download resources to work on first launch, show the size and ask first (relevant to
  the Keiyoushi runtime and neural TTS voices).
- **2.1(a):** the reviewer must see a working app. Tachimanga and Eclipse both describe themselves as local-file/Komga
  readers with backup import — they don't show a source browser as the pitch. Yomi's App Store description and review
  notes should follow that pattern (local files + OPDS/Komga + backups first).
- 5.2.2 (third-party content permission) is unchanged — still the real legal exposure (§5).

### 25.8 General mobile UX and performance

- **Onboarding:** NN/g ("Onboarding Tutorials vs. Contextual Help", "Mobile Tutorials: Wasted Effort?") — deck-of-cards
  tutorials get skipped and forgotten; contextual tips at the moment of need work better. For Yomi the bigger issue is
  §25.5 law 5: onboarding should *do* the first setup (add a starting repo/source list with one tap, or import a backup /
  local files), not describe where the settings are.
- **Touch:** Hoober 2013 (1,333 observations): 49 % one-handed, 36 % cradled, 15 % two thumbs; Hoober 2017: grips
  change constantly and people are most accurate in the **center** — static "thumb zone" maps oversimplify. Keep the
  center tap for the menu, large side zones, no tiny corner targets.
- **Perceived speed:** skeleton screens vs spinners is mixed (Mejtoft et al. 2018 ECCE: skeletons felt faster; Viget
  2017: skeletons felt slowest). The uncontroversial fix is showing cached content instantly (S131 step 3 did this for
  detail screens).
- **Apple's budgets** (WWDC transcripts): hitch time ratio < 5 ms/s good, 5–10 noticeable, > 10 critical (WWDC20 10077);
  first frame at launch within 400 ms (WWDC19 423); `XCTHitchMetric` can gate UI tests (WWDC25 247). Use these as
  pass/fail numbers when step 6 re-measures.
- **iOS 26.1 Liquid Glass Tinted** exists because Clear hurt legibility — test Yomi's glass in both modes.

### 25.9 Things Martin didn't ask about that matter

1. **Dynamic Type is missing app-wide** (§25.2). Apple asks for it for custom fonts too; low-vision users and anyone
   with larger system text get a fixed-size app. Reader font should start from it.
2. **Reduce Motion and the invisible overlay in the VoiceOver tree** — accessibility debt in the reader.
3. **Stale onboarding copy** ("More → Plugins") — a new user's first instruction points to a screen that moved.
4. **Spanish localization.** Martin is Argentine; there are no `.xcstrings`/`.lproj` files. Localizing is also an App
   Store discoverability lever (separate metadata per locale). UNVERIFIED: size of the effect for this category.
5. **Library safety:** automatic local backups on a schedule + visible sync status, before CloudKit ships.
6. **Import from Tachimanga (`.tmb` = zip + SQLite, §24.2) and local CBZ/EPUB** — Eclipse users ask for exactly this,
   and it gives App Review a working app without any source.
7. **Performance as a release gate** (Apple budgets above) — slowness after updates is the #4 cross-app complaint.
8. **Legal:** the community itself warns "be careful including sources within the app instead of users importing
   themselves since many manga apps have gotten popped" (ArcReader thread). Keep sources user-added.

### 25.10 Ranked recommendations (for Martin to dissect next session — none implemented)

*Updated by §25.13 (Reddit part 2): bulk migration + multi-source moves to #3, a lockable SFW mode to #5, and
volume-button page turns are dropped (Guideline 2.5.9).*

Ordered by evidence strength × impact. Batch-pass items already planned in the S128 plan (reader controller,
infinite scroll, swipe, tap fixes) are not repeated.

1. **Reader typography pass:** Dynamic-Type-based default size; `max-width` column cap; paragraph spacing control;
   letter/word spacing; `hyphens:auto` when justified; fonts: add New York + a few curated faces + import; fix the
   CLAUDE.md "Newsreader" claim.
2. **Pages mode for novels** as an option next to scroll/infinite scroll (§25.3.7).
3. **First-run setup that does the work** (one-tap starter repo/list, backup import, local files) + fix the stale copy.
4. **Accessibility baseline:** Dynamic Type in chrome (text styles or `relativeTo:`), Reduce Motion, overlay out of
   the a11y tree, test under Liquid Glass Tinted / Increase Contrast.
5. **Library safety:** scheduled local auto-backup + sync status.
6. **Imports:** Tachimanga `.tmb`, local CBZ/EPUB (also the App Review story).
7. **Manga reader parity with Tachimanga v5:** separate tap zones per mode, press-and-hold scroll, custom backgrounds,
   long-strip max width on iPad, seam-free stitching.
8. **TTS upgrade:** sentence highlight + auto-advance (evidence: listening ≈ reading).
9. **Streak repair** (Silverman & Barasch) — keep streaks opt-in and quiet.
10. **App Store copy + review notes** per §25.7 (local/Komga/backups framing; DPLA 3.3.1(B) + 4.7 wording).
11. **Performance gates** in UI tests (XCTHitchMetric < 5 ms/s on reader scroll).
12. **Spanish localization.**

### 25.11 Still unverified / open

- How Eclipse runs Mihon extensions; whether its "Tachiyomi/Mihon repos" support is on-device.
- Whether user-added repos fall under Guideline 4.7's "software offered in your app".
- Reading-while-listening meta-analysis (Clinton-Lisell, UND commons `ehb-fac/75`) — effect size not read.
- Exact Instruments hang thresholds (≥ 250 ms hang) — not re-verified this session.
- Reddit: covered in §25.13 (part 2, 18 threads read in full via old.reddit). Not covered: r/LightNovels,
  r/noveltranslations, r/manga, r/manhwa at the same depth.
- How Lipex and Buny run LNReader plugins (JavaScriptCore? WebView?) and how Mangra runs Mihon extensions.
- `last30days` skill not used — it needs its interactive first-run setup (Martin's consent).

### 25.12 Sources (primary first)

Papers: Rello, Pielot & Marcos 2016 CHI "Make It Big!" (pielot.org/pubs/Rello2016-Fontsize.pdf) · Dyson 2004
"How physical text layout affects reading from screen", *Behaviour & IT* 23(6) · Dyson & Haselgrove 2001 *IJHCS* ·
Wallace et al. 2022 *ACM TOCHI* doi:10.1145/3502222 · Piepenbrock, Mayr, Mund & Buchner 2013 *Ergonomics* (PMID
23654206); Piepenbrock, Mayr & Buchner 2014 *Human Factors* doi:10.1177/0018720813515509 · Luzsa & Mayr 2025 *Ergonomics*
doi:10.1080/00140139.2025.2457470 · Sengsoon & Intaruk 2025 *IJERPH* doi:10.3390/ijerph22040609 · Fan et al. 2024
*Sensors* doi:10.3390/s24113516 · Dash & Hu 2021 MobiSys "How much battery does dark mode save?" doi:10.1145/3458864.3467682 ·
Chang et al. 2015 *PNAS* doi:10.1073/pnas.1418490112 · Nagare, Plitnick & Figueiro 2019 *Lighting Res. & Tech.* (PMID
31191118) · Wery & Diliberto 2017 *Annals of Dyslexia* (PMID 26993270) · Kuster et al. 2018 *Annals of Dyslexia* ·
Zorzi et al. 2012 *PNAS* doi:10.1073/pnas.1205566109 · Trollip & Sales 1986 *Human Factors* · Delgado et al. 2018
*Educ. Research Review* 25:23–38 · Schwabe et al. 2022 *Media Psychology* doi:10.1080/15213269.2022.2070216 ·
Clinton-Lisell & Litzinger 2026 *Educ. Inf. Technol.* doi:10.1007/s10639-025-13843-8 · Sanchez & Wiley 2009 *Human
Factors* doi:10.1177/0018720809352788 (note: a public PDF copy is hosted by Two Sides NA, a paper-industry group) ·
Clinton-Lisell 2022 *Review of Educ. Research* doi:10.3102/00346543211060871 · Rogowsky, Calhoun & Tallal 2016 *SAGE
Open* doi:10.1177/2158244016669550 · Chen, Chen & Zheng 2026 *SAGE Open* doi:10.1177/21582440261416099 · Cohn 2013
*Frontiers in Psychology*; Cohn & Campbell 2015 *ACP* doi:10.1002/acp.3086; Kirtley 2023 *ACP* doi:10.1002/acp.4018 ·
Henchobdee & Teeravarunyou AHFE 2022 · Silverman & Barasch 2023 *J. Consumer Research* 49(6):1095 · Gomez-Uribe & Hunt
2015 *ACM TMIS* doi:10.1145/2843948 · Mejtoft, Långström & Söderström 2018 ECCE doi:10.1145/3232078.3232086.

Standards / platform: Apple HIG Typography, Dark Mode, Accessibility (developer.apple.com JSON, fetched 2026-09-29) ·
WCAG 2.2 Understanding 1.4.8 and 1.4.12 (w3.org) · App Review Guidelines (updated 2026-06-08) · Apple Developer
Program License Agreement §3.3.1(B) (current PDF) · Apple docs: `TranslationSession` (iOS 18+),
`AVSpeechSynthesizer.PersonalVoiceAuthorizationStatus` (iOS 17+) · WWDC19 423, WWDC20 10076/10077, WWDC23 10248,
WWDC25 247.

Industry / UX (interest noted): NN/g — Budiu 2025 "Liquid Glass Is Cracked"; "Onboarding Tutorials vs. Contextual
Help"; "Mobile Tutorials" (UX consultancy) · Hoober 2013 (A List Apart/UXmatters), 2017 "Design for Fingers, Touch,
and People" (UXmatters) · Baymard 2022 line length (sells research) · McKinsey 2021 personalization (sells
consulting) · Duolingo blog on streaks (own product) · MacRumors/Engadget/TechCrunch on iOS 26.1 Liquid Glass toggle.

Community / data: App Store Search & Lookup API and customer-review RSS (2026-09-29) for Tachimanga, Eclipse,
ArcReader, Madomi, Paperback, MANGA Plus, WEBTOON, Panels, Apple Books, Kindle, Royal Road, WebNovel · GitHub issue
search sorted by 👍 for mihonapp/mihon, Aidoku/Aidoku, LNReader/lnreader, readest/readest, koreader/koreader,
KotatsuApp/Kotatsu, komikku-app/komikku, kodjodevf/mangayomi, Paperback-iOS/app · Reddit r/mangapiracy `1v4sucd`
(Eclipse launch) and `1uzjuk8` (ArcReader launch) · Discord exports (§24). Part 2 (§25.13): r/mangapiracy `1qi3occ`,
`1s9ez7u`, `1va6lco`, `1v6cke5`, `1vcumoa`, `1uxms9y`, `1tnchbj`, `1j0ns1z`, `1rpb688`, `1v6n5vz`, `1t22o3x`, `1wm7nue`,
`1wmtg2f`, `1wobnvr`, `1wajeog`, `1w52d59`, `1wqg7sb`, `1wi04gj`, `1wfmf2r`; r/Piracy `1sarlv7`, `1w8wju8` ·
github/dmca `2026/03/2026-03-23-fakku.md`, `2026/07/2026-07-07-ridi-corporation.md`, `2026/08/2026-08-24-ridi.md` ·
TuMangaOnline raid: elchapuzasinformatico.com (2026-04), en.wikipedia.org/wiki/TuMangaOnline · App Store Lookup API for
Lipex (id6789770915) and Mangra (id6502868308).

### 25.13 Reddit deep-dive — r/mangapiracy and r/Piracy (S132 part 2, 2026-09-29)

Martin asked for Reddit specifically. Read through old.reddit in a regular (logged-in) Firefox window — the private
window needed a login. Sampled: r/mangapiracy search "ios" (top of all time, ~100 threads), r/mangapiracy top of the
last month (~100 threads), r/Piracy search "manga reader ios", and 18 threads read in full. Reddit users and app
developers posting their own apps are not neutral sources — self-promotion is marked. Anything legal was checked
outside Reddit.

**What changes Yomi's strategy**

1. **The "LNReader on iOS" gap is closing — two App-Store-style competitors appeared in July 2026.**
   - **Lipex Light Novel Reader** (App Store id6789770915, solo dev, released 2026-07-17, v1.28 on 2026-08-31, 5.0★/9,
     63 MB, free + cosmetic Pro subscription). Runs **LNReader plugin repos** ("the app ships empty and you connect the
     community repos you want"; users are pointed to lnreader.app/plugins). Has themes, fonts, custom colours, a photo
     behind the text, streaks/goals/home-screen widget/monthly "Wrapped" recap, offline + **EPUB export**, AniList/MAL/
     Kitsu/MangaUpdates, natural-voice TTS, 35 languages, iPad with a **reader-width control**, in-app Cloudflare
     verification. Its App Store description only says "Import and read light novels in EPUB format". Launch
     `1v6cke5` (2026-07-25) and update `1vcumoa` (2026-08).
   - **Buny** (buny.app, `1uxms9y`, 2026-07-15): "similar to LN-Reader", EPUB/PDF, iCloud sync, external sources, Kavita,
     trackers — TestFlight via Discord, not App Store.
   - → §24.1's "the iOS slot for an LNReader-plugin novel reader is open" is **no longer true**. Yomi's remaining
     unique position is **manga + manhwa + novels in one polished app**, not "the only LNReader on iOS".
2. **Keiyoushi officially supports only Android apps** (Keiyoushi Discord notice, last edited 2026-07-29, quoted in
   `1va6lco`): extensions "fully dropped compatibility with outdated apps"; supported = Mihon, TachiyomiSY, Komikku;
   Suwayomi "isn't compatible but v2.3.2243 should be able to view & access most"; everything else shows
   "Obsolete"/"Orphaned". Tachimanga users broke until Tachimanga shipped an update. Also (`1w52d59`, 2026-09): mass
   updates of 41 extensions at once to fix version numbers, and users stuck on "pending update" because the same repo
   was added twice (the "yuzono" repo now points at Keiyoushi). → Yomi's Keiyoushi runtime must follow extension-lib
   updates (1.6 / tachiyomix, §24.6) or every extension goes Obsolete overnight; and Yomi should **detect duplicate
   repos** (same `repo.json` signing key / index name).
3. **Source death is the #1 recurring event, and migration is the pain.** Bato (gone Jan 2026, revived as XBatCat —
   `1qi3occ`, 809 pts, 851 comments), Comick, MangaDex purges (`1wajeog`: licensed series removed, only "release by
   official publisher, Manga Plus" left; uploads revoked after DMCA `1wpqkjh`), Comix outages (6 threads in one month),
   Tapas shutting down, TMO (Spanish) raided. Users: "Migrating out my 250+ list on Bato right is so ass", "90 % of my
   library was Bato", people migrating 800–1,083 titles alphabetically by hand, "That's why I use multiple sources
   after that". Yomi's `MigrateView` moves **one title at a time**. → **Bulk migration** ("move everything from source
   X", auto-match by title, review list) and **more than one source per title** (Mihon #1837, Komikku merged series,
   Tachimanga suggestion #2) are survival features, not extras.
4. **Many iOS users fail at "add a repo".** "The whole extension repo thing doesn't work for me… it's tooooo
   stressful" (`1wmtg2f`, 2026-09-21); a user whose all-in-one scraper app vanished from the App Store asks what to use
   now; Eclipse and Lipex users ask "what repository can I use?". Confirms §25.5 law 5.
5. **Parents want a lockable safe mode.** `1v6n5vz` (62 comments, iOS): Tachimanga's NSFW toggle "can't filter out
   everything for sites that have the usual shonen manga mixed with other smut"; Comix filters by default "but you
   can't lock it in". `1wi04gj` "Kids Friendly Mihon" (`ShakeyHands91/Kodomo`): an allow-list of 25 extensions —
   **licensed publishers** (MANGA Plus, VIZ, K Manga, Manga UP!, Comikey, Mangamo, Comics Kingdom), official game comics,
   free webcomics — because Mihon Nightly's new per-extension age-rating switch "is very easily turned off by a 10
   year old". → A **PIN/Face ID-locked SFW mode with an allow-list**; the same "official & free sources" list is also
   the safest default catalog to show App Review (§25.7, Guideline 4.7.5).
6. **Legal climate hardened in 2026 (verified outside Reddit).**
   - **TuMangaOnline (TMO)**, the largest Spanish-language manga site since 2014, dismantled by Spain's Policía
     Nacional (announced 2026-04-22): 3 arrests in Almería, investigation since June 2025 driven by Korea's COA
     (representing Kakao/Webtoon), >€400k in crypto seized (elchapuzasinformatico.com, Wikipedia "TuMangaOnline").
     Relevant to Martin: Spanish-language sources are an active enforcement target.
   - **FAKKU (via Remove Your Media LLC) DMCA to GitHub, 2026-03-23** (`github/dmca/2026/03/2026-03-23-fakku.md`, read):
     §1201 notice against the **self-hosted readers** LANraragi and happypandax ("server software for managing downloaded
     pirated content") and parts of gallery-dl. GitHub found no valid anti-circumvention claim but "other valid copyright
     claim(s)". → Being "just a reader" is not a shield when the project ships plugins/metadata fetchers aimed at piracy
     sites — Yomi's first-party catalog of scanlation sites (§5, S104) is the exposed part.
   - RIDI's 2026-07-07 and 2026-08-24 GitHub notices targeted DRM removers only.
   - Community's own read: shutdowns are driven by Korean publishers (Kakao); "Just don't try to monetize it, as soon
     as money is involved these type of projects get DMCA'd pretty quickly" (ArcReader thread).
7. **Volume-button page turns are not allowed on the App Store.** ArcReader added them on Android only ("iOS gives apps
   no way to do this"). Guideline **2.5.9**: apps that "alter or disable the functions of standard switches, such as the
   Volume Up/Down… will be rejected". Remove it from Yomi's future list (§2 table).

**Smaller signals worth keeping**

- **Trackers people actually use** (`1wqg7sb`, 2026-09): AniList (modern, more manhwa/manhua), MAL (legacy, anime-
  adaptation discovery), **MangaUpdates** (22 years, tag system, some webtoons only there), **MangaBaka** (aggregator,
  "largest manga library", staff: would open-source it rather than shut down, no-piracy policy so no DMCA exposure),
  Kitsu (no origin rules). Yomi has MAL/AniList/Shikimori/Bangumi — MangaUpdates and MangaBaka are the gaps (Tachimanga
  v5.0 added both).
- **Stats per title:** a Mihon user envies Tachimanga's per-series time read (`1rpb688`); a Lipex user asks for the same.
  Yomi's Insights shows a "most read" top list; per-title time on the detail screen is not there.
- **Comments:** "Comments are one of my favorite parts" (69 pts) vs "Comments are trash" (−17) — sites win on community;
  a moderated in-app social layer is a legal/moderation burden (Guideline 1.2/4.7.1). Cheap middle ground: a button that
  opens the chapter's comment section in the WebView. A thoughtful reply in the same thread: put "exportable reading
  progress, a clear offline state, and separate interface/content language controls ahead of comments".
- **Tap a speech bubble to zoom** (`1wfmf2r`, Mihon fork prototype with on-device bubble detection): positive reception
  ("feature I sorely miss from Google Books"), but users want it as tap-to-zoom, not forced bubble-by-bubble. Fits
  Chen et al. 2026 (guided view helps less fluent readers).
- **Aidoku's reputation:** Mihon staff recommend it for iOS; praised for tracking ("update your library chapters based on
  your AniList") and a built-in upscaler on iPad; still sideload/TestFlight only.
- **Tachimanga free-tier locks** (`1s9ez7u`, 2026-04): MAL/AniList sync, background download, multi-chapter download,
  double page are Premium; one ad at launch is tolerated.
- **Novel readers often just use EPUB** in Apple Books/ReadEra/Lithium/Moon+ (`1tnchbj`) → EPUB import *and* export
  matter for Yomi's novel side (Lipex has export).
- **Nostalgia for Manga Rock's page-flip animation** (386 pts: "such a nice quality of life feature"). Panels users also
  ask for page curl (§25.5). A page-curl option for paged manga/novels has real fans.
- **Other new names** (not investigated): Mangra (App Store "Manga Translator – Mangra", 4.16★/94; claims to run
  Mihon/Tachimanga/Paperback extensions + AI translation; its supportive replies look like shills), Inkdex, Sora,
  Suwatte, Yomotsu (Mihon fork with AI translation), Uchiyomi (self-hosted webtoon server), torika.app (local reader),
  MangaPin (4.87★/5.6k) and "Manga Reader" (4.5★/18k) — App Store apps with built-in sources.
- **Self-promotion noise:** the ArcReader developer recommends his app in unrelated threads; Mangra's thread has
  one-line "best of the best!" replies. Discount developer comments accordingly.

**Changes to the §25.10 ranking** — add and move up:
- **Bulk migration + multiple sources per title** → rank 3 (after typography and pages mode).
- **Lockable SFW/kids mode with an allow-list** (+ "official & free" starter catalog, which doubles as the App Review
  story) → rank 5.
- **Keiyoushi extension-lib tracking + duplicate-repo detection** → attach to the Keiyoushi runtime work.
- **MangaUpdates + MangaBaka trackers**, **EPUB export for novels**, **per-title reading time**, **tap-to-zoom bubbles**,
  **page-curl option** → mid/low.
- **Remove "volume-button page turn"** from every list (Guideline 2.5.9).

---

*End of RESEARCH.md — last compiled S132, 2026-09-29 (§25)*
