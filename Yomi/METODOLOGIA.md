# Working methodology — Yomi

## Workflow (updated S22 — Claude Code-first)

### Roles
- **Claude Code (terminal)** → everything: reads files, plans, implements, builds, fixes errors, commits/pushes
- **Claude.ai (Desktop app)** → session strategy only: review priorities, flag risks, architectural concerns. Does NOT generate implementation prompts anymore.
- **Xcode** → compile verification, simulator, UI inspection
- **GitHub Desktop** → visual diff review, manual push when required
- **User** → product owner + QA: decides what to build, tests on simulator, reports what feels wrong

### Why the relay was eliminated
The old workflow (Claude.ai generates prompts → user copy-pastes → Claude Code executes) existed because
Claude.ai couldn't see the real file state and compensated by generating extremely explicit prompts.
Claude Code can read actual files before acting, making the relay unnecessary and harmful.
Evidence: S21 regressions (OnboardingView, markRead()) happened because Claude.ai replaced entire files
without seeing what they omitted. Claude Code reading first prevents this class of bug.

### Workflow rules
- Claude Code reads the target file before every edit. Always. No exceptions.
- One file at a time, compile after each new file.
- Never create multiple files simultaneously (docs are the valid exception).
- Commits after each logical unit — not at session close. Clean rollback points matter.
- Code changes and doc updates go in the same session. Never leave docs stale overnight.
- When chaining independent fixes: run all without compiling, compile once at the end.
- Diagnose before prescribing: (1) read the actual file, (2) find exact failure point, (3) write one targeted fix.
- All code, commits, docs, and communication in English (from S15 onward).

### Session start
`cd /Users/martingamberg/Documents/GitHub/Yomi` → open Claude Code.
CLAUDE.md loads automatically with full context. No pasting required.
If starting a session after a long gap: read ROADMAP.md to confirm current state.

### Session close
Claude Code updates all three docs (ROADMAP + METODOLOGIA + ARQUITECTURA) in one step.
Valid exception to "one file per prompt": they are docs, not Swift code.

## AI tooling setup (established S22)

### Philosophy
Claude Code is capable of reading files, planning, implementing, building, and iterating without a human relay. The workflow that uses Claude.ai to generate prompts for Claude Code to execute treats Claude Code as a dumb executor — this is suboptimal. Claude Code-first is better: Claude Code reads actual file state, generates its own implementation plan, writes code, builds, fixes errors, and commits. Claude.ai is reserved for session-level strategy.

### CLAUDE.md
Located at `/Users/martingamberg/Documents/GitHub/Yomi/CLAUDE.md`. Loaded automatically every session. Contains: tech stack, iOS 26 rules, GRDB/concurrency rules, key file paths, current session state, build command, App Store checklist. Update after every session close. This file replaces the session-start paste ritual.

### Memory system
Located at `~/.claude/projects/-Users-martingamberg/memory/`. Contains `MEMORY.md` (index) and `project_yomi.md` (project state). Persists project path, tech stack, and session state across conversations.

### MCP servers
Model Context Protocol servers extend Claude Code with external capabilities. Installed at user scope (available across all projects).

| Server | Install command | What it does |
|--------|----------------|--------------|
| XcodeBuildMCP | `claude mcp add --scope user XcodeBuildMCP -- npx -y xcodebuildmcp@latest mcp` | 59 tools: build, simulator, LLDB, read errors |
| context7 | `claude mcp add --transport http --scope user context7 https://mcp.context7.com/mcp` | Live docs for GRDB, SwiftUI, JS libraries. Append `use context7` to prompts. |
| apple-docs | `claude mcp add --scope user apple-docs -- npx -y @kimsungwhee/apple-docs-mcp@latest` | SwiftUI + iOS 26 API from developer.apple.com |
| github | `claude mcp add --transport http --scope user github https://api.githubcopilot.com/mcp -H "Authorization: Bearer TOKEN"` | PR/issue management |
| mobile-mcp | `claude mcp add --scope user mobile-mcp -- npx -y @mobilenext/mobile-mcp@latest` | iOS Simulator UI automation |

Verify: `claude mcp list` (terminal) or `/mcp` (inside Claude Code session).

### Plugins
Claude Code has a `/plugin` marketplace system. Install inside a Claude Code session.

| Plugin | Command | What it does |
|--------|---------|--------------|
| swift-lsp | `/plugin install swift-lsp@claude-plugins-official` | Real-time Swift diagnostics (note: produces false positives for cross-file types — see S22 learnings) |

### What was evaluated and discarded
- **Phase 3 plugins from Claude.ai research** (`/plugin install frontend-design@claude-plugins-official`, etc.): some did not exist and were hallucinated. Always verify slash commands with `/help` before spending time on them.
- **Custom Yomi MCP**: evaluated, deferred. XcodeBuildMCP already covers build/simulator needs. A custom MCP for GRDB inspection or JSContext isolation testing may be worth building in a future session.
- **Claude.ai connectors** (GitHub, Figma, etc.): these affect the Claude.ai web app, not Claude Code terminal sessions. Useful for Claude.ai planning context but irrelevant to implementation.

## Tech stack
- Swift + SwiftUI (iOS 26)
- GRDB for local SQLite database
- JavaScriptCore for executing JS plugins (Yomi format and LNReader format)
- Architecture inspired by LNReader (Android, TypeScript plugins) and Mihon (Android)

## JS plugin structure
Yomi supports two plugin formats:

**Format A — Yomi/Manga** (global functions):
  getMangaList(page) → [{id, path, title, coverURL, summary, author, artist, status, genres}]
  getChapterList(mangaPath) → [{id, path, name, chapterNumber}]
  getPageList(chapterPath) → [urlString]
  searchManga(query, page) → [{id, path, title, coverURL, summary, author, artist, status, genres}]

**Format B — LNReader/Novel** (class exported on global `plugin`):
  plugin.popularNovels(pageNo, options) → [{name, path, cover}]
  plugin.parseNovel(novelPath) → {path, name, cover, author, summary, status, chapters}
  plugin.parseChapter(chapterPath) → String (HTML)
  plugin.searchNovels(searchTerm, pageNo) → [{name, path, cover}]

JSBridge auto-detects the format: if `plugin.popularNovels` exists → Format B, otherwise → Format A.

## Shims injected by JSBridge
- SOURCE.fetch(url, options) → synchronous HTTP GET or POST via DispatchSemaphore
    options: { method, body, headers } — defaults to GET, POST if method="POST"
- cheerio.load(html) → recursive HTML parser + CSS selector engine in pure JS (functional since S6)
- localStorage / sessionStorage → in-memory JS objects
- console.log/warn/error → Swift print()
- require(name) → module cache shim: routes cheerio/he/node-fetch/axios to native equivalents; injects module, exports, process globals (since S18)

## File path rules
- Before generating any edit prompt, Claude.ai must cite the confirmed exact file path
- If path is uncertain, the prompt includes a `find Yomi -name "*.swift"` step before editing
- Frequently referenced paths:
  - JSBridge: Yomi/Features/Extensions/JSBridge.swift
  - ExtensionManager: Yomi/Features/Extensions/ExtensionManager.swift
  - PluginCatalogService: Yomi/Features/Extensions/PluginCatalogService.swift
  - UpdatesView+ViewModel: Yomi/Features/More/UpdatesView.swift (ViewModel embedded in same file)
  - AppSettings: Yomi/AppSettings.swift (project root, not in Core/)
  - ContentView: Yomi/ContentView.swift (project root)

## Sessions
| # | Date | What was done |
|---|------|---------------|
| 1 | 2026-03-13 | Full setup: Homebrew, Node, Claude Code, folder structure, 4 models (Manga, Chapter, Category, Source), GRDB, 4-tab bar working in simulator |
| 2 | 2026-03-14 | Adaptive LibraryView grid + ViewModel + MangaCoverCell + basic MangaDetailView + grid→detail navigation + DatabaseManager initialized on launch |
| 3 | 2026-03-14 | JS extension system: Extension model, ExtensionQueries, DatabaseManager migration v2, JSBridge v1 (JavaScriptCore), ExtensionManager, test-source.js, BrowseView with CTA + installed extensions list, AdaptiveGrid in LibraryView |
| 4 | 2026-03-15 | JSBridge v2 (dual format Yomi+LNReader, SOURCE.fetch semaphore, cheerio stub, localStorage shim), real mangadex.js plugin (MangaDex API), end-to-end BrowseView with SourceBrowseView, PluginsView (install from URL + Keiyoushi reference catalog), ChapterReaderView (RTL manga + webtoon scroll, pinch zoom 1-4x, immersive overlay), MangaDetailView with real chapter list |
| 5 | 2026-03-15 | Save to library (heart button → MangaQueries.update, inLibrary toggle + haptics). ChapterQueries (markRead: isRead=true, readAt=now, progress=1.0, touchLastRead on parent manga). mangadex.js pagination loop (offset to json.total, limit=500, cap 20 iterations). Real HistoryView with MangaQueries.fetchHistory() (lastReadAt != nil, desc). Prev/next chapter in ReaderOverlayView (displayedChapter state, extracted loadPages()). Dedup plugin install with SHA256(URL).prefix(8) via CryptoKit. |
| 7 | 2026-03-15 | UX audit (visual + code). NSFW filter default off in PluginsView, BrowseView picker below title. AppSettings singleton (@Observable + UserDefaults, 6 properties). SettingsView (General / Reader manga / Reader novel / Appearance / About). InsightsView (total reading time + per-manga list). DB migration v4_reading_insights (readingSeconds INTEGER on manga + novel). ChapterReaderView: time tracking in onDisappear, keepScreenOn via isIdleTimerDisabled, readerMode from AppSettings. MoreView restructured: Settings + Plugins + Insights + About. |
| 8 | 2026-03-15 | BackupManager + BackupView (JSON export/import to Files.app). MALService + MALView (OAuth PKCE plain, yomi:// callback, automatic tracking). ChapterReaderView: refactor to currentChapterIndex + activeChapter, navigateToChapter, Timer 1s → addReadingTime. DB migration v4_reading_time (readingSeconds on chapter). HistoryView: rewrite without ViewModel, Task.detached + MainActor.run, clear button. SettingsView + InsightsView moved to Features/More. MangaDetailView: upsert/insert on heart button, merge isRead+readingSeconds from DB. MangaQueries: fetchRecentlyRead, upsert, removed fetchHistory. PluginsView: SHA256 id to 32 chars. mangadex.js: limit=100, offset loop, cap 2000. MoreView: 6 sections (App / Sources / Reading / Tracking / Data / Info). |
| 9 | 2026-03-16 | Save to library (heart → GRDB upsert + UIImpactFeedbackGenerator). Mark chapter read on last page + onDisappear. ChapterQueries full CRUD (fetchAll, fetchOne, insert, upsert, upsertAll, markRead, markAllRead, updateProgress, addReadingTime, delete, deleteAll). MangaQueries.fetchOne/upsert. Real HistoryView data from GRDB sorted by lastReadAt DESC with swipe-to-delete. Prev/next chapter via navigateToChapter in-place state mutation. BrowseView Search tab functional with client-side filter over getMangaList + source picker. Animated MangaCoverCell shimmer skeleton. Double-tap zoom reset in MangaPageView with simultaneousGesture. Fix: Extension+Hashable for Picker. Fix: Text interpolation iOS 26 (replaced Text+Text). |
| 10 | 2026-03-16 | searchManga(query,page) in mangadex.js and asurascans.js. JSBridge.searchManga(query:page:sourceId:). BrowseView: replaced client-side filter with server-side with debounce 500ms via Task.sleep + cancel. Migration v5_categories (manga_category join table, ON DELETE CASCADE). Full CategoryQueries CRUD. LibraryViewModel: selectedCategoryId + filteredIds + displayedManga. LibraryView: horizontal category chips in .safeAreaInset. CategoryView CRUD UI. MoreView: Library section → CategoryView. |
| 11 | 2026-03-17 | MangaDetailView: category assignment sheet (tag toolbar button, disabled+opacity if !inLibrary, loadCategories/toggleCategory via Task.detached, local Set<String> for immediate feedback). Chapter pagination: displayedChapterCount=50, "Load N more" button, chapterIndex via firstIndex(where:). MangaQueries.fetchLibraryByLastUpdated + touchLastUpdated. UpdatesViewModel (@Observable, withTaskGroup, checkUpdates per plugin). UpdatesView + UpdatesRow. "Updates" tab in ContentView between History and More. |
| 12 | 2026-03-18 | aquamanga.js (Format A, cheerio). DownloadManager singleton (@Observable, sequential queue, parallel pages x3 with withTaskGroup). DB migration v6_downloads (downloadedAt on chapter). DownloadQueries. DownloadsView in More. Badge + swipe-to-delete in MangaDetailView. ChapterReaderView fallback to local files. |
| 13 | 2026-03-18 | Audit and fixes. seedBundledPlugins in ExtensionManager (mangadex/asurascans/aquamanga copied from bundle on launch, SHA256(filename) as ID, DB upsert, skip if exists on disk). bridge(for:) reconstructs URL from extensionsDirectory+id (fix sandbox stale). mangadex.js: multi-language (es/es-la/pt-br/pt), guard NaN chapterNumber, fix empty title. JSBridge SOURCE.fetch: User-Agent iPhone Safari + Accept + Accept-Language as defaults. |
| 14 | 2026-03-22 | Fix InsightsView (active breakpoint, not a real deadlock). Fix "Failed to load source plugin" (bridge(for:) in BrowseView+UpdatesView). New plugins: royalroad.js (Fmt B), scribblehub.js (Fmt B, POST), novelfire.js (Fmt B), comick.js (Fmt A). UX: LibraryView empty state Browse button, Source.swift removed, UpdatesView bell.badge icon, AppSettings decimal locale fix. |
| 15 | 2026-04-04 | AppRouter singleton (@Observable, module-level, Tab(value:) iOS 26). LibraryView empty state navigates to Browse. JSBridge POST support (SOURCE.fetch method/body/headers, _fetchSync 4 args). ContinueReadingRow horizontal in LibraryView. NotificationManager + local push on first library save. TextReaderView: #E8E8E8, line-height 1.5, 18pt min, sepia mode. Fix MangaDetailView loadChapters (bridge(for:)). Fix ContinueReadingRow duplicate .task. Fix comick.js domain (comick.fun). Plugin diagnosis: HTML arrives OK for RoyalRoad/ScribbleHub/NovelFire but selectors incorrect; Asura=React SSR; AquaManga=domain unreachable. |
| 16 | 2026-04-05 | Plugin root cause analysis and fixes. seedBundledPlugins overwrite fix. each() callback pattern fix in royalroad/scribblehub/novelfire/aquamanga. aquamanga domain (aquareader.net) and cover selector fix. All 6 non-Asura plugins working. |
| 17 | 2026-04-05 | InsightsView v2: 4 stat cards (reading streak, chapters read, time read, titles started), streak computed from readAt dates via Set<DateComponents>. asurascans.js full rewrite to api.asurascans.com JSON API (no HTML scraping). All 7 bundled plugins working. |
| 18 | 2026-04-06 | PluginCatalogService (@Observable singleton, PluginCatalogEntry Codable, fetchCatalog async URLSession, isInstalled check). JSBridge require() shim (cheerio, he entity decoder, node-fetch→SOURCE._fetchSync, axios stubs, module/exports/process globals). PluginsView: Installed + Browse sections, Browse fetches remote catalog, installEntry via ExtensionManager, replaces Keiyoushi Android reference. AppSettings.pluginCatalogURL UserDefaults. SettingsView Developer section. scripts/build-plugins.mjs (esbuild IIFE bundler + index.json generator). scripts/catalog-output/index.json (7 plugins seeded). Firebase Hosting: https://yomi-plugins.web.app |
| 19 | 2026-04-06 | App Store compliance: .js removed from Xcode target, seedBundledPlugins() call removed from YomiApp. OnboardingView: 3-page TabView(.page) fullScreenCover on #1C1C1E, hasSeenOnboarding flag, navigates to tabMore. ChapterReaderView: Color.clear immersive tap layer. HistoryView: plugin display name via ExtensionManager. Dark mode and TextReader font re-inject attempted (code written) but not confirmed working in simulator — diagnostic read needed at S20 start. |
| 20 | 2026-04-06 | Dark mode fixed: @State private var settings = AppSettings.shared in YomiApp, @Observable tracking fires on WindowGroup re-evaluation, .preferredColorScheme(settings.colorScheme) reactive. PluginsView catalog: .task → .onAppear { Task { ... } }, retry button, empty state, pull-to-refresh. TextReaderView fontSize: reads+writes AppSettings.shared.fontSize — single source of truth with SettingsView Stepper. Accent color: AppSettings.accentColor (String, default #FF6B6B), 6-swatch picker in SettingsView, Color(hex:) extension, .tint(Color(hex: settings.accentColor)) at WindowGroup root. |
| 21 | 2026-04-07 | Color+Hex.swift (Yomi/Core/, 6+8-digit hex, hexString via UIColor sRGB). AppSettings: fontSize default 18.0, accentColor, colorScheme computed var, pluginCatalogURL kept. YomiApp: #if DEBUG seedBundledPlugins, .tint + .preferredColorScheme on ContentView (Scene has no .tint — WindowGroup build failure). SettingsView: Slider 14–28, 10 swatches + custom ColorPicker sheet. TextReaderView: CSS re-inject via evaluateJavaScript on every updateUIView cycle. Regressions introduced: OnboardingView fullScreenCover removed (not in prompt scope), NovelQueries.markRead() dropped in rewrite. |
| 22 | 2026-04-07 | Restore S21 regressions: OnboardingView gate + NovelQueries.markRead(). PrivacyInfo.xcprivacy (NSPrivacyAccessedAPICategoryUserDefaults, reason CA92.1). Reading resume in ChapterReaderView (Task.detached DB read after loadPages, MainActor.run to set currentPage). Pan when zoomed in MangaPageView (GeometryReader, DragGesture with clamping, guard scale > 1.0). Browse pagination in SourceBrowseView (currentPage/isLoadingMore/hasMoreContent, "Load more" button, both Format A and B). Workflow change: Claude Code-first, no relay. MCP setup: XcodeBuildMCP, context7, apple-docs, github, mobile-mcp. CLAUDE.md created at project root. Memory system initialized. |
| 23 | 2026-04-07 | Fix dark mode + accent color: AppSettings converted from computed vars to stored properties with didSet — @Observable graph now tracks all 11 settings. Plugin UX overhaul: LibraryView empty state branches on installed.isEmpty → "No plugins" + Get plugins → More tab. PluginsView installed section shows title+description. Catalog distinguishes search-no-results from truly-empty. LTR reading mode: .horizontalLTR added to ReaderMode enum, MangaReaderView gains isRTL param. Unread badge: MangaCoverCell loads unread count via .task, shows accent Capsule overlay. ContinueReading direct navigation: tapping cell loads chapters via JSBridge+Task.detached, merges DB progress, finds last-read by readAt, navigates directly to ChapterReaderView. Bulk download: "Download next N" button (max 10) in Chapters header. Storage size: FileManager enumerates Downloads/{mangaId}/, ByteCountFormatter, shown in header. Page-jump slider: ReaderOverlayView bottom bar, currentPage promoted to @Binding, Slider hidden in Webtoon mode. Bonus fix: accent swatch HStack → ScrollView(.horizontal), swatch 28→32pt. All 8 items committed + pushed. Items 9-13 deferred to S24. |
| 24 | 2026-04-07 | Library sort: SortOrder enum + Menu button in LibraryView toolbar. Webtoon scroll persistence: WebtoonReaderView gains @Binding currentPage, ScrollViewReader + .scrollPosition(id:anchor:.top), scrollTo on appear. Novel read semantics: WKUserScript fires readComplete JS message at 90% scroll, Coordinator WKScriptMessageHandler calls markRead. MAL → Keychain: KeychainHelper with SecItem* wrappers, MALService migrated, auto-migrates UserDefaults on first load. Downloads cleanup: toggleLibrary deletes Downloads/{mangaId}/ when removing from library. Discuss button: JSBridge.getDiscussionURL, bubble icon in ReaderOverlayView, DiscussWebSheet WKWebView bottom sheet. Paperback shim: require('paperback-extensions-common') in JSBridge cache (Source base class + App constructors + RequestManager wrapping SOURCE._fetchSync), injectPaperbackAdapter post-eval detects Source subclass in exports, wires getMangaList/searchManga/getChapterList/getPageList. Chapter paths encode mangaId|chapterId. All 7 items shipped. App icon + privacy policy deferred to S25. |
| 25 | 2026-04-08 | Extension catalog inline in Browse tab (Extensions sub-tab, YomiCatalogEntryRow reused from PluginsView, NSFW filtered by AppSettings). AppRouter.openBrowseExtensions flag: "Get plugins" in Library deep-links to Browse → Extensions directly. EXTENSIONS.md guide in repo root with step-by-step install instructions + copy-paste URLs for all 7 sources. Firebase index.json populated (7 entries) + privacy.html deployed at yomi-plugins.web.app/privacy. Reading status: ReadingStatus enum (none/planToRead/reading/onHold/completed/dropped) added to Manga model + DB migration v7_reading_status + MangaQueries.updateReadingStatus + ReadingStatusMenu pill in MangaDetailView header. Unread count sort: SortOrder.unreadCount + ChapterQueries.fetchUnreadCountsByManga (single GROUP BY SQL, no N+1) + LibraryViewModel.unreadCounts dict loaded at library load. Multi-select long-press: MangaCoverCell gains isSelecting/isSelected/onLongPress/onSelect params, long press → selection mode, checkmark+ring overlays, NavigationLink disabled while selecting. LibraryView: isSelecting + selectedIds state, Cancel+SelectAll toolbar in selection mode, bottom action bar with bulk Remove from Library (Task.detached remove + download cleanup), ContinueReadingRow hidden during selection. PluginCatalogService: guard !isLoading at entry. SettingsView: Privacy Policy link. |

## Technical learnings — S23

### @Observable + external storage
`@Observable` macro expansion only generates `access(keyPath:)` / `withMutation(keyPath:)`
calls for **stored properties**. Computed properties backed by UserDefaults are invisible to
the observation graph — mutations write to UserDefaults but no notification fires. The fix:
store the value in a `var` with `didSet` that persists to UserDefaults. The singleton's
`private init()` reads the current UserDefaults value into each stored property.
`@ObservationIgnored` must be applied to the `defaults` ivar to prevent the macro from
trying to observe it. `colorScheme` can remain computed because it derives from `theme`
(a tracked stored property) — the observation chain propagates correctly.

### navigationDestination(isPresented:) for dynamic navigation
When the destination view requires reference-type state (like JSBridge) that doesn't conform
to Hashable, use `navigationDestination(isPresented: $flag)` with separate `@State` vars for
the data, rather than `navigationDestination(item:)` which requires Hashable. Set the data
vars first, then set the Bool flag to trigger navigation.

### Slider binding for Int page state
SwiftUI Slider works with Double. To bind it to an `@Binding<Int>`:
```swift
Slider(
    value: Binding(get: { Double(currentPage) }, set: { currentPage = Int($0.rounded()) }),
    in: 0...Double(totalPages - 1),
    step: 1
)
```
The `.rounded()` prevents off-by-one drift from floating point.

### ScrollView fixes overflow in List sections
A plain `HStack` inside a `List` cell does not clip or scroll — items overflow off-screen
silently. Wrap in `ScrollView(.horizontal, showsIndicators: false)` when the content count
is variable or guaranteed to exceed screen width (e.g., color swatch rows).

## Technical learnings — S24

### Paperback shim: Promise resolution in JavaScriptCore
Paperback plugins use async/await (compiled to generator + Promise chains by TypeScript).
These work in JSContext because: (1) SOURCE.fetch is synchronous (DispatchSemaphore), so
`await fetch()` resolves immediately; (2) JavaScriptCore drains the microtask queue before
returning from `evaluateScript` / `JSValue.call(withArguments:)`. The `_resolve(promise)`
helper in the adapter captures the synchronously-resolved value via `.then(v => result = v)`.

### Paperback chapter path encoding
Paperback's `getChapterDetails(mangaId, chapterId)` needs both IDs. Yomi's `getPageList(path)`
only receives one string. Solution: encode as `mangaId + "|" + chapterId` in `getChapterList`,
split on first `|` in `getPageList`. Safe because `|` doesn't appear in typical manga IDs.

### WKScriptMessageHandler for JS→Swift callbacks
To detect scroll-to-end in WKWebView: inject a `WKUserScript` at `.atDocumentEnd` containing
a scroll event listener that calls `window.webkit.messageHandlers.name.postMessage(...)`.
The Coordinator must conform to `WKScriptMessageHandler` and be added via
`config.userContentController.add(coordinator, name: "readComplete")` BEFORE the WKWebView is created.
The `once: true` event listener option ensures the message fires only once per chapter.

### Keychain migration pattern
When migrating from UserDefaults to Keychain: in `loadToken()`, check if the legacy UserDefaults
key exists → save to Keychain → delete from UserDefaults. This runs once on first launch after
update. Users are seamlessly migrated without needing to re-login.

### scrollPosition(id:anchor:) for scroll restoration
iOS 17+: `.scrollPosition(id: $binding, anchor: .top)` tracks the ID of the topmost visible item.
Use `onChange(of: visibleId)` to update currentPage. On appear, call `proxy.scrollTo(id, anchor: .top)`
inside a `ScrollViewReader` to restore position. The binding is `Binding<(Int)?>`  —
unwrap in onChange before assigning to `Int`.

## UX research — reading apps (S23 basis)

This section records findings from a deep research pass comparing Tachiyomi (Android), Paperback (iOS),
Aidoku (iOS), MangaPlus, Webtoon, INKR, Azuki, Moon+ Reader, ReadEra, and Shosetsu.
Sources: App Store reviews, Reddit (r/manga, r/manhwa, r/lightnovels), GitHub issue trackers.
Purpose: inform S23 priorities and serve as a permanent reference for product decisions.

### Library UX — what the best apps do

**Unread count badge on covers:**
Every top reader app (Tachiyomi, Paperback, Aidoku) shows a blue capsule with unread chapter count
on each cover cell. Users say "I can scan my whole library in 3 seconds." Without this, users must
open each title to know if there's new content. This is the single most-cited UX improvement request
for any library-based reading app.

**Categories as tabs vs. chips:**
Tachiyomi puts categories as tabs across the top of the screen (full navigation weight).
Yomi uses horizontal chips in a safeAreaInset — a softer, less intrusive approach. Both are valid.
Chips work better when categories are optional/additive; tabs work better when categories are primary
navigation. Yomi's chip approach is correct for its use case.

**Reading status (Reading/Completed/On Hold/Dropped/Plan to Read):**
Aidoku and all MAL/AniList-integrated apps surface reading status as a first-class field, distinct from
categories. Yomi tracks library (in/out) and connects to MAL for chapter tracking, but has no local
reading status field. Consider adding a `status: String` field to the `manga` table in a future migration.

**Multi-select long-press:**
Tachiyomi: long-press any cover → multi-select mode → bulk download, mark read, delete, categorize.
No other reader does this as well. This is a meaningful power-user feature Yomi doesn't have.
Not prioritized for S23 but worth tracking as a future feature.

**Sort options:**
Tachiyomi: Alphabetical, Last Read, Last Updated, Unread Count, Date Added.
Yomi: only Last Read DESC (hardcoded in LibraryViewModel).
S23 adds sort options. Implementation: a sort enum in LibraryViewModel, Picker in LibraryView toolbar.

### Reader UX — what the best apps do

**Reading direction:**
- RTL: manga (Japanese). Yomi has this.
- LTR: manhwa (Korean), manhua (Chinese). Yomi does NOT have this. Major gap.
- Webtoon scroll: Yomi has this.
- Double-page spread: Tachiyomi supports side-by-side pages for wide displays. Complex, not S23.

**Tap zones:**
Left 1/3 → prev page, Right 1/3 → next page, Center → toggle overlay.
Tachiyomi, Paperback, Aidoku all use this exact model. Yomi uses it for overlay toggle but RTL swipe
handles prev/next. This is fine — the TabView swipe is more natural than tap-to-turn.

**Page-jump slider:**
All top apps have a bottom slider that scrubs through pages (e.g., "47 / 200").
Yomi shows "Page X / Y" text but no slider. Add a `Slider` bound to `currentPage` in `ReaderOverlayView`.

**Background color options:**
Tachiyomi: White, Gray, Black presets for the reader background.
Yomi: hardcoded `Color.black`. The reader should offer at minimum White and Black. Black is correct for
AMOLED (most manga phones), White is needed for older scans with white borders.

**Volume button page-turn:**
Optional feature, beloved by power users. Requires UIApplication key event interception.
Not in S23 but worth noting — Tachiyomi and Paperback both support it.

**Webtoon scroll position:**
Every webtoon reader (Naver, LINE, Tachiyomi) saves scroll position. Yomi's webtoon mode always
restarts from the top. Fix: `ScrollViewReader` + `scrollTo` on appear using saved `chapter.progress`
converted to a page anchor index.

### Download UX — what users say

Across 100+ Reddit threads and GitHub issue trackers, the consistent pattern:

1. **Bulk download is #1.** "Why can't I download all unread at once?" appears verbatim in Paperback,
   Tachiyomi, Aidoku issue trackers. All three have it tracked as a major feature request.
   Implementation for Yomi: "Download next N unread" button → filter chapters for !isDownloaded && !isRead →
   enqueue in DownloadManager.

2. **Storage size is #2.** Users don't know how much space downloads are consuming. Show `FileManager`
   directory size in `MangaDetailView` header or `DownloadsView`. One utility function.

3. **Download while backgrounded is #3.** Background `URLSession` (`.background(withIdentifier:)`) lets
   downloads continue when app is suspended. Significant architectural change. Not S23 but worth tracking.

4. **Download discoverability.** Yomi's per-chapter download is a swipe action — users miss it.
   Adding an explicit download button (or a long-press context menu) to chapter rows would help.

### Comment sections — research conclusion and design decision

**Decision: no native comments in Yomi.** Reasoning:
- Apple requires moderation infrastructure for UGC → complex, ongoing operational burden
- Privacy policy must be updated → legal work
- Age gating required for NSFW content (Yomi supports NSFW plugins)
- Tachiyomi tested a community tab and removed it for these exact reasons
- Paperback has had a comments feature request open for 3+ years, never shipped

**Correct path: "Discuss" button → WKWebView bottom sheet.**
Button appears in reader overlay only when the active plugin declares `getDiscussionURL(chapterPath)`.
Opens the source's own comment section in a contained WebView. Zero moderation burden.
Future extension: Disqus API for read-only native comments on Disqus-powered sites.

### Plugin ecosystem — definitive research findings

**What's possible and what isn't:**

| Ecosystem | Format | iOS compatible? | Path |
|-----------|--------|-----------------|------|
| Keiyoushi/Tachiyomi | Kotlin APK | ❌ Never | Use as source directory only |
| Aidoku | Swift → WASM | ❌ Requires WasmSwift | Not worth pursuing |
| Paperback | TypeScript → esbuild JS | ✅ With JSBridge shim | Highest-leverage unlock, ~100 sources |
| LNReader | TypeScript → CommonJS JS | ✅ Already works (Format B) | Write more plugins |
| Own Format A | Plain JS | ✅ Native | Expand source library |

**Keiyoushi dead end explained:** Keiyoushi plugins are compiled Kotlin running inside Android APKs,
communicating with Tachiyomi forks via Android's inter-process `PackageManager` API and `HttpSource`
class reflection. No JavaScript, no WASM, no path to iOS. The correct mental model: Keiyoushi is
a *catalog of what sites exist*, not code Yomi can run.

**Paperback shim opportunity:** Paperback extensions are TypeScript bundled to a single IIFE `.js` file.
They export a `Source` class with methods nearly identical to Yomi's Format A. A JSBridge preamble
injecting a `Source` base class + post-eval `sources` object detection would enable running them
directly. This is the single highest-leverage plugin ecosystem unlock available to Yomi.

**LNReader sources available today:** LightNovelPub, WuxiaWorld, FreeWebNovel, NovelBin, ReadLightNovel,
Webnovel (may need extra headers). These can be written as TypeScript plugins using the existing
`scripts/build-plugins.mjs` pipeline and deployed to Firebase. No JSBridge changes needed.

### App icon research

- Mascot characters build brand recall. Tachiyomi's octopus is cited by name in App Store reviews.
- Warm gradients (coral, amber, teal) outperform flat blue in App Store search grid.
- "Yomi" (読み) = reading in Japanese. Also references Yomi-no-kuni (Japanese underworld mythology).
- Kitsune (fox) mascot: culturally layered (Japanese folklore), soft, friendly, distinct from existing
  reader app icons (octopus, book, P).
- Minimum viable: 1024×1024 PNG, no alpha, coral-to-amber gradient, 読 kanji centered.

## S22 — Technical learnings

- **PBXFileSystemSynchronizedRootGroup eliminates manual Xcode target membership**: Yomi uses this Xcode feature, which means any file dropped into the `Yomi/` directory is automatically included in the target. No "Add Files to Yomi" step needed. Confirmed by checking `project.pbxproj` for the `isa = PBXFileSystemSynchronizedRootGroup` entry. Applies to `PrivacyInfo.xcprivacy` and any new `.swift` or resource file. Never perform the manual Xcode add step without first verifying this setting.

- **SourceKit false positives are always noise — xcodebuild is the signal**: swift-lsp (the LSP plugin) analyzes each file in isolation without the full Xcode module context. It will always report "Cannot find type 'Manga' in scope", "Cannot find 'AppSettings' in scope", etc. These are structurally unavoidable and carry zero diagnostic value for this project. The only reliable error source is `xcodebuild`. Rule: ignore SourceKit errors entirely; act only on xcodebuild errors.

- **Chapter.progress is Double, not Double? — check model types before writing conditionals**: the `Chapter` model has `progress: Double` (non-optional). Writing `if let progress = saved.progress` fails to compile. Before writing any conditional binding in a fix, read the model definition to confirm optionality. The correct pattern here: `if saved.progress > 0 { let progress = saved.progress }`.

- **Simulator device names change across Xcode versions**: "iPhone 16 Pro" does not exist in Xcode 26.3.1. Available iPhone simulators: iPhone 16e, iPhone 17, iPhone 17 Pro, iPhone 17 Pro Max, iPhone Air. Always check with `xcrun simctl list devices available | grep iPhone` before hardcoding a destination. Update CLAUDE.md and ARQUITECTURA.md when simulator names change.

- **PrivacyInfo.xcprivacy reason code for UserDefaults: CA92.1**: Apple requires a specific reason code when accessing UserDefaults. The correct reason for a settings/preferences use case is `CA92.1` ("Access from the app itself"). Do not use `C617.1` (which is for user-triggered actions) or leave the reasons array empty — App Store validation checks the reason code, not just the presence of the file.

- **MCP --scope user flag placement**: `claude mcp add --scope user NAME -- COMMAND` is correct. `claude mcp add NAME -- COMMAND --scope user` is wrong — the flag after `--` is passed to the subprocess, not to `claude mcp add`. This caused XcodeBuildMCP and mobile-mcp to register incorrectly on first install.

- **Never share credentials in conversation**: a GitHub PAT was accidentally pasted into the conversation during MCP setup. Revoke and regenerate immediately when this happens. Use `YOUR_TOKEN_HERE` as a placeholder in all command examples in docs.

- **Claude Code-first workflow is strictly better than the relay for this project**: the relay (Claude.ai generates prompts → user copy-pastes → Claude Code executes) was necessary when Claude.ai was the only context-holder. With CLAUDE.md + memory + XcodeBuildMCP, Claude Code has everything it needs to plan and implement independently. The relay added latency, introduced stale-context bugs (S9, S14, S21 regressions), and degraded the user experience. The correct model: Claude.ai for strategic session review, Claude Code for everything inside a session.

- **Reading progress restore: Task.detached for DB read, MainActor.run for state**: after `loadPages()` sets `pages`, reading `chapter.progress` from DB must happen in `Task.detached` (ChapterQueries is nonisolated but DB access should not block MainActor). The page index is `Int(progress * Double(pageCount - 1))`. Setting `currentPage` requires `await MainActor.run { ... }`. Always verify both write path (updateProgress on disappear) and read path (fetchOne on load) when implementing progress features.

- **Pan-when-zoomed requires GeometryReader for clamping dimensions**: `.scaleEffect` scales around the view center but doesn't move the image. Adding pan requires knowing the view's actual rendered size, which means wrapping in `GeometryReader`. Clamping formula: `maxOffset = (scale - 1) * dimension / 2` for both axes. The DragGesture must guard `scale > 1.0` to avoid intercepting the TabView's page swipe gesture at scale == 1.0.

- **Browse pagination: empty page = no more content**: there is no `total` field to compare against in Format A or Format B. The correct signal for "no more pages" is an empty result from the next page fetch. When the source returns 0 items, set `hasMoreContent = false` and hide the button. This works for all 7 current plugins.

## S21 — Technical learnings

- **WindowGroup / Scene has no `.tint()` modifier**: `.tint()` is a `View` modifier. Applying it to `WindowGroup` fails to compile: "value of type 'WindowGroup<some View>' has no member 'tint'". Both `.preferredColorScheme()` and `.tint()` must be applied to `ContentView()` inside `WindowGroup`, not to the `WindowGroup` or `Scene` itself.

- **`updateUIView` fires on every SwiftUI re-render — guard if expensive**: `UIViewRepresentable.updateUIView` is called whenever the parent view re-evaluates, not only when binding values change. The old `Coordinator.lastHTML` guard that prevented redundant `loadHTMLString` calls was removed in S21. The replacement `evaluateJavaScript` is cheap enough that always-firing is acceptable, but for expensive operations (full page reload, heavy computation) always implement a diffing guard.

- **`#if DEBUG` is the correct gate for dev-only code in `@main App`**: placing `#if DEBUG ExtensionManager.shared.seedBundledPlugins() #endif` in `YomiApp.init()` ensures the release archive is clean. Swift strips `#if DEBUG` blocks in Release configuration by default — no additional build setting needed. This is the correct pattern for any code that must exist in simulator/debug but must never ship.

- **`Color.hexString` via UIColor: sRGB only, P3 values are quantized**: `UIColor.getRed(_:green:blue:alpha:)` returns sRGB components. If the user picks a wide-color P3 color from the system ColorPicker, `hexString` will quantize it to the nearest sRGB value. In practice this is invisible at `#RRGGBB` precision, but the stored hex will differ slightly from the original P3 color.

- **Partial file rewrites silently drop existing logic**: two regressions in S21 (OnboardingView gate, `NovelQueries.markRead()`) happened because the prompt provided a complete replacement file that did not include those pieces. Rule: when replacing an entire file, always read the current file first and explicitly check for logic the new file does not include. Any omission from a replacement file is a silent deletion.

## S20 — Technical learnings

- **@Observable singletons on App structs require @State to drive WindowGroup re-evaluation**: a plain `AppSettings.shared.colorScheme` call in `WindowGroup.body` does NOT register SwiftUI observation — tracking only fires on `@State`-held references. Fix: `@State private var settings = AppSettings.shared` in `YomiApp`. Then `settings.colorScheme` and `settings.accentColor` in the body trigger re-evaluation on every change. Without this, `.preferredColorScheme` and `.tint` are set once at launch and never update.

- **.task {} vs .onAppear {} for tab-triggered fetches**: `.task {}` fires once, when a view first enters the hierarchy. `.onAppear {}` fires on every appearance, including programmatic tab navigation (`appRouter.selectedTab = tabMore`). For PluginsView, `.task` silently failed after onboarding navigated to More (view already mounted). Rule: use `.onAppear { Task { ... } }` for any fetch that must re-fire when the user navigates back to a tab.

- **Three-file prompts are justified for interconnected state**: the accentColor feature required coordinated changes in AppSettings (new property), SettingsView (picker UI), and YomiApp (wiring .tint). Running these as separate prompts would leave the app in a broken intermediate state. When a feature's backing storage, UI, and root wiring all live in different files and must be consistent, a single prompt touching all three is correct — not a violation of the one-file rule.

- **.tint() across .fullScreenCover boundaries needs runtime verification**: `.tint(Color(hex: settings.accentColor))` applied to `ContentView()` inside `WindowGroup` may not propagate into `OnboardingView` (presented via `.fullScreenCover`, which creates a new presentation context). If broken at runtime: add `.tint(Color(hex: AppSettings.shared.accentColor))` directly inside `OnboardingView`.

## S19 — Technical learnings

- **preferredColorScheme(nil) does not force system appearance in simulator**: passing `nil` tells SwiftUI to follow the system preference, but this may not apply in the simulator as expected. Before writing any fix, read `YomiApp.swift` to confirm the modifier placement. To diagnose, pass explicit `.dark` or `.light` first — only switch to nil once explicit values are confirmed working.

- **AppSettings reader values and local @State must not coexist as dual sources of truth**: `TextReaderView` has a local `@State private var fontSize: Double` that drives the slider but is disconnected from `AppSettings.novelFontSize`. Font changes don't persist and settings from `SettingsView` have no effect. Fix: remove local `@State fontSize`, use `AppSettings.shared.novelFontSize` as the single source. Re-inject CSS via `webView.evaluateJavaScript` on `.onChange(of: AppSettings.shared.novelFontSize)`.

- **OnboardingView pattern — fullScreenCover + hasSeenOnboarding**: gate with `@State private var showOnboarding = !AppSettings.shared.hasSeenOnboarding` in `YomiApp`. Use `.fullScreenCover(isPresented: $showOnboarding)`. Last page: `AppSettings.shared.hasSeenOnboarding = true` then `dismiss()`. Persists across launches via UserDefaults.

- **seedBundledPlugins call removed from YomiApp**: removed from `YomiApp.init()` for App Store compliance. Method kept in `ExtensionManager` for dev use. `.js` files removed from Xcode target membership (not from disk) — they no longer ship in the binary.

- **Never write a fix for a UIViewRepresentable without reading the current file first**: `ReaderWebView` has a `Coordinator.lastHTML` guard in `updateUIView`. Any re-inject change must account for it — writing blind risks duplicating the guard or breaking the reload path entirely.

- **PluginsView .task{} catalog fetch may not fire when tab is activated programmatically**: when `appRouter.selectedTab = tabMore` is called during onboarding, `PluginsView` may already be in the hierarchy and its `.task {}` won't re-fire. Add explicit `errorMessage` state + retry button before assuming network is the cause of an empty Browse tab.

- **Immersive tap layer in ZStack**: add `Color.clear.contentShape(Rectangle()).onTapGesture { ... }` after the background color, before reader content. Tap target for full screen without blocking scroll/pinch above. Placing it on top intercepts scroll events.

## Pre-S19 Audit — Research findings

### App Store compliance (confirmed)
- Paperback and Aidoku are on the App Store using the identical extension model
- The legal line: app binary must ship with ZERO piracy-adjacent plugin files
- Users install plugins themselves = user action, not developer action
- Bundled .js files in Yomi/Resources/ must be removed before App Store submission
- seedBundledPlugins in YomiApp.swift must be removed with them
- Onboarding replaces bundled plugins: first-launch screen → Browse catalog → install

### Dark mode — correct SwiftUI pattern
- `.preferredColorScheme()` must be applied in YomiApp.swift on ContentView inside WindowGroup, NOT on a child NavigationStack or individual views
- AppSettings.theme stores "system"/"light"/"dark" as String
- Computed var `colorScheme: ColorScheme?` — nil for system, .light or .dark otherwise
- Pattern: `ContentView().preferredColorScheme(appSettings.colorScheme)`

### Immersive reader — correct pattern
- `@State var showChrome = true` toggled by TapGesture on scroll content
- All chrome (nav, tab bar, controls) uses: `.opacity(showChrome ? 1 : 0).animation(.easeInOut(duration: 0.2), value: showChrome)`
- System status bar: `.statusBarHidden(!showChrome)` on the root reader view
- Tab bar: `.toolbar(showChrome ? .visible : .hidden, for: .tabBar)`
- Never use `.hidden` directly — always opacity+animation for smooth transition

### TextReaderView font size fix
- WKWebView renders HTML once — changing AppSettings.novelFontSize after load has no effect
- Fix: call `webView.evaluateJavaScript("document.body.style.fontSize = '\(size)px'")` on every font size change
- Better fix: observe AppSettings changes via `.onChange(of:)` and re-inject the full CSS string
- Line height should be 1.6× (not 1.5×) per research — more comfortable for long-form reading

### Novel reader optimal settings (research-confirmed)
- Font size default: 18pt, range 14–28pt
- Line height: 1.6× font size
- Dark text color: #E8E8E8 (not white — reduces glare)
- Dark background: #1C1C1E (not pure black — easier on eyes)
- Sepia text: #2C1810 on #FFF8F0 background
- Light mode: #1C1C1E on white
- Contrast ratios meet WCAG 4.5:1 in all three modes
- Font: SF Pro (system) for default; Georgia acceptable for sepia mode

## S18 — Technical learnings

- **require() shim in JSBridge**: inject before plugin eval via `injectRequireShim(into:)`. Cache modules in `__moduleCache`. Route `cheerio` to global, `he` inline (named + numeric + hex entity decode/encode), `node-fetch`/`node-fetch/src/index.js` to `SOURCE._fetchSync`, `axios` get/post to `SOURCE._fetchSync`. Unknown modules return empty `{}` — never crash. Always inject `module`, `exports`, `process` globals. This enables LNReader v2.x plugins to run in JavaScriptCore without an esbuild compilation step.

- **PluginCatalogService pattern**: `@Observable` singleton that owns remote catalog state (`entries`, `isLoading`, `errorMessage`). `fetchCatalog()` is a plain `async func` — call from `.task {}` in the View. Never call from `init()`. `isInstalled()` cross-references `ExtensionManager.shared.installed` by name.

- **Firebase Hosting as plugin CDN**: project yomi-plugins, live at https://yomi-plugins.web.app. `index.json` + `.js` files in `~/Desktop/yomi-firebase/public/`. Deploy: `cd ~/Desktop/yomi-firebase && firebase deploy --only hosting`. Firebase folder lives outside the Xcode repo (`~/Desktop/yomi-firebase`) — not committed to git.

- **esbuild IIFE for JSContext**: `format: 'iife'`, `bundle: true`, `platform: 'browser'`, `target: 'es6'`. Output is a self-contained JS file with no `import`/`require` statements — directly evaluatable by `JSContext.evaluateScript()`.

## S17 — Technical learnings

- **api.asurascans.com requires Origin + Referer headers**: Cloudflare blocks requests without these headers. Every `SOURCE.fetch` call in asurascans.js must include `{ headers: { "Origin": "https://asurascans.com", "Referer": "https://asurascans.com/" } }`. Without them, the API returns 403 or an empty response.

- **asurascans chapterPath format**: `"{seriesSlug}/{chapterSlug}"` — split on first `/` to get both components. `getChapterList` builds it as `mangaPath + "/" + ch.slug`. `getPageList` splits it to call `/api/series/{seriesSlug}/chapters/{chapterSlug}`. Pages are in `json.data.chapter.pages[].url`.

- **asurascans getMangaList endpoint**: `GET /api/search?page={page}&order=popular` (not `/api/series`). Chapter list pagination via `GET /api/series/{slug}/chapters?limit=100&page={page}`, loop while `json.meta.has_more === true`.

- **DateComponents is Hashable in Foundation**: `Set<DateComponents>` works without any custom conformance. Used in InsightsView streak logic to collect distinct calendar days where reading occurred. No need for a custom wrapper type.

- **Streak logic — check yesterday if today is empty**: streak should not reset if the user hasn't read yet today but read yesterday. Pattern: count consecutive days starting from today; if streak == 0, restart count from yesterday. This preserves the streak through the morning before the user opens the app.

## S16 — Technical learnings

- **seedBundledPlugins skip logic is a deployment trap**: the `fileExists` check that skips copying bundled JS files means simulator never picks up JS fixes after the first install. Rule: bundled plugins must always be overwritten on launch (`removeItem` then `copyItem`). Safe because bundled plugins are read-only source-of-truth — only network-installed plugins should be preserved.

- **cheerio shim each() contract**: the Yomi cheerio shim passes `(index, wrappedCheerioObject)` to `.each()` callbacks — NOT `(index, rawDOMElement)` as real cheerio does. Plugin code must use `el.find()`, `el.attr()`, `el.text()` directly. Never do `$(el)` inside an `.each()` callback — `$(wrappedObject)` fails silently and returns empty results.

- **Debug prints are the fastest path to root cause**: when a plugin returns empty and the cause is unknown, add `print("🔍 ...")` to JSBridge before `parseMangaArray`/`parseNovelItems` to see the raw JS return value. This immediately distinguishes between: network failure (empty string), selector mismatch (JS array length 0), or type mismatch (JSValue not convertible to array).

- **GitHub repo ≠ simulator disk**: Claude Code writes to disk but changes only reach the simulator after a build. The simulator runs files from the app bundle (built from disk), not from the git repo. Always push after a fix session — GitHub is the source of truth, not the simulator cache.

- **Verify fixes in repo before diagnosing simulator**: after CC commits, confirm the actual file content via `curl https://raw.githubusercontent.com/PacoDealer/Yomi/main/...` before assuming the simulator is running the fixed code. Divergence between repo and disk is a common source of confusion.

- **Claude.ai can read the GitHub repo directly**: use `curl https://raw.githubusercontent.com/PacoDealer/Yomi/main/{path}` to read any file without asking CC. This eliminates a full round-trip prompt for diagnostic reads and speeds up root cause analysis significantly.

- **Workflow improvement — diagnose before prescribing**: when plugins return empty, the correct flow is: (1) read the actual file from GitHub, (2) read the shim implementation from GitHub, (3) identify the exact failure point, (4) write one targeted fix prompt. Do not write fix prompts based on assumptions — the each() bug was correctly identified only after reading the actual shim code.

## Technical learnings
- **PrivacyInfo.xcprivacy is required for all iOS 17+ App Store submissions**: Apple rejects builds that access privacy-sensitive APIs without a `PrivacyInfo.xcprivacy` file. Yomi uses `UserDefaults` (NSPrivacyAccessedAPICategoryUserDefaults) for AppSettings and MAL token — both must be declared. Create the file at `Yomi/PrivacyInfo.xcprivacy` (XML plist format). Without it, App Store Connect will reject the upload automatically. This cannot be patched post-submission.

- **Reading progress saved but never restored — always verify the full round-trip**: `ChapterQueries.updateProgress(id:progress:readingSeconds:)` is called on disappear and stores progress as a 0.0–1.0 Double. But `ChapterReaderView` initializes `currentPage = 0` and `loadPages()` never reads the stored progress back. The data exists in the DB unused. When implementing progress features, always verify both the write path AND the read path before closing the session.

- **SourceBrowseView only shows page 1 — pagination must be explicit**: `getMangaList(page:)` is designed for pagination but `SourceBrowseView.loadContent()` calls it with `page: 1` and never calls it again. There is no "load more" trigger. This is a silent limitation — the app appears to work but users see ~20 titles on MangaDex instead of thousands. Never assume pagination works without testing with a source that has more than one page of results.

- **MangaPageView zoom without pan is broken UX**: `.scaleEffect` scales around the view center but doesn't move the image. At 4x zoom, all four corners of the image are inaccessible. The fix requires `@State var offset: CGSize` + `DragGesture` with clamping. The clamping logic: `max offset.x = (scale - 1) * viewWidth / 2`, same for y. Reset offset to `.zero` when scale returns to 1.0.

- **Novel chapter read semantics — mark on finish, not on open**: `TextReaderView.loadContent()` calls `NovelQueries.markRead()` immediately after the HTML string is received. A chapter is "read" the instant it opens. The correct trigger is scroll-to-bottom, detectable via WKWebView's `scrollView.contentOffset.y + scrollView.frame.height >= scrollView.contentSize.height`. Use a WKNavigationDelegate or JS injection to detect this.

- **@Bindable for @Observable singletons in views**: to create a SwiftUI binding to a property on an `@Observable` singleton (e.g. `AppSettings.shared`), you cannot use `$AppSettings.shared.someProperty` directly. You must first declare `@Bindable var settings = AppSettings.shared` inside the view (or receive it as a parameter), then bind via `$settings.someProperty`. Without `@Bindable`, the `$` prefix won't compile on a non-`@State` reference.
- **JSBridge is per-extension, not a singleton**: never share a JSBridge instance between extensions or between concurrent tasks. Each JSBridge owns a JSContext that evaluates one script. The correct pattern is `JSBridge(scriptURL: localURL)` fresh for each plugin call site. Sharing instances causes state bleed between plugins.
- **SwiftUI view identity: mutate @State instead of replacing the view for in-reader navigation**: ChapterReaderView uses `currentChapterIndex: @State Int` + computed `activeChapter` to navigate between chapters without SwiftUI creating a new view instance. If the view were replaced (e.g. via NavigationLink push/pop), all `@State` (pages, isLoading, timer) would reset. Mutating existing @State preserves the view lifecycle and avoids redundant loads.
- **Context window auto-summary can describe planned work as completed**: when Claude Code's context compresses mid-session, the summary may present outcomes that were planned (or partially executed) as fully done. At the start of any resumed session, always read the actual file state — do not trust the summary's description of completed work.
- **xcode-select pointing to CommandLineTools**: if `xcodebuild` fails with "xcode-select: error: tool 'xcodebuild' requires Xcode" or similar, prefix all build commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Check with `xcode-select -p`. Fix permanently via `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
- **Simulator device name changes across Xcode versions**: "iPhone 16 Pro" may not exist in a newer Xcode's simulator list. Always check available names with `xcrun simctl list devices available | grep iPhone` before hardcoding a destination in build commands. Use the newest available Pro model.
- **iOS 26 TabView**: new API `Tab("title", systemImage:) {}` — old `.tabItem {}` renders nothing
- **Xcode PBXFileSystemSynchronizedRootGroup**: all files in the folder are included automatically — never use `.gitkeep` or `.gitignore` inside the target
- **Swift 6 + GRDB**: `init(row:)` and `encode(to:)` from FetchableRecord/PersistableRecord require `nonisolated` with `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`
- **DerivedData stale**: clean with `rm -rf ~/Library/Developer/Xcode/DerivedData/Yomi-*` and ⇧⌘K in Xcode
- **JSBridge async**: JSContext is synchronous; SOURCE.fetch blocks with DispatchSemaphore; always call from Task.detached, never from MainActor
- **Keiyoushi plugins**: they are Android .apk, do not run on iOS; replaced in S18 by a real Yomi-native catalog on Firebase Hosting
- **LNReader plugins**: TypeScript compiled to JS — compatible with JavaScriptCore if correct shims are implemented (fetch, cheerio, storage, require)
- **Cheerio shim**: full recursive HTML parser + CSS selector engine implemented in pure JS; functional since S6. Not a stub.
- **db.write unused result**: GRDB db.write returns the closure value — use `_ = try appDatabase.write { ... }` to silence the "Result of call to 'write' is unused" warning
- **GRDB bulk column update**: use `Model.filter(Column("id") == id).updateAll(db, [Column("field").set(to: value)])` instead of fetch-mutate-save for partial updates
- **SHA256 stable IDs**: `CryptoKit.SHA256.hash(data: Data(url.utf8)).compactMap { String(format: "%02x", $0) }.joined().prefix(32).lowercased()` — generates reproducible 32-char IDs from a URL
- **MangaDex pagination**: use limit=100 with offset loop; cap at 2000 to avoid infinite loops on series with many chapters
- **@Observable + UserDefaults**: use `@ObservationIgnored` on the `defaults` ivar; computed properties with get/set to UserDefaults work correctly as bindings
- **UIApplication.isIdleTimerDisabled**: always reset to `false` in `.onDisappear` — otherwise the screen stays on globally even after the user leaves the reader. Must be `true` in `.onAppear`
- **GRDB + Swift 6 strict concurrency**: expose DatabaseQueue as a `nonisolated(unsafe) var appDatabase: DatabaseQueue!` at module level. Official GRDB pattern for `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`. All `*Queries` methods access `appDatabase` directly — no actor hop
- **\*Queries enums**: all static methods must be `nonisolated` or the compiler infers MainActor isolation and blocks calls from `Task.detached`
- **Two v4_ migrations coexist**: GRDB tracks migrations by string name, not numeric prefix. `v4_reading_insights` and `v4_reading_time` are independent and coexist without conflict. Next migration must use prefix `v6_`
- **appDatabase.read async overload**: from a `@MainActor` context (like `exportBackup()` in `BackupManager`), `appDatabase.read` resolves to the async overload. Requires `try await appDatabase.read { ... }`
- **MAL OAuth PKCE plain**: MAL does not support S256, only the `plain` method (code_challenge == code_verifier). The verifier is a random string of 43-128 chars
- **Timer in SwiftUI**: `@State private var readingTimer: Timer?` started in `.onAppear` and always invalidated in `.onDisappear` + in every navigation function before creating the next timer
- **ChapterReaderView activeChapter pattern**: use `currentChapterIndex: Int` as `@State` + `var activeChapter: Chapter { chapters[currentChapterIndex] }` as computed property, instead of storing the chapter directly — enables prev/next navigation without re-init of the view
- **Extension must be Hashable for Picker + .tag()**: iOS 26 `Picker` requires the selection type to conform to `Hashable`. `Extension` only had `Identifiable + Codable` — adding `Hashable` to the conformance list is sufficient; the compiler synthesizes it automatically because all stored properties (`String`, `URL?`, `Bool`, `[String]`) already conform
- **Text + Text deprecated in iOS 26**: the `+` operator on `Text` was removed. Old: `Text(date, style: .relative) + Text(" ago")`. New: `Text("\(Text(date, style: .relative)) ago")`. SwiftUI `Text` supports interpolating other `Text` values (including those with special formatters like `.relative`) — the live-updating behavior of `.relative` is preserved
- **simultaneousGesture for multi-tap**: double-tap + single-tap on the same view requires `.simultaneousGesture` on the double-tap gesture; without it SwiftUI routes all taps to the single-tap handler
- **Shimmer with GeometryReader + animated LinearGradient**: animate a `@State private var phase: CGFloat` from -1 to 1 with `.linear(duration:).repeatForever(autoreverses: false)`, use it as offset in `Gradient.Stop` locations — creates a horizontal sweep effect with no external dependencies
- **debounceTask pattern**: `@State private var debounceTask: Task<Void, Never>?` — cancel on each keystroke before creating a new `Task.sleep(500ms)`. Cleaner than Combine for simple debounce in SwiftUI
- **didSet in @Observable**: properties with `didSet` in `@Observable` classes work correctly for side effects (e.g.: `selectedCategoryId { didSet { updateFilteredIds() } }`)
- **INSERT OR IGNORE**: for join tables where the composite PK guarantees uniqueness, use `INSERT OR IGNORE` instead of `save()` — avoids errors if the pair already exists
- **CategoryView + MoreView in one prompt**: violated the "one file per prompt" rule because CategoryView required an entry point in MoreView. Compiled without errors, but the correct pattern is to split into two prompts. Acceptable exception only when the second change is a single-line NavigationLink
- **Category assignment pattern**: assignment sheet in DetailView loads `allCategories` + `assignedIds` in a separate `.task` via `Task.detached`; toggle calls `assign`/`unassign` individually and updates local `Set<String>` for immediate feedback without reloading the entire list from DB. Category button in toolbar: `disabled` + `opacity(0.4)` when `!manga.inLibrary` — only makes sense to assign if in library
- **Chapter pagination pattern**: `@State displayedChapterCount: Int = 50`; full array in memory; only the `.prefix(count)` slice is rendered in List. The index passed to ChapterReaderView must be the real index in the full array: `chapters.firstIndex(where: { $0.id == chapter.id })` — not the index in the visible slice, or prev/next navigation breaks
- **Updates tab / background refresh pattern**: `withTaskGroup` to refresh multiple manga in parallel from background; each task creates its own `JSBridge` (don't share instances). Compare remote IDs vs local IDs with `Set` to detect new chapters without saving all of them — only update `lastUpdatedAt` if `hasNew`. `ProgressView` in toolbar replaces button during `isRefreshing`; `guard !isRefreshing` at start of method to avoid concurrent executions
- **Dedup by URL → ID (confirmed since S8)**: `SHA256(url).prefix(32)` as plugin id guarantees the same URL never produces two different entries — dedup by id is sufficient, no need to compare `sourceListURL` separately

## S14 — Technical learnings
- **@Observable final class is automatically Sendable**: when a class conforms to `@Observable`, Swift makes it `Sendable` implicitly. Therefore `nonisolated(unsafe)` on `static let shared` of an `@Observable` singleton is unnecessary — Xcode rejects it with a "consider removing it" warning. Do not add `nonisolated(unsafe)` to `@Observable` singletons.

- **ExtensionManager.shared from Task.detached — correct pattern**: `ExtensionManager.shared` is MainActor-isolated and not accessible from `Task.detached`. The solution is to capture a local closure BEFORE entering the Task, in the MainActor context where `shared` is accessible:
```swift
  let bridgeFn: (Extension) -> JSBridge? = { ext in
      let docs = FileManager.default.urls(
          for: .documentDirectory, in: .userDomainMask)[0]
      return JSBridge(scriptURL: docs
          .appendingPathComponent("Extensions", isDirectory: true)
          .appendingPathComponent("\(ext.id).js"))
  }
  // Inside Task.detached use bridgeFn(ext) instead of
  // ExtensionManager.shared.bridge(for: ext)
```
  If the calling context is already `@MainActor` (e.g.: `loadContent()` in `SourceBrowseView`), the closure can be used directly without `Task.detached`.

- **bridge(for:) nonisolated**: the `bridge(for:)` method in `ExtensionManager` must be `nonisolated` and reconstruct the URL directly with `FileManager.default.urls(for:in:)` — it cannot access MainActor-isolated properties like `self.extensionsDirectory`.

- **Xcode breakpoint as false crash**: an active breakpoint in a frequently called function (e.g.: `MangaQueries.fetchAll`) pauses execution simulating a crash or deadlock. Before diagnosing concurrency or GRDB issues, check Xcode → Breakpoints for unexpected active breakpoints. The `Breakpoints_v2.xcbkptlist` file in xcuserdata is the source of truth — `shouldBeEnabled = "Yes"` activates the breakpoint.

- **sourceListURL stale — definitive rule**: NEVER build `JSBridge(scriptURL: ext.sourceListURL)` directly anywhere in the app. The URL stored in DB becomes stale after sandbox reinstallation. The only valid pattern is to reconstruct the path from `FileManager` + `ext.id` at runtime. This applies in BrowseView, UpdatesView, MangaDetailView, and any future point that needs to access a plugin.

- **Claude.ai generates prompt against wrong file**: without seeing the real code, Claude.ai may indicate a fix goes in `BrowseView.swift` when it's actually in `UpdatesView.swift`. Claude Code detects this when reading the file, but it costs an extra prompt. Improved protocol: at session start, paste the content of files that will be touched, not just `find` + ROADMAP.

- **JS plugins — selectors unverified in session**: plugins written during a session (royalroad, scribblehub, novelfire, comick) use CSS selectors/API endpoints inferred at the time of writing. HTML selectors change without notice. When debugging a broken plugin, first verify the root list selector (`.fiction-list-item`, `.search_main_box`, `.novel-item`, API endpoint). Each plugin has a `// Selectors verified: {date}` comment in its header.

- **ScribbleHub requires POST in SOURCE.fetch**: ScribbleHub loads the TOC via POST to `wp-admin/admin-ajax.php` with `action=wi_gettocchp`. If `JSBridge.swift` only supports GET, the TOC will be empty and `parseNovel` will return zero chapters. Before testing `scribblehub.js`, verify that `SOURCE.fetch` supports `method: "POST"` and `options.body`.

- **Firebase Hosting as plugin repo**: Firebase Hosting (free tier) hosts the Yomi plugin repository (`index.json` + `.js` files). Live at `https://yomi-plugins.web.app/index.json`. `PluginCatalogService` fetches from this URL; `PluginsView` Browse tab lists entries with real Install buttons. Implemented in S18.

- **User retention findings from S14 research**: highest ROI retention features, ordered by impact: (1) key action in first 3 minutes = 2x retention — the "Browse sources" button in LibraryView empty state goes in this direction; (2) push notifications for new chapters — request permission AFTER user saves their first manga (iOS opt-in rate 43.9%); (3) "Continue reading" row at LibraryView top — maximum friction reduction; (4) light gamification without pressure (streaks, milestones without points/badges/leaderboards); (5) optimal typography in TextReaderView: 18pt minimum, line-height 1.5x, color `#E8E8E8` in dark mode (not pure white).

## S13 — Technical learnings
- **iOS sandbox path invalidation**: absolute paths stored in GRDB become stale after reinstallation or sandbox update. Rule: never persist an absolute path and use it directly — always reconstruct the path at runtime from a reference directory (e.g.: `extensionsDirectory`) + stable ID. Applies to any `URL` in DB pointing to `Documents/`.
- **seedBundledPlugins skip logic**: base the skip on `FileManager.fileExists(atPath:)`, not on whether the ID is already in DB. The DB may have the record but the file may be missing (reinstallation). Always DB upsert even if the file already exists — guarantees metadata is in sync.
- **SOURCE.fetch User-Agent**: many scrapers block requests without User-Agent (Cloudflare, CDN). Inject realistic UA (iPhone Safari) + Accept + Accept-Language as defaults in the URLRequest of SOURCE.fetch. Plugins can override with their own headers if needed.
- **SHA256(filename) for bundled plugins**: use the JS file name (without extension) as the SHA256 id seed, not the URL. Bundled plugins have no network URL — the ID must be derivable from the name at compile time to perform idempotent upserts on every launch.
- **Bundled plugins vs network plugins**: bundled plugins are copied from `Bundle.main` to `Documents/Extensions/` on every launch (skip if already on disk). Network plugins are downloaded from URL. Both use the same `extension` table format and the same `bridge(for:)` flow.

## S12 — Technical learnings
- **cheerio `.each` callback (Yomi shim contract)**: the Yomi shim passes `(index, wrappedCheerioObject)` to `.each()` callbacks — NOT a raw DOM node. Use `el.find()`, `el.attr()`, `el.text()` directly. Never do `$(el)` inside `.each()` — `$(wrappedObject)` fails silently and returns empty results. ⚠️ This is the opposite of what real cheerio does — the shim wraps before calling the callback.
- **`attr()` helper in plugins**: must receive a cheerio object `$el`, not raw HTML. Define it as: `function attr($el, name) { return $el.attr("data-src") || $el.attr(name) || "" }`.
- **`DownloadManager.queue` does not contain the active chapter**: when `processQueue()` starts a download, it removes the item from `queue` immediately. The UI cannot depend on `queue` to show the in-progress chapter — use `activeChapter: Chapter?` exposed as a separate property.
- **In UI prompts about singletons**: specify the state of each property and its invariants before describing the UI. E.g.: "activeChapter was already removed from queue when it starts downloading — show it separately with `dm.activeChapter`".
- **async/sync signatures in prompts**: always explicitly specify whether a singleton method is `async` or not. The compiler may infer differently and generate hard-to-trace errors.
- **`ForEach` over reactive state**: before describing a `ForEach`, confirm what the collection contains in each possible state. Don't assume the active element is still in the list.
- **For new ViewModels**: explicitly list the Queries it uses in the prompt. E.g.: "`load()` uses `DownloadQueries.fetchAllDownloaded()` + `MangaQueries.fetchOne(id:)`". Prevents Claude Code from inferring incorrect names.

## S9 — Lessons learned

**Problem:** S9 prompts were generated against the S7 codebase state, not the real state. This caused ~60% of the session to rewrite work that already existed since S8.

**Root cause:** Claude.ai didn't have access to the real repo files. It planned against the system prompt (which described S7) instead of the current codebase.

**Solution — Session start protocol:**
Before asking Claude.ai for prompts, always run in Claude Code:
```
find Yomi -name "*.swift" | sort
find Yomi -name "*.js" | sort
cat Yomi/ROADMAP.md
```
Paste the complete output into Claude.ai and ask for analysis BEFORE generating prompts. Don't generate prompts until confirming the scope.
Additionally: paste the content of files that will be modified in that session. Prevents Claude.ai from generating prompts against the wrong file.

**Rule:** Claude.ai analyzes → proposes → user confirms → only then generates prompts. Never the other way around.

**Corollary:** ARQUITECTURA.md and METODOLOGIA.md in Claude.ai project knowledge are static until manually updated. If a session closes without updating them, they diverge from reality. The session start `find + ROADMAP` paste will catch new files, but architecture decisions, singleton descriptions, and learnings will be wrong. When in doubt, paste the relevant section of ARQUITECTURA.md alongside the file contents.

## Platform compatibility

**Current deployment target: iOS 26.2**

The project uses iOS 26-exclusive APIs that don't exist in earlier versions:

| API | File(s) | iOS 18 alternative |
|-----|---------|-------------------|
| `Tab("…", systemImage:) {}` | ContentView.swift | `.tabItem { Label(…) }` |
| `ContentUnavailableView` | HistoryView, BrowseView, PluginsView | Custom empty view |
| `.refreshable` | HistoryView | Manual pull-to-refresh |
| `.searchable` | BrowseView, SourceBrowseView | Custom search bar |
| `.ascNullsLast` (GRDB) | ChapterQueries | Raw SQL ORDER BY |
| `Text("\(Text(…)) …")` interpolation | HistoryView | DateFormatter or .formatted |

**Decision: do not lower the deployment target.**
Reasons:
- The app was intentionally designed for iOS 26 from session 1
- Backporting would require maintaining two code paths (`#available`) in at least 6 files
- The development iPhone can be updated to iOS 26 when available
- iOS 26 is the current shipping OS (2026)

**Rule:** if iOS 18 support is needed in the future, create a separate branch
`compat/ios18` and never mix it with main development.

## Architecture decisions
- GRDB over SwiftData: full schema control, more mature, compatible with incremental migrations
- JavaScriptCore over WKWebView: lighter, no UI required, better for headless plugins
- Own plugin format (Format A) + LNReader compatibility (Format B): maximum flexibility without depending on Android ecosystem
- Plugins installed in Documents/Extensions/ as local .js files
- MAL token in UserDefaults (not Keychain): sufficient for MVP; migrate to Keychain before App Store
