# Yomi — Master Research Document
**Last updated:** 2026-04-20 (S44 deep audit) | **Do not re-research topics marked with ✅ RESEARCHED**

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
| Volume button page-turn | ❌ Not yet (future) |
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
✅ RESEARCHED (S19–S24, 2026-04-14)

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

### Plugin/Extension System (Guideline 2.5.2) — corrected S104
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

**Guideline 2.5.2** ("Apps should not download, install, or execute code which introduces or changes features or functionality of the app") has a JS/WebKit exemption. The key: scripts must not change the app's **primary purpose** — in Yomi's case the primary purpose IS reading from sources, so adding sources via scripts is consistent with the purpose.

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
As of S47, all 131 English LNReader v3 plugins should work in Yomi at the JSBridge level. Remaining failures (if any) are source-specific (site structure changes, Cloudflare blocks, dead sites) — not JSBridge gaps.

---

*End of RESEARCH.md — last compiled S47, 2026-04-25*
