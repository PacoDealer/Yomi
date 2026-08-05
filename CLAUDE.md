# Yomi — Claude Code Project Context

## What this app is
iOS manga, manhwa, manhua, and light novel reader. Plugin-based architecture:
JS plugins run in JavaScriptCore. Two plugin formats: Format A (manga) and Format B (LNReader/novels).
Firebase CDN hosts all 15 production plugins. App binary ships zero plugin files (App Store compliance).

## Tech stack
- **Swift + SwiftUI — iOS 26.2 deployment target. No iOS 18 fallbacks. Ever.**
- GRDB for SQLite (NOT SwiftData)
- JavaScriptCore for plugin execution
- Firebase Hosting: https://yomi-plugins.web.app

## Project path
`/Users/martingamberg/Desktop/Projects/Yomi/iOS`

## Key docs (read these at session start)
- `Yomi/ROADMAP.md` — current state, planned work, tech debt
- `Yomi/ARQUITECTURA.md` — full architecture, data flows, DB schema
- `Yomi/METODOLOGIA.md` — workflow rules, tech learnings per session
- `Yomi/RESEARCH.md` — master research doc (competitive, UX, App Store, iOS 26, plugins, architecture)
- `Yomi/design/DESIGN_HANDOFF.md` — **design track handoff + roadmap to launch (start here for design/publish work)**
- `Yomi/design/DESIGN_SYSTEM.md` — the justified design system (concept, color/theming, type, components, screens)
- `Yomi/design/DESIGN_RESEARCH.md` — design/UX/competitive research behind the system
- `Yomi/design/design_handoff_yomi/YOMI Screens.dc.html` — **full 16-screen design spec** (primary implementation reference; HTML + inline CSS; all canvas/reader theme colors, screentone patterns, Liquid Glass overlays)

## Design track (S82-S86 — Blocks 1-6 of 12 implemented, Phase 0 fidelity gaps closed S85)

All 16 screens designed and confirmed. Concept: **"reading instrument / living archive"** — warm editorial canvas, covers + user accent are the only color, monospace catalog notation, ink/screentone signature. Confirmed: default accent **Vermilion `#E5473A`**, default canvas **Ink (`#14110F`)**, Space Grotesk (UI) + Space Mono (notation), Newsreader serif (novel body). Design tokens live in `DesignTokens.swift`; canvas colors are wired app-wide via `\.yomiCanvas` environment (`CanvasEnvironment.swift`, set from `AppSettings.canvasColors`); notation helpers in `Notation.swift`; Appearance Studio in `AppearanceStudioView.swift`. **Full design spec**: `Yomi/design/design_handoff_yomi/YOMI Screens.dc.html` — 16 screens as HTML with inline CSS. App icon assets: `AppIcon-Ink.png` + `AppIcon-Paper.png` in `Yomi/design/design_handoff_yomi/assets/`. **Implementation order (12 blocks):** ~~Library~~ → ~~Library-selection~~ → ~~Detail~~ → ~~Manga Reader overlay~~ → ~~Novel Reader overlay~~ → ~~Browse~~ → ~~History~~ → ~~Updates~~ → Downloads → Insights → More+Settings → Onboarding+empty states. Compile + screenshot checkpoints after blocks 1, 3, 5, 12 — **Blocks 1-5 screenshot-verified with no known fidelity debt as of S85; Block 6 (Browse) screenshot-verified S86; Block 7 (History) live-verified S91; Block 8 (Updates) live-verified S92.** Next session: Block 9 (Downloads).

## Current state (post S92 — 2026-08-05 · Block 8 — Updates)

S92 implemented Block 8 (Updates) of the 12-block design track against N.12 in
`YOMI Screens.dc.html`. Blocks 1-8 of 12 complete; Block 9 (Downloads) is next. `UpdatesView.swift`
moved from a native `List`/`.insetGrouped` layout (one `Section` per manga/novel, one row per new
chapter) to `ScrollView` + `LazyVStack` grouped by date bucket (Today/Yesterday/This week/This
month/Earlier), matching N.12's `sec.group`/`it` row shape — **a real behavior change, not just
visual**: the mock is one summary row per title, not per chapter, so the old per-chapter row list was
consolidated into a single row per manga/novel with a chapter-range note (new
`Notation.chapterRange(low:high:)`, e.g. "CH. 002–008") and a count pill. Two judgment calls for
behavior the mock didn't spell out: (1) per-chapter tap-to-read → a trailing circular icon jumps into
the reader at the *oldest* unread new chapter (picking a different chapter is still possible by
tapping the row to open Detail, same as History); (2) the header "mark all read" button → moved to a
long-press `.contextMenu` per row (`ScrollView`/`LazyVStack` has no `.swipeActions`, same constraint
History hit in S91). The mock's second header icon (filter/lines glyph) was interpreted as a shortcut
into the existing "Update rules" settings (`UpdatesSettingsView`, un-privatized from `SettingsView.swift`).
Also extracted `Notation.dateGroupLabel()`/`dateGroupOrder` out of `HistoryView.swift`'s private
date-bucketing so History and Updates share one implementation. Verified live via `build_run_sim` +
mobile-mcp against real on-device data: row→Detail navigation, start-reading icon opening the reader
at the correct oldest chapter, long-press mark-all-read (row disappears, correct empty state), and
the filter icon reaching Update Rules — all confirmed working, zero build warnings. Full detail in
`Yomi/ROADMAP.md`'s S92 entry.

Full session-by-session history (S1-S90) lives in `Yomi/ROADMAP.md` (recent) and `Yomi/HISTORY.md`
(archived) — not duplicated here. This file keeps only the single most-recent state above.
## Known issues / carry-forward

| # | Issue | Notes |
|---|-------|-------|
| 1 | Chapters from Browse (partial) | ✅ NovelFire + NovelBin fixed and verified live S88 (see Yomi/ROADMAP.md S88 entry). NovelFire was hardcoded to chapter-list page 1 only (100/3,139 chapters); rewrote to loop all pages. NovelBin's domain (`novelbin.me`) was dead (DNS_PROBE_FINISHED_NXDOMAIN) — rebranded to `novelarrow.com`, rewrote the whole plugin against its clean JSON API. FreeWebNovel's scrape was also rewritten (old code picked up unrelated links, not chapters) but is now blocked by a new site-wide Cloudflare challenge with no bypass wired into the novel-detail path — see row 11. Asura Scans/MangaDex only code-reviewed (pagination logic already loops correctly), not live-retested. |
| 2 | ~~App icon missing~~ | ✅ Done S87 — wired into Xcode (see #3). |
| 3 | ~~Alternate icons need Xcode step~~ | ✅ Done S87 — `AppIcon.appiconset` now ships `AppIcon-Ink-1024.png`; new `AppIcon-Paper.appiconset` added; `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES` set in both configs (Xcode 26's automatic alternate-icon Info.plist generation — verified `CFBundleAlternateIcons.AppIcon-Paper` in the compiled Info.plist). Deleted the two stale empty `AppIconDark`/`AppIconMinimal` appiconsets and fixed `AppearanceStudioView.swift`'s icon picker to use the real `AppIcon-Paper` key instead of leftover placeholder names. |
| 4 | App Store content missing | Age rating 18+, description, screenshots pending in App Store Connect. |
| 5 | ~~Firebase deploy pending~~ | ✅ Deployed S53 — babelnovel.js + lightnovelpub.js live. |
| 6 | ReadComicOnline + Mangapill broken | Downloaded from dead GitHub repo. User should uninstall from Extensions tab. |
| 7 | ~~Inconsistent cover-cell sizes in grid~~ | ✅ Root-caused + fixed S87. `.aspectRatio(_, contentMode: .fill)` alone falls back to the content's own intrinsic size whenever the parent proposes unbounded height (grid cell with only column width fixed, or `.frame(width:)` with no height) — cell height ended up varying per image. Fixed with a new `coverAspectSized()` modifier (`Core/CoverImage.swift`): a `Color.clear.aspectRatio(2/3, contentMode: .fit)` sizer drives a deterministic width-based height, with the real image as an `.overlay` + `.clipped()`. Applied to the shared `CoverImage` component (fixes `NovelLibraryCoverCell`, `NovelCoverCell`, `OPDSBrowseView` for free) plus the inline duplicates in `MangaCoverCell.swift`, `LibraryView.swift`'s `NovelLibraryCoverCell` custom-cover branch, `ContinueReadingRow.swift` (both manga/novel cells), and `HistoryView.swift`. Verified live: MangaDex Popular grid cells are now uniform. |
| 8 | Manga sources never show Popular/Latest tabs | ✅ Root-caused S88 for Suwayomi specifically: `SuwayomiSource.supportsLatest` was already decoded from the server's own API (real Keiyoushi/Tachiyomi extensions do report it correctly) but `SuwayomiService` had no `fetchLatest()` and `SuwayomiBrowseView` never called anything but popular — a pure client-side gap. Added `fetchLatest()` + a `FeedTab` picker in `SuwayomiBrowseView`, matching `BrowseView.swift`'s existing pattern. S89: Popular tab now live-verified working end-to-end against a real Suwayomi server; Latest tab specifically not re-tested this session (same code path, lower risk). Prior verdict still stands for direct JS plugins: `JSBridge.supportsLatest` requires `getLatestManga`, which `mangadex.js`/`asurascans.js` never implemented. |
| 9 | ~~AquaManga "Cloudflare bypass fails"~~ | ✅ Root-caused S87 — **misdiagnosed originally, not a Cloudflare problem at all.** Confirmed live (Chrome + in-app debug logging): SOURCE.fetch's plain UA/headers get a clean `200` with full HTML every time, no CF challenge — the domain migrated `aquareader.net` → `aquareader.org` and was **rebuilt on a custom theme** (no longer Madara WordPress), so `aquamanga.js`'s old selectors (`div.page-item-detail`, `li.wp-manga-chapter`, etc.) matched nothing. Rewrote `getMangaList`/`getChapterList`/`searchManga` against the live DOM (`article.aqua-archive-card`, `a.aqua-ch-item`, fixed a `searchManga` container bug that only ever matched the first of N results). `getPageList` needed no change — the reader page kept the old markup. Deployed to Firebase (`v1.1.0`). **While chasing why the fix "didn't take" during testing, found and fixed two real caching bugs**, both `URLCache` serving stale CDN responses despite `Cache-Control: max-age=3600` no longer matching the redeployed content: `PluginCatalogService.fetchCatalog(force: true)` and `ExtensionManager.install()` now both set `.reloadIgnoringLocalCacheData` — without this, "Update" and even a fresh reinstall could silently keep running old plugin code indefinitely. **Two things found but left unfixed, for next session:** (a) AquaManga's cover images still render as gray placeholders — the image host (`wp-content/uploads`) is Cloudflare-protected and Kingfisher's requests don't carry `cf_clearance`/matching UA; added a global Kingfisher `requestModifier` in `YomiApp.swift` setting `CFBypassConstants.userAgent`, but did **not** get to verify it actually fixes the covers (see (b)). (b) **Runaway pagination**: `SourceBrowseView.loadMore()` fetched **100+ pages in seconds** for AquaManga — `hasMoreContent` only goes false on an *empty* result, but AquaManga's archive apparently never returns empty past the real last page (~63 pages for 1,495 series), so it never terminates. Very likely also the actual reason covers never load (Kingfisher/URLSession flooded by concurrent `SOURCE.fetch` calls). Needs a page-level dedup or max-page safety cap in `BrowseView.swift`'s `loadMore()`. |
| 10 | ~~Keiyoushi repo — not missing, architectural~~ | ✅ Architecture verdict still correct (Kotlin/APK, cannot run in JSC, confirmed since S18) — but S89 found the bridge itself had **two real bugs** that meant it never actually worked even with a server configured: no ATS exception (all Suwayomi/OPDS traffic over plain HTTP was silently blocked) and `SuwayomiService.fetchChapters()` hit a 404ing REST path. Both fixed and live-verified S89 against a real Suwayomi-Server with the real Keiyoushi repo and a real installed extension (Asura Scans) — Popular/detail/chapters/page-image all confirmed working end-to-end. Tachimanga researched and confirmed to use the *exact same* self-hosted-server-bridge architecture, not an embedded/bundled Keiyoushi — Yomi's S41 design was already correct, it just had bugs. See `ROADMAP.md`'s S89 entry for full detail including how to stand up a persistent server. |
| 11 | FreeWebNovel blocked by Cloudflare (new, S88) | freewebnovel.com now Cloudflare-challenges **all** non-browser requests — confirmed via cold `curl` (no cookies): both the plain HTML novel page and the site's own AJAX chapter-list endpoint return a "Just a moment…" JS-challenge page, not real content. `freewebnovel.js`'s `parseNovel` was rewritten this session to use the correct AJAX pagination (fixing a worse bug where the old scrape picked up unrelated "related novels" links, not chapters) and is deployed as v1.1.0, but **cannot succeed** until CF-bypass is wired into the novel detail/chapter path — `CFBypassManager`/`CFBypassView` currently only exist in `BrowseView.swift`'s manga `SourceBrowseView`, not in `MangaDetailView.loadChapters()` (which novels also go through). Needs the same bypass flow extended to novel sources, or the source may need to be dropped if a bypass proves impractical for Format B. |
| 12 | Duplicate extension rows (new, found+fixed S88) | `ExtensionManager.install()` always inserted under the *catalog's* id without removing an existing install of the same plugin under a *different*, older id — Yomi went through a sha256-hash-id → stable-catalog-id migration at some point and nothing ever cleaned up the old rows. Result: Plugins/Browse showed some sources (NovelFire, FreeWebNovel, NovelBin) **twice**, one stale/unupdatable alongside one fresh, confirmed directly in `yomi.db`. Fixed: `install()` now deletes any other installed extension with the same name before writing the new row. **The user's real device likely has this same duplication for any plugin installed before the id-scheme migration** — worth a quick glance at the Plugins screen next session; if duplicates are there, tapping "Update" on the affected source once (with this fix shipped) will self-heal it. |
| 13 | Custom fonts (Space Grotesk/Space Mono) may never have rendered (new, found S89, unverified) | While fixing the ATS bug, found `INFOPLIST_ADDITIONAL_FILE` (the mechanism used since S80 to merge `UIAppFonts` into the generated Info.plist) silently merges nothing — confirmed via `plutil -p` on a clean-built app, `UIAppFonts` was absent from the compiled Info.plist. Fixed as a side effect of the ATS fix (switched to an explicit `Yomi/Info.plist`, confirmed `UIAppFonts` now present). **Not yet confirmed whether this was actually broken live** (i.e. whether the app has been silently falling back to the system font this whole time) — needs a screenshot compare against pre-S89 screenshots, or just a live look, next session. |

## MCP tools — use these every session

### XcodeBuildMCP (build + simulator)
**Always call `session_show_defaults` before the first build of a session.** Then `build_run_sim` (or `build_sim`).
```
mcp__XcodeBuildMCP__session_show_defaults  — verify project/scheme/simulator configured
mcp__XcodeBuildMCP__session_set_defaults   — set if missing: project=Yomi.xcodeproj, scheme=Yomi, simulator="iPhone 17 Pro"
mcp__XcodeBuildMCP__build_sim              — compile only (fast check)
mcp__XcodeBuildMCP__build_run_sim          — compile + launch in simulator
mcp__XcodeBuildMCP__screenshot             — screenshot the running simulator
mcp__XcodeBuildMCP__launch_app_logs_sim    — stream live logs
```

### context7 (live library docs)
Use whenever touching GRDB, SwiftUI, or any third-party API. Append `use context7` to the query.
```
mcp__context7__resolve-library-id  — find the library ID (e.g. "grdb swift")
mcp__context7__query-docs          — fetch current API docs for that library
```
Never rely on training-data knowledge for GRDB migration syntax, SwiftUI modifiers, or iOS 26 APIs — always fetch via context7.

### mobile-mcp (simulator UI automation)
Use to inspect what's actually rendered on screen after a build+run.
```
mcp__mobile-mcp__mobile_take_screenshot         — visual snapshot
mcp__mobile-mcp__mobile_list_elements_on_screen — accessibility tree with coordinates
mcp__mobile-mcp__mobile_click_on_screen_at_coordinates — tap a UI element
```

### github
Use for PR/issue management. Repo: `PacoDealer/Yomi`.
```
mcp__github__list_issues    — see open issues
mcp__github__issue_read     — read a specific issue
mcp__github__create_pull_request
```

### swift-lsp plugin
Installed via `/plugin install swift-lsp@claude-plugins-official` inside a Claude Code session.
Provides real-time Swift diagnostics. **Remember: SourceKit errors from swift-lsp are always noise
(cross-file types not resolved in isolation). Only xcodebuild errors are signal.**

### apple-docs (SwiftUI + iOS 26 API)
Use for SwiftUI + iOS 26 API lookups from developer.apple.com.
```
mcp__apple-docs__search_apple_docs      — search for a symbol or topic
mcp__apple-docs__get_apple_doc_content  — fetch full doc page
mcp__apple-docs__search_wwdc_content    — search WWDC session transcripts
```

## Research rule — never say "impossible" without asking the second question

For 40 sessions, "Keiyoushi extensions are impossible on iOS" was the stock answer. Suwayomi — a self-hosted server that exposes all 1000+ extensions via REST — was always the solution. It shipped in S41.

**Before concluding any ecosystem integration is impossible:**
1. Does a self-hosted server/proxy expose it via REST? (Suwayomi for Keiyoushi, FlareSolverr for Cloudflare, Komga for local libraries)
2. Does any competing iOS app (Paperback, Aidoku, Tachimanga) already support it? If yes, find out how.
3. Use `WebSearch` — never rely on training-data knowledge alone for ecosystem research.

"X format is impossible to run on iOS" ≠ "there is no path." Always ask: **what bridge, proxy, or server exists?**

## ABSOLUTE RULES — never violate

### Swift 6 + concurrency
- All `*Queries` methods must be `nonisolated`
- All JSBridge calls must be `Task.detached(priority: .userInitiated)` — never call from MainActor (SOURCE.fetch blocks with DispatchSemaphore)
- Deliver results via `await MainActor.run { state = result }`
- `appDatabase` is `nonisolated(unsafe) var` at module level — never wrap in an actor
- `ExtensionManager.shared` is MainActor-isolated — capture a local closure before entering Task.detached
- **Never read `AppSettings.shared` properties inside `Task.detached`.** Capture any needed values as local constants on MainActor before entering the detached task — `AppSettings` is not thread-safe.

### File editing
- **Always read the target file before editing it.** Never write against assumptions.
- **When replacing an entire file: explicitly check what the new file omits vs the current file.** Silent deletion of existing logic is the #1 source of regressions (OnboardingView, markRead() both dropped this way in S21).
- **Before removing or renaming any public symbol (function, property, type): grep for all call sites first.** A symbol that looks unused in its own file may be the only path through a critical flow elsewhere.
- **Before editing doc sections (ROADMAP/METODOLOGIA/ARQUITECTURA/CLAUDE.md): read the current content of that section.** Never update docs from memory — diffs, not recollection.
- Compile before touching a third unrelated file. Chaining two tightly coupled edits then compiling is fine; letting errors compound across unrelated files is not.
- Never create a file that isn't strictly required.

### GRDB
- Next migration prefix must be `v20_` (v19_ used for source indexes in S77)
- `nonisolated` on all `*Queries` static methods
- Use `_ = try appDatabase.write { ... }` to silence unused result warning
- `appDatabase.read` from `@MainActor` context requires `try await`
- **INSERT OR IGNORE pattern**: `try ch.insert(db, onConflict: .ignore)` — never use `ch.save(db)` for chapter list persistence (save = INSERT OR REPLACE which overwrites existing read/download state)

### Diagnosing errors
- **Read the full build error before touching any code.** Never fix what you expect — fix what the compiler says.
- After a session gap of more than a few days: run a build before writing any new code. DerivedData and simulator state can drift.

### iOS 26 patterns
- TabView: `Tab("title", systemImage:) {}` — `.tabItem {}` renders nothing in iOS 26
- `Text + Text` is deprecated — use `Text("\(Text(…)) …")` interpolation
- `.tint()` and `.preferredColorScheme()` go on `ContentView()` inside WindowGroup, NOT on WindowGroup/Scene itself
- `@Observable` singletons in App structs require `@State` to drive re-evaluation (not just `AppSettings.shared.property`)

### Image loading
- **Never use `AsyncImage` for cover images or manga pages.** `AsyncImage` has no disk cache — every app launch re-fetches all images. Use `KFImage` from Kingfisher (SPM: `https://github.com/onevcat/Kingfisher`). Drop-in replacement: `KFImage(url)` instead of `AsyncImage(url:)`.
- Kingfisher provides automatic disk + memory cache. Cover images load instantly after the first fetch.
- For manga page images inside readers, `AsyncImage` is acceptable (pages are transient — not worth caching to disk).

### Database performance
- **Always add an index when a new table is queried by a non-primary-key column.** Current indexes: `idx_chapter_mangaid`, `idx_chapter_unread`, `idx_novel_chapter_novelid` — added in v18_ migration.
- Every new `WHERE column = ?` query pattern on a large table needs a corresponding index.

### Plugin system
- Never build `JSBridge(scriptURL: ext.sourceListURL)` — URL in DB goes stale. Always reconstruct from `FileManager` + `ext.id`
- `JSBridge` is per-extension, never shared between concurrent tasks
- `#if DEBUG seedBundledPlugins()` in `YomiApp.init()` — never in release

## Key file paths
```
Yomi/AppSettings.swift                         # @Observable singleton, UserDefaults, 40+ props (incl. canvas, accentColor, libraryColumns, keepScreenOn, isIncognito, showUnreadBadge, lineSpacing, libraryDisplayMode)
Yomi/ContentView.swift                         # Root TabView with AppRouter binding
Yomi/YomiApp.swift                             # Entry point, DB setup, #if DEBUG seed, .tint + .preferredColorScheme on ContentView
Yomi/Core/AppRouter.swift                      # @Observable, module-level appRouter var
Yomi/Core/Color+Hex.swift                      # Color(hex:) init + Color.hexString
Yomi/Core/DesignTokens.swift                   # YomiTokens: Canvas (Ink/Midnight/Paper/Sepia), Accent (Vermilion default), Font (Space Grotesk + Mono), TypeScale, Reader themes, Radius, Spacing, Motion
Yomi/Core/CanvasEnvironment.swift               # \.yomiCanvas environment key — set once in ContentView from AppSettings.canvasColors, read via @Environment everywhere
Yomi/Core/GlassChip.swift                       # .glassChip() — shared 44×44 floating Liquid Glass circle modifier for chrome buttons
Yomi/Core/UIImage+AverageColor.swift            # UIImage.averageColor() via CIAreaAverage — backs Continue hero's ambient-tint-from-cover background
Yomi/Core/Notation.swift                       # Catalog-notation formatters (Space Mono output): chapter(), progress(), readingTime(), status(), novelIndex(), historyTimestamp(), etc. `nonisolated enum` (S91) — safe to call from Task.detached.
Yomi/Core/NotificationManager.swift
Yomi/Database/DatabaseManager.swift            # Migrations v1–v19_source_indexes; next must be v20_
Yomi/Database/Queries/MangaQueries.swift
Yomi/Database/Queries/ChapterQueries.swift     # insertAllIgnoringConflicts (INSERT OR IGNORE — safe bulk persist, called from loadChapters)
Yomi/Database/Queries/CategoryQueries.swift
Yomi/Database/Queries/NovelQueries.swift       # fetchLibrary() EXISTS but is never called by LibraryViewModel
Yomi/Database/Queries/ExtensionQueries.swift
Yomi/Features/Extensions/JSBridge.swift        # JavaScriptCore bridge, shims, require(), getLatestManga(), supportsLatest
Yomi/Features/Extensions/ExtensionManager.swift
Yomi/Features/Extensions/PluginCatalogService.swift  # multi-URL parallel fetch, dedup by id, invalidateCache()
Yomi/Features/Extensions/SuwayomiService.swift       # Suwayomi REST client; SuwayomiSource/MangaPage/ChapterItem structs; isEnabled check
Yomi/Features/Extensions/SuwayomiBrowseView.swift    # Browse one Suwayomi source (infinite scroll, search, isPresented: nav)
Yomi/Features/Library/LibraryView.swift        # grid/list toggle (settings.libraryDisplayMode), grid columns, multi-select
Yomi/Features/Library/LibraryViewModel.swift   # manga + novels; SortOrder enum; fetchLibrary() runs in Task.detached
Yomi/Features/Library/MangaDetailView.swift    # Chapter tap→reader via navigationDestination(item:). insertAllIgnoringConflicts in loadChapters.
Yomi/Features/Library/MangaCoverCell.swift     # Cover cell + MangaListRow struct (for list mode)
Yomi/Features/Browse/BrowseView.swift          # SourceBrowseView: FeedTab enum, supportsLatest picker, bridge reuse; Suwayomi section
Yomi/Features/Reader/ChapterReaderView.swift   # Auto-mark read, incognito guard, lastPageRead save/resume
Yomi/Features/Reader/TextReaderView.swift      # Novel reader; overlay opacity animation; dynamic colorScheme (sepia/dark/light)
Yomi/Features/More/PluginsView.swift
Yomi/Features/More/SettingsView.swift          # Plugin Repos section, Suwayomi section, Advanced → NavigationLink; Appearance → AppearanceStudioView
Yomi/Features/More/AppearanceStudioView.swift  # Canvas × Accent × Type studio; live preview card; WCAG contrast badge; app icon tiles; Reset defaults
Yomi/Features/More/AdvancedSettingsView.swift  # Cache, Network (read-only), Database (log export), Build info
Yomi/Features/More/InsightsView.swift          # ScrollView + LazyVGrid StatCards redesign
Yomi/Features/Onboarding/OnboardingView.swift
Yomi/Resources/                                # JS plugins (test-source.js only; production on Firebase)
Yomi/design/design_handoff_yomi/YOMI Screens.dc.html  # PRIMARY DESIGN REFERENCE — 16 screens, HTML+CSS, all tokens/themes inline
Yomi/design/Fonts/                             # SpaceGrotesk-Variable.ttf, SpaceMono-Regular.ttf, SpaceMono-Bold.ttf, YomiFonts.plist
scripts/build-plugins.mjs                      # esbuild bundler for TS plugins
```

## Build command
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme Yomi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
# Available simulators (Xcode 26.3.1): iPhone 16e, iPhone 17, iPhone 17 Pro, iPhone 17 Pro Max, iPhone Air
```
Check available simulators: `xcrun simctl list devices available | grep iPhone`
Clean DerivedData if stale: `rm -rf ~/Library/Developer/Xcode/DerivedData/Yomi-*`

## Firebase plugin deploy
```bash
cd ~/Projects/Yomi/Firebase && firebase deploy --only hosting
```
Firebase folder lives outside the Xcode repo — not committed to git.

## App Store checklist (incomplete items)
- App icon — ✅ designed S79/S82, ✅ Xcode-wired S87 ("Y." monogram, Ink default + Paper alternate; `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS`, verified in compiled Info.plist). Remaining: upload to App Store Connect at submission time.
- Screenshots — blocked until design implementation complete (Blocks 9-12 remain: Downloads, Insights, More+Settings, Onboarding+empty states)
- Age rating 17+ declaration (App Store Connect only)
- App description, screenshots, support URL (App Store Connect only)
- PrivacyInfo.xcprivacy — DONE (S22)
- Privacy policy URL — DONE (yomi-plugins.web.app/privacy)
- MAL token → Keychain — DONE (S24)

## Session close
1. Update all three docs in one prompt: ROADMAP.md + METODOLOGIA.md + ARQUITECTURA.md
2. **Commit and push to GitHub** — every session ends with `git add -A && git commit && git push`. No exceptions.
3. **If JS plugins were modified** — copy changed `.js` files to `~/Projects/Yomi/Firebase/public/` and run: `cd ~/Projects/Yomi/Firebase && firebase deploy --only hosting` (requires `firebase login --reauth` if credentials expired).
