# Yomi — Master Research Document
**Last updated:** 2026-04-15 (S35) | **Do not re-research topics marked with ✅ RESEARCHED**

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
11. [Ranked Recommendations](#11-ranked-recommendations)

---

## 1. Competitive Landscape
✅ RESEARCHED (S23 + S32 + S35, 2026-04-07 through 2026-04-15)

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
| iCloud sync | ❌ Not yet (S38+) |
| Pure black OLED mode | ❌ Not yet (S36) |
| Home screen widget | ❌ Not yet (S38) |
| Volume button page-turn | ❌ Not yet (future) |

---

## 3. Source Sites & Scraping
✅ RESEARCHED (S23 + S32, 2026-04-14)

| Site | Type | API | Scraping | Status in Yomi | Notes |
|------|------|-----|----------|----------------|-------|
| MangaDex | Aggregator | ✅ Official free API | N/A | ✅ Working (mangadex.js) | Lost 7k series in May 2025 DMCA wave. Rate limited but generous. |
| ComicK | Aggregator | Partial | Needed | ❌ Removed (Cloudflare 403) | api.comick.dev returns 403 from non-browser clients. Site-level block. |
| Asura Scans | Publisher | JSON API | N/A | ✅ Working (asurascans.js) | api.asurascans.com JSON API — reliable. |
| AquaManga | Aggregator | None | HTML | ✅ Working (aquamanga.js) | aquareader.net domain. |
| Royal Road | Platform | None | Possible | ✅ Working (royalroad.js) | Web serials/LitRPG. Anti-scraping but accessible. |
| ScribbleHub | Platform | None | Possible | ✅ Working (scribblehub.js) | Web serials. AJAX POST TOC. |
| NovelFire | Aggregator | None | HTML | ⚠️ Temporarily removed | Site under active security attack (S35 — official notice posted on novelfire.net). novelfire.js exists and works. Restore to index.json once incident resolves. NOT a permanent Cloudflare block. |
| FreeWebNovel | Aggregator | None | HTML | ✅ Working (freewebnovel.js) | Fixed S34. |
| NovelBin | Aggregator | None | HTML | ✅ Working (novelbin.js) | Uses text slugs not numeric IDs. Fixed S34. |
| LightNovelWorld | Aggregator | None | HTML | ❌ Removed (site dead) | Permanently down. Removed from catalog S34. |
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
4. **Pure Black / AMOLED** — #000000 bg (battery saving, OLED users) ❌ **Not yet (S36)**

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
✅ RESEARCHED (S23 + S32, updated 2026-04-14)

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

### Plugin/Extension System (Guideline 2.5.2)
- Apple does NOT allow third-party plugins that download additional native code.
- **EXCEPTION**: JavaScriptCore and WebKit are explicitly allowed for remote JS execution.
- Requirements: scripts must not change app's primary purpose, must not bypass review.
- **Yomi is compliant**: Uses JavaScriptCore, plugins are JS scripts (not binaries).
- Legal precedent: Paperback and Aidoku use identical extension model and are approved.
- Do NOT market as "extensible with third-party plugins" — frame as "sources + community scripts."

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
✅ RESEARCHED (S35, 2026-04-15)

| Feature | Tachimanga | Aidoku | Paperback | **Yomi** |
|---------|-----------|--------|-----------|---------|
| Alternate app icons | ✅ Multiple sets | ❌ | ❌ | ❌ **S36** |
| iOS 18/26 adaptive icons | ✅ v4.2 | ❓ | ❓ | ❌ **S36** |
| Custom themes (dark/sepia/light) | ✅ Premium | ✅ | ✅ | ✅ (reader only) |
| Pure black OLED mode | ✅ | ❓ | ❓ | ❌ **S36** |
| Per-source custom colors | ❌ | ❌ | ❌ | N/A |
| Tab bar customization | ✅ v4.13 | ❓ | ❓ | ❌ **S38+** |
| Home screen widget | ❓ | ❓ | ❓ | ❌ **S38** |
| App-wide themes (not just reader) | ✅ | ❓ | ❓ | ❌ **S36+** |

---

## 8. Plugin Ecosystem — Platform Compatibility
✅ RESEARCHED (S23 + S32 + S35, 2026-04-15)

### Tachiyomi/Mihon → iOS: NOT VIABLE

| Approach | Verdict | Reason |
|----------|---------|--------|
| Direct APK execution | ❌ Impossible | Dalvik/ART doesn't exist on iOS |
| Kotlin Multiplatform (KMP) | ❌ Not applicable | KMP shares business logic, not plugin execution environments |
| Kotlin/Wasm | ❌ Wrong target | Targets browsers via WasmGC, not embedded in-app runtimes |
| JS transpilation of Kotlin | ❌ No tooling | No mature Kotlin→JS pipeline that preserves Android API calls |

**Conclusion:** No action needed. No iOS reader has solved this, and it's not solvable with current tooling.

### iOS Plugin Format Comparison

| App | Format | Language for Authors | Yomi Support |
|-----|--------|---------------------|--------------|
| **Yomi (Format A)** | Global JS functions (IIFE) | JavaScript | ✅ Native |
| **Yomi (Format B)** | LNReader JS class on `plugin` global | JavaScript/TypeScript | ✅ Native |
| **Paperback** | TypeScript → IIFE bundle, `Source` class export | TypeScript | ⚠️ Shim in S24 (partial) |
| **Aidoku** | `.aix` packages (WASM) | Rust (aidoku-rs SDK + aidoku-cli) | ❌ Not viable |
| **Mihon** | Kotlin APK | Kotlin | ❌ Impossible |

### Paperback Compatibility — HIGHEST LEVERAGE UNLOCK (S37)
- Paperback has ~100+ community TypeScript sources already written
- Format: TypeScript → IIFE bundle exporting `Source` class
- **S24 foundation already exists**: `require('paperback-extensions-common')` shim in JSBridge, `injectPaperbackAdapter()` post-eval detection
- **Gap**: HTTP bridge via `requestManager.schedule()` pattern not fully wired for all source types
- **S37 target**: Full Format C support, tested against 3+ real Paperback sources, 5–10 catalog entries added

### LNReader (Format B) — Already Working
- Yomi Format B implements the full LNReader plugin API
- Sources available today without code changes: Royal Road ✅, ScribbleHub ✅, NovelFire ✅, FreeWebNovel ✅, NovelBin ✅
- Unimplemented LNReader gaps:
  - `latestUpdates()` not called by Yomi's UpdatesView (low priority)
  - `plugin.options` (per-source settings) not surfaced in UI (low priority)

### WASM Runtime (Aidoku's approach) — Long-term only
- Requires embedding `wasm3` or `WasmKit` (~500KB–2MB binary addition)
- Plugin authors must know Rust — high barrier vs. plain JS
- All 8 existing plugins would need complete rewrite
- **Verdict:** Best architecture for security + performance at scale. Revisit S40+.

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

## 11. Ranked Recommendations

### Immediate — App Store Blockers (User Actions)
| # | Action | Where | Time |
|---|--------|-------|------|
| 1 | Firebase deploy (fixed plugins) | `firebase login --reauth && firebase deploy --only hosting` in `~/Desktop/Yomi\ 2.0/yomi-firebase` | 5 min |
| 2 | Uninstall LightNovelWorld | Yomi app → Extensions → swipe left on LightNovelWorld | 1 min |
| 3 | App icon design (1024×1024 PNG) | Figma/Sketch/AI + Icon Composer for 3 layers | 30–60 min |
| 4 | Age rating 18+ | App Store Connect → App Information | 5 min |
| 5 | App description | Paste S33 draft into App Store Connect | 10 min |
| 6 | Screenshots (6.9" iPhone + iPad) | Xcode Simulator → File → Take Screenshot | 20 min |
| 7 | Support URL | GitHub repo URL in App Store Connect | 2 min |

### S36 — App Store Push + Customization Polish (Claude codes)
| # | Feature | Impact | Effort |
|---|---------|--------|--------|
| 1 | Alternate app icons (2–3 variants + SettingsView picker) | High — visual polish | Low–Medium |
| 2 | Pure black OLED mode (`AppSettings.pureBlack`) | Medium — matches Tachimanga | Very Low |
| 3 | NovelFire targeted WKWebView fallback (`requiresWebView` flag) | Medium — fixes synopsis | Medium |
| 4 | App icon integration (user delivers PNG → Icon Composer layers → xcassets) | High — App Store blocker | Low (after user delivers) |
| 5 | `xcrun mcpbridge` supplemental Xcode MCP | Low — SwiftUI previews | Very Low |

### S37 — Paperback Ecosystem Unlock ~100 sources (Claude codes)
| # | Feature | Impact | Effort |
|---|---------|--------|--------|
| 1 | JSBridge Format C full detection + Source class bridge | Very High — unlocks 100+ sources | Medium |
| 2 | requestManager HTTP bridge compatibility | High — required for Paperback sources | Medium |
| 3 | Test with 3 real Paperback sources | High — validation | Low |
| 4 | 5–10 curated Paperback sources in Firebase catalog | High — user-facing | Low |

### S38 — WidgetKit + Community Infrastructure (Claude codes)
| # | Feature | Impact | Effort |
|---|---------|--------|--------|
| 1 | WidgetKit ContinueReading widget (App Groups + shared DB) | High — acquisition/retention | High |
| 2 | `yomi.d.ts` TypeScript type definitions for plugin authors | Medium — community growth | Medium |
| 3 | GitHub issue template for plugin submissions | Low — process | Very Low |

### Long-term (S40+)
| # | Feature | Impact | Effort |
|---|---------|--------|--------|
| 1 | WASM plugin runtime (wasm3/WasmKit) | High — security + perf | Very High |
| 2 | iCloud CloudKit sync | High — cross-device | High |
| 3 | Text-to-speech (Apple Spoken Content integration) | Medium — accessibility | Low–Medium |
| 4 | Tab bar reordering | Low–Medium | Medium |
| 5 | Novel list view (vs grid) | Low | Low |
| 6 | Glossary / character notes (per novel) | Medium | High |

---

*End of RESEARCH.md — last compiled S35, 2026-04-15*
