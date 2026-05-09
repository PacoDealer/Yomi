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
`/Users/martingamberg/Projects/Yomi/iOS`

## Key docs (read these at session start)
- `Yomi/ROADMAP.md` — current state, planned work, tech debt
- `Yomi/ARQUITECTURA.md` — full architecture, data flows, DB schema
- `Yomi/METODOLOGIA.md` — workflow rules, tech learnings per session
- `Yomi/RESEARCH.md` — master research doc (competitive, UX, App Store, iOS 26, plugins, architecture)

## Current state (post S65 — 2026-05-09)

**S65 shipped:**
1. Last-read chapter label on library covers: both `MangaCoverCell` and `NovelLibraryCoverCell` show the most recently read chapter name as a `black.opacity(0.65)` semi-transparent label stacked above the progress bar inside `.overlay(alignment: .bottom)`. Only shown when `readProgress > 0`. Manga uses chapter with latest `readAt`; novel prefers in-progress (`lastScrollPercent > 0.01 && !isRead`) over fully-read.
2. Reading activity calendar in InsightsView: 13-week rolling heatmap in new `ReadingCalendarView` private struct, placed between stat cards and Breakdown. Month labels use `ZStack + .offset(x:)` to avoid width-clipping. Intensity: `accentColor.opacity(min(0.35 + Double(count-1)*0.18, 1.0))`. Calendar data built in `loadStats()` Task.detached, returned as 10th tuple element, assigned via `MainActor.run`.

## Current state (post S64 — 2026-05-09)

S44–S59: all 4 JS plugin formats live, Suwayomi+OPDS, Cloudflare bypass, AniList badges, settings UX (7 sections), novel metadata sync, HistoryView search, S57 incognito audit + GlobalSearch thread fix, S58 novel parity (custom cover, chapter multi-select, format badges), S59 incognito fix + catalog novel badge.

**S60 shipped:**
1. Novel mid-chapter scroll position save/restore: `v17_novel_scroll` migration (`lastScrollPercent REAL` on `novel_chapter`); JS 400ms debounced scroll reporter via `WKScriptMessage`; `WKNavigationDelegate.didFinish` restores position on chapter load; flush on dismiss and chapter nav; incognito guarded
2. Auto-scroll to resume chapter in `NovelDetailView`: `ScrollViewReader` + `proxy.scrollTo("ch_<id>")` fires 300ms after chapters load, targeting first unread/in-progress chapter
3. In-progress chapter progress bar: thin `accentColor` bar in `NovelChapterRow` for chapters with `lastScrollPercent > 2%` and `!isRead`
4. `NovelDetailView` refreshes chapter states (isRead + lastScrollPercent) 500ms after reader closes — mirrors `MangaDetailView` pattern
5. `BackupManager` novels now encode/decode `customCoverPath` and `lastScrollPercent` (parity with manga)
6. Pull-to-refresh on both `NovelDetailView` and `MangaDetailView` (force re-fetch from plugin)

**S61 shipped:**
1. Chapter finished banner in `TextReaderView`: spring-animated bottom banner appears when `onReadComplete` fires (JS 90% scroll trigger); shows "Chapter finished" + "Next →" button (calls `navigateToChapter(currentChapterIndex + 1)`) or "All caught up!" on last chapter; auto-dismisses after 5s; cleared on any chapter navigation; DB write remains incognito-guarded but banner always shows

**S62 shipped:**
1. Novel continue-reading cell opens reader directly: `ContinueReadingNovelCell.openReader()` fetches chapters from DB (no network), resolves bridge from `ExtensionManager`, uses same resume logic as `NovelDetailView` (in-progress → first unread → last); `lastChapterName` now shows in-progress chapters (`lastScrollPercent > 0`)
2. Library sort order + status filter persist across launches: `LibraryViewModel.sortOrder`/`statusFilter` backed by `UserDefaults` via stored-property `didSet`/default-value closures
3. `resumeChapter`/`hasStartedReading` in `NovelDetailView` now check `lastScrollPercent > 0.01` — chapters opened before reaching 90% were previously invisible to resume detection
4. Chapter list sheet in novel reader: list button in `TextReaderOverlayView` top bar opens sheet with all chapters, read/progress status, accent color for current; tap jumps; auto-scrolls to current chapter after 100ms delay
5. Chapter list sheet in manga reader: same pattern in `ReaderOverlayView` for `ChapterReaderView`
6. Mark previous chapters as read: trailing swipe action "Mark previous" on `ChapterRow` (manga) and `NovelChapterRow`; finds chapter position in ascending source array, bulk-marks all lower-index chapters via `ChapterQueries.setRead` / `NovelQueries.markRead(chapterId:)`, updates local `@State` with a `Set`
7. Chapter search in detail views: inline search field (shown only when `chapters.count > 30`) in both `MangaDetailView` and `NovelDetailView`; `ContentUnavailableView` empty-search state; search applied after scanlator/status filter
8. Reading progress bar in detail headers: `ProgressView(value:total:)` above the resume button in both `MangaDetailView` and `NovelDetailView`; shows read-count/total-chapters + caption
9. `ContinueReadingRow` refresh fix: replaced `.task { }` (fires once per view lifetime) with `.onAppear { Task { await loadItems() } }` — row now re-queries DB every time the library tab is shown
10. `ContinueReadingCell` DB fallback: if bridge returns empty chapters (network failure / Cloudflare block), falls back to DB-saved chapters — mirrors `MangaDetailView.loadChapters()` S55 fix
11. Plugin update detection by ID: `PluginCatalogService.isInstalled` + `availableUpdate(for:)` now match by `ext.id` first, falling back to `ext.name` — prevents false "no update" when catalog uses the same ID with a different name string
12. Relative time bar in Insights "By Title": each row wrapped in `ZStack(alignment:.leading)` with `GeometryReader` background `Rectangle().fill(Color.accentColor.opacity(0.12))` scaled to `stat.seconds / maxSeconds`; visually compares reading time across titles at a glance

**S64 shipped:**
1. Reading time in detail view headers: `MangaDetailView` and `NovelDetailView` progress bar caption now appends "· Xh Ym" (computed from `chapters.reduce(0) { $0 + $1.readingSeconds }`) when total > 0; new `formatReadingTime(_ seconds: Int) -> String` private helper in both views
2. `InsightsView` manga/novel breakdown: "Breakdown" section between stat cards and "By Title" shows manga vs novel chapter counts and reading time separately; 4 new state vars (`mangaChaptersRead`, `novelChaptersRead`, `mangaSeconds`, `novelSeconds`) threaded through `loadStats()` return tuple (now 9 elements); `breakdownRow(@ViewBuilder)` helper renders each row
3. `InsightsView` novel badge in "By Title": `isNovel: Bool` added to stats tuple; novel entries show small accentColor "N" badge before title — matches ContinueReadingRow badge pattern; tuple type updated throughout `loadStats()`
4. `HistoryView` `.onAppear` refresh: `.task { await loadHistory() }` → `.onAppear { Task { await loadHistory() } }` — history now re-queries DB every time the History tab becomes visible (same pattern as S62 ContinueReadingRow fix)
5. `LibraryView` `.onAppear` refresh: `.task { await viewModel.loadLibrary() }` → `.onAppear { Task { await viewModel.loadLibrary() } }` — library reloads on every navigation return (e.g. after marking chapters read in detail view)
6. Library sort by reading time: `SortOrder.readingTime = "Reading Time"` added to `LibraryViewModel`; systemImage `"timer"`; sorts `displayedManga` and `displayedNovels` by `readingSeconds` descending; auto-appears in sort menu via `SortOrder.allCases`
7. `HistoryView` novel chapter subtitle shows in-progress chapter: replaces `readAt != nil` filter with `(inProgress ?? lastFullyRead)?.name` — shows where user actually stopped (lastScrollPercent > 0.01) rather than last finished chapter

**S63 shipped:**
1. Line spacing control in novel reader overlay: Tight/Normal/Airy segmented capsule picker added to `TextReaderOverlayView` between font/margin row and theme swatches; `@Binding var lineSpacing: Double`; onChange persists to `AppSettings.shared.lineSpacing`
2. Chapter finished banner in manga reader: `ChapterReaderView` gets identical spring-animated bottom banner to `TextReaderView` (S61); triggers when `currentPage == pages.count - 1`; "Next →" calls `navigateToChapter(currentChapterIndex + 1)`; `showFinishedBanner = false` reset in `navigateToChapter`
3. Backup v3 — categories: `encodeCategory` added; `categories` key in export payload; `importBackup` restores category rows via `INSERT OR IGNORE` before assignment pairs — fresh-device restore no longer leaves `manga_category`/`novel_category` rows pointing to missing category IDs. Bumped backup `version` to 3
4. Backup fix — manga `readingStatus`: `encodeManga` was missing `readingStatus`; `decodeManga` now decodes it with `ReadingStatus(rawValue:) ?? .none`
5. Backup fix — chapter `lastPageRead`: `encodeChapter` was omitting `lastPageRead > 0`; now encoded so resume position survives backup/restore
6. Backup fix — manga category assignments: `exportBackup` fetches `manga_category` rows and includes `"mangaCategories"` key; `importBackup` restores them in the same DB write block as `novel_category`
7. Novel refresh smart-skip parity: `checkNovelUpdates` now applies `skipUpdateNotStarted`, `skipUpdateCompleted`, `skipUpdateWithUnread`, and `excludedCategoryIds` — previously novels were always refreshed regardless of these settings
8. Library context menu (grid + list, manga + novel): long-press on any cover cell or list row shows Reading Status submenu (Plan to read / Reading / On hold / Completed / Dropped) and destructive "Remove from Library"; DB write on status change; `loadLibrary()` called on remove
9. `MangaListRow` custom cover fix: list-mode manga rows were ignoring `customCoverPath` and always using `AsyncImage(url:)`; now mirrors `NovelLibraryListRow` pattern
10. `ContinueReadingNovelCell` resume fix: `openReader()` used `readAt != nil` to detect in-progress chapters; now uses `lastScrollPercent > 0.01` to match `NovelDetailView` S62 fix — chapters read below 90% are now correctly resumed

**Current DB/code state:**
- DB at v17_novel_scroll (18 migrations total, next must be v18_)
- Backup at v3 (adds `categories` array; v2 backups still import cleanly — `categories ?? []` fallback)
- All `*Queries` nonisolated ✅, all bridge calls Task.detached ✅, no MainActor DB reads ✅
- Novel parity gaps: ✅ custom cover ✅ chapter multi-select ✅ scroll position — all done

**App Store status:** Apple Developer account created. Blocked on icon design only for submission.

## Known issues / carry-forward

| # | Issue | Notes |
|---|-------|-------|
| 1 | Chapters from Browse (partial) | Defensive fixes in S37. Root cause unconfirmed — needs live device test. |
| 2 | App icon missing | User designing — 3-layer PNG for iOS 26 Icon Composer. |
| 3 | Alternate icons need Xcode step | Drop PNGs into appiconsets + add `CFBundleAlternateIcons` in Xcode Target → Info. |
| 4 | App Store content missing | Age rating 18+, description, screenshots pending in App Store Connect. |
| 5 | ~~Firebase deploy pending~~ | ✅ Deployed S53 — babelnovel.js + lightnovelpub.js live. |
| 6 | ReadComicOnline + Mangapill broken | Downloaded from dead GitHub repo. User should uninstall from Extensions tab. |

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

### File editing
- **Always read the target file before editing it.** Never write against assumptions.
- **When replacing an entire file: explicitly check what the new file omits vs the current file.** Silent deletion of existing logic is the #1 source of regressions (OnboardingView, markRead() both dropped this way in S21).
- One file at a time. Compile after each new file.
- Never create a file that isn't strictly required.

### GRDB
- Next migration prefix must be `v18_` (v17_ used for novel_chapter.lastScrollPercent in S60)
- `nonisolated` on all `*Queries` static methods
- Use `_ = try appDatabase.write { ... }` to silence unused result warning
- `appDatabase.read` from `@MainActor` context requires `try await`
- **INSERT OR IGNORE pattern**: `try ch.insert(db, onConflict: .ignore)` — never use `ch.save(db)` for chapter list persistence (save = INSERT OR REPLACE which overwrites existing read/download state)

### iOS 26 patterns
- TabView: `Tab("title", systemImage:) {}` — `.tabItem {}` renders nothing in iOS 26
- `Text + Text` is deprecated — use `Text("\(Text(…)) …")` interpolation
- `.tint()` and `.preferredColorScheme()` go on `ContentView()` inside WindowGroup, NOT on WindowGroup/Scene itself
- `@Observable` singletons in App structs require `@State` to drive re-evaluation (not just `AppSettings.shared.property`)

### Plugin system
- Never build `JSBridge(scriptURL: ext.sourceListURL)` — URL in DB goes stale. Always reconstruct from `FileManager` + `ext.id`
- `JSBridge` is per-extension, never shared between concurrent tasks
- `#if DEBUG seedBundledPlugins()` in `YomiApp.init()` — never in release

## Key file paths
```
Yomi/AppSettings.swift                         # @Observable singleton, UserDefaults, 35+ props (incl. libraryColumns, keepScreenOn, isIncognito, showUnreadBadge, lineSpacing, libraryDisplayMode)
Yomi/ContentView.swift                         # Root TabView with AppRouter binding
Yomi/YomiApp.swift                             # Entry point, DB setup, #if DEBUG seed, .tint + .preferredColorScheme on ContentView
Yomi/Core/AppRouter.swift                      # @Observable, module-level appRouter var
Yomi/Core/Color+Hex.swift                      # Color(hex:) init + Color.hexString
Yomi/Core/NotificationManager.swift
Yomi/Database/DatabaseManager.swift            # Migrations v1–v17_novel_scroll; next must be v18_
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
Yomi/Features/More/SettingsView.swift          # Plugin Repos section, Suwayomi section, Advanced → NavigationLink
Yomi/Features/More/AdvancedSettingsView.swift  # Cache, Network (read-only), Database (log export), Build info
Yomi/Features/More/InsightsView.swift          # ScrollView + LazyVGrid StatCards redesign
Yomi/Features/Onboarding/OnboardingView.swift
Yomi/Resources/                                # JS plugins (test-source.js only; production on Firebase)
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
- App icon — missing (user designing)
- Age rating 17+ declaration (App Store Connect only)
- App description, screenshots, support URL (App Store Connect only)
- PrivacyInfo.xcprivacy — DONE (S22)
- Privacy policy URL — DONE (yomi-plugins.web.app/privacy)
- MAL token → Keychain — DONE (S24)

## Session close
1. Update all three docs in one prompt: ROADMAP.md + METODOLOGIA.md + ARQUITECTURA.md
2. **Commit and push to GitHub** — every session ends with `git add -A && git commit && git push`. No exceptions.
