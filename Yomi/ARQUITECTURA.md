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
│       ├── MangaQueries.swift       # CRUD manga: fetchAll, fetchOne, fetchLibrary, fetchLibraryByLastUpdated, fetchRecentlyRead, insert, update, upsert, touchLastRead, touchLastUpdated, delete
│       ├── ChapterQueries.swift     # CRUD chapter: fetchAll(ASC NULLS LAST), fetchOne, insert, upsert, upsertAll, markRead, markAllRead, updateProgress, addReadingTime, delete, deleteAll
│       ├── CategoryQueries.swift    # CRUD category + manga_category join: fetchAll, insert, rename, delete, updateSort, assign, unassign, categoriesForManga, mangaIds(inCategory:)
│       ├── NovelQueries.swift       # CRUD novel + novel_chapter
│       └── ExtensionQueries.swift   # CRUD extensions
├── Core/
│   ├── AppRouter.swift              # @Observable singleton for programmatic tab navigation
│   ├── Color+Hex.swift             # Color(hex:) init (#RRGGBB and #RRGGBBAA) + Color.hexString via UIColor sRGB
│   └── NotificationManager.swift   # @Observable singleton, UNUserNotificationCenter
├── Features/
│   ├── Library/
│   │   ├── LibraryView.swift        # Saved manga grid + horizontal category filter chips + ContinueReadingRow
│   │   ├── LibraryViewModel.swift   # State, filtering, sort by lastReadAt DESC NULLS LAST; selectedCategoryId + displayedManga
│   │   ├── CategoryView.swift       # Category CRUD UI (create, rename, reorder, delete)
│   │   ├── ContinueReadingRow.swift # Horizontal scrollable row of recently read manga
│   │   ├── MangaCoverCell.swift     # Cover cell + animated ShimmerView skeleton
│   │   └── MangaDetailView.swift    # Detail + chapter list + heart button (upsert) + DB merge + category assignment sheet + chapter pagination (50/page)
│   ├── Browse/
│   │   ├── BrowseView.swift         # Sources tab + SearchView (server-side search with debounce 500ms) + SourceBrowseView (dual manga/novel)
│   │   │                            # ⚠️ SourceBrowseView calls getMangaList(page: 1) once — no pagination, no "load more". Users see only first ~20 titles per source.
│   │   └── NovelDetailView.swift    # Novel detail + chapter list
│   ├── Reader/
│   │   ├── ChapterReaderView.swift  # RTL manga + webtoon, zoom, overlay, prev/next chapter via currentChapterIndex+navigateToChapter, reading timer, MAL tracking; accepts chapters:[Chapter] for navigation
│   │   │                            # ⚠️ chapter.progress IS saved on disappear but never restored on open — currentPage always starts at 0
│   │   │                            # ⚠️ MangaPageView: .scaleEffect zoom works but no DragGesture offset — pan at zoom >1x is missing
│   │   └── TextReaderView.swift     # HTML reader for novels (WKWebView, font size, dark/light/sepia)
│   │                                # ⚠️ NovelQueries.markRead() called on chapter load, not on scroll-to-end — semantically incorrect
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
├── AppSettings.swift                # @Observable singleton, UserDefaults-backed, 12 properties. colorScheme: ColorScheme? derived from theme. accentColor: String hex default #FF6B6B. fontSize default 18.0.
├── ContentView.swift                # Root TabView with AppRouter selection binding
├── YomiApp.swift                    # Entry point. DB setup. #if DEBUG seedBundledPlugins(). @State private var settings drives .preferredColorScheme(settings.colorScheme) + .tint(Color(hex: settings.accentColor)) on ContentView(). ⚠️ OnboardingView fullScreenCover removed in S21 — restore in S22.
├── PrivacyInfo.xcprivacy            # ❌ MISSING — required for App Store (iOS 17+). Must declare NSPrivacyAccessedAPICategoryUserDefaults.
├── Resources/
│   └── test-source.js               # Test plugin (Format A) — kept for SwiftUI previews only
│   # Note: 7 production plugins (mangadex, asurascans, aquamanga, comick,
│   # royalroad, scribblehub, novelfire) removed from binary in S19 for App Store
│   # compliance. All plugins hosted on Firebase: https://yomi-plugins.web.app
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

### Current tables (migration v5)
```sql
manga        (id, path, sourceId, title, coverURL, summary, author, artist,
              status, genres JSON, inLibrary, isLocal, lastReadAt, lastUpdatedAt,
              readingSeconds INTEGER NOT NULL DEFAULT 0)

chapter      (id, mangaId FK→manga, path, name, chapterNumber, isRead,
              isDownloaded, readAt, progress,
              readingSeconds INTEGER NOT NULL DEFAULT 0)

category     (id, name, sort)

manga_category (mangaId TEXT NOT NULL FK→manga ON DELETE CASCADE,
                categoryId TEXT NOT NULL FK→category ON DELETE CASCADE,
                PRIMARY KEY (mangaId, categoryId))

source       (id, name, language, version, iconURL, baseURL, isInstalled, isNSFW)

extension    (id, name, version, language, iconURL, sourceListURL,
              isInstalled, isNSFW, sourceIds JSON)

novel        (id, path, sourceId, title, coverURL, summary, author, status,
              genres JSON, inLibrary, lastReadAt, lastUpdatedAt,
              readingSeconds INTEGER NOT NULL DEFAULT 0)

novel_chapter (id, novelId FK→novel, path, name, chapterNumber, isRead,
               readAt, releaseTime)
```

### Migrations
- **v1_initial**: manga, chapter, category, source
- **v2_extensions**: extension
- **v3_novels**: novel, novel_chapter
- **v4_reading_insights**: `ALTER TABLE manga ADD COLUMN readingSeconds` / `ALTER TABLE novel ADD COLUMN readingSeconds`
- **v4_reading_time**: `ALTER TABLE chapter ADD COLUMN readingSeconds INTEGER NOT NULL DEFAULT 0`
- **v5_categories**: manga_category join table (mangaId + categoryId, composite PK, ON DELETE CASCADE)

> Note: two migrations with v4_ prefix coexist without conflict — GRDB tracks them by string name, not number. Next migration must use prefix `v6_`.

### Why GRDB and not SwiftData
- Full SQL schema and incremental migration control
- More mature and stable
- Compatible with schemas inspired by LNReader/Mihon

## Singletons / core state

### AppSettings (Yomi/AppSettings.swift)
`@Observable final class`, accessed via `AppSettings.shared`
- `readerMode: String` — "Manga (RTL)" or "Webtoon"
- `fontSize: Double` — novel reader font size (points)
- `lineSpacing: Double` — novel reader line spacing multiplier
- `theme: String` — "System", "Light", or "Dark"
- `useSystemFont: Bool` — system font vs built-in reader font
- `showNSFW: Bool` — show NSFW sources and catalog entries
- `hasRequestedNotifications: Bool` — flag to request permission only once
- `novelSepia: Bool` — sepia mode toggle for TextReaderView
- `pluginCatalogURL: String` — remote index.json URL; default `https://yomi-plugins.web.app/index.json`
- `hasSeenOnboarding: Bool` — UserDefaults flag; set to true when user completes OnboardingView; prevents re-showing on subsequent launches
- `accentColor: String` — hex string for app tint color; default `#FF6B6B`; 10-swatch picker + custom ColorPicker in SettingsView Appearance; applied via `.tint(Color(hex:))` on ContentView (S21)
- `colorScheme: ColorScheme?` — computed var derived from `theme`; nil = system, .light, or .dark; drives `.preferredColorScheme` at ContentView root (S21)

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
```

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
  comick.js
  asurascans.js
  aquamanga.js
  royalroad.js
  scribblehub.js
  novelfire.js
```

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

## Workflow and prompts

### Prompt template for Claude Code
Each prompt follows this structure:
1. Header: tech stack + build setting
2. ABSOLUTE RULES (nonisolated, Task.detached, no partials)
3. TASK: [Create/Edit] file + one-sentence description
4. If editing: "Read [file] first" — mandatory
5. REQUIREMENTS: specific list of what to add/change
6. DO NOT TOUCH: explicit list of intact methods/sections
7. OUTPUT: complete file + ADDED/MODIFIED/UNTOUCHED/LINES summary

### Session start
Paste into Claude.ai:
```
find Yomi -name "*.swift" | sort
find Yomi -name "*.js" | sort
cat Yomi/ROADMAP.md
```
METODOLOGIA.md and ARQUITECTURA.md are NOT pasted — they live in Claude.ai project knowledge.

### Session close
Claude.ai generates doc update prompt → Claude Code writes
all three files (ROADMAP + METODOLOGIA + ARQUITECTURA) in a single prompt.
Valid exception to "one file per prompt": they are docs, not Swift code.

## Platform requirements

**Deployment target: iOS 26.2**
**Xcode:** 26+ (developer directory: `/Applications/Xcode.app`)
**Build for simulator:** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Yomi -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`

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
| MAL token in UserDefaults | Keychain | Sufficient for MVP; migrate to Keychain before App Store |
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
