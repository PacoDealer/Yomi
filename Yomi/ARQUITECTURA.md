# Architecture — Yomi

## Overview
Yomi is a manga, manhwa, manhua, and light novel reader for iOS.
Architecture inspired by Mihon (Android) and LNReader (Android).
Content fetched via JavaScript plugins executed in JavaScriptCore.

## Folder structure
Yomi/
├── Models/
│   ├── Manga.swift          # Manga/manhwa/manhua — main model
│   ├── Chapter.swift        # Chapter of a work
│   ├── Category.swift       # Library categories
│   └── Extension.swift      # Installed JS plugin — Identifiable, Codable, Hashable
├── Database/
│   ├── DatabaseManager.swift        # GRDB setup, migrations, FetchableRecord conformances; module-level appDatabase var
│   └── Queries/
│       ├── MangaQueries.swift       # CRUD manga: fetchAll, fetchOne, fetchLibrary, fetchLibraryByLastUpdated, fetchRecentlyRead, insert, update, upsert, touchLastRead, touchLastUpdated, updateReadingStatus, delete
│       ├── ChapterQueries.swift     # CRUD chapter: fetchAll(ASC NULLS LAST), fetchOne, fetchUnreadCountsByManga (single GROUP BY), insertAllIgnoringConflicts (INSERT OR IGNORE — safe bulk persist), insert, upsert, upsertAll, markRead, markAllRead, updateProgress (saves lastPageRead), addReadingTime, setRead(chapterId:isRead:), delete, deleteAll
│       ├── CategoryQueries.swift    # CRUD category + manga_category join: fetchAll, insert, rename, delete, updateSort, assign, unassign, categoriesForManga, mangaIds(inCategory:)
│       ├── NovelQueries.swift       # CRUD novel + novel_chapter
│       └── ExtensionQueries.swift   # CRUD extensions
├── Core/
│   ├── AppRouter.swift              # @Observable singleton for programmatic tab navigation; openBrowseExtensions flag for Library → Browse Extensions deep link
│   ├── Color+Hex.swift             # Color(hex:) init (#RRGGBB and #RRGGBBAA) + Color.hexString via UIColor sRGB
│   └── NotificationManager.swift   # @Observable singleton, UNUserNotificationCenter
├── Features/
│   ├── Library/
│   │   ├── LibraryView.swift        # Saved manga grid + category chips + ContinueReadingRow + multi-select (long-press, Cancel/SelectAll toolbar, bulk Remove)
│   │   ├── LibraryViewModel.swift   # State, filtering, SortOrder (lastRead/alphabetical/lastUpdated/unreadCount); unreadCounts dict from single GROUP BY query
│   │   ├── CategoryView.swift       # Category CRUD UI (create, rename, reorder, delete)
│   │   ├── ContinueReadingRow.swift # Horizontal scrollable row of recently read manga
│   │   ├── MangaCoverCell.swift     # Cover cell + shimmer skeleton + selection mode (isSelecting/isSelected overlays, long press enters select)
│   │   └── MangaDetailView.swift    # Detail + chapter list + heart button + ReadingStatusMenu pill + category sheet
│   │                                # Chapter selection mode (long-press → isSelectingChapters, bottom action bar). Download sub-menu. Per-chapter download button. Overflow menu.
│   │                                # loadChapters() calls insertAllIgnoringConflicts() after JSBridge fetch — chapters persisted before DB merge
│   │                                # refreshChapterStates() merges DB state on .onAppear + .onChange(of: downloadManager.completedDownloadCount)
│   │                                # navigationDestination(item: $chapterForNav) for tap-to-reader. .onChange(of: chapterForNav) triggers 500ms delayed refresh on return.
│   ├── Browse/
│   │   ├── BrowseView.swift         # Sources / Extensions / Search tabs; Extensions tab shows Yomi catalog inline (reuses YomiCatalogEntryRow); openBrowseExtensions reacts to AppRouter flag
│   │   │                            # SourceBrowseView: currentPage/isLoadingMore/hasMoreContent state, "Load more" button below grid, appends for Format A and B (S22)
│   │   │                            # FeedTab enum (.popular/.latest). Segmented Picker shown when supportsLatest && !isNovelSource. Bridge reused across tab switches.
│   │   └── NovelDetailView.swift    # Novel detail + chapter list
│   ├── Reader/
│   │   ├── ChapterReaderView.swift  # RTL manga + webtoon, zoom+pan, overlay, prev/next chapter via currentChapterIndex+navigateToChapter, reading timer, MAL tracking
│   │   │                            # Reading resume: after loadPages(), Task.detached reads chapter.progress, sets currentPage on MainActor (S22)
│   │   │                            # MangaPageView: GeometryReader + DragGesture with clamping, guard scale > 1.0. Double-tap resets scale+offset (S22)
│   │   │                            # Auto-mark read: last page reached OR (multi-page && ≥80% read). Incognito guard skips markChapterRead + updateProgress.
│   │   └── TextReaderView.swift     # HTML reader for novels (WKWebView, font size, dark/light/sepia)
│   │                                # Overlay: .opacity/.allowsHitTesting/.animation — smooth fade animation (S29). colorScheme: sepia→.light, dark→.dark, else .light (S29).
│   ├── History/
│   │   └── HistoryView.swift        # Real GRDB data (lastReadAt IS NOT NULL, DESC), swipe-to-delete local
│   ├── More/
│   │   ├── MoreView.swift           # Root More tab (Library / App / Sources / Reading / Tracking / Data / Info)
│   │   ├── PluginsView.swift        # Installed plugins + Browse catalog (PluginCatalogService, Install button per entry) + NSFW filter
│   │   ├── SettingsView.swift       # General / Reader manga / Reader novel / Appearance / About / Developer (catalog URL)
│   │   ├── InsightsView.swift       # Stat cards (streak, chapters read, time read, titles started) + per-manga time list
│   │   ├── BackupManager.swift      # Export/import JSON (manga + chapters)
│   │   ├── BackupView.swift         # UI: ShareLink export + fileImporter import
│   │   ├── MALService.swift         # OAuth PKCE plain, searchManga, updateMangaProgress
│   │   ├── MALView.swift            # Login/disconnect UI + SafariView
│   │   └── UpdatesView.swift        # UpdatesViewModel (@Observable, withTaskGroup, checkUpdates per plugin) + UpdatesRow
│   ├── Onboarding/
│   │   └── OnboardingView.swift     # First-launch full-screen card (S19 — new); guides user to Browse catalog; gated by AppSettings.hasSeenOnboarding
│   └── Extensions/
│       ├── JSBridge.swift           # JavaScriptCore bridge (Format A + B, real cheerio shim, require() shim, searchManga, POST support)
│       ├── ExtensionManager.swift   # Install/remove plugins; seedBundledPlugins() method kept for dev use — call removed from YomiApp in S19
│       └── PluginCatalogService.swift  # @Observable singleton; fetches remote index.json; PluginCatalogEntry Codable struct
├── AppSettings.swift                # @Observable singleton, UserDefaults-backed, 34 properties. Covers reader mode/font/theme, OLED (pureBlack), tap zones, webtoon padding, auto-scroll speed, novel theme/font, library columns/badges/categories, update skip filters, concurrent downloads, incognito, notifications, onboarding, accent color, alternate icon.
├── ContentView.swift                # Root TabView with AppRouter selection binding
├── YomiApp.swift                    # Entry point. DB setup. #if DEBUG seedBundledPlugins(). @State settings drives .preferredColorScheme + .tint on ContentView(). @State showOnboarding = !AppSettings.shared.hasSeenOnboarding gates .fullScreenCover(OnboardingView) (restored S22).
├── PrivacyInfo.xcprivacy            # ✅ Done (S22). Declares NSPrivacyAccessedAPICategoryUserDefaults.
├── Resources/
│   └── test-source.js               # Test plugin (Format A) — kept for SwiftUI previews only
│   # Note: 9 production plugins (mangadex, asurascans, aquamanga, royalroad,
│   # scribblehub, novelfire, freewebnovel, novelbin, novelfull) hosted on Firebase.
│   # Binary ships zero plugin files for App Store compliance. https://yomi-plugins.web.app
├── ARQUITECTURA.md
├── METODOLOGIA.md
└── ROADMAP.md

scripts/
├── build-plugins.mjs               # Node.js ESM esbuild bundler: reads plugins-src/*.ts → IIFE JS → Yomi/Resources/ + Firebase public/; generates index.json
├── plugins-src/                    # LNReader v2.x TypeScript plugin sources (place .ts files here; built by build-plugins.mjs)
└── catalog-output/
    └── index.json                  # Seeded catalog (7 plugins) for Firebase Hosting deployment reference

## Architecture layers
┌─────────────────────────────────────────┐
│            SwiftUI Views                │  Features/
├─────────────────────────────────────────┤
│   ViewModels (@Observable) + AppSettings│  LibraryViewModel, UpdatesViewModel, BackupManager, MALService
├─────────────────────────────────────────┤
│  AppRouter + NotificationManager        │  Core/
├─────────────────────────────────────────┤
│  ExtensionManager + JSBridge            │  Features/Extensions/
│  PluginCatalogService                   │
├──────────────────┬──────────────────────┤
│   GRDB (SQLite)  │  JavaScriptCore      │
│   appDatabase    │  JS Plugins          │
│   *Queries       │  (mangadex.js, etc.) │
└──────────────────┴──────────────────────┘

## Database (SQLite via GRDB)

### Current tables (migration v13_custom_cover)
```sql
manga        (id, path, sourceId, title, coverURL, summary, author, artist,
              status TEXT (MangaStatus: unknown/ongoing/completed/hiatus/cancelled),
              genres JSON, inLibrary, isLocal, lastReadAt, lastUpdatedAt,
              readingSeconds INTEGER NOT NULL DEFAULT 0,
              readingStatus TEXT NOT NULL DEFAULT 'none',
              customCoverPath TEXT)

chapter      (id, mangaId FK→manga, path, name, chapterNumber, isRead,
              isDownloaded, downloadedAt, readAt, progress,
              readingSeconds INTEGER NOT NULL DEFAULT 0,
              lastPageRead INTEGER NOT NULL DEFAULT 0,
              scanlator TEXT)

category     (id, name, sort)

manga_category (mangaId TEXT NOT NULL FK→manga ON DELETE CASCADE,
                categoryId TEXT NOT NULL FK→category ON DELETE CASCADE,
                PRIMARY KEY (mangaId, categoryId))

source       (id, name, language, version, iconURL, baseURL, isInstalled, isNSFW)

extension    (id, name, version, language, iconURL, sourceListURL,
              isInstalled, isNSFW, sourceIds JSON)

novel        (id, path, sourceId, title, coverURL, summary, author, status,
              genres JSON, inLibrary, lastReadAt, lastUpdatedAt,
              readingSeconds INTEGER NOT NULL DEFAULT 0,
              readingStatus TEXT NOT NULL DEFAULT 'none')

novel_chapter (id, novelId FK→novel, path, name, chapterNumber, isRead,
               readAt, releaseTime,
               readingSeconds INTEGER NOT NULL DEFAULT 0)

novel_category (novelId TEXT NOT NULL FK→novel ON DELETE CASCADE,
                categoryId TEXT NOT NULL FK→category ON DELETE CASCADE,
                PRIMARY KEY (novelId, categoryId))
```

### Migrations
- **v1_initial**: manga, chapter, category, source
- **v2_extensions**: extension
- **v3_novels**: novel, novel_chapter
- **v4_reading_insights**: `ALTER TABLE manga ADD COLUMN readingSeconds` / `ALTER TABLE novel ADD COLUMN readingSeconds`
- **v4_reading_time**: `ALTER TABLE chapter ADD COLUMN readingSeconds INTEGER NOT NULL DEFAULT 0`
- **v5_categories**: manga_category join table (mangaId + categoryId, composite PK, ON DELETE CASCADE)
- **v6_downloads**: `ALTER TABLE chapter ADD COLUMN downloadedAt TEXT` (downloadedAt on chapter)
- **v7_reading_status**: `ALTER TABLE manga ADD COLUMN status TEXT NOT NULL DEFAULT 'none'`
- **v8_last_page**: `ALTER TABLE chapter ADD COLUMN lastPageRead INTEGER NOT NULL DEFAULT 0`
- **v9_novel_chapter_reading_time**: `ALTER TABLE novel_chapter ADD COLUMN readingSeconds INTEGER NOT NULL DEFAULT 0`
- **v10_novel_category**: novel_category join table (novelId + categoryId, composite PK, ON DELETE CASCADE)
- **v11_novel_reading_status**: `ALTER TABLE novel ADD COLUMN readingStatus TEXT NOT NULL DEFAULT 'none'`
- **v12_scanlator**: `ALTER TABLE chapter ADD COLUMN scanlator TEXT`
- **v13_custom_cover**: `ALTER TABLE manga ADD COLUMN customCoverPath TEXT`

> Note: two migrations with v4_ prefix coexist without conflict — GRDB tracks by string name. Next migration must use prefix `v14_`.

### Why GRDB and not SwiftData
- Full SQL schema and incremental migration control
- More mature and stable
- Compatible with schemas inspired by LNReader/Mihon

## Singletons / core state

### AppSettings (Yomi/AppSettings.swift)
`@Observable final class`, accessed via `AppSettings.shared`

**Pattern (fixed S23):** All stored properties use `didSet` to persist to `UserDefaults`.
`@ObservationIgnored` on the `defaults` ivar. `private init()` reads all values from UserDefaults
with fallback defaults. `colorScheme` remains computed (derived from `theme`).

**Reader / display**
- `readerMode: String` — "Manga (RTL)", "Manhwa (LTR)", or "Webtoon"
- `fontSize: Double` — novel reader font size (points); default 18.0
- `lineSpacing: Double` — novel reader line spacing multiplier
- `theme: String` — "System", "Light", or "Dark"
- `useSystemFont: Bool` — system font vs built-in reader font
- `accentColor: String` — hex string for app tint color; default `#FF6B6B`; applied via `.tint(Color(hex:))` on ContentView
- `pureBlack: Bool` — OLED pure-black background in dark mode (S36); key "pureBlack"; default false
- `autoWebtoonFromTags: Bool` — auto-switch to Webtoon mode if manga genres include "Manhwa"/"Manhua" (S37); default true
- `tapZoneLayout: String` — reader tap zone config: "default"/"sides"/"disabled" (S39); default "default"
- `webtoonHorizontalPadding: Int` — horizontal inset for webtoon pages in points: 0/8/16/24 (S39); default 0
- `autoScrollSpeed: Double` — hold-to-auto-scroll interval in seconds (S39); default 3.0
- `novelTheme: String` — novel reader theme: "light"/"dark"/"sepia" (S39); default "light"
- `novelFontFamily: String` — novel reader font family name (S39); default system serif
- `novelHorizontalPadding: Int` — novel reader horizontal padding (S39); default 16

**Library**
- `libraryColumns: Int` — grid columns in LibraryView; default 3; range 2–6
- `showUnreadBadge: Bool` — show unread count capsule badge on library covers; default true
- `excludedCategoryIds: [String]` — category IDs excluded from update checks (S38); default []

**Library update skip filters (S38)**
- `skipUpdateWithUnread: Bool` — skip manga with any unread chapters; default false
- `skipUpdateNotStarted: Bool` — skip manga with no chapters read; default false
- `skipUpdateCompleted: Bool` — skip manga with readingStatus == .completed; default false

**Downloads**
- `deleteDownloadAfterReading: Bool` — auto-delete downloaded chapter after reader closes (S38); default false
- `concurrentDownloads: Int` — max parallel chapter downloads (S38); default 3; range 1–5

**App behavior**
- `showNSFW: Bool` — show NSFW sources and catalog entries
- `hasRequestedNotifications: Bool` — flag to request notification permission only once
- `hasSeenOnboarding: Bool` — set to true when user completes OnboardingView
- `pluginCatalogURL: String` — remote index.json URL; default `https://yomi-plugins.web.app/index.json`
- `keepScreenOn: Bool` — disables idle timer in ChapterReaderView; default true
- `isIncognito: Bool` — skip chapter read/progress persistence when true; default false
- `alternateIconName: String?` — nil = default icon; set to alternate icon asset name (S36); nil default

**Appearance (computed)**
- `colorScheme: ColorScheme?` — computed; nil=system, .light, .dark; derived from `theme`; drives `.preferredColorScheme` at ContentView root

### AppRouter (Yomi/Core/AppRouter.swift)
`@Observable final class`, module-level: `nonisolated(unsafe) var appRouter = AppRouter()`
- `selectedTab: Int` — active tab index in ContentView TabView
- Constants: `tabLibrary=0`, `tabBrowse=1`, `tabHistory=2`, `tabUpdates=3`, `tabMore=4`
- Used from LibraryView empty state and any view needing programmatic navigation
- `init()` is internal (not private) so the module-level var can call it

### NotificationManager (Yomi/Core/NotificationManager.swift)
`@Observable singleton`, accessed via `NotificationManager.shared`
- `requestPermission() async` — requests `.alert + .badge + .sound`
- `scheduleChapterNotification(mangaTitle:newCount:)` — immediate local notification
- Trigger: MangaDetailView, first library save, only if `!hasRequestedNotifications`

### PluginCatalogService (Yomi/Features/Extensions/PluginCatalogService.swift)
`@Observable final class`, accessed via `PluginCatalogService.shared`
- `entries: [PluginCatalogEntry]` — decoded catalog from remote index.json
- `isLoading: Bool` / `errorMessage: String?` — fetch state
- `fetchCatalog() async` — fetches `AppSettings.shared.pluginCatalogURL`, decodes `[PluginCatalogEntry]`
- `isInstalled(_ entry:) -> Bool` — cross-references `ExtensionManager.shared.installed` by name
- `PluginCatalogEntry`: `Codable + Identifiable`; fields: `id`, `name`, `version`, `language`, `description`, `iconURL: String?`, `fileURL`, `isNSFW`

## JS plugin system

### Lifecycle
User enters .js URL
↓
ExtensionManager.install(_:)
→ downloads file via URLSession
→ saves to Documents/Extensions/{id}.js
→ persists metadata in extension table (GRDB)
↓
ExtensionManager.bridge(for: ext)
→ JSBridge(scriptURL: localURL)
↓
JSBridge.init
→ creates JSContext
→ injects shims (SOURCE.fetch, cheerio, localStorage, console, require())
→ evaluates the JS script
→ detects format (A or B)
↓
View calls bridge.getMangaList() / bridge.popularNovels()
→ JSBridge calls JS function via JSContext
→ JS calls SOURCE.fetch → Swift makes HTTP → returns String to JS
→ JS parses and returns object
→ JSBridge maps to Swift structs

### Format A — Yomi/Manga
Global functions. Used for manga, manhwa, manhua.
```javascript
getMangaList(page)        → [{id, path, title, coverURL, summary, author, artist, status, genres}]
getChapterList(mangaPath) → [{id, path, name, chapterNumber}]
getPageList(chapterPath)  → [urlString]
searchManga(query, page)  → [{id, path, title, coverURL, summary, author, artist, status, genres}]

// Optional — JSBridge checks for undefined before calling
getLatestManga(page)      → [{id, path, title, coverURL, ...}]   // Latest tab in SourceBrowseView
```
`JSBridge.supportsLatest: Bool` — returns true only if `getLatestManga` is a defined function in the plugin context.

### Format B — LNReader/Novel
Class exported on global `plugin`. Compatible with LNReader ecosystem plugins.
```javascript
plugin.popularNovels(pageNo, options) → [{name, path, cover}]
plugin.parseNovel(novelPath)          → {path, name, cover, author, summary, status, chapters}
plugin.parseChapter(chapterPath)      → String (chapter HTML)
plugin.searchNovels(searchTerm, page) → [{name, path, cover}]
```

### Automatic format detection
```swift
var isLNReaderPlugin: Bool {
    context.objectForKeyedSubscript("plugin")
           .objectForKeyedSubscript("popularNovels")
           .isObject
}
```

### Shims injected by JSBridge
| Shim | Implementation | Status |
|------|---------------|--------|
| `SOURCE.fetch(url, opts)` | URLSession + DispatchSemaphore (blocking, 30s timeout) | ✅ Functional |
| `console.log/warn/error` | Swift print() | ✅ Functional |
| `localStorage` / `sessionStorage` | In-memory JS object with get/set/removeItem | ✅ Functional |
| `cheerio.load(html)` | Recursive HTML parser + CSS selector engine in pure JS | ✅ Functional (since S6) |
| `require(name)` | Module cache shim: cheerio→global, he inline, node-fetch/axios→SOURCE._fetchSync, unknown→{}; injects module/exports/process | ✅ Functional (since S18) |

SOURCE.fetch supports GET and POST:
```javascript
SOURCE.fetch(url)  // GET by default
SOURCE.fetch(url, { method: "POST", body: "...", headers: {...} })  // POST
```
`_fetchSync` receives 4 parameters: `(url, method, body, headersJSON)`
Swift handler merges default headers (iPhone Safari User-Agent) with plugin headers.
Plugin headers take precedence over defaults.

### require() shim detail
Injected via `injectRequireShim(into: ctx)` as an IIFE before plugin evaluation.
```javascript
(function(global) {
    var __moduleCache = {};
    function require(name) {
        if (__moduleCache[name]) return __moduleCache[name];
        var mod = { exports: {} };
        if      (name === 'cheerio')       { mod.exports = global.cheerio || {}; }
        else if (name === 'he')            { /* inline entity decode/encode */ }
        else if (name === 'node-fetch' || name === 'node-fetch/src/index.js') { /* SOURCE._fetchSync wrapper */ }
        else if (name === 'axios')         { /* get/post via SOURCE._fetchSync */ }
        else                              { mod.exports = {}; }
        __moduleCache[name] = mod.exports;
        return mod.exports;
    }
    global.require = require;
    global.module  = { exports: {} };
    global.exports = global.module.exports;
    global.process = { env: { NODE_ENV: 'production' }, version: 'v18.0.0',
                       platform: 'ios', versions: {} };
})(this);
```

## Firebase Hosting

**Project:** yomi-plugins
**URL:** https://yomi-plugins.web.app
**index.json:** https://yomi-plugins.web.app/index.json
**Local folder:** `~/Desktop/yomi-firebase/` (outside Xcode repo, not committed to git)
**Deploy:** `cd ~/Desktop/yomi-firebase && firebase deploy --only hosting`

**Structure:**
```
public/
  index.json     ← plugin catalog ([PluginCatalogEntry] JSON array)
  mangadex.js
  asurascans.js
  aquamanga.js
  royalroad.js
  scribblehub.js
  novelfire.js
  freewebnovel.js
  novelbin.js
  novelfull.js
```
Note: comick.js removed (Cloudflare 403 from non-browser clients). lightnovelworld.js removed (site permanently closed Jan 2026).

Plugin IDs in index.json are `SHA256(fileURL).prefix(32)` — consistent with the ID scheme used by `ExtensionManager` for network-installed plugins.

## Data flows

### Browse → Reader
BrowseView
→ SourceBrowseView(ext)
→ Task.detached { bridge.getMangaList(page:1) }  // background
→ await MainActor { mangas = result }
→ LazyVGrid → MangaCoverCell → NavigationLink
→ MangaDetailView(manga)
→ Task.detached { bridge.getChapterList(mangaPath:) }
→ merge with DB (isRead, readingSeconds per chapter)
→ List → ChapterRow → NavigationLink
→ ChapterReaderView(manga:bridge:chapters:chapterIndex:)
→ Task.detached { bridge.getPageList(chapterPath:) }
→ MangaReaderView (RTL TabView)  or
   WebtoonReaderView (ScrollView LazyVStack)

### Plugin catalog install (OTA)
PluginsView Browse tab
→ .onAppear { Task { await PluginCatalogService.shared.fetchCatalog() } }  // fires on every tab activation (S20)
→ GET AppSettings.shared.pluginCatalogURL (index.json)
→ [PluginCatalogEntry] listed with Install button
→ installEntry(_:) builds Extension(id: entry.id, sourceListURL: URL(entry.fileURL))
→ extensionManager.install(ext)
→ URLSession downloads .js → Documents/Extensions/{id}.js → GRDB upsert

### Server-side search
SearchView (BrowseView)
→ .onChange(of: searchQuery) with debounce 500ms (Task.sleep)
→ debounceTask?.cancel() on each keystroke
→ Task.detached { bridge.searchManga(query:page:sourceId:) }
→ await MainActor.run { searchResults = results }
→ LazyVGrid → MangaCoverCell

### Mark-as-read + tracking
ChapterReaderView
→ .onChange(of: currentPage) { if newPage == pages.count - 1 }
→ Task { ChapterQueries.markRead(id:mangaId:) }
   → UPDATE chapter SET isRead=true, readAt=now, progress=1.0
   → MangaQueries.touchLastRead(mangaId:)
      → UPDATE manga SET lastReadAt=now
→ if MALService.isLoggedIn
   → MALService.searchManga(title:)
   → MALService.updateMangaProgress(malId:chaptersRead:)

### Reading time tracking
ChapterReaderView.onAppear
→ isIdleTimerDisabled = true
→ readingTimer = Timer(1s) { sessionSeconds += 1 }

ChapterReaderView.onDisappear / navigateToChapter
→ readingTimer.invalidate()
→ Task.detached { ChapterQueries.addReadingTime(id:seconds:) }
   → UPDATE chapter SET readingSeconds += seconds
→ Task.detached { MangaQueries.update(manga with accumulated readingSeconds) }
→ isIdleTimerDisabled = false

### Backup
BackupManager.exportBackup()
→ MangaQueries.fetchAll() + await appDatabase.read { Chapter.fetchAll }
→ JSONSerialization → Data
→ FileManager.temporaryDirectory → URL
→ BackupView presents via ShareLink

BackupManager.importBackup(from:)
→ Data(contentsOf:) → JSONSerialization
→ decodeManga / decodeChapter
→ MangaQueries.upsert + ChapterQueries.upsert (merge, does not replace)

### MAL OAuth
MALService.authorizationURL()
→ generates random code_verifier (plain PKCE)
→ builds MAL authorize URL

BackupView / MALView → SFSafariViewController
→ user authorizes → MAL redirects to yomi://callback?code=...

YomiApp / MALView.onOpenURL
→ MALService.handleCallback(url:)
→ POST /oauth2/token (code + code_verifier)
→ GET /users/@me (username)
→ saves accessToken in UserDefaults

## Components

### ContinueReadingRow (Yomi/Features/Library/ContinueReadingRow.swift)
- Horizontal scrollable row at the top of LibraryView
- Data: `MangaQueries.fetchRecentlyRead(limit: 10)`
- Automatically hidden when no reading history exists
- Cell: 2:3 ratio cover, title (2 lines max), NavigationLink → MangaDetailView
- Single `.task` on `Group` container loads data once on appear

## Concurrency
- All JSBridge calls are made from `Task.detached(priority: .userInitiated)`
- JSBridge and its methods are `nonisolated` to satisfy Swift 6 with `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`
- SOURCE.fetch blocks the thread with `DispatchSemaphore` — never call from MainActor
- Result delivered to UI via `await MainActor.run { state = result }`
- `appDatabase` is a `nonisolated(unsafe) var` at module level — accessible from any context without actor hop
- `appDatabase.read` has async overload: from `@MainActor` context requires `try await appDatabase.read { ... }`
- `ExtensionManager` is `@Observable final class` — automatically conforms to `Sendable`. `nonisolated(unsafe)` on `static let shared` is unnecessary and generates a warning. To access `bridge(for:)` from `Task.detached`, capture a local `bridgeFn` closure in the `@MainActor` context before entering the Task.
- `AppRouter` uses module-level `nonisolated(unsafe) var appRouter = AppRouter()` — same pattern as `appDatabase`. Access via `appRouter.selectedTab` from any context.

## Workflow

### Current workflow (Claude Code-first, from S22)
Claude.ai role: **session strategy only** — review priorities, flag risks, architectural concerns.
Claude Code role: **everything else** — reads files, plans, implements, builds, fixes errors, commits.

No relay. No copy-paste between AIs. The user's role: product owner + QA.

**Why this works now:**
- `CLAUDE.md` at project root loads full context into every Claude Code session automatically
- XcodeBuildMCP lets Claude Code trigger builds and read errors without user relay
- swift-lsp gives real-time diagnostics after every edit
- Memory system persists project path and state across sessions

**Session start:** `cd` into the Yomi project, open Claude Code. CLAUDE.md loads automatically.
No need to paste `find` output or ROADMAP — Claude Code reads actual files before acting.

**Session close:** Claude Code updates all three docs (ROADMAP + METODOLOGIA + ARQUITECTURA) in one step.

**Commit discipline:** Commit after each logical unit, not at session close. If something breaks mid-session, rollback is clean.

### MCP servers (user scope, all connected)
| Server | Package / URL | Status | Purpose |
|--------|--------------|--------|---------|
| XcodeBuildMCP | `npx -y xcodebuildmcp@latest mcp` | ✅ Connected | Build, simulator control, LLDB, read Xcode errors |
| context7 | `https://mcp.context7.com/mcp` (HTTP) | ✅ Connected | Live GRDB, SwiftUI, JS library docs |
| github | `https://api.githubcopilot.com/mcp` (HTTP) | ✅ Connected | PR/issue management |
| mobile-mcp | `npx -y @mobilenext/mobile-mcp@latest` | ✅ Connected | iOS Simulator UI automation |
| apple-docs | `npx -y @kimsungwhee/apple-docs-mcp@latest` | ✅ Connected | SwiftUI + iOS 26 API from developer.apple.com |

**Install syntax:** `--scope user` flag must come BEFORE the `--` separator. Everything after `--` is passed to the subprocess.
```bash
claude mcp add --scope user XcodeBuildMCP -- npx -y xcodebuildmcp@latest mcp   # correct
claude mcp add XcodeBuildMCP -- npx -y xcodebuildmcp@latest mcp --scope user   # wrong — scope passed to npx
```

### Plugins
| Plugin | Installed | Purpose |
|--------|-----------|---------|
| swift-lsp@claude-plugins-official | v1.0.0 (since S13) | Real-time Swift diagnostics |

Install: `/plugin install swift-lsp@claude-plugins-official` inside a Claude Code session.
The `/plugin` marketplace system is real. Check with `/help` inside Claude Code.

### SourceKit false positives
swift-lsp analyzes files in isolation (not as the full Xcode module). It will report
"Cannot find type 'Manga' in scope" and similar errors on every Swift file. These are
always false positives — ignore them unless `xcodebuild` confirms the same error.
Rule: SourceKit errors are noise. xcodebuild errors are signal.

## Platform requirements

**Deployment target: iOS 26.2**
**Xcode:** 26+ (developer directory: `/Applications/Xcode.app`)
**Build for simulator:** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Yomi -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
**Available simulators (Xcode 26 / OS 26.3.1):** iPhone 16e, iPhone 17, iPhone 17 Pro, iPhone 17 Pro Max, iPhone Air. "iPhone 16 Pro" no longer exists.

### iOS 26-exclusive APIs in use

| API | File | Note |
|-----|------|------|
| `Tab("…", systemImage:, value:) {}` | ContentView.swift | New TabView syntax; `.tabItem {}` does not work; `.tag()` not available on iOS 26 Tab |
| `ContentUnavailableView` | BrowseView, HistoryView, PluginsView | Does not exist in iOS 18 |
| `.refreshable` | HistoryView | Does not exist in iOS 18 |
| `.searchable` | BrowseView, SourceBrowseView | Exists since iOS 15 but behavior differs |
| `.ascNullsLast` (GRDB) | ChapterQueries | GRDB helper that generates `ASC NULLS LAST` |
| `Text("\(Text(…)) …")` | HistoryView | Text interpolation in Text; `+` deprecated in iOS 26 |

### Why iOS 26 and not iOS 18
- The project was started on Xcode 26 beta from session 1
- `Tab()` with `value:` is the only syntax that renders tabs in iOS 26; `.tabItem {}` produces empty tabs
- Lowering the target would require `#available(iOS 26, *)` in ≥6 files and maintaining two code paths
- iOS 26 is the shipping OS in 2026; the development device can be updated

## Plugin format compatibility matrix

| Format | Description | Compatibility | Sources |
|--------|-------------|---------------|---------|
| **Yomi Format A** | Global JS functions: getMangaList, getChapterList, getPageList, searchManga | Native | MangaDex, Comick, Asura, AquaManga |
| **Yomi Format B (LNReader)** | `plugin` class: popularNovels, parseNovel, parseChapter, searchNovels | Native | Royal Road, ScribbleHub, NovelFire |
| **Paperback** | TypeScript → esbuild JS. `Source` class export. getHomePageSections, getSearchResults, getChapterDetails | JSBridge shim implemented (S24) | ~100 iOS sources |
| **Keiyoushi / Tachiyomi** | Kotlin → Android APK. Inter-process via PackageManager. | ❌ Impossible on iOS | N/A |
| **Aidoku** | Swift → WebAssembly (.aix). WasmSwift runtime. | ❌ Requires WASM runtime | N/A |

### Paperback shim design (implemented S24)
Paperback extensions export: `export const sources = { MySource }` where `MySource` extends `Source`.
The JSBridge shim would inject before plugin eval:
```javascript
// Injected preamble
class Source { constructor(s) { this.stateManager = s; } }
var sources = {};
```
After eval, detect `Object.keys(sources).length > 0` → Paperback format.
Map methods: `getHomePageSections` → `getMangaList`, `getSearchResults` → `searchManga`,
`getChapterDetails` → `getChapterList` + `getPageList`.

### LNReader sources available today (no new code needed)
LightNovelPub, WuxiaWorld, FreeWebNovel, NovelBin, ReadLightNovel, WebNovelPub.
Write `.ts` plugin in `scripts/plugins-src/`, build with `build-plugins.mjs`, deploy to Firebase.
Constraint: JavaScriptCore has no event loop. Only microtask-chain Promises work (no setTimeout/setInterval).
Covers 95%+ of LNReader sources. Sources using `crypto` module need a `require('crypto')` shim (CommonCrypto bridge).

## Known architectural issues

### @Observable computed property chain — theme/accent ✅ Fixed S23
All 11 AppSettings properties are now stored properties with `didSet`. `@Observable` correctly
instruments them. `colorScheme` remains computed and is now reactive because `theme` (its source)
is tracked. Dark mode and accent color apply instantly at runtime. See METODOLOGIA.md Technical
learnings S23 for the full pattern explanation.

## Comments / Discussion architecture (planned S23)

### Approach: "Discuss" button → WKWebView bottom sheet
Native UGC comments require moderation infrastructure, privacy policy update, and Apple age gating.
The correct approach: plugin declares an optional `getDiscussionURL(chapterPath)` function.
When present, a "Discuss" button appears in `ReaderOverlayView`.
Tapping it opens a `.sheet` presenting a `WKWebView` pointing to the chapter's comment page.

**Plugin format extension (optional):**
```javascript
// Format A — optional
function getDiscussionURL(chapterPath) {
    return "https://site.com/chapter/123#comments";
}
```
JSBridge detects: `context.objectForKeyedSubscript("getDiscussionURL").isObject`.

### Disqus read-only comments (future)
Sites using Disqus (Flame Scans, MangaFire) can be queried via Disqus API:
`GET https://disqus.com/api/3.0/threads/listPosts.json?forum={shortname}&thread=link:{url}&api_key={key}`
Returns read-only comments natively — no moderation burden, no UGC risk.
Plugin declares `disqusShortname` field. Future feature, not S23.

## Design decisions
| Decision | Discarded alternative | Reason |
|----------|----------------------|--------|
| JavaScriptCore | WKWebView | Headless, no UI, lighter for plugins |
| GRDB | SwiftData | Schema control, migrations, maturity |
| Local .js plugins | Own remote API | No server, works offline |
| Own Format A | LNReader only | LNReader has no manga plugins, only novels |
| Keiyoushi as reference (S4–S17) | Try to run .apk | Android .apk don't run on iOS; replaced in S18 by real Yomi-native catalog |
| Yomi-native plugin catalog (S18) | Keiyoushi Android catalog | Keiyoushi plugins are Android .apk — incompatible with iOS. Yomi hosts its own index.json on Firebase Hosting with real installable .js plugins |
| require() shim over esbuild-only | Require esbuild for all plugins | Shim enables LNReader v2.x plugins to run without a build step; esbuild script available for TS authoring |
| nonisolated GRDB access | Singleton property on MainActor | Module-level `nonisolated(unsafe) var appDatabase` is the official GRDB pattern for Swift 6 — avoids actor hops in *Queries |
| UserDefaults for settings | CoreData / JSON file | Simple settings don't need a DB |
| MAL token in Keychain | UserDefaults | Migrated to Keychain in S24 for App Store compliance |
| Manual JSON backup | CloudKit / iCloud Drive sync | No dependency on Apple services; portable across platforms |
| MAL PKCE plain | PKCE S256 | MAL API only supports the plain method |
| debounceTask (Task.sleep) | Combine debounce | Less code, no Combine dependency, sufficient for a TextField |
| Firebase Hosting for plugin repo | Own server / paid CDN | Free, stable URLs, no backend — sufficient for index.json + .js files |
| module-level appRouter | AppRouter.shared singleton | Consistent with appDatabase pattern; nonisolated(unsafe) at module level is the established pattern in this project |
| Remove bundled plugins for App Store | Ship 7 .js files in binary | Binary with piracy-adjacent content risks rejection; user-installed model is legally sound and has App Store precedent |
| OnboardingView on first launch | No onboarding, empty state only | Without onboarding, new users see an empty app and churn; Paperback users confirm the "setup moment" is critical |

## App Store strategy
Yomi uses the extension model for App Store compliance, identical to Paperback and Aidoku:
- App binary ships with ZERO plugin .js files
- All plugins hosted on Firebase Hosting (https://yomi-plugins.web.app)
- Users install plugins themselves via PluginsView Browse tab
- First-launch OnboardingView guides users to install their first source
- App Store description frames Yomi as "an extensible reader with user-installed JavaScript plugins"
- seedBundledPlugins removed from YomiApp.swift before App Store build (S19)
- Legal precedent: Paperback (App Store), Aidoku (TestFlight) use identical model

## Language
All code, commits, documentation, prompts, and communication between
Claude.ai, Claude Code, and the developer are in English from Session 15 onward.
