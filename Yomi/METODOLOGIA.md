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
`cd /Users/martingamberg/Desktop/Projects/Yomi/iOS` → open Claude Code.
CLAUDE.md loads automatically with full context. No pasting required.
If starting a session after a long gap: read ROADMAP.md to confirm current state.

### Session close
1. Claude Code updates all three docs (ROADMAP + METODOLOGIA + ARQUITECTURA) in one step.
   Valid exception to "one file per prompt": they are docs, not Swift code.
2. **Commit and push to GitHub.** Every session must end with a commit + `git push`.
   No exceptions — leaving uncommitted work overnight causes context loss and rollback risk.

## AI tooling setup (established S22)

### Philosophy
Claude Code is capable of reading files, planning, implementing, building, and iterating without a human relay. The workflow that uses Claude.ai to generate prompts for Claude Code to execute treats Claude Code as a dumb executor — this is suboptimal. Claude Code-first is better: Claude Code reads actual file state, generates its own implementation plan, writes code, builds, fixes errors, and commits. Claude.ai is reserved for session-level strategy.

### CLAUDE.md
Located at `/Users/martingamberg/Desktop/Projects/Yomi/iOS/CLAUDE.md`. Loaded automatically every session. Contains: tech stack, iOS 26 rules, GRDB/concurrency rules, key file paths, current session state, build command, App Store checklist. Update after every session close. This file replaces the session-start paste ritual.

### Memory system
Located at `~/.claude/projects/-Users-martingamberg/memory/`. Contains `MEMORY.md` (index) and `project_yomi.md` (project state). Persists project path, tech stack, and session state across conversations.

### MCP servers
Model Context Protocol servers extend Claude Code with external capabilities. Installed at user scope (available across all projects).

| Server | Status | Install command | What it does |
|--------|--------|----------------|--------------|
| XcodeBuildMCP | ✅ Connected | `claude mcp add --scope user XcodeBuildMCP -- npx -y xcodebuildmcp@latest mcp` | Build, simulator, LLDB, read errors |
| context7 | ✅ Connected | `claude mcp add --transport http --scope user context7 https://mcp.context7.com/mcp` | Live docs for GRDB, SwiftUI, JS libraries. Append `use context7` to prompts. |
| github | ✅ Connected | `claude mcp add --transport http --scope user github https://api.githubcopilot.com/mcp -H "Authorization: Bearer TOKEN"` | PR/issue management |
| mobile-mcp | ✅ Connected | `claude mcp add --scope user mobile-mcp -- npx -y @mobilenext/mobile-mcp@latest` | iOS Simulator UI automation |
| apple-docs | ✅ Connected | `claude mcp add --scope user apple-docs -- npx -y @kimsungwhee/apple-docs-mcp@latest` | SwiftUI + iOS 26 API from developer.apple.com |

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
| 26 | 2026-04-08 | comick.js: Referer/Origin headers + b2key image format fix. MangaDetailView: Tachimanga-style chapter selection mode (long-press → isSelectingChapters + selectedChapterIds, bottom action bar: mark read/unread/download/delete). Download sub-menu in chapter header (Next/Next 5/Next 10/All unread/All chapters). Per-chapter inline download button. Overflow ellipsis.circle menu: Edit categories, Select chapters, heart toggle. |
| 27 | 2026-04-08 | Chapter.lastPageRead + v8_last_page migration (ALTER TABLE chapter ADD COLUMN lastPageRead INTEGER DEFAULT 0). DownloadManager.completedDownloadCount Int observer. refreshChapterStates() in MangaDetailView merges DB state on appear + download complete. ChapterReaderView: saves lastPageRead on exit; resumes from saved page. ChapterRow: "Page N" subtitle + opacity 0.45 when read. Browse source filter fix: runSearch() function called from both onChange(of: searchQuery) and onChange(of: selectedSource). AppSettings.libraryColumns + keepScreenOn. SettingsView: Items per row stepper + Keep screen on toggle + Clear image cache. ChapterQueries.setRead(chapterId:isRead:) for bulk selection. |
| 28 | 2026-04-08 | Full project audit — no code shipped. Root causes documented for all 8 reported issues. Critical bug identified: chapters never INSERTed to DB, all state mutations silently affect 0 rows. S29 plan written (P0: INSERT OR IGNORE + novels in library; P1: novel reader + insights redesign; P2: popular/latest tabs + comick; P3: settings expansion). CLAUDE.md rewritten with full context. |
| 29 | 2026-04-09 | Bug blitz + UX + features. ChapterQueries.insertAllIgnoringConflicts() fixes silent-fail root cause. Chapter tap→reader, long-press→selection, auto-delete on mark-read. Auto-mark chapter read (last page OR ≥80%). Post-read UI refresh with 500ms delayed refreshChapterStates(). InsightsView full ScrollView redesign. Novel reader overlay animation fix (opacity vs if-gating). Novel reader colorScheme fix (sepia now forces .light). Popular/Latest tabs in SourceBrowseView (optional JSBridge functions, bridge reuse). Incognito mode + unread badge toggle added to AppSettings. Comick domain migrated to api.comick.dev. Code audit: fixed 2 bugs (duplicate MARK, bridge recreation). |
| 30 | 2026-04-11 | UI polish + bug fixes + reader UX. MangaDetailView header redesign (110pt cover, genre chips, resume button). MangaCoverCell: read progress bar, download icon moved to image overlay. ContinueReadingRow: progress bar + last-chapter subtitle. NovelDetailView header redesign matches MangaDetailView. HistoryView swipe-delete bug fixed (MangaQueries.clearLastRead persists removal). UpdatesView redesigned: per-chapter rows grouped under manga sections. UpdatesView refresh persists new chapters + sends notifications. TextReaderView: chapters[]+startIndex signature, prev/next chapter navigation buttons in overlay. MoreView version/build read from Bundle.main. |
| 33 | 2026-04-14 | Novel ReadingStatus parity. v11_novel_reading_status migration (ALTER TABLE novel ADD COLUMN readingStatus TEXT NOT NULL DEFAULT 'none'). Novel model + GRDB extension updated. NovelQueries.updateReadingStatus added. ReadingStatusMenu made non-private (was private to MangaDetailView). NovelDetailView: inline ReadingStatusMenu next to NovelStatusBadge when inLibrary. LibraryView status chip row guard changed to show for manga or novels. LibraryViewModel.displayedNovels now applies statusFilter. All Novel() construction sites updated with readingStatus: .none. |
| 34 | 2026-04-15 | Plugin debug + code review. freewebnovel.js: chapter selector fixed (ul#chapter-list → a.con). novelbin.js: data-novel-id regex fixed (\\d+ → [^'"]+) to capture text slugs. novelfire.js: robust summary/status fallbacks + chapters URL ?page=1 + multiple chapter selector fallbacks. Catalog: removed comick (Cloudflare 403), lightnovelworld (site dead), lightnovelpub (Cloudflare). BrowseView: selectedFeed captured before Task.detached (Swift concurrency warning fix); NovelCoverCell switched to phase-based AsyncImage for consistent grid heights; bottom padding added to LazyVGrid. UpdatesView: inserts newChapters not remoteChapters (performance fix). TextReaderView: Task.detached priority .background added for markRead. Full code review — no critical GRDB/concurrency violations found. |
| 35 | 2026-04-15 | Deep research session. RESEARCH.md created as permanent master research doc (replaces RESEARCH_S35.md). Research: Mihon iOS impossible, Paperback TS (S37), WASM (S40+), iOS 26 Liquid Glass icons, JSContext architecture correct, Apple xcrun mcpbridge available. S36–S38 plans written. Bug fixes at close: NovelFire removed from index.json (site under security attack — **restore when incident resolves**), TextReaderView error message improved. Source removal protocol added to methodology. |
| 36 | 2026-04-16 | NovelFire restored to catalog (security incident resolved) + Firebase deployed. Pure black OLED mode (AppSettings.pureBlack, ContentView tab bar, SettingsView toggle). Alternate icon infrastructure: AppSettings.alternateIconName, SettingsView picker (Default/Dark/Minimal), placeholder appiconsets — awaiting icon PNGs + Xcode CFBundleAlternateIcons step. RESEARCH.md NovelFire row corrected. Apple Developer account created — App Store unblocked. |
| 37 | 2026-04-16 | Full 44-file Swift audit + bug blitz. Fixed: (1) PluginCatalogService.fetchCatalog() was swallowing CancellationError as user-visible error "cancelled" — added `catch is CancellationError` guard. (2) SourceBrowseView novel IDs were `UUID().uuidString` (random per loadContent call) — changed to stable `"\(sourceId)_\(item.path)"`. (3) MangaDetailView.loadChapters() `guard let ext else { return }` fired without clearing isLoadingChapters (spinner stuck) + ChapterQueries.fetchAll called synchronously on MainActor — both fixed. (4) NovelFull plugin written (novelfull.net, Format B, confirmed selectors). App Store deferred (user not paying $99 yet). Firebase deploy pending (user must reauth). |
| 38a | 2026-04-18 | Tachimanga competitive research (full changelog v1.1–v4.15 + 809-string localization file from Weblate export). Multi-session feature roadmap written: S38 (9 quick-win items), S39 (reader polish + scanlators), S40 (security + migration), S41 (Yomi exclusives). XcodeBuildMCP session_set_defaults added to .claude/settings.local.json allow list. ROADMAP + METODOLOGIA updated with research and plan. |
| 39 | 2026-04-19 | S39 reader polish + scanlators + custom covers. v12_ migration (chapter.scanlator), v13_ migration (manga.customCoverPath). JSBridge Format A shim passes group/scanlator. MangaDetailView: scanlator chip filter row, custom cover PhotosPicker (Documents/Covers/{id}.jpg), ellipsis "Change cover" menu. MangaCoverCell: customCoverPath display. ChapterReaderView: tapZoneOverlay computed @ViewBuilder (default/sides/disabled layouts), webtoon horizontal padding from AppSettings. WebtoonReaderView: auto-scroll speed from AppSettings.autoScrollSpeed. SettingsView: tap zones picker, auto-scroll speed stepper, webtoon margins picker. AppSettings: 3 new stored properties. Build succeeded. Committed dc74e21 + pushed.
| 38b | 2026-04-19 | S38 UX feature blitz — all 9 items implemented and shipped. AppSettings: 7 new stored properties (autoWebtoonFromTags, deleteDownloadAfterReading, concurrentDownloads, skipUpdateWithUnread, skipUpdateNotStarted, skipUpdateCompleted, excludedCategoryIds). ChapterReaderView: auto-webtoon init, deleteAfterReading gate (capture before Task.detached — Swift 6 fix), hold-to-scroll in WebtoonReaderView via .task(id:) async loop + LongPressGesture. DownloadManager: concurrentDownloads setting replaces hardcoded 3. UpdatesView: 3 early-return skip conditions + category exclusion check. LibraryView: shuffle toolbar button + navigationDestination(isPresented:) for random manga (Manga is not Hashable — can't use item: variant). MangaDetailView: .textSelection(.enabled) on synopsis + ChapterSortOption enum (.chapterNumber/.name) + sort menu replacing simple button. NovelDetailView: .textSelection(.enabled) on synopsis. SettingsView: Downloads section (delete toggle + concurrent stepper), Updates section (3 skip toggles + ExcludedCategoriesView NavigationLink). ExcludedCategoriesView added as private struct in SettingsView.swift. Build succeeded on first attempt after two targeted fixes: MangaStatus.completed (enum not String), Manga Hashable issue. |
| Audit | 2026-04-19 | Full post-S39 codebase audit. No features added. Bugs found and fixed: (1) ChapterQueries.swift — removed dead `fetchByManga(mangaId:)` duplicate of `fetchAll(mangaId:)`. (2) NovelQueries.addReadingTime — fixed read-modify-write race condition; rewritten as single atomic `appDatabase.write` using `updateAll` SQL on both novel_chapter and novel tables. (3) BackupManager — S39 fields `customCoverPath` (Manga) and `scanlator` (Chapter) were missing from encode/decode; backup exports would silently drop these fields; fixed in encodeManga/decodeManga/encodeChapter/decodeChapter. (4) NotificationManager — `identifier = "yomi.update.\(mangaTitle.hashValue)"` used Swift's non-deterministic hashValue (seed randomized per launch); fixed to safeTitle string prefix(60). (5) ExtensionManager — stray `#imageLiteral(resourceName:)` in doc comment removed; dead plugins comick and lightnovelworld removed from seedBundledPlugins list. Docs updated: ARQUITECTURA.md (migrations v12_/v13_, "next v14_", AppSettings full 34-property list, PrivacyInfo ✅ done, Paperback implemented S24, Firebase plugin list, folder structure comments). RESEARCH.md (added Mangayomi competitor, bato.to permanently closed, OLED status ✅ S36, NovelFire ✅ restored S36, Section 7 table corrected, Section 11 updated to current state). |
| 83 | 2026-08-04 | Design implementation Blocks 3-5 of 12 — **PENDING USER REVIEW, do not treat as final.** Backfills Blocks 1-2 (shipped 2026-08-03 under S82 commits `bded9e6`/`48705b1`, never logged here). Block 3 (Detail): `MangaDetailView`/`NovelDetailView` token-ified per the Block 1-2 incremental pattern — no layout rebuild, just font/radius/notation swaps (`Notation.status()`, `Notation.progress()`, `Notation.readingTime()`), plus a capsule resume button and a leading unread-dot on chapter rows (new — matches the design's read/downloaded 2×2 dot pattern). Block 4 (Manga Reader overlay) — done reactively after the user spot-checked it and found the existing overlay (built pre-design-system, S68) didn't match the mockup: rebuilt `ReaderOverlayView` from one edge-to-edge `Rectangle().glassEffect()` bar into individual floating `Circle().glassEffect()` chips + a floating `RoundedRectangle(22).glassEffect()` bottom card with `Notation.pagePosition()`. **Bug fix within scope**: the page slider looked present but was non-functional in vertical scroll mode — `WebtoonReaderView`'s `currentPage` binding was one-way (scroll → state only); added a guarded `.onChange(of: currentPage)` → `proxy.scrollTo(new, anchor: .top)` (guard: `new != visibleId`, prevents feedback loop with the scroll-driven update) so the slider now actually seeks in every mode. Block 5 (Novel Reader overlay) — done in full to hit the plan's own block-5 checkpoint: same floating-chip top bar, bottom sheet becomes a floating `RoundedRectangle(24).glassEffect()` card, and a new live `CH. XXX · %` progress footer + accent bar was added, threaded from `TextReaderView`'s existing `lastKnownScrollPercent` @State (was already tracked for DB persistence, never surfaced in UI before). Key learning: when a `Text` needs mixed-styling inline segments (e.g. an accent-colored percentage inside a caption), use the iOS 26 interpolation form `Text("\(plainPart)\(styledText)")` — `Text + Text` concatenation is deprecated as of iOS 26. Key learning: always check whether an existing progress/notation value already exists as tracked state before adding new plumbing — the novel reader's live scroll percent was sitting unused.
| 82 | 2026-08-03 | Pre-implementation housekeeping — no Swift changed. (1) **Full 16-screen handoff confirmed**: all screens designed in Claude Design (DESIGN_SYSTEM v0.2) — Library, Manga Reader, Novel Reader, Appearance Studio, Detail, Browse, Settings, Onboarding, Empty state, More, History, Updates, Downloads, Insights, Library-selection, Browse-search. Handoff file: `Yomi/design/design_handoff_yomi/YOMI Screens.dc.html`. (2) **Design assets consolidated**: `DESIGN_*.md` + `Fonts/` moved from `Yomi/` root → `Yomi/design/`; `INFOPLIST_ADDITIONAL_FILE` in `project.pbxproj` updated to `$(SRCROOT)/Yomi/design/Fonts/YomiFonts.plist`; stale partial screen exports (`Yomi/design/screens/`) removed; new app icon assets (`AppIcon-Ink.png`, `AppIcon-Paper.png`) added to `Yomi/design/design_handoff_yomi/assets/`. (3) **Implementation plan locked**: 12 blocks — Library → Library-selection → Detail → Manga Reader overlay → Novel Reader overlay → Browse → History → Updates → Downloads → Insights → More+Settings → Onboarding+Empty state. Compile after blocks 1, 3, 5, 12. Next: Block 1 — LibraryView. Key learning: macOS sandbox blocks `~/Downloads/` from both Bash and `cp`; files must be moved via Finder or opened in Chrome before they can be read by Claude Code.
| 81 | 2026-08-03 | Appearance Studio (Phase 3 steps 4–5). (1) `AppSettings.canvas: String` — primary appearance axis; migration from legacy `theme`+`pureBlack` in `init()`; `colorScheme` computed var checks canvas first; default accent updated `#FF6B6B`→`#E5473A`. (2) `YomiApp.swift`: `.preferredColorScheme(settings.colorScheme)` (single line replaces ternary). (3) `AppearanceStudioView.swift` (new, ~500 lines): live preview card with Space Mono notation + canvas colors + accent progress/resume; Canvas swatches (nested surface chips, accent ring, checkmark overlay); Accent swatches (11 presets + rainbow custom ColorPicker + WCAG relativeLuminance contrast badge AAA/AA/Fail); Type section (UI font, reading font, fontSize slider, lineSpacing segmented, side margins); Library section (columns stepper, unread badge toggle); App icon section (moved from SettingsView); Reset to defaults destructive button. (4) `SettingsView.swift`: `appearanceSection` reduced to single `NavigationLink("Canvas, Accent & Type") { AppearanceStudioView() }`; removed stale state vars, swatch helpers, custom color sheet, applyAlternateIcon. All 4 files compiled clean sequentially. Key learning: WCAG AA requires contrast ratio ≥ 4.5 for normal text; Vermilion #E5473A on Ink #14110F achieves ≈12:1 (AAA).
| 80 | 2026-08-02 | Design system foundation (Phase 3 step 1–3). (1) **Fonts**: Space Grotesk (variable TTF, wght 300–700) + Space Mono (Regular + Bold) in `Yomi/Fonts/`; `YomiFonts.plist` registers `UIAppFonts`; `INFOPLIST_ADDITIONAL_FILE` added to both pbxproj build configs — no manual file-reference edits needed (`PBXFileSystemSynchronizedRootGroup` auto-picks up `Yomi/Fonts/`). (2) **`DesignTokens.swift`** rewritten: `YomiTokens.Canvas` preset struct (Ink/Midnight/Paper/Sepia; bg/surface1/surface2/textPrimary/textSecondary/hairline), `YomiTokens.Font` (Grotesk family + Mono PS names + convenience constructors), `YomiTokens.TypeScale` (display→notation), `YomiTokens.Motion`, cover radius 8→10, Vermilion default accent. All existing reader themes/radius/spacing preserved. (3) **`Notation.swift`** new file in `Core/`: `chapter()`, `volumeChapter()`, `progress()`, `readingTime()`, `readingTimeShort()`, `chapterProgress()`, `pagePosition()`, `status()`, `novelIndex()`, `catalogIndex()`, `novelFooter()`. Build clean first attempt. Key learnings: `PBXFileSystemSynchronizedRootGroup` auto-includes all files in `Yomi/` folder — zero pbxproj file-reference edits for new Swift or resource files; font registration with `GENERATE_INFOPLIST_FILE = YES` uses `INFOPLIST_ADDITIONAL_FILE` (merged plist); variable fonts registered by filename in UIAppFonts, referenced in SwiftUI via family name (`"Space Grotesk"`) + `.weight()`; SourceKit errors are noise, xcodebuild is signal.
| 40 | 2026-04-20 | Multi-repo plugin catalog + 6 new novel TypeScript plugins. AppSettings: `pluginCatalogURL: String` → `pluginCatalogURLs: [String]` with UserDefaults migration (reads legacy key on first launch, stores as JSONEncoder Data under new key). PluginCatalogService: parallel fetch via `withThrowingTaskGroup`, merge dedup by id (first-wins), sort by name, `invalidateCache()` public method. SettingsView: "Plugin Repositories" section with swipe-to-delete + add-repo sheet. New TypeScript plugins compiled via esbuild (globalThis pattern — see below): LightNovelPub, BoxNovel, MTLNovel, BabelNovel (JSON API, no HTML scraping), NovelHall, ReadWN. build-plugins.mjs: updated to merge with existing Firebase index.json instead of overwriting. npm/esbuild installed (package.json in repo root, node_modules/ gitignored). Firebase deployed: 15 plugins live. |
| 41 | 2026-04-20 | Suwayomi integration + library list view + advanced settings. New files: `SuwayomiService.swift` (REST client — `fetchSources`, `fetchPopular`, `fetchSearch`, `fetchMangaDetail`, `fetchChapters`, `pageURLs`, `toManga`; ID format `"suwayomi_{sourceId}_{mangaId}"`), `SuwayomiBrowseView.swift` (infinite-scroll browse + search; uses `isPresented:` navigation — Manga not Hashable), `AdvancedSettingsView.swift` (cache/network/DB/build info sections, log export via UIActivityViewController). Modified: `AppSettings.swift` (+ `libraryDisplayMode`, `suwayomiURL`), `BrowseView.swift` (Section("Suwayomi Server") when isEnabled), `SettingsView.swift` (suwayomiSection, advancedSection → NavigationLink), `LibraryView.swift` (grid/list toggle toolbar, LazyVStack list mode), `MangaCoverCell.swift` (+ MangaListRow struct). Build succeeded. Cloudflare bypass + Tachiyomi backup import deferred to S42. |
| 42 | 2026-04-20 | Yomi exclusives. (1) Manga Notes: `notes: String?` field on Manga model, v14_manga_notes GRDB migration, `MangaQueries.updateNotes()`, Notes section in MangaDetailView with `NotesEditorSheet`, BackupManager encode/decode updated. (2) App Lock: `AppSettings.appLockEnabled` + `ttsSpeechRate`, new `AppLockView.swift` (LAContext `.deviceOwnerAuthentication`, FaceID/TouchID icon, auto-auth on appear), YomiApp `@State isLocked` + `.fullScreenCover` + `.onChange(of: scenePhase)` re-lock. (3) TTS for novels: HTML stripping with regex, `AVSpeechSynthesizer` + `TTSDelegate` (NSObject+AVSpeechSynthesizerDelegate, strong synth ref prevents ARC dealloc), play/stop button in TextReaderView overlay Row 4, stops on navigate/disappear, TTS speed slider in Settings. (4) Global Search: replaced `SearchView` in BrowseView with `GlobalSearchView`; `withTaskGroup` parallel search across all installed sources; results stream per-source to MainActor; per-source section headers; Format A (`searchManga`) + Format B (`searchNovels`); `NovelCoverCell` for novel results; pending count spinner. All 4 built cleanly first attempt (except TTS — initial `didFinishSpeechUtteranceNotification` doesn't exist → switched to delegate pattern). |
| 43 | 2026-04-20 | Tachiyomi backup import + tab reordering. `TachiyomiBackupParser.swift`: hand-written protobuf3 decoder (`ProtoReader` class — varint/length-delimited/fixed32) + gzip decompressor (libz C API via bridging header `Yomi/Yomi-Bridging-Header.h`, `SWIFT_OBJC_BRIDGING_HEADER` in project.pbxproj both configs). `inflateInit2_` with `windowBits=47` (MAX_WBITS+32) auto-detects gzip format. Source ID map `[UInt64: String]` maps Tachiyomi int64 hash → Yomi plugin ID; unmapped = `"tachiyomi_{id}"` placeholder. `BackupManager.importTachiyomiBackup(from:)` + BackupView Tachiyomi section with `.fileImporter` accepting `.tachibk` UTType. `ContentView.swift`: `@AppStorage("tabViewCustomization") TabViewCustomization` + `.customizationID()` on each Tab + `.tabViewCustomization($customization)` — iOS 26 native tab drag-to-reorder. Key learning: `NSData.decompressed(using: .zlib)` expects RFC 1950 (zlib format), not gzip RFC 1952 — cannot be used directly on `.tachibk` data; bridging header + libz C API is the correct approach. |
| 76 | 2026-05-20 | Verification + simulator unification. No code changes. Two simulator instances (same model/OS, different UDIDs) caused Xcode and XcodeBuildMCP to use divergent app data; fixed by running `xcrun simctl list devices available`, then `session_set_defaults` with `simulatorId: "34C346C3-F274-4DE0-A7B2-E9D2DE0CCA97"` and `persist: true` (saved to `.xcodebuildmcp/config.yaml`). Comprehensive app verification across all tabs via mobile-mcp — no bugs found. Key learning: mobile-mcp cannot trigger SwiftUI List `.onTapGesture` rows (they appear as `StaticText` in accessibility tree, not `Button`); only `Button`-wrapped rows respond to coordinate taps. |
| 75 | 2026-05-17 | Plugin duplicate install fix. `PluginsView.installFromURL()` now checks `ext.id == id` OR `ext.name.lowercased() == name.lowercased()` — prevents re-installing an already-installed plugin under a different catalog ID. |
| 74 | 2026-05-16 | Live-testing fixes. (1) `ContinueReadingRow` body used `Group { EmptyView() }.onAppear` — `Group` with `EmptyView` has no layout presence so `.onAppear` never fires; items never loaded; fixed by replacing with `VStack(spacing: 0)`. (2) `StatusBadge`/`NovelStatusBadge`/`ReadingStatusMenu` label lacked `lineLimit(1)` + `fixedSize(horizontal:vertical:)` — text wrapped in narrow HStack; fixed in `MangaDetailView.swift` + `NovelDetailView.swift`. |
| 73 | 2026-05-16 | Notification deep linking + live-testing fixes. (1) Tapping chapter-update notification navigates to detail view: `AppRouter` gets `pendingOpenMangaId`/`pendingOpenNovelId`; `AppDelegate` conforms to `UNUserNotificationCenterDelegate`, reads `userInfo`, routes to pending ID; `LibraryView.onChange` fetches from DB + presents detail; `scheduleChapterNotification` accepts `mediaId`/`mediaType`. (2) Chapter number formatting in `MangaDetailView.ChapterRow`: whole numbers show "Chapter 1" not "Chapter 1.0" via `truncatingRemainder(dividingBy:1) == 0`. (3) Novel reader "Restore scroll position" artifact: `ReaderWebView.makeUIView` uses `.nonPersistent()` datastore; JS `TreeWalker` removes injected DOM element before content renders. |
| 72 | 2026-05-16 | App Store review prompt + Spanish comment cleanup. `AppSettings.chaptersReadCount` + `recordChapterRead() -> Bool` (milestones 10/50/200). Both readers import StoreKit, use `@Environment(\.requestReview)` + `@State shouldRequestReview`; `.onChange` fires prompt; incognito-safe. `MangaQueries.swift` and `NovelQueries.swift` fully translated to English. Key learning: `@Environment(\.requestReview)` is the correct SwiftUI API for iOS 16+ — use `.onChange(of: flag)` to trigger it from async code paths rather than calling it directly inside a Task, so SwiftUI can guarantee the request runs on the main thread in the right scene context. |
| 71 | 2026-05-16 | Reading reminders. `NotificationManager.scheduleReadingReminder(lastReadTitle:afterDays:)` — `UNCalendarNotificationTrigger` at 10am on day N; "Continue [Title]?" body from last-read DB query; `cancelReadingReminder()` + `checkAuthorizationStatus()` added. `AppSettings`: `readingReminderEnabled` (default false) + `readingReminderDays` (default 2). `YomiApp`: cancel on `.active`; fetch last-read title via `Task.detached` + schedule on `.background`. `UpdatesSettingsView`: toggle + days picker (1/2/3/7). Key learning: `UNCalendarNotificationTrigger` is more reliable than `UNTimeIntervalNotificationTrigger` for day-level reminders — fires at a specific clock time (10am) rather than an exact second offset, so it survives device restarts and works correctly even when the interval spans midnight. |
| 70 | 2026-05-16 | Auto iCloud backup + Kingfisher cache fix. (1) `AppSettings.iCloudAutoBackup: Bool` (default true); `YomiApp.onChange(scenePhase == .background)` triggers `uploadToICloud()` when enabled; toggle in `BackupView` iCloud section. (2) `AdvancedSettingsView` "Clear image cache" button adds `ImageCache.default.clearCache()` — previously only `URLCache.shared` was cleared, leaving Kingfisher disk cache intact. Key learning: Kingfisher's disk cache is completely separate from `URLCache` — clearing one does not affect the other; `ImageCache.default` is the singleton, `clearCache()` clears both memory and disk. |
| 69 | 2026-05-16 | iCloud Drive backup sync. `BackupManager`: extracted `buildBackupData() async throws -> Data` from `exportBackup()` — shared by local export and iCloud upload; added `uploadToICloud()`, `downloadFromICloud()`, `checkICloudBackup()` with file I/O in `Task.detached`; `ICloudSyncStatus` enum (idle/uploading/downloading/success/unavailable/error); `lastICloudUploadDate` in UserDefaults. `BackupView`: iCloud section added at top — "Back up to iCloud" button, last backup date, "Restore from iCloud" with `confirmationDialog`; `checkICloudBackup()` called in `.task` on appear. `Yomi.entitlements`: `com.apple.developer.ubiquity-container-identifiers: ["iCloud.pacodealer.Yomi"]` added. Xcode step required: Target → Signing & Capabilities → + iCloud → iCloud Documents. Key learning: `FileManager.url(forUbiquityContainerIdentifier:)` must be called off main thread — always wrap in `Task.detached`; polling `ubiquitousItemDownloadingStatus` with `Thread.sleep` in Task.detached is the correct pattern for waiting on iCloud file download (no NSMetadataQuery needed for one-off restore). |
| 68 | 2026-05-15 | Performance + iOS 26 polish. (1) **Library sort optimization**: `LibraryViewModel.displayedManga`/`displayedNovels` converted from computed properties to stored properties rebuilt by `rebuildDisplayed()` — sorting runs only when data changes, not on every SwiftUI render. `didSet` on `mangas`, `novels`, `unreadCounts`, `novelUnreadCounts`, `searchText`, `sortOrder`, `statusFilter`; `updateFilteredIds()` also calls `rebuildDisplayed()` after async category resolution. (2) **iOS 26 Liquid Glass reader overlays**: `ReaderOverlayView` (manga) and `TextReaderOverlayView` (novel) both replace `ZStack { LinearGradient ... }` gradient bars with `Rectangle().glassEffect().ignoresSafeArea(edges: .top/.bottom)` background pattern; all control `.white`/`.white.opacity()` colors replaced with `.primary`/`.secondary` for glass-adaptive styling. Key learning: `glassEffect()` API confirmed from SwiftUICore.swiftinterface — signature is `func glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape()) -> some View`; apply it to a background `Rectangle` with `ignoresSafeArea` to span into safe area while keeping content padded normally. |
| 67 | 2026-05-15 | Infrastructure fix — four audit issues resolved. (1) **Kingfisher 8.9.0 via SPM**: `project.pbxproj` edited directly (PBXBuildFile, Frameworks build phase, packageProductDependencies, packageReferences, XCSwiftPackageProductDependency, XCRemoteSwiftPackageReference); `Package.resolved` auto-updated by `-resolvePackageDependencies`; `CoverImage.swift` created in `Yomi/Core/` (KFImage wrapper, 2/3 aspect ratio, 0.2s fade, secondary placeholder). All 21 `AsyncImage` cover usages across 11 files migrated to `CoverImage` or `KFImage`; readers and widget left unchanged per policy. (2) **DB indexes** via `v18_indexes` migration: `idx_chapter_mangaid`, `idx_chapter_unread` on `chapter`; `idx_novel_chapter_novelid` on `novel_chapter`. (3) **Double `markChapterRead()` fix**: `@State private var didMarkCurrentChapterRead = false` guard prevents both `onChange(of: currentPage)` and `onDisappear` from writing to DB for the same chapter; reset in `navigateToChapter`. (4) **Spanish comments cleaned**: `DatabaseManager.swift` and `ChapterQueries.swift` fully translated to English. Key learning: Xcode 26.5 requires iOS 26.5 simulator runtime — older runtimes (26.0–26.3) in simctl are not accepted as build destinations. `iphonesimulator26.5` SDK is present but the runtime OS image must be downloaded separately from Xcode → Settings → Platforms. Workaround: `-target Yomi` compiles Swift (no scheme needed) but cannot resolve SPM modules from a different derivedDataPath. Build verification requires the runtime download. |
| 66 | 2026-05-09 | Novel reader justify + home screen quick actions. (1) **Text justification toggle**: `novelJustifyText: Bool` in `AppSettings`; `text-align: justify/start` in CSS; circular `"text.justify"` icon button in Row 2 of `TextReaderOverlayView` (between Aa and margin picker); persisted via onChange. (2) **Home screen quick actions**: `AppDelegate` added to `YomiApp.swift` via `@UIApplicationDelegateAdaptor`; `didFinishLaunchingWithOptions` registers "Continue Reading" + "Browse" `UIApplicationShortcutItem`; `performActionFor` sets `appRouter.selectedTab`. Cold-launch `launchOptions[.shortcutItem]` omitted — deprecated in iOS 26, `performActionFor` handles both cold + foregrounded cases. Build clean (zero warnings). Key learning: iOS 26 deprecates `launchOptions[.shortcutItem]` in favour of UIScene `ConnectionOptions.shortcutItem`; since we use SwiftUI App lifecycle, `performActionFor` alone suffices for all cases. |
| 65 | 2026-05-09 | UX polish + Insights calendar. (1) **Last-read chapter label on library covers**: `MangaCoverCell` and `NovelLibraryCoverCell` show the most recently read chapter name as a `black.opacity(0.65)` label at the bottom of the cover image, stacked above the progress bar; only when `readProgress > 0`. Novel cells prefer in-progress (`lastScrollPercent > 0.01 && !isRead`) over last fully-read. (2) **Reading activity calendar in InsightsView**: 13-week rolling heatmap placed between stat cards and Breakdown section. `ReadingCalendarView` private struct; month labels use `ZStack + .offset(x:)` to avoid width-clipping. Intensity: `accentColor.opacity(min(0.35 + Double(count-1)*0.18, 1.0))`; empty: `secondary.opacity(0.15)`; future: `secondary.opacity(0.06)`. Calendar data built in `loadStats()` Task.detached, returned as 10th tuple element. Also ran full concurrency + DB + docs audit: ARQUITECTURA.md and CLAUDE.md brought current to S64 state (v17 schema, v18 prefix, AppSettings props, InsightsView description). |
| 64 | 2026-05-09 | Stats + polish + data freshness pass. (1) **Reading time in detail headers**: `formatReadingTime(_ seconds: Int) -> String` helper added to both `MangaDetailView` and `NovelDetailView`; progress caption extended with "· Xh Ym" (sum of `chapter.readingSeconds`). (2) **InsightsView breakdown section**: "Breakdown" shows manga vs novel chapters+time; `(title, seconds, isNovel: Bool)` tuple threads through `loadStats()` 9-element return. (3) **InsightsView novel badge**: novel rows in "By Title" list get small accentColor "N" badge. (4) **`HistoryView` `.onAppear`**: `.task` → `.onAppear { Task { } }` — same fix as S62 ContinueReadingRow. (5) **`LibraryView` `.onAppear`**: same pattern — library reloads when tab returns from detail view. (6) **`SortOrder.readingTime`**: added to `LibraryViewModel.SortOrder` enum + `displayedManga`/`displayedNovels` switch cases. (7) **HistoryView novel subtitle**: novel chapter name now shows in-progress chapter (`lastScrollPercent > 0.01`) before last fully-read chapter. All builds clean on first attempt. Key learnings: SourceKit errors are always noise — only xcodebuild results are signal; `.onAppear { Task { } }` is the correct pattern for data that must refresh on every navigation return; named tuple key paths with `ForEach id:` are unsafe — use explicit row helpers instead. |
| 63 | 2026-05-09 | Data integrity + parity + UX polish. (1) **BackupManager v3**: added `encodeCategory` helper + `categories` key to export payload; import restores categories via `INSERT OR IGNORE INTO category` before assignment pairs (prevents FK orphans on clean-device restore); `version` bumped 2→3. (2) **Novel update smart-skip parity**: `checkNovelUpdates` now mirrors all 4 skip conditions from manga path — `skipUpdateNotStarted`, `skipUpdateCompleted` (status.lowercased().contains("completed")), `skipUpdateWithUnread`, `excludedCategoryIds`. (3) **Library context menus** (manga + novel, grid + list): `.contextMenu` with Reading Status submenu (checkmark on current) + destructive Remove action; callbacks in `MangaCoverCell` (`onReadingStatusChange`, `onRemoveFromLibrary`) and `NovelLibraryCoverCell`; DB writes in `Task.detached`; inline `.contextMenu` on list-mode rows too. (4) **`MangaListRow` custom cover**: added `customCoverPath` + `UIImage(contentsOfFile:)` branch — was the only cover surface missing it. (5) **`ContinueReadingNovelCell` resume fix**: `readAt != nil` → `lastScrollPercent > 0.01` in both `openReader()` resume logic and subtitle `.task` filter — matches S62 `NovelDetailView` fix that was never propagated here. Key learnings: only xcodebuild errors are signal (all SourceKit "Cannot find type X" errors were cross-file noise; all builds succeeded clean first attempt); `.contextMenu` with nested `Menu` for submenus uses the same `ForEach(ReadingStatus.allCases)` pattern as detail views. |
| 62 | 2026-05-06 | UX polish + reader improvements. (1) `ContinueReadingNovelCell.openReader()`: DB-only chapter fetch + bridge from `ExtensionManager`, resume = in-progress (readAt set) → first unread → last; `lastChapterName` includes `lastScrollPercent > 0` in-progress chapters; `.navigationDestination` opens `TextReaderView` directly. (2) `LibraryViewModel.sortOrder`/`statusFilter`: `UserDefaults`-backed default-value closures + `didSet` writers — persist across app restarts without touching `AppSettings`. (3) `NovelDetailView.resumeChapter`/`hasStartedReading`: now check `lastScrollPercent > 0.01` — chapters opened before reaching 90% were invisible to resume detection. (4) Chapter list sheet in `TextReaderOverlayView`: list button in top bar, `NavigationStack` + `ScrollViewReader`, `proxy.scrollTo(target, anchor: .center)` after 100ms `Task.sleep` (List needs time to populate before scroll fires). (5) Same chapter list sheet pattern in `ReaderOverlayView` (manga reader). Key learnings: `proxy.scrollTo` in `onAppear` fires before `List` rows are laid out — always use 100ms async delay; capture `let target = currentChapterIndex` before sheet body to avoid lazy @Binding re-evaluation. (6) Mark previous chapters as read: trailing swipe "Mark previous" in `ChapterRow` + `NovelChapterRow`; finds chapter position in ascending array, bulk-marks all lower-index chapters via `ChapterQueries.setRead` / `NovelQueries.markRead(chapterId:)`, updates local state with a `Set`. (7) Chapter search in detail views: inline `TextField` (threshold 30 chapters) in `MangaDetailView` + `NovelDetailView`; filter applied after scanlator/status filter; `ContentUnavailableView` empty-search state. (8) Reading progress bar in detail headers: `ProgressView(value:total:)` above the resume button in both detail views with read-count/total caption. (9) `ContinueReadingRow` refresh fix: `.task { }` (once per view lifetime) → `.onAppear { Task { } }` — row re-queries DB every time the library tab is shown. (10) `ContinueReadingCell` DB fallback: if bridge returns empty, falls back to DB chapters (mirrors MangaDetailView S55 fix). (11) Plugin update ID matching: `PluginCatalogService.isInstalled` + `availableUpdate(for:)` match by `ext.id` first, fall back to `ext.name`. (12) Relative time bar in Insights "By Title": `ZStack` + `GeometryReader` background `Rectangle` scaled to `seconds/maxSeconds` ratio with `accentColor.opacity(0.12)`. Key learning: `.onAppear { Task { } }` is the correct pattern for data that must refresh on every navigation return; `.task` is for one-shot initialization only. |
| 61 | 2026-05-05 | Chapter finished banner in `TextReaderView`: `@ViewBuilder chapterFinishedBanner` computed property, spring `.move(edge:.bottom).combined(with:.opacity)` transition, 5s auto-dismiss via `Task.sleep`, "Next →" calls `navigateToChapter(currentChapterIndex + 1)`, "All caught up!" on last chapter, cleared in `navigateToChapter`. DB write (`NovelQueries.markRead`) incognito-guarded; banner shows regardless (in-memory UI state). |
| 53 | 2026-05-02 | Firebase deploy + embedded JVM feasibility study. (1) Firebase: babelnovel.js + lightnovelpub.js deployed — all 15 plugins live. (2) Deep feasibility study on embedding OpenJDK Zero + Suwayomi-Server JAR to eliminate self-hosting friction. Verdict: DEFERRED. Three hard blockers: (a) Java version gap — only proven iOS App Store JVM is OpenJDK 8 (thebaselab/Code App); Suwayomi v1.1+ dropped Java 8, v2.x requires Java 21 — no confirmed-working combination exists; (b) NSExtension architecture required — Code App sandboxes Java in a separate process via NSExtension, not a simple framework embed; doubles scope; (c) +150–200MB binary. Key insight: `SuwayomiService.swift` is fully URL-agnostic (`baseURL` computed from `AppSettings.shared.suwayomiURL`) — if an embedded server starts at localhost:4567, existing service and all browse UI work with zero changes. Path viable if/when OpenJDK Mobile (Java 21, Gluon initiative) matures. Tachimanga architecture clarification: App Store listing shows native Swift, iOS 15.0+ — conflicts with S52 OpenJDK Zero conclusion; architecture unconfirmed either way. |
| 52 | 2026-05-02 | Full codebase audit + HistoryView search. Audit: 55 Swift files, ~16,000 lines, DB at v15_novel_notes (16 migrations, next v16_). All `*Queries` nonisolated ✅, all bridge calls Task.detached ✅, no MainActor DB reads ✅. `UpdatesViewModel` promoted to singleton (`static let shared`) so ContentView badge observes `totalCount` without a separate service. `NotesEditorSheet` made non-private (internal) for reuse by NovelDetailView. `NovelDetailView` bridge made optional + lazy-resolved from `ExtensionManager` — removes required `bridge:` argument at all call sites (Library, History, Updates, ContinueReading, UpdatesView). `AppSettings.sendUpdateNotifications: Bool` added; UpdatesView notification calls gated behind it. `SettingsView UpdatesSettingsView` shows push notification toggle. `CategoryView` shows item counts per category (UNION ALL SQL across manga_category + novel_category). `InsightsView` gets pull-to-refresh. `ContentView` tab badge on Updates tab via `UpdatesViewModel.shared.totalCount`. `Novel.notes: String?` field + v15_ migration + `NovelQueries.updateNotes()` + `NovelDetailView` Notes section + BackupManager encode/decode updated. `HistoryView`: search bar (`.searchable` + `filteredItems` computed property + `ContentUnavailableView.search` empty state), clear-all trash button with `confirmationDialog`, `clearAllHistory()` func. `HistoryView` navigation to novels no longer requires bridge lookup. `LibraryView` / `ContinueReadingRow` novel navigation simplified (no bridge argument). Novel parity gaps remaining: no custom cover PhotosPicker (MangaDetailView has PhotosPicker), no chapter multi-select mode. Firebase deploy pending: babelnovel.js + lightnovelpub.js in `~/Projects/Yomi/Firebase/public/` — run `firebase deploy --only hosting`. |
| 51 | 2026-04-29–30 | CF bypass + settings UX + AniList + novel metadata fix + plugin fixes + tech debt cleanup. (1) CF bypass: `AutoBypassHelper` WKWebView full-size off-screen, 30s timeout, poll restarts on server redirect, `CFBypassConstants.userAgent` shared constant. (2) Settings: 12→7 sections, `MangaReaderSettingsView`/`NovelReaderSettingsView`/`UpdatesSettingsView`/`SuwayomiSettingsView`/`OPDSSettingsView` sub-views. (3) `AniListService.swift` (actor, GraphQL, cache) — `averageScore` badge in `MangaDetailView` + `NovelDetailView` headers. (4) Language filter moved to Extensions tab, `BrowseView.displayLanguage(_:)` deduplicates ISO codes + full names. (5) Library list mode for novels: `NovelLibraryListRow` struct. (6) `NovelDetailView`: `let novel` → `@State private var novel`; updates summary/author/status/coverURL after parse; upserts to DB if in library. (7) `lightnovelpub.ts` BASE_URL `.com` → `.vip`. (8) `JSBridge.getChapterList` for Mangayomi: chapter extraction moved entirely to JS; handles `url`/`link`/`id`/`href`/`path` variants; caches `lastMangayomiMeta` (description/status/cover) from same getDetail call — `MangaDetailView.loadChapters` applies it to synopsis/status/coverURL. (9) `BabelNovel` v1.1.0: adds proper browser-like API headers; HTML-response guard. (10) `LibraryViewModel.loadLibrary()` moved to `Task.detached` — DB reads no longer block MainActor. (11) `Extension.init(row:)` force-unwrap removed — throws `DatabaseError` on malformed URL. Key learning: `toDictionary()` on JSC objects with complex prototype chains silently drops or mistyps nested arrays — always extract structured data in JS then pass flat arrays/strings to Swift. | 45 | 2026-04-23 | Cloudflare auto-bypass + LNReader/Mangayomi plugin fixes. (1) `CFBypassView.swift`: manual full browser sheet. (2) `CFBypassManager` + `AutoBypassHelper`: hidden WKWebView, polls for `cf_clearance`, 10s timeout, `withCheckedContinuation<Bool>`. (3) `JSBridge.swift` CF detection: `ObjectIdentifier(ctx)` keyed dict, CF-RAY header or 403+"Just a moment" detection, `cfBlockedURL`/`clearCFBlock()` instance props. (4) `SourceBrowseView.loadWithBypass()`: auto-bypass flow with `isBypassing` overlay. (5) LNReader v3 `module.exports` fallback in `injectLNReaderAdapter`. (6) Mangayomi `.js`-only filter in `PluginCatalogService`. (7) `injectRequireShim` additions: `@libs/fetch` → `{fetchApi: fn}` wrapping `SOURCE._fetchSync`; `@libs/novelStatus` → `{NovelStatus:{Ongoing,Completed,Unknown}}`; `dayjs` → lightweight stub (subtract/add/format/isValid). (8) `CFBypassView` `initialURL` param — `init` initializes `@State var urlText` from blocked URL so manual bypass sheet opens on the right domain. |
| 46 | 2026-04-25 | Community LNReader + cheerio plugin fixes. Three JSBridge bugs fixed: (1) cheerio `each`/`map` were passing wrapped objects to callbacks instead of raw DOM nodes — real cheerio passes `(index, rawNode)`, `$(node)` then wraps; (2) CSS selector engine split only on whitespace, so `"h4.heading > a"` (child combinator `>`) was misparsed — added proper `>` tokenisation with direct-children-only semantics; (3) `$()` inside `cheerio.load` didn't handle raw node or wrap-object arguments — added `typeof selector === 'object'` branch. Result: AllNovel ✅ and Archive Of Our Own ✅ now return titles. ReadComicOnline + Mangapill confirmed broken downloads (source URL `entityJY/mangayomi-extensions-eJ` returns 404 — repo deleted). Removed all diagnostic code (yomi_diag.json writes, `__lnr_dbg_*` globals). |
| 44 | 2026-04-20 | Onboarding + multi-format catalog + Format D Mangayomi + catalog UX overhaul. (1) `PluginsView.swift`: toolbar `+` → Menu → `AddRepoSheet` (LNReader featured repo, custom URL, GitHub guide). (2) `PluginCatalogService.swift`: 3-format parser (Yomi native → LNReader → Mangayomi), `MangayomiEntry` struct, `repoURL` on entries (set post-fetch, excluded from Codable via CodingKeys), `PluginCatalogGroup` (groups same-name multi-lang entries), `groupedEntries`, `repoLabel(from:)`. (3) `JSBridge`: Format D Mangayomi shim — `Client`, `Document`/`Element` (built on cheerio), String prototype extensions, `Preferences` stub. Adapter detects `source` via identifier lookup (NOT `global.source` — `const` is lexical, not on globalThis). Critical lesson: `const` at JS top-level is a lexical env binding, not a globalThis property. `global.source` returns undefined; `typeof source` correctly walks lexical scope. (4) `BrowseView.swift`: Extensions tab uses groups + language picker dialog + repo badges + search + pull-to-refresh + repo filter chips (horizontal scroll, multi-select, "All" default). `RepoFilterChip` view. `availableRepos` computed from catalog entries. Sources tab: swipe-to-delete, "Get more" header button, empty state → Extensions. `CatalogGroupRow` (internal, shared with PluginsView). (5) Research: Mangayomi extensions are ALL Dart (`.dart` files, `sourceCodeLanguage: 0`) — Format D JS shim is irrelevant to their catalog. Mangayomi removed from featured repos. LNReader URL corrected: `plugins/v3.0.0/.dist/plugins.min.json` (was wrong branch + wrong path). Tachimanga = Flutter + **embedded OpenJDK Zero + local Tachidesk-Server JAR** (S44 described as "C-native DEX interpreter" but S52 research proved no such standalone C library exists; see ROADMAP Session 44 entry for correction). Mihon forks all Android-only. README.md updated with correct LNReader URL. |
| 79 | 2026-07-16 | **Design session — no code.** Design-track kickoff via Cowork (not Claude Code). Delivered 3 repo docs: `DESIGN_RESEARCH.md` (competitive/UX/typography/personalization/gamification + iOS 26 Liquid Glass NN/g critique), `DESIGN_SYSTEM.md` v0.2 (justified system — concept "reading instrument / living archive," color+theming Ink/Midnight/Paper/Sepia, Space Grotesk+Space Mono, monospace notation, components + 3 key screens), `DESIGN_HANDOFF.md` (roadmap to launch + who-does-what). Mined Andy's own portfolio (Prometheus/Velvet Moon) + Pinterest for design DNA. Confirmed: Vermilion `#E5473A` accent, Ink `#14110F` canvas, ink/screentone texture, serif novel reader, Grotesk+Mono standard (user-swappable). Visual production to happen in **Claude Design** → handoff bundle → Claude Code. App-icon direction defined (App Store blocker). Key learning: Cowork/Claude Design is now part of the workflow — Claude Design reads the repo (design system + tokens) so strategy flows through the codebase, not copy-pasted prompts. App icon finalized in cont. session 2026-07-18 — "Y." monogram (Space Grotesk Y + Vermilion dot), Ink default + Paper alternate; assets in `Yomi/design/icons/`. |

## Research methodology — lessons learned (post S42)

### The Suwayomi blind spot: "impossible" is never the final answer

For 40 sessions, every question about Keiyoushi/Tachiyomi/Mihon extensions received the same answer: **"impossible — Kotlin APKs, Android-only runtime, no iOS path."** This was technically correct for *direct integration* but missed the actual solution entirely.

**What was missed:** Suwayomi/Tachidesk is a self-hosted Java server that runs all 1000+ Keiyoushi Kotlin extensions server-side and exposes them as a REST+GraphQL API. The iOS app needs zero Kotlin — just URLSession. This was available from S1. It shipped in S41.

**Root cause of the miss:** Research stopped at the first-order question ("can Kotlin run on iOS?") and never asked the second-order question: **"what server-side bridges or proxies exist in this ecosystem?"**

### Rule for all future research

> When a direct implementation path is blocked, ALWAYS ask: **"Does a proxy, bridge, or server exist that exposes this through an API Yomi can consume?"**

Checklist to run before concluding "impossible":
1. Is there a self-hosted server that wraps this ecosystem? (Suwayomi for Keiyoushi, Komga for CBZ libraries)
2. Is there a REST/GraphQL API maintained by a third party?
3. Is there a web interface that could be scraped or automated?
4. Does any competing iOS app already support this — and if so, how?

**Point 4 is the most reliable signal.** If Paperback, Aidoku, or any other iOS reader already supports a feature or ecosystem, there is a path. Find out how they did it before concluding it's impossible.

### Implication for web search

Never rely on training-data knowledge alone for ecosystem research. Training data has a cutoff and may not reflect current tools, servers, or bridges. Use `WebSearch` for:
- "X iOS reader how does it support Y extensions"
- "Y extension format iOS bridge"
- "self-hosted server for Y manga/novel sources"

### What this means for the current app

Suwayomi is already integrated (S41). The same second-order thinking applies to every future "impossible" claim:
- "Kindle books can't be read" → is there a Calibre REST API?
- "Cloudflare blocks everything" → is there a FlareSolverr proxy?
- "Mangayomi uses Flutter+Dart plugins" → is there a server bridge or REST API?

Always ask the second question.

## Technical learnings — S47

- **`FormData` is a global, not a `require()` module**: LNReader's Madara/WordPress multisrc plugins (52+ sources) use `new FormData()` directly — it is a Web API global, like `URL` or `URLSearchParams`, not something loaded via `require()`. JavaScriptCore has none of these Web APIs. Missing `FormData` throws `ReferenceError: Can't find variable: FormData` at the very first line of `popularNovels()`, silently returning `[]`. Fix: inject a `FormData` constructor into `injectWebAPIs()` alongside `URL` and `URLSearchParams`. It only needs `_entries` array + `append`/`get`/`has`/`set`/`toString` — no file upload support required.

- **FormData body requires `Content-Type: application/x-www-form-urlencoded`**: the Madara plugins POST to WordPress's `wp-admin/admin-ajax.php` with a FormData body. The server reads parameters via PHP's `$_POST` superglobal, which only populates when `Content-Type` is `application/x-www-form-urlencoded` (for URL-encoded) or `multipart/form-data`. Since our shim serializes FormData as URL-encoded, the header must be set automatically — plugins don't set it themselves. Detect FormData body via `rawBody._entries` (the private marker array), serialize, and inject the header. Both `@libs/fetch`'s `fetchApi` and the global `fetchApi` in `injectSourceFetch` need the same treatment.

- **Full plugin audit pattern**: to find JSBridge gaps in an ecosystem, scan all plugin files for `require(` calls + global constructors. For LNReader: `grep -rh "require(" plugins/ | grep -oP "'[^']+'" | sort | uniq -c | sort -rn` gives the complete require frequency table. Then `grep -rl "FormData\|fetch\b" plugins/` finds global usage. This takes 60 seconds and surfaces all gaps at once.

- **`@libs/isAbsoluteUrl` is simple**: returns a boolean — `true` if the string has a scheme prefix. A simple `indexOf('://') > 0 && indexOf('://') < 20` check is sufficient without regex backslash escaping concerns in Swift string literals.

- **S46 cheerio shim correction — `each`/`map` pass wrapped objects, not raw nodes**: the S46 summary incorrectly described the final fix as "pass raw DOM nodes." The actual committed fix passes **wrapped cheerio objects** (`wrap([nodes[i]])`). This is compatible with both plugin styles: (1) Yomi-style `el.find(...)` — works because the wrapped object has `.find()`; (2) LNReader AO3-style `$(t).find(...)` — works because `$()` detects `typeof selector.find === 'function'` and returns the wrapper as-is. The METODOLOGIA S16 entry was updated in S46 to note this, but the description was still wrong. The wrapped-object approach is correct and final.

## Technical learnings — S45

- **Cloudflare auto-bypass with hidden WKWebView**: attach a 1×1pt `WKWebView` (frame `CGRect(x: -2, y: -2, width: 1, height: 1)`) to the app's `keyWindow`. It loads the URL silently in the background — the real WebKit engine solves the CF JS challenge without any user interaction. Poll `webView.configuration.websiteDataStore.httpCookieStore.getAllCookies` every 0.5s. `httpCookieStore` callbacks arrive on an arbitrary queue — always dispatch back to main before calling completion. Keep a 10s `Task` timeout as safety.

- **WKWebView navigationDelegate is held weakly**: `WKWebView` holds its `navigationDelegate` as a `weak` reference. If the coordinator is only a local variable, it will be deallocated before the delegate method fires. Solution: store the delegate in a `class` instance held by the caller (e.g. `AutoBypassHelper` owns itself as long as `withCheckedContinuation` is alive, since the continuation is captured in the class property).

- **`withCheckedContinuation` keeps the caller alive**: when `withCheckedContinuation` is used inside an `async` method on a `class` instance, the class instance is retained for the duration of the continuation's lifetime. This means `AutoBypassHelper.run(url:)` is safe — `self` remains alive even after `run()` returns (it's awaiting continuation resolution).

- **Top-level `let` in Swift 6 is `@MainActor` by default**: module-level stored `let` constants (not `lazy`) are inferred as `@MainActor` by Swift 6's concurrency model. Accessing them from `nonisolated` contexts produces a warning. Fix: add `nonisolated(unsafe)` if the type is non-`Sendable`; for `Sendable` types (like `NSLock`), the compiler will also warn that `nonisolated(unsafe)` is "unnecessary". Both warnings build successfully — pick whichever produces fewer total warnings (usually `nonisolated(unsafe)` on the var).

- **LNReader v3 plugins export via `module.exports`, not `globalThis.plugin`**: LNReader v3.0.0 TypeScript plugins compiled with CommonJS output set `module.exports = pluginInstance`. The `injectLNReaderAdapter` that runs AFTER `evaluateScript` must check `module.exports` / `exports.default` as fallback before the `var p = global.plugin; if (!p) return` guard. If not done, the plugin is treated as Format A (manga), `getMangaList` finds no function, and returns empty results.

- **Mangayomi catalog is Dart-only**: `sourceCodeUrl` for every Mangayomi entry ends with `.dart`, not `.js`. Installing them downloads a Dart file saved as `.js`. JSC evaluates Dart source as JavaScript → exception thrown → no globals set → `getMangaList` returns `[]`. Fix at catalog level (filter before install, not after).

- **LNReader v3 `@libs/fetch` returns an object, not a function**: `require("@libs/fetch")` must return `{ fetchApi: fn }` — not a raw function. Plugins call `(0, n.fetchApi)(url, opts)` — indirect call pattern to strip `this` binding. Returning `{}` silently sets `n.fetchApi` to `undefined`, which throws `TypeError` at call site. Same pattern applies to any `@libs/*` module that destructures its export.

- **`@State` with a parameter requires an `init`**: you cannot write `@State private var x = someParam` — the `@State` wrapper's initial value must be a literal or a constant expression. To initialize `@State` from a constructor argument, write `init(param: T) { _x = State(initialValue: param) }`. Attempting `@State private var x: String` then assigning in `init` via `self.x = …` compiles but ignores the value — `@State` ignores direct property assignment outside the `_x = State(…)` form.

- **`CFBypassView` `initialURL` pre-fills and auto-navigates**: `makeUIView` in `CFWebViewRepresentable` calls `navigate(wv)` immediately on creation. So if `urlText` is pre-filled with a valid URL (from `bridge?.cfBlockedURL`), the WKWebView navigates there automatically when the sheet opens — no user action required.

- **`JSContext.evaluateScript` drains microtasks before returning to Swift**: JSC internally calls `drainMicrotasks()` after executing a script, before returning control to the Swift caller. This means a full `async`/`await` Promise chain (compiled from TypeScript's `__awaiter`/`__generator`) resolves within a single `evaluateScript` call, provided all underlying operations are synchronous (i.e., `SOURCE._fetchSync` blocks and returns). **Consequence:** you can capture the resolved Promise value in a JS global (`__lnr_result`) and read it from Swift immediately after `evaluateScript` returns — it will always be populated. This is the correct pattern for calling LNReader v3 async plugin methods from Swift.

- **`JSValue.call(withArguments:)` does NOT drain microtasks**: calling a JS function from Swift via `.call(withArguments:)` returns the raw return value of the function — which is a `Promise` object for any `async` method. Microtasks are NOT drained before `.call` returns. The old `_resolve` trick tried to read a result set by a `.then()` callback, but `.then()` is a microtask scheduled for AFTER the call returns — so Swift always read `undefined`. Only `evaluateScript` triggers the microtask drain. **Rule: never call async JS plugin methods via `.call(withArguments:)` — always use `evaluateScript` with a global result variable.**

- **LNReader v3 TypeScript compiles `async/await` to `__awaiter`/`__generator`**: every `async` method in a LNReader v3 plugin returns a `Promise`, not a synchronous value. The compiled output looks like: `return __awaiter(this, void 0, void 0, function* () { yield SOURCE._fetchSync(...); return parsedItems; })`. Without the `evaluateScript` drain trick, every plugin method appears to return `undefined` to Swift. The correct `callPluginMethod` helper injects: `var __r = plugin['methodName'](...); if (__r && typeof __r.then === 'function') { __r.then(function(v) { __lnr_result = v; }); } else { __lnr_result = __r; }` — then reads `__lnr_result` after `evaluateScript` completes.

- **`JSContextDrainMicrotasks` is not exported in the iOS JavaScriptCore SDK**: the C function `JSContextDrainMicrotasks(JSContextRef)` exists on macOS (confirmed in TBD files) but is absent from the iOS simulator and device TBD files. Attempting `@_silgen_name("JSContextDrainMicrotasks")` in Swift 6 fails at link time with "undefined symbol". Do NOT attempt to call it on iOS — use `evaluateScript` instead, which drains internally.

## Technical learnings — S44 JavaScript lexical scope in JSC

### `const`/`let` at top-level are NOT on globalThis

In JavaScript, `var` at the top level of a script creates a property on the global object (`globalThis.x` works). But `const` and `let` at the top level create bindings in the **global lexical environment** — NOT properties on `globalThis`.

**Consequence:** Mangayomi plugins use `const source = {...}`. Inside a `injectMangayomiAdapter` JS closure, `global.source` (where `global = this`) is **undefined** because `source` is lexical, not a global object property.

**Correct detection:**
```javascript
// WRONG — doesn't find const/let bindings
var src = global.source;

// CORRECT — identifier lookup walks lexical scope
var src = null;
try {
    if (typeof source !== 'undefined' && source !== null) src = source;
} catch(e) {}
```

`typeof source` performs an identifier lookup that checks the lexical environment, finding `const source`. `global.source` only checks the global object property bag.

**Note:** `context.objectForKeyedSubscript("source")` in Swift/JSC DOES find lexical bindings (it checks both), so Swift-side detection works. The bug only affects JS-side detection within a second `evaluateScript` call.

## Technical learnings — S40 plugin build system

### esbuild IIFE format + JSC global scope
When esbuild compiles TypeScript to `format: 'iife'`, the output is wrapped as `(function() { ... })()`. Inside that IIFE, `var plugin = {...}` would be **function-scoped** (not global) and thus inaccessible via `context.objectForKeyedSubscript("plugin")` in JSC.

**Correct pattern:** end every TypeScript plugin with `(globalThis as any).plugin = plugin;`. This works because `globalThis` refers to the actual global object in JSC (available iOS 14+), so the property is set globally and JSBridge's `context.objectForKeyedSubscript("plugin")` finds it.

**Wrong pattern:** `var plugin = {...}` at top level in TypeScript → esbuild wraps it in IIFE → variable is local → JSC detection fails.

### build-plugins.mjs merge strategy
The script now loads existing Firebase index.json before writing. New TS-compiled entries override existing entries with the same `fileURL`; all other existing entries are preserved. This lets us mix hand-written `.js` files (existing 9 plugins) with TypeScript-compiled ones (new 6) in the same catalog.

### Multi-repo catalog merge in PluginCatalogService
`withThrowingTaskGroup` fetches all URLs concurrently (not sequentially). The `for try await result in group` loop is safe — it serializes result consumption even though tasks run in parallel. Post-merge dedup uses `Set<String>` of seen IDs and processes batches in fetch order (first catalog = highest priority on conflict).

## Competitive research — S38 (Tachimanga)

### Sources
- Full changelog scraped: tachimanga.app/docs/changelogs.html (v1.1–v4.15, Apr 2026)
- Full localization file: Weblate export ZIP — `tachimanga-intl-en.csv` (809 strings, Apr 19 2026 build)
- The ARB file in the same ZIP is for Sorayomi (Flutter desktop client), not the iOS app

### Key findings
- Tachimanga is **Flutter-based** (not SwiftUI). Many features Yomi has natively (SwiftUI animations, iOS 26 Tab API) are harder for them.
- **Premium paywall** on notes, sync, unlimited downloads. Yomi is fully free — strong competitive differentiator to highlight in App Store description.
- **Features Yomi already has** at parity: OLED mode, incognito, backup/restore, reading insights, categories, multi-select, downloads, progress resume, page slider, unread badge, alternate icons, NSFW filter, MAL tracking, reading status, continue reading.
- **Biggest gaps (S38):** auto webtoon from tags, hold-to-scroll, skip update conditions, concurrent downloads, delete-after-read, chapter sort options, random entry, text selection on descriptions.
- **Medium gaps (S39):** scanlator filter/priority, reader tap zones, separate padding settings, auto-scroll, saved searches, custom covers.
- **Long-term gaps (S40+):** app lock, Tachiyomi backup import, bulk migration, multiple extension repos.
- **Yomi exclusives to build (S41):** WidgetKit, TTS for novels, manga notes (free), global search, tab reordering.

### Tachimanga localization string keys worth knowing
- `auto_webtoon_mode` / `auto_webtoon_mode_desc` — tags: 'webtoon', 'long strip', 'manhwa'
- `hold_to_scroll` — only in webtoon + continuous modes
- `remove_after_read` — delete download automatically when chapter marked read
- `concurrent_download_title` / `concurrent_download_tips` — warn about IP bans from same-source concurrent
- `skip_updating_titles_with_unread_chapters` / `that_havent_been_read` / `with_completed_status`
- `exclude_categories` — categories excluded from global update
- `action_open_random_manga` — random entry from library
- `readerNavigationLayout*` — 6 tap zone layout modes (Default, Edge, Kindle-ish, L-Shape, Right&Left, Disabled + Invert toggle)
- `readerPaddingWebtoon` / `readerPaddingPaged` — separate per mode
- `scanlator_filter_label` / `scanlator_priority_label` — filter + priority per manga
- `saved_searches` / `save_query_title` — persist named search queries
- `repair_database` — dangerous DB repair tool
- `liquid_glass_appearance_title` — iOS 26 Liquid Glass toggle

## Technical learnings — S39 visual audit

### Tachimanga is a Flutter+JVM app, not a native iOS JS app
The "credits" screen of Tachimanga reveals its architecture: it is built on Tachidesk-Server (Kotlin/JVM, fork of Suwayomi-Server) + Tachidesk-Sorayomi (Flutter UI). The app bundles an embedded JVM that runs as a local HTTP server, executing real Mihon/Tachiyomi Kotlin extensions. The Flutter UI communicates with the server via REST.

**Why this matters:**
- Tachimanga's 100+ sources come from Kotlin APK extensions — not JS plugins. We cannot run them.
- Their architecture requires ~100MB+ JVM bundle; Yomi is fully native Swift with no server.
- The architectural gap is not closeable by writing more plugins. Our response must be quality over quantity.
- Tachimanga is Flutter-based, so it cannot use SwiftUI, iOS 26 APIs, or native animations. This is a UI quality moat for Yomi.

### Cloudflare bypass pattern (from Tachimanga Advanced settings)
Tachimanga's "Bypassing Cloudflare automatically" toggle works by:
1. Opening a hidden `WKWebView` to the blocked domain
2. Waiting for WKWebView to complete the JS challenge (authentic browser fingerprint)
3. Extracting `cf_clearance` cookie + User-Agent via `WKWebView.configuration.websiteDataStore.httpCookieStore`
4. Injecting both into subsequent `URLSession` requests for that domain

This is implementable in Yomi. The 403 from SOURCE.fetch triggers the bypass flow; subsequent retries with the extracted cookies succeed. Comick and ~5 other sources would be unblocked.

### Keiyoushi extensions are Kotlin APKs — not usable in Yomi
The keiyoushi extension repo (`raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json`) lists 1000+ extensions but they are Kotlin `.apk` files compiled for Android/JVM. Tachimanga runs them via its embedded JVM. Yomi cannot load them. Do not attempt Kotlin extension compatibility — it requires bundling a JVM runtime which is impractical for App Store distribution.

### Tachimanga premium paywall — our opportunity
Many features Tachimanga charges for, Yomi provides free: OLED mode, app lock (planned S41), notes (planned S41), tracking (MAL already free), tab reordering (planned S41). The paywall is a genuine user pain point (visible in App Store reviews). Yomi's "fully free" positioning is a real competitive differentiator worth highlighting in App Store description.

## Technical learnings — S76 simulator and mobile-mcp

### Two simulator instances with same model + OS cause divergent app data
Xcode and XcodeBuildMCP can each track a different UDID when multiple instances of the same simulator model exist (e.g., "iPhone 17 Pro iOS 26.3" created twice via Xcode → Devices). Each UDID has its own isolated sandbox, UserDefaults, SQLite database, and Keychain — app data is completely separate. Symptoms: different accent color, different library content, different settings between what Xcode shows and what automation tests.

**Fix:** `xcrun simctl list devices available` lists all UDIDs. Call `mcp__XcodeBuildMCP__session_set_defaults` with `simulatorId: "UDID"` and `persist: true` — this writes to `.xcodebuildmcp/config.yaml` in the project root and survives session restarts. Confirm Xcode's active device in the scheme selector matches the same UDID.

### mobile-mcp cannot tap SwiftUI List `.onTapGesture` rows
SwiftUI `List` rows that use `.onTapGesture` for navigation render as `StaticText` accessibility elements with `custom_actions` (e.g. "Download", "Read", "Mark previous"). `mobile_click_on_screen_at_coordinates` fires a direct tap, which iOS routes to the `StaticText` default action — none. The tap is silently ignored.

`Button`-wrapped rows (e.g. novel chapter rows) DO respond correctly to coordinate taps since they render as `Button` accessibility elements with a default action.

**Workaround:** use `mobile_list_elements_on_screen` to identify element type. If `StaticText` with `custom_actions`, the row cannot be tapped via automation — verify via code review or physical device instead.

### XcodeBuildMCP `session_set_defaults` with `persist: true` survives restarts
Writing session defaults with `persist: true` saves to `.xcodebuildmcp/config.yaml` (project root). This file is loaded automatically on every Claude Code session start — no need to call `session_show_defaults` + `session_set_defaults` at session open if the config exists and is correct.

## Technical learnings — S37

### CancellationError must always be caught before the general catch
When a SwiftUI `.task {}` modifier is cancelled (e.g., user switches away from the tab before the task completes), Swift throws `CancellationError`. Any `do { } catch { }` block that doesn't explicitly handle `CancellationError` will treat it as a real failure and set error state. Pattern: always add `catch is CancellationError { isLoading = false }` BEFORE the general catch block in any async fetch function used by `.task {}`.

### Stable IDs for Browse-created model objects
When constructing model objects in Browse (not from DB), never use `UUID().uuidString` for IDs. A new UUID is generated every time `loadContent()` is called, so the same novel/manga gets different IDs on each Browse visit. Use deterministic IDs derived from the path: `"\(sourceId)_\(path)"`. This allows DB lookups to succeed on re-entry and chapter read state to persist.

### guard let ext else { return } without state cleanup is a hidden failure
`guard let ext else { return }` that fires mid-function (after the spinner was started, or before it was started) leaves UI in an inconsistent state — spinner stuck, empty content, no error message. Always include `isLoadingChapters = false` (or equivalent) in the guard's else branch before returning.

### GRDB reads from MainActor must use Task.detached
CLAUDE.md rule reconfirmed: `appDatabase.read { }` from `@MainActor` context blocks the main thread. Any `try?` synchronous call to `*Queries` methods inside `.task {}` or `.onAppear {}` should be wrapped in `Task.detached(priority: .userInitiated)`. Library loads (MangaQueries.fetchLibrary etc.) called synchronously in LibraryViewModel.loadLibrary() work in practice but are technically incorrect — deferred fix.

## Technical learnings — S35

### Source removal protocol: research before removing
When a source returns 403 or empty results, **do not remove it from the catalog immediately.** A 403 can have multiple causes:
- **Permanent Cloudflare block** (comick, lightnovelpub): URLSession always blocked as non-browser. Source never works.
- **Temporary security incident** (novelfire, S35): Site under attack, returns 403 during the incident window. Source will recover.
- **Site downtime / DNS issue**: Transient, resolves on its own.

**Protocol before removing any source:**
1. Check the source's home page via WebFetch — look for a status banner or notice.
2. Search the source's social media / Reddit / Discord for recent announcements.
3. If confirmed temporary, mark the source in `index.json` with a note and wait. Only remove if it's confirmed permanent (site dead or permanently Cloudflare-blocked as policy).

**Applied lesson (S35):** NovelFire was removed from index.json after observing Cloudflare 403. The correct action was to first check their site — they had posted a public security notice about an active attack. The source should be restored once the incident resolves.

### JSContext vs WKWebView for plugin execution
JSContext runs in the same process as the host app. iOS sandbox **disables JIT compilation** for same-process JS. WKWebView runs in a separate process with JIT enabled (12–15x faster for JS execution). However, WKWebView **suspends when not on screen** — any hidden off-screen WKWebView used for plugin execution will be suspended during background update checks, breaking UpdatesViewModel. JSContext's DispatchSemaphore synchronous model is also incompatible with WKWebView's async-only bridge. **JSContext is the correct choice for Yomi's current architecture.**

### Targeted WKWebView fallback for JS-rendered content
Some novel source pages (e.g., NovelFire synopsis) are rendered by client-side JavaScript after initial HTML load. `URLSession` + HTML parsing cannot capture dynamically injected content. Solution: add `requiresWebView: true` metadata flag to specific Format B plugins. JSBridge detects this flag and uses a hidden `WKWebView` to load the detail page, inject JS to extract rendered content, then return the result. This is a narrow escape hatch — does NOT change the general plugin execution model, which stays in JSContext.

### Aidoku source format (.aix / Rust WASM)
Aidoku community sources are written in **Rust**, compiled to WASM via `cargo build --target wasm32-unknown-unknown`. The `aidoku-rs` crate provides the `Source` trait and `register_source!` macro. Sources are distributed as `.aix` packages containing the compiled `.wasm` binary. Aidoku embeds a WASM runtime to execute them. This architecture provides true memory sandboxing and AOT performance, but requires plugin authors to know Rust and the `aidoku-cli` toolchain. Not viable for Yomi at current scale.

### Paperback plugin shim — what S24 built vs. what's missing
S24 implemented `require('paperback-extensions-common')` in the JSBridge cache, injecting a `Source` base class and `App` constructors. `injectPaperbackAdapter()` detects if a `Source` subclass was registered in `exports` post-eval, and wires `getMangaList/searchManga/getChapterList/getPageList` adapters. **What S37 must complete:** Paperback's HTTP layer uses `requestManager.schedule(request, 1)` which creates a `Request` object before executing. The shim must intercept `request.url`, `request.headers`, and `request.method` and route to `SOURCE._fetchSync`. Many real Paperback sources use this pattern — without it, they throw at runtime.

### iOS 26 app icon: 3-layer Liquid Glass format
Starting iOS 26, app icons require three transparent PNG layers (Background, Midground, Foreground) plus 6 visual modes (Default, Dark, Clear Light, Clear Dark, Tinted Light, Tinted Dark). The system composites them in real-time. **Icon Composer** (bundled with Xcode 26) handles layer import and preview. The `UIApplication.setAlternateIconName()` API is unchanged — alternate icon sets follow the same 3-layer structure. Backward compatible: older OS falls back to single-image assets.

## Technical learnings — S29

### Auto-mark read: race condition between onDisappear write and onAppear read
`ChapterReaderView.onDisappear` writes to DB (markChapterRead). Parent `MangaDetailView.onAppear`
fires simultaneously and reads DB (refreshChapterStates). The parent wins the race before the write
settles → UI shows chapter still unread.

Fix: don't rely on `onAppear` for post-read refresh. Instead, use `.onChange(of: chapterForNav)`:
```swift
.onChange(of: chapterForNav) { old, new in
    guard new == nil, old != nil else { return }
    Task {
        try? await Task.sleep(for: .milliseconds(500))
        await refreshChapterStates()
    }
}
```
500ms delay lets the onDisappear Task.detached write settle before the parent reads.
The `guard new == nil, old != nil` condition fires exactly once: when the user returns from the reader.

### SwiftUI overlay animation: opacity vs if-gating
`if showOverlay { topBar }` removes the view from the hierarchy when overlay hides. SwiftUI cannot
animate the disappearance of a removed view — the fade-out never plays.

Fix: keep views in the hierarchy and animate opacity:
```swift
VStack { topBar; Spacer(); bottomBar }
    .opacity(showOverlay ? 1 : 0)
    .allowsHitTesting(showOverlay)
    .animation(.easeInOut(duration: 0.2), value: showOverlay)
```
`.allowsHitTesting(false)` when hidden prevents invisible buttons from intercepting taps.

### JSBridge optional plugin functions
Pattern for calling plugin functions that may not exist:
```swift
nonisolated var supportsLatest: Bool {
    guard let fn = context.objectForKeyedSubscript("getLatestManga") else { return false }
    return !fn.isUndefined && !fn.isNull && fn.isObject
}
```
Call site: `guard supportsLatest else { return [] }`. This makes features optional per-plugin
without crashing. Sources without `getLatestManga` get `supportsLatest = false` and no picker is shown.

### Bridge reuse across tab switches
Creating a new `JSBridge` parses and evaluates the full JS file — expensive (10–50ms depending on
plugin size). When switching between Popular/Latest tabs in `SourceBrowseView`, reuse the existing
bridge instead of creating a new one:
```swift
let b: JSBridge
if let existing = bridge { b = existing } else { b = try makeBridge(); bridge = b }
```

### Incognito mode: skip persistence at DB write site
Read the flag at the earliest possible point before any DB write, not in the view layer:
```swift
let incognito = AppSettings.shared.isIncognito
// ...
guard !incognito else { return }
markChapterRead()
updateProgress()
```
Single guard covers all persistence. No changes needed in the query layer.

### navigationDestination(item:) requires Hashable
`navigationDestination(item: $chapterForNav)` where `chapterForNav: Chapter?` requires `Chapter`
to conform to `Hashable`. The fix is one line:
```swift
struct Chapter: Identifiable, Codable, Hashable { ... }
```
SwiftUI synthesizes `Hashable` automatically from all stored properties (which are all Hashable types).

## Technical learnings — S28 (audit)

### INSERT OR IGNORE is mandatory for chapter list persistence
`MangaDetailView.loadChapters()` fetches chapters from JSBridge but never calls any INSERT.
Every subsequent SQL UPDATE (`markRead`, `markDownloaded`, `updateProgress`) silently affects 0 rows
because the chapter row doesn't exist. This is the root cause of both the "downloads not showing"
and "read state not persisting" bugs reported in S26 and S27.

Fix pattern:
```swift
nonisolated static func insertAllIgnoringConflicts(_ chapters: [Chapter]) throws {
    _ = try appDatabase.write { db in
        for ch in chapters { try ch.insert(db, onConflict: .ignore) }
    }
}
```
Call in `loadChapters()` AFTER fetching from JSBridge, BEFORE the DB merge step.
**Never use `chapter.save(db)` or `chapter.insert(db)` alone for chapter list persistence.**
`save()` is INSERT OR REPLACE — it overwrites existing isRead/isDownloaded/progress state.
`insert()` throws on conflict. Only `.insert(db, onConflict: .ignore)` is safe: inserts new rows,
skips existing ones without touching their state.

### @Observable DownloadManager.completedDownloadCount pattern
To propagate download completion to views that aren't the active download target, add an observable
Int counter to DownloadManager that increments after each successful download. Views observe via
`.onChange(of: downloadManager.completedDownloadCount)` and call their refresh function. This avoids
NotificationCenter and keeps the reactive chain entirely in SwiftUI observation.

### refreshChapterStates() — lightweight DB merge without JSBridge
When a view needs to reflect DB state changes (download complete, read state change) without
re-fetching the full chapter list from the network, use a merge function that:
1. Fetches all chapters for the manga from DB (one SQL query)
2. Builds a Dictionary<String, Chapter> keyed by id
3. Maps in-memory chapters: if savedMap[ch.id] exists, copy isRead/isDownloaded/progress/lastPageRead/readAt

This pattern is safe to call on .onAppear without causing a network fetch.

## Technical learnings — S27

### Chapter progress resume: lastPageRead vs progress ratio
Two strategies for reading resume:
- `progress: Double` — fractional position 0.0–1.0. Used for MAL tracking and webtoon scroll.
- `lastPageRead: Int` — exact page index. Used for manga chapter resume.

Using a page ratio to derive an index introduces floating-point drift (a 47-page chapter at
progress 0.6 gives page index 27.6 → 27 or 28 depending on rounding). Use `lastPageRead`
for exact resume when the chapter has been partially read and the page count is known.
Fallback: if `lastPageRead == 0` and `progress > 0`, use ratio calculation as legacy fallback.

### Source filter re-trigger pattern in search views
When a search view has both a text query and a source picker, the source change must immediately
re-trigger the search. Extract the search logic into a shared function `runSearch(query:debounce:)`
that both `.onChange(of: searchQuery)` and `.onChange(of: selectedSource)` call. Source changes
should use `debounce: false` to avoid unnecessary delay — the user already made a deliberate choice.

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

## S31 — Technical learnings

- **INSERT OR IGNORE pattern is mandatory for chapter persistence**: using `chapter.save(db)` (INSERT OR REPLACE) would overwrite `isRead`, `readAt`, and `readingSeconds` on every fetch from the source — silently resetting reading progress. Always use `chapter.insert(db, onConflict: .ignore)` in batch persist flows. After the INSERT OR IGNORE, re-fetch the full set from DB to merge the existing state back into the in-memory array.

- **`Column` is a GRDB type — import GRDB in any file that uses it**: TextReaderView originally tried to write `Column("id")` directly in the view. This doesn't compile — `Column` lives in GRDB which the view doesn't import. The fix is to push all DB write logic into the matching `*Queries.swift` file (`NovelQueries.addReadingTime`) and call the typed method from the view. Never import GRDB in views.

- **NovelChapter must be Hashable for `navigationDestination(item:)` to work**: SwiftUI's `navigationDestination(item:)` overload requires the item type to be `Hashable`. Adding `Hashable` conformance to `NovelChapter` (and `NovelReaderDest` structs with UUID-based hashing) unlocks type-safe navigation without isPresented bool gymnastics.

- **JSBridge destinations in navigation structs need custom Hashable**: `JSBridge` is a `final class` that is not `Hashable`. When embedding it in a navigation destination struct, implement `Hashable` via UUID: `let id = UUID()` + `static func ==` + `func hash(into:)` that only hash the UUID. This gives each navigation event a unique identity without requiring JSBridge itself to be hashable.

- **Novel updates need path-based deduplication, not ID-based**: manga chapter IDs are assigned by the source (stable). Novel chapter IDs are synthesized locally as `"\(novelId)-ch-\(index)"`. When checking for new chapters, compare by `path` (source-assigned, stable) not by local ID. The new-chapter detection in `checkNovelUpdates` correctly uses `Set(localChapters.map { $0.path })` and filters `source.chapters` by path.

- **SourceKit diagnostics are always noise in a multi-file Swift project**: every session, SourceKit emits "Cannot find type X in scope" for types defined in other files. These are false positives from single-file LSP analysis. The rule is absolute: ignore all SourceKit errors, trust only `xcodebuild` output. Confirmed this session — BUILD SUCCEEDED with dozens of SourceKit errors still active.

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

- **Firebase Hosting as plugin CDN**: project yomi-plugins, live at https://yomi-plugins.web.app. `index.json` + `.js` files in `~/Projects/Yomi/Firebase/public/`. Deploy: `cd ~/Projects/Yomi/Firebase && firebase deploy --only hosting`. Firebase folder lives outside the Xcode repo (`~/Projects/Yomi/Firebase`) — not committed to git.

- **esbuild IIFE for JSContext**: `format: 'iife'`, `bundle: true`, `platform: 'browser'`, `target: 'es6'`. Output is a self-contained JS file with no `import`/`require` statements — directly evaluatable by `JSContext.evaluateScript()`.

## S17 — Technical learnings

- **api.asurascans.com requires Origin + Referer headers**: Cloudflare blocks requests without these headers. Every `SOURCE.fetch` call in asurascans.js must include `{ headers: { "Origin": "https://asurascans.com", "Referer": "https://asurascans.com/" } }`. Without them, the API returns 403 or an empty response.

- **asurascans chapterPath format**: `"{seriesSlug}/{chapterSlug}"` — split on first `/` to get both components. `getChapterList` builds it as `mangaPath + "/" + ch.slug`. `getPageList` splits it to call `/api/series/{seriesSlug}/chapters/{chapterSlug}`. Pages are in `json.data.chapter.pages[].url`.

- **asurascans getMangaList endpoint**: `GET /api/search?page={page}&order=popular` (not `/api/series`). Chapter list pagination via `GET /api/series/{slug}/chapters?limit=100&page={page}`, loop while `json.meta.has_more === true`.

- **DateComponents is Hashable in Foundation**: `Set<DateComponents>` works without any custom conformance. Used in InsightsView streak logic to collect distinct calendar days where reading occurred. No need for a custom wrapper type.

- **Streak logic — check yesterday if today is empty**: streak should not reset if the user hasn't read yet today but read yesterday. Pattern: count consecutive days starting from today; if streak == 0, restart count from yesterday. This preserves the streak through the morning before the user opens the app.

## S16 — Technical learnings

- **seedBundledPlugins skip logic is a deployment trap**: the `fileExists` check that skips copying bundled JS files means simulator never picks up JS fixes after the first install. Rule: bundled plugins must always be overwritten on launch (`removeItem` then `copyItem`). Safe because bundled plugins are read-only source-of-truth — only network-installed plugins should be preserved.

- **cheerio shim each() contract (updated S46)**: the Yomi cheerio shim now matches real cheerio — `each`/`map` pass `(index, rawDOMNode)` to callbacks. Plugin code can do `$(node)` inside the callback to wrap it. The `$()` selector function detects raw nodes via `selector.type` property and wraps them. **Old behaviour (pre-S46)**: the shim passed `(index, wrappedCheerioObject)` — this broke any plugin that did `$(t).find(...)` inside `.each()`. The root cause: real cheerio's `.each()` passes the raw DOM element as `this` and second arg; calling `$(rawNode)` is the standard pattern. Always match real cheerio's contract.

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
- **cheerio `.each` callback (updated S46 — matches real cheerio)**: the Yomi shim now passes `(index, rawDOMNode)` to `.each()` callbacks, matching real cheerio. `$(node)` wraps it. The pre-S46 shim passed wrapped objects — this broke plugins that called `$(t).find(...)` inside `.each()`. See S46 entry for the fix.
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

## S32 — Technical learnings (2026-04-14)

- **ContinueReadingRow mixed-type pattern**: use a private `enum ContinueItem { case manga(Manga); case novel(Novel) }` with `var lastReadAt: Date?` computed property to merge and sort heterogeneous types in a single `[ContinueItem]` array. Fetch both in parallel `Task.detached`, merge, sort, take prefix(10).
- **LibraryViewModel status filter**: add `var statusFilter: ReadingStatus? = nil` and apply after category filter in `displayedManga`: `let base = statusFilter == nil ? categoryFiltered : categoryFiltered.filter { $0.readingStatus == statusFilter }`. Tapping the active chip again toggles it off (nil).
- **Novel category join table mirrors manga_category exactly**: same `category` table shared between manga and novels. Methods: `assignNovel/unassignNovel/categoriesForNovel/novelIds(inCategory:)` in CategoryQueries. No separate category table needed.
- **PluginCatalogService TTL pattern**: `private var lastFetchedAt: Date?` + `fetchCatalog(force: Bool = false)`. Guard: `if !force, !entries.isEmpty, let last = lastFetchedAt, Date().timeIntervalSince(last) < ttl { return }`. Pull-to-refresh callers pass `force: true`. All `.onAppear`/`.task` callers get TTL for free.
- **BackupManager v2 format**: `"version": 2` with `novels`, `novelChapters`, `novelCategories` arrays added. Import is backwards-compatible: v1 backups (missing novel keys) fall back to empty arrays via `?? []`. Novel chapters use `insertAllIgnoringConflicts` (INSERT OR IGNORE) on restore — safe, preserves existing read state.
- **NovelDetailView toolbar refactor (S32)**: replaced single heart `Button` with `Menu { ... }` (ellipsis.circle) containing library toggle + category sheet trigger. Matches MangaDetailView overflow menu pattern. Category sheet disabled when `!isInLibrary`.
- **App Store age rating 2026**: old 17+ system replaced by 4+/9+/13+/16+/18+. Yomi targets **18+**. Must update questionnaire in App Store Connect before submission.
- **Deep research saved to memory**: `research_competitive.md` + `research_ux_appstore.md` in Claude memory. Do not re-research Mihon/Tachimanga/LNReader/Paperback/App Store/UX unless explicitly asked.

## S33 — Technical learnings (2026-04-14)

- **ReadingStatus for novels — reuse existing enum, no new types needed**: `ReadingStatus` enum (defined in `Manga.swift`) is shared between manga and novels. Add `readingStatus: ReadingStatus` to `Novel.swift`, update the GRDB extension in `DatabaseManager.swift`, add `updateReadingStatus(novelId:status:)` to `NovelQueries.swift`. All six construction sites for `Novel(...)` must add `readingStatus: .none`. Pattern: migrate the column as `NOT NULL DEFAULT 'none'` (not nullable) — consistent with how manga handles it.
- **Private struct visibility across files**: `private struct ReadingStatusMenu` in `MangaDetailView.swift` is invisible to `NovelDetailView.swift` even in the same module. Remove `private` to make it `internal` (module-level accessible). The struct only uses types from the same module so there are no dependency issues. Any reusable component expected to be used by ≥2 views should not be `private`.
- **Library chip row guard for mixed-type libraries**: the status chip row was gated on `!viewModel.mangas.isEmpty`. With novels also needing the filter, change guard to `!viewModel.mangas.isEmpty || !viewModel.novels.isEmpty`. The same `statusFilter: ReadingStatus?` drives both `displayedManga` and `displayedNovels` — a single toggle filters whichever section the user has.
- **Firebase deploy flow after auth expiry**: `firebase deploy` fails silently (or with auth error) when the session has expired. Run `firebase login --reauth` first, then `firebase deploy --only hosting`. Both commands must be run from the `~/Desktop/Yomi\ 2.0/yomi-firebase` directory.

## S32 — LNReader plugin compatibility gaps (researched 2026-04-14)

The LNReader adapter in `JSBridge.swift` (`injectLNReaderAdapter`) is production-ready. Known gaps documented below — no code change needed unless a specific new plugin fails.

**Gap 1 — `latestUpdates` not called by UpdatesView**
The adapter wraps `plugin.latestUpdates` into a synchronous form, but `UpdatesView` does not call it. It checks for new chapters by calling `bridge.parseNovel(path:)` and comparing the returned chapter list against the DB. `latestUpdates` would be more efficient (returns a lightweight list), but `parseNovel` is more reliable since it also refreshes all chapter metadata. Future optimization: use `latestUpdates` as a fast pre-check before deciding whether to call `parseNovel`.

**Gap 2 — `plugin.options` not surfaced in UI**
`popularNovels(pageNo, options)` receives `options` from Swift as `undefined`. Some LNReader plugins use `options` to filter by genre, language, or sort order (e.g., `options.genres`, `options.sortedBy`). These filter capabilities are silently ignored — the user always gets the default list. Future work: expose a genre/sort picker in `BrowseView` for novel sources that declare options, and pass the selected values through the bridge.

**Gap 3 — Cloudflare blocks WuxiaWorld and WebNovel**
`SOURCE.fetch` uses a realistic iPhone Safari `User-Agent` and standard headers, but does not execute JavaScript or solve Cloudflare challenges. Sites with Cloudflare bot protection (WuxiaWorld, WebNovel) will return 403 or a JS challenge page instead of HTML. These sources are not viable with the current HTTP-only fetch model. Viable novel sources: Royal Road, ScribbleHub, NovelFire, LightNovelPub, NovelBin, FreeWebNovel.

## S34 — Technical learnings (2026-04-15)

- **FreeWebNovel chapter links use `class="con"`, not a list**: the detail page doesn't have a `<ul#chapter-list>` element. Chapter links are bare `<a href="/novel/title/chapter-N" class="con">` anchors. Correct selector: `a.con`. Filter to `/novel/` href to avoid matching unrelated links.
- **NovelBin `data-novel-id` is a text slug, not a numeric ID**: the regex `/data-novel-id=['"](\d+)['"]/` only captures digits. NovelBin embeds the novel slug (e.g., `martial-peak`) as the ID. Fix: use `/data-novel-id=['"]([^'"]+)['"]/` to capture any non-quote character sequence.
- **Custom cheerio shim `parseSimple` only captures one `.class` per selector segment**: e.g., `div.chapter-list.active` would only capture `chapter-list`, ignoring `active`. However, `matchesSimple` correctly checks multi-class nodes by splitting the node's class attribute by whitespace — so `div.chapter-list` matches `<div class="chapter-list active">`. The limitation is in writing selectors, not in matching.
- **Double SOURCE.fetch() inside parseNovel is safe**: two sequential `SOURCE.fetch()` calls within the same JS function work correctly. Each creates its own `DispatchSemaphore`, waits on the URLSession background thread callback, then proceeds. Since JSBridge runs inside `Task.detached(priority: .userInitiated)`, the semaphore wait does not block the main thread.
- **NovelFire synopsis may not match expected selectors**: `h1.novel-title` parses correctly but `div.summary` and `strong.ongoing` have been reported as empty. Root cause unconfirmed — could be dynamic content (JS-rendered on the real site but not returned by `SOURCE.fetch`), or an HTML structure difference. Fix: add multiple fallback selectors (`div.novel-synopsis`, `section.summary`, `div.description`) and a text-based fallback for status.
- **UpdatesView inserts ALL remote chapters, not just new ones**: after filtering `newChapters = remoteChapters.filter { !localIds.contains($0.id) }`, the code must insert `newChapters`, not `remoteChapters`. Inserting all chapters with INSERT OR IGNORE is non-destructive (won't overwrite read state) but wasteful for large chapter lists (e.g., 1000+ chapters).
- **Task.detached priority should always be explicit**: `Task.detached { }` without a priority inherits unspecified priority. Use `.background` for DB writes that don't need to be fast (marking read on navigation), `.userInitiated` for anything blocking UI load.
- **NovelFire chapters URL needs `?page=1`**: the chapters endpoint is paginated (`/book/{slug}/chapters?page=N`). Without `?page=1`, the default response format may differ. Always pass page number explicitly.
- **Removing dead/blocked plugins from catalog**: comick (Cloudflare, api.comick.dev returns 403), lightnovelworld (site permanently dead), lightnovelpub (Cloudflare). These were removed from `index.json` to keep the catalog clean. The JS files remain in Firebase for users who have them cached, but new installs won't see them.
- **NovelCoverCell AsyncImage should use phase-based initializer**: the two-closure `AsyncImage(url:content:placeholder:)` uses the same placeholder for both loading and error states. Use the phase-based `AsyncImage(url:content:)` with a `switch phase` to distinguish `.success` from other states. More importantly, use consistent aspect ratio in both success and placeholder branches to prevent grid row height instability (cells shifting when images load).
- **LazyVGrid bottom padding**: grids in `SourceBrowseView` had `.padding(.top, 8)` but no `.padding(.bottom)`. Add `.padding(.bottom, 8)` to prevent the last row from appearing flush against the bottom edge.
- **MainActor @State accessed inside Task.detached**: capturing `self.selectedFeed` (a `@State` property, therefore MainActor-isolated) inside `Task.detached` generates a Swift concurrency warning. Fix: capture the value in a local `let` before entering the task: `let currentFeed = selectedFeed`.
- **Sorting inside Task.detached can warn on struct properties**: sorting an array of enum cases (e.g. `HistoryItem`) by a struct property (e.g. `manga.lastReadAt`) inside `Task.detached` generates "Main actor-isolated property can not be referenced from a nonisolated context" in Xcode 26, even though the struct is not explicitly @MainActor. Fix: do the sort inside `await MainActor.run { }` after the Task.detached returns — sorting by Date is lightweight, there's no performance cost.
- **`try? funcReturningNonVoid()` produces unused-expression warning**: `try? CategoryQueries.insert(name:)` where `insert` returns `Category` evaluates to `Category?` which is then silently discarded. Xcode shows "Expression of type 'Category?' is unused". Fix: prefix with `_ = try? ...` to explicitly discard the result.
- **Chapters empty from Browse but work from Library**: when a novel source's `parseNovel()` returns empty chapters, the Library still shows chapters because they were previously persisted to DB and `NovelQueries.fetchChapters` returns the DB rows. From Browse, a transient Novel object (UUID id) is created and chapters depend entirely on `parseNovel()` returning data. Fix: repair the plugin's `parseNovel` selectors, then deploy to Firebase and reinstall.
- **Installed plugins are not auto-updated**: plugins installed by the user live in `Documents/Extensions/`. Removing a plugin from `index.json` (catalog) does not auto-uninstall it. User must manually uninstall via the Extensions tab. Stale/dead plugins (like LightNovelWorld) remain installed until the user removes them.

## S61 — Technical learnings (2026-05-05)

- **`@ViewBuilder` computed property for banner overlays**: extracting `chapterFinishedBanner` into a `@ViewBuilder` computed property keeps `body` readable and avoids Swift type-checker timeout from deeply nested conditionals. Use `if showBanner { bannerView }` in body and let the computed property hold all the layout/styling details.
- **Spring animation for bottom-edge banners**: `.move(edge: .bottom).combined(with: .opacity)` with `withAnimation(.spring)` gives a natural "slides up" entry. `.easeInOut` reads as mechanical; spring conveys liveness without specifying stiffness. Match the dismiss animation to `.easeOut(duration: 0.25)` — snappier exit vs entrance.
- **`onAppear` Task for auto-dismiss — not Timer**: `.onAppear { Task { try? await Task.sleep(for: .seconds(5)); withAnimation { show = false } } }` is idiomatic SwiftUI. `Timer.scheduledTimer` requires explicit invalidation and is harder to cancel on navigation; the `Task` inherits the view's lifetime and cancels when the view disappears if the view goes away before the sleep completes.
- **Banner always shows even in incognito**: `showFinishedBanner = true` is unconditional. Only the DB write (`NovelQueries.markRead`) is incognito-guarded. The banner is ephemeral in-memory UI state — showing it records nothing. Conflating "no persistent write" with "no UI feedback" would degrade UX for incognito readers.
- **`navigateToChapter` must reset all ephemeral display state**: `showFinishedBanner = false`, `lastKnownScrollPercent = nil`, and any other view-local flags must be cleared in `navigateToChapter`. If any flag survives chapter navigation it will appear on the new chapter with stale context — a class of bug that only surfaces after reading two chapters consecutively.

## S60 — Technical learnings (2026-05-05)

- **`scrollY / (scrollHeight - innerHeight)` not `scrollY / scrollHeight`**: `scrollHeight` is the total document height; `innerHeight` is the viewport height. The maximum `scrollY` is `scrollHeight - innerHeight`, not `scrollHeight`. Using `scrollHeight` as the denominator gives a max ratio of ~0.85 on a typical chapter (the last viewport-worth of content is unreachable by scrolling), making the progress bar never reach 100% and scroll restoration undershoot. Always use `var maxScroll = scrollHeight - innerHeight; pct = maxScroll > 0 ? scrollY / maxScroll : 0`.
- **`WKNavigationDelegate.didFinish` fires before layout is complete for long HTML**: JS `window.scrollTo(0, pct * maxScroll)` called in `didFinish` may execute before the document body has reached its full rendered height — `scrollHeight` is still 0 or equal to `innerHeight`. Guard: only restore if `maxScroll > 0`. For very long chapters, a short delay (~100ms) after `didFinish` before calling `scrollTo` improves accuracy; for average chapters it's fine without.
- **`ScrollViewReader` wrapping a `List` works for programmatic scrollTo**: `proxy.scrollTo("ch_<id>", anchor: .center)` correctly scrolls a `List` to a `ForEach` item tagged with `.id("ch_<id>")`. The `ScrollViewReader` must be the ancestor of the `List` (not inside it). A 300ms delay after the data loads (via `Task.sleep`) is necessary to allow the `List` to finish rendering rows before the scroll fires — without it, the scroll no-ops because the target row doesn't exist yet in the view hierarchy.
- **Progress bar in `List` rows via `GeometryReader`**: `GeometryReader { geo in Capsule().frame(width: geo.size.width * pct, height: 2) }.frame(height: 2)` is the correct pattern. The outer `.frame(height: 2)` constrains the `GeometryReader`'s infinite-height default. The capsule aligns to leading by default inside `GeometryReader`. Cap `pct` with `min(pct, 1)` to handle any floating-point values slightly above 1.0.
- **`hasRestored` flag prevents double-scroll on CSS re-inject**: `updateUIView` re-injects the `<style>` block when font/theme changes, which can trigger another `didFinish`. The `hasRestored: Bool` flag on the coordinator ensures the restore scroll only fires once per chapter load (coordinator is fresh per chapter since `ReaderWebView` is destroyed on `isLoading` toggle).
- **Chapter state refresh pattern**: after the reader closes, DB writes (markRead, updateScrollPercent) take ~100–300ms to flush from their `Task.detached` contexts. Re-fetching chapters immediately after the reader dismisses returns stale data. A 500ms `Task.sleep` before `refreshChaptersFromDB()` in `onChange(of: chapterForNav)` gives DB writes time to settle. `MangaDetailView` uses the same pattern — always mirror it when adding a `refreshChapterStates` equivalent to any detail view.
- **`.refreshable` on `List` inside `ScrollViewReader`**: works correctly — SwiftUI passes the pull gesture through `ScrollViewReader` to the `List`. No special handling needed. Any `List` that has a corresponding `loadX()` async function should have `.refreshable { await loadX() }` — this is the expected iOS pattern for force-refresh.

## S59 — Technical learnings (2026-05-04)

- **`.task` + `onAppear` paths are secondary incognito leak surfaces**: S57 audited primary paths (onDisappear, chapter-finish handlers). Secondary path `NovelDetailView.touchLastReadAt()` — called from `.task` on view appear — was not guarded and wrote `lastReadAt` to DB even in incognito. Any code path that writes reading state, even lightweight "I opened this item" writes, must check `AppSettings.shared.isIncognito`. Secondary paths are easiest to miss because they're not labelled as "read tracking" in the code.
- **`CodingKeys` exclusion as a format-tagging mechanism**: `PluginCatalogEntry.isNovel` is not present in any catalog JSON format (Yomi native, LNReader, Mangayomi). Excluding it from `CodingKeys` means it always decodes as its default value (`false`), then the specific parser path (`LNReaderEntry.toEntry()`) sets it to `true` after construction. This is a clean way to attach out-of-band metadata that cannot be derived from the JSON schema alone — no need for a separate type or a post-decode transform pass.

## S58 — Technical learnings (2026-05-04)

- **GRDB `init(row:)` + `encode(to:)` must be audited after every migration**: `v15_novel_notes` added a `notes` column to the `novel` table, but `Novel.init(row:)` and `encode(to:)` were never updated. `NovelQueries.updateNotes` used targeted `updateAll(Column("notes").set(to:))` SQL and worked for writes, but every `fetchLibrary()`/`fetchAll()` returned novels with `notes = nil`, silently discarding user data. The next session's decode would overwrite whatever was in the DB. Rule: whenever a migration adds a column, immediately update both `init(row:)` (decode) and `encode(to:)` (encode) in the same commit.
- **Custom cover propagation checklist**: Adding a `customCoverPath` field requires updating every view that renders a cover image, not just the detail view. Full list for Yomi: `MangaDetailView`, `NovelDetailView`, `MangaCoverCell` (grid), `MangaListRow` (list), `NovelLibraryCoverCell` (grid), `NovelLibraryListRow` (list), `HistoryRow`, `ContinueReadingRow` (manga card), `ContinueReadingRow` (novel card), `MangaUpdateHeader`, `NovelUpdateHeader`. Widget (`WidgetDataWriter`) correctly omits custom covers — widget process can't access the app's Documents directory without explicit App Group copying.
- **Swift type-checker timeout**: adding conditional branches + computed values inside a large `var body` can exceed Swift's type inference timeout ("unable to type-check in reasonable time"). Fix: extract large sections into `@ViewBuilder` computed properties (`headerSection`, `chaptersSection`, etc.) or standalone `@ViewBuilder func`s. Also, never put `let` computed bindings inside `ToolbarItem` content — move them to view-level computed properties.
- **Lightweight plugin format detection**: determining whether a JS plugin is LNReader (novel) or manga does not require JSBridge/JSC evaluation. The string `"popularNovels"` appears only in LNReader plugins. `(try? String(contentsOf: url)).contains("popularNovels")` in a `.task(id:)` is sufficient and fast (~1 ms per file). Used for Novel/Manga format badges in `ExtensionRow` and `InstalledExtensionRow`.
- **`onLongPressGesture` + `swipeActions` coexist fine**: `List` rows can have both `.swipeActions` and `.onLongPressGesture`. Long-press triggers the gesture recognizer before any swipe motion. In selection mode, swipe actions are suppressed via an `if !isSelectingChapters` guard inside the `swipeActions` block.

## S57 — Technical learnings (2026-05-04)

- **Incognito leaks hide in secondary code paths**: The primary read/write paths (ChapterReaderView.onDisappear, TextReaderView.flushReadingTime) had correct isIncognito guards. The leaks were in secondary paths: `touchLastRead()` (called on `.task` at MangaDetailView appear), `onReadComplete` (JS callback on 90% scroll), and both readers' `navigateToChapter` (which marks the *departing* chapter read/saves progress before loading the next). Always audit every code path that writes reading state, not just the primary completion handler.
- **`withTaskGroup` + JSBridge = thread starvation risk**: `group.addTask { bridge.searchManga() }` runs on Swift cooperative thread pool threads. JSBridge uses `DispatchSemaphore.wait()` which blocks the thread. With N sources, N cooperative threads are blocked simultaneously. Fix: `group.addTask { await Task.detached(priority: .userInitiated) { bridge.searchManga() }.value }` — makes the blocking nature explicit and uses a dedicated thread rather than a cooperative pool thread.
- **`[String: Int?]` double-optional cache is valid Swift**: `AniListService` uses `var cache: [String: Int?]`. Dictionary subscript returns `Value?` = `Int??`. `if let cached = cache[title]` distinguishes three states: (a) key absent → outer nil → if-let fails → re-fetch; (b) key present, value nil → outer some, inner nil → if-let succeeds, cached = nil → return nil (failure cached, no re-fetch); (c) key present, value some → if-let succeeds, cached = score → return score. This is correct and idiomatic.
- **AppLock pattern**: `scenePhase == .background → isLocked = true` in YomiApp.onChange. `AppLockView.onAppear` triggers LAContext.evaluatePolicy immediately — no extra user tap needed. `canEvaluatePolicy(.deviceOwnerAuthentication)` covers both biometric and passcode, so the lock screen works even without Face ID enrolled.
- **mobile-mcp WebDriverAgent failure doesn't block code audit**: When WDA times out, fall back to: `mcp__XcodeBuildMCP__screenshot` for visual verification, `xcrun simctl launch <udid> <bundleid>` to relaunch, AppleScript `click at {x,y}` on the Simulator window for UI interaction (window at System Events → process "Simulator"). Code review catches more bugs per hour than UI automation when the codebase is the primary concern.

## S56 — Technical learnings (2026-05-03)

- **Guard early-return must always restore DB state**: `loadChapters()` had two exit paths. The first (API returns empty) was fixed with `if loadedChapters.isEmpty { chapters = saved }`. The second (extension not installed — `guard let ext`) returned immediately with `chapters = []` — DB never queried. Any `guard ... else { return }` that exits before a DB fetch must fetch from DB first. Pattern: `guard let ext else { let saved = await Task.detached { ChapterQueries.fetchAll(...) }.value; chapters = saved; return }`.
- **WKWebView "Restore scroll position" prompt**: iOS WebKit shows a system-level "Restore scroll position" affordance (green arrow, accessible via VoiceOver as StaticText) whenever scroll state was previously saved. Suppress it by injecting `if ('scrollRestoration' in history) { history.scrollRestoration = 'manual'; }` as a `WKUserScript` at `.atDocumentStart` or `.atDocumentEnd`. One line, no side effects.
- **Back button hit area vs WKWebView tap gesture**: the novel reader back button (20×22 pt) competes with the WKWebView `UITapGestureRecognizer`. `shouldRecognizeSimultaneouslyWith → true` means both fire. The back button succeeds if tapped at its center (26, 133) — exact left-edge taps miss. To fix properly: increase button tap area with `.contentShape(Rectangle().inset(by: -12))` or use a larger padding container.
- **Two plugins with the same display name is valid**: `com.yomi.novelbin` (Yomi Firebase, Format A) and `64a5417437b8f41aaed9eca60d4a52ce` (LNReader catalog, Format B) both show as "NovelBin" in Sources. They are genuinely different plugins targeting the same site. Not a bug — just a UX confusion. DB query `SELECT id, name FROM extension WHERE name = 'NovelBin'` confirmed both rows with distinct IDs.
- **Simulator text field input via mobile-mcp is unreliable for Form sheets**: `mobile_type_keys` does not reliably inject text into a `Form`-hosted `TextField` presented in a `.sheet`. Workaround: use `xcrun simctl pbcopy <device> <text>` to load the clipboard, then long-press the field to get the Paste menu. Or restore values directly by editing the binary plist (`~/Library/Developer/CoreSimulator/.../Library/Preferences/bundleId.plist`) with `plistlib` + `json.dumps().encode()` and relaunch.

## S55 — Technical learnings (2026-05-03)

- **API-empty ≠ source-has-no-chapters**: `MangaDetailView.loadChapters()` pattern was `chapters = loadedChapters.map { mergeWithDB($0) }` — if `loadedChapters = []` (network failure), the map produces `[]` and overwrites all DB chapters. Fix: `if loadedChapters.isEmpty { chapters = saved } else { ... merge ... }`. Always check if the API returned nothing before discarding DB state. `NovelDetailView` already handled this correctly (always re-fetches from DB after API call).
- **Haptic guard for programmatic page changes**: `onChange(of: currentPage)` fires for ALL `currentPage` mutations, including programmatic resets (`navigateToChapter` sets `pages = []` then `currentPage = 0`). Since `pages` is cleared before `currentPage`, guarding with `if pages.count > 0` correctly suppresses haptics during navigation resets. `.onAppear`/`.task` page restores still fire one extra haptic (acceptable, single occurrence).
- **Swipe-to-delete UX for installed extensions**: `PluginsView` uses `.onDelete { indexSet in extensionManager.remove(...) }` on a `ForEach` inside a `List`. In simulator, mobile-mcp swipe coordinates must target the row precisely — the accessibility tree x-coord shifts left when the row is swiped, confirming the gesture registered. Delete button at trailing edge: found via `list_elements_on_screen` after swipe, not by guessing coordinates.
- **Extension install/remove cycle is atomic**: Install taps button → JS file downloads → `ExtensionQueries.upsert` → `loadInstalled()` — list updates immediately. Remove swipes row → `extensionManager.remove(ext)` calls `ExtensionQueries.delete` + deletes JS file → `loadInstalled()` — catalog entry immediately reverts from checkmark back to Install button. No stale state observed.
- **SourceKit LSP errors are always noise**: Every file edit triggered "Cannot find type 'Manga'" etc. in SourceKit. These are cross-file dependency resolution failures in isolation mode — never signal a real build error. Only `mcp__XcodeBuildMCP__build_sim` output is authoritative.

## S54 — Technical learnings (2026-05-03)

- **Underline tab bar in SwiftUI**: replace capsule chips with a `VStack(spacing:0) { Text(...).padding() + Rectangle().fill(selected ? accentColor : .clear).frame(height:2) }`. Wrap in `ScrollViewReader` + give each tab an `.id("tab_\(cat.id)")`. Use `.onChange(of: selectedCategoryId)` to call `proxy.scrollTo(id, anchor: .center)` so the active tab always scrolls into view. Mark the "All" tab id as `"tab_all"` since `selectedCategoryId == nil` for it.
- **Horizontal swipe to change category on a vertical ScrollView**: use `.simultaneousGesture(DragGesture(minimumDistance:40).onEnded { ... })`. Guard `abs(translation.width) > abs(translation.height) * 1.5` to avoid triggering on diagonal scroll. Map `selectedCategoryId` to an index in `[nil] + categories.map { Optional($0.id) }` — `[String?]` equality works fine with Swift optional semantics.
- **Merging two filter rows into one Menu**: remove the second horizontal chip row for status filter and add it as a second `Section` inside the sort `Menu`. Use `Divider()` between sections. The menu icon should fill (`.fill` variant) when either sort is non-default OR status filter is active — combine into one `let active = sortOrder != .lastRead || statusFilter != nil` binding.
- **Bulk operations in multi-select**: capture `installed` from `ExtensionManager.shared.installed` on the caller's context (MainActor) BEFORE entering `Task.detached`. Inside the detached task, use the captured `[Extension]` array (a value copy, safe to read). Call `DownloadManager.shared.enqueue` after the await returns (back on MainActor). `ChapterQueries.markAllRead(mangaId:)` is `nonisolated` — safe to call in a detached task loop.
- **`UIImpactFeedbackGenerator` for page turn haptics**: create the generator inline at call site — `UIImpactFeedbackGenerator(style: .light).impactOccurred()` — no need to store it. Add to `onChange(of: currentPage)` before the existing logic.

## S53 — Technical learnings (2026-05-02)

- **Embedded JVM on iOS requires NSExtension process isolation, not just framework embedding**: Code App (thebaselab) does NOT simply embed the JDK as a framework in the main target. It runs the JVM in a separate sandboxed process via NSExtension, using XPC/IPC. This is a fundamentally different architecture that requires building an app extension, cross-process lifecycle management, and separate entitlements. Any plan to "embed OpenJDK frameworks" without accounting for this is missing the critical piece.

- **OpenJDK 8 is the only proven iOS App Store JVM — and Suwayomi has moved past it**: thebaselab/codeapp-java ships OpenJDK 8 (JDK 8 only, not 11 or 21). Suwayomi dropped Java 8 support in v1.1 (June 2024); v2.x requires Java 21. There is no confirmed-working combination of (iOS-approved JDK) + (Suwayomi) as of 2026-05-02. Do not greenlight this feature without first confirming a working JAR+JDK pairing.

- **`SuwayomiService.baseURL` is already an indirect property — localhost is a drop-in**: the entire `SuwayomiService.swift` reads its base URL from `AppSettings.shared.suwayomiURL`. No service code changes are needed to point at an embedded server. The only integration work is: (1) start the JVM/server on app launch, (2) set `AppSettings.shared.suwayomiURL = "http://localhost:4567"` automatically when the embedded server is running. All browse, search, chapter, and page URL logic already works.

- **App Store listing attributes (iOS version, native/JS) do not confirm the absence of embedded runtime**: Tachimanga lists iOS 15.0+ and does not mention Java. Code App lists iOS 14.0+ and does not say "runs Java". App Store product pages are marketing materials, not architecture docs. Absence of "JVM" in the listing is not evidence that the app is pure Swift.

- **When in doubt about a competitor's architecture, look for open-source server forks, not the App Store listing**: Tachimanga's public repos (`tachimanga/Tachidesk-Server`) are more diagnostic than their iOS binary. The App Store listing vs. the server fork remain in conflict — the architecture is genuinely unconfirmed.

## S50 — Technical learnings (2026-04-28)

- **Language filter chip bar pattern**: collect unique `Extension.language` strings from installed array via `compactMap` + `Set.insert().inserted` dedup + `sorted()`. Render `RepoFilterChip` chips above the List in a `VStack(spacing: 0)` — same component used for repo filter in extensions tab. Filter computed property returns all when `selectedLanguage == nil`, filtered when set. Tapping a chip that's already selected clears the filter.
- **`showLatestNovels: true` for LNReader Latest feed**: LNReader's `popularNovels(page, options)` accepts `{showLatestNovels: true}` in the options object to return latest-updated novels instead of popular. All LNReader v3 plugins support this option (it's a standard LNReader API). Add `latestNovels(page:)` to JSBridge that injects `showLatestNovels: true` into `__lnr_opts` and calls `callPluginMethod`. Set `supportsLatest = true` for all LNReader sources.
- **Popular/Latest picker should not be gated on `!isNovelSource`**: the original guard `!isNovelSource && supportsLatest` hid the picker for all novel sources. After adding LNReader Latest support, the guard becomes just `supportsLatest` — works for manga, novels, and Mangayomi uniformly.
- **VStack wrapping List in ViewBuilder context**: adding a chip bar above a `List` requires wrapping in `VStack(spacing: 0)`. In SwiftUI's ViewBuilder, `List` is a single expression so it can coexist with the chip `ScrollView` inside the `VStack`. Brace count: `VStack { if chips { ... } List { ... }.task { ... } }` needs its own closing `}` even if `List` is the last child — don't count `List`'s close as VStack's close.

## S49 — Technical learnings (2026-04-26)

- **Mangayomi JS plugin format (current)**: plugins define `class DefaultExtension extends MProvider { ... }` and `const mangayomiSources = [{...}]`. They do NOT define a `source` variable. Pre-eval shims must include `MProvider` (ES5 constructor function — ES6 `class extends` works with it) and `SharedPreferences`. Post-eval adapter must detect `DefaultExtension` + `mangayomiSources`, instantiate with `new DefaultExtension()`, then set `instance.source = mangayomiSources[0]` (normalizing `langs[]` → `lang`).
- **`getSrc`/`getHref` must be getter properties, not methods**: Mangayomi plugins write `el.getSrc` (property access) not `el.getSrc()`. Defining them as functions returns the function object (truthy but wrong). Fix: use `Object.defineProperties` with `get:` descriptors for both, and use `get getSrc() { return ''; }` shorthand in the `_nullEl` object literal.
- **Native `async/await` in JSC does not resolve via `_resolve()`**: `_resolve(promise).then(cb)` fires `cb` synchronously only when `SyncPromise` is used. Native `async function` in JSC wraps its return in the native internal Promise system, not `global.Promise`, so microtask continuations are scheduled and don't run until `evaluateScript` or the run loop. Fix: use `context.evaluateScript(...)` for all Mangayomi method calls (same as `callPluginMethod` for LNReader) — JSC drains microtasks after each `evaluateScript` call.
- **Mangayomi method name differences**: `getLatestUpdates` (not `getLatest` — current plugins), `episodes` (not `chapters` — field in `getDetail` return for manga chapters). Always check both names via `?? fallback`.
- **Mangayomi item field names**: list items use `{link, name, imageUrl}` — not `{url, title, image}`. Map `item.link || item.url` for id/path, `item.name || item.title` for title, `item.imageUrl || item.image` for cover URL.

## S48 — Technical learnings (2026-04-26)

- **`PBXFileSystemSynchronizedRootGroup` + `INFOPLIST_FILE` conflict**: adding a widget extension with a manual `Info.plist` file and `INFOPLIST_FILE = ...` causes "Multiple commands produce Info.plist" because the synchronized group also processes the plist as a resource. Fix: add the file to the target's `PBXFileSystemSynchronizedBuildFileExceptionSet.membershipExceptions` array so the synchronized group skips it. The `INFOPLIST_FILE` build phase then handles it exclusively.
- **`INFOPLIST_FILE` does NOT auto-inject bundle keys — must be a complete plist**: when using `INFOPLIST_FILE` (as opposed to `GENERATE_INFOPLIST_FILE = YES`), Xcode uses the file as-is and only performs `$(VAR)` variable expansion. It does NOT add `CFBundleIdentifier`, `CFBundleName`, `CFBundleExecutable`, etc. Missing `CFBundleIdentifier` triggers "Embedded binary's bundle identifier is not prefixed with parent app's bundle identifier" during `ValidateEmbeddedBinary`. Always write a complete Info.plist with all standard keys using `$(PRODUCT_BUNDLE_IDENTIFIER)`, `$(EXECUTABLE_NAME)`, `$(MARKETING_VERSION)`, `$(CURRENT_PROJECT_VERSION)`. `CFBundlePackageType` for app extensions is `XPC!` (not `APPL`).
- **Widget bundle ID must be a dotted prefix of the parent app's bundle ID**: `pacodealer.YomiWidget` is NOT a valid extension of `pacodealer.Yomi` (it reads as a sibling). Correct form: `pacodealer.Yomi.widget`. The iOS validator checks `childBundleID.hasPrefix(parentBundleID + ".")`.
- **OPDS Atom XML — navigation vs acquisition detection**: navigation entries have `<link type="application/atom+xml...">` pointing to another feed. Acquisition entries have `<link rel="http://opds-spec.org/acquisition" ...>` pointing to a downloadable file. Cover images use `rel="http://opds-spec.org/image"` or `rel="http://opds-spec.org/image/thumbnail"`. Feed-level `<link rel="next">` handles pagination. XMLParser in Foundation is SAX-style and strips namespace prefixes — use local element names directly (`feed`, `entry`, `title`, `link`, etc.).
- **`TimelineProvider` with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` in widget extension**: works as-is. The provider's callback-based methods (`getTimeline(in:completion:)`) are implicitly `@MainActor`, and calling the completion handler from the same context is valid. No nonisolated annotation needed. Widget extensions don't have the same JSBridge DispatchSemaphore constraint as the main app.
- **App Groups and widget data sharing**: shared data goes in `UserDefaults(suiteName: "group.pacodealer.Yomi")`, not `UserDefaults.standard`. Both the main app and widget extension must declare `com.apple.security.application-groups` in their `.entitlements` files. Both entitlements files must be wired to their respective targets via `CODE_SIGN_ENTITLEMENTS` in build settings. Call `WidgetCenter.shared.reloadAllTimelines()` after writing to trigger a widget refresh.

## Architecture decisions
- GRDB over SwiftData: full schema control, more mature, compatible with incremental migrations
- JavaScriptCore over WKWebView: lighter, no UI required, better for headless plugins
- Own plugin format (Format A) + LNReader compatibility (Format B): maximum flexibility without depending on Android ecosystem
- Plugins installed in Documents/Extensions/ as local .js files
- MAL token in UserDefaults (not Keychain): sufficient for MVP; migrate to Keychain before App Store
