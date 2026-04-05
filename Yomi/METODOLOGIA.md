# Working methodology — Yomi

## Workflow
- **Claude.ai (Desktop app)** → architecture, planning, generating optimized prompts for Claude Code
- **Claude Code (terminal)** → executes prompts, writes Swift/JS files, makes git commit/push
- **Xcode** → compile, run on simulator, see exact errors
- **GitHub Desktop** → review diffs, manual push when required

## Workflow rules
- One file at a time, compile after each new file
- Never create multiple files simultaneously
- Report exact Xcode errors to Claude.ai before continuing
- Claude.ai generates the prompt → paste into Claude Code → Claude Code writes the file
- Commits after each complete functional block (not after each file)
- Prompt template for Claude Code includes an explicit DO NOT TOUCH section and ADDED/MODIFIED/UNTOUCHED/LINES summary at the end
- At session start: paste only `find` + ROADMAP. METODOLOGIA and ARQUITECTURA live in Claude.ai project knowledge.
- At session close: explicit Claude Code prompt updates all three docs (ROADMAP + METODOLOGIA + ARQUITECTURA). Valid exception to "one file per prompt": they are docs, not Swift code.
- At session start, also paste the content of files that will be modified (in addition to `find` + ROADMAP.md) — prevents Claude.ai from planning against the wrong file
- When a prompt creates a prop/callback in a child view, the same prompt must wire it in the parent view, or register it as debt in ROADMAP before closing the session
- Debug prompts always end with an explicit numbered cleanup prompt
- "DO NOT modify any file" only in pure diagnostic prompts — never in edit prompts
- When chaining independent fixes: run all without compiling, compile once at the end
- All planning and communication is in English from Session 15 onward
- Claude Code also operates in English for all prompts, commits, and responses

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

## File path rules
- Before generating any edit prompt, Claude.ai must cite the confirmed exact file path
- If path is uncertain, the prompt includes a `find Yomi -name "*.swift"` step before editing
- Frequently referenced paths:
  - JSBridge: Yomi/Features/Extensions/JSBridge.swift
  - ExtensionManager: Yomi/Features/Extensions/ExtensionManager.swift
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
- **iOS 26 TabView**: new API `Tab("title", systemImage:) {}` — old `.tabItem {}` renders nothing
- **Xcode PBXFileSystemSynchronizedRootGroup**: all files in the folder are included automatically — never use `.gitkeep` or `.gitignore` inside the target
- **Swift 6 + GRDB**: `init(row:)` and `encode(to:)` from FetchableRecord/PersistableRecord require `nonisolated` with `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`
- **DerivedData stale**: clean with `rm -rf ~/Library/Developer/Xcode/DerivedData/Yomi-*` and ⇧⌘K in Xcode
- **JSBridge async**: JSContext is synchronous; SOURCE.fetch blocks with DispatchSemaphore; always call from Task.detached, never from MainActor
- **Keiyoushi plugins**: they are Android .apk, do not run on iOS; shown as reference catalog only
- **LNReader plugins**: TypeScript compiled to JS — compatible with JavaScriptCore if correct shims are implemented (fetch, cheerio, storage)
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

- **Firebase Hosting as plugin repo**: Firebase Hosting (free tier) is the optimal option for hosting a custom plugin repository (`index.json` + `.js` files). Enables stable URLs like `https://yomi-plugins.web.app/index.json`. PluginsView can point to this URL to discover and install plugins without knowing each `.js` URL directly. Implementation pending.

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
