# Roadmap — Yomi

## Current state (post S22)
App Store compliant: binary ships zero plugin files. All 7 plugins on Firebase CDN.
Dark mode, accent color, font size all wired correctly from S21. OnboardingView restored (S22
regression fix). PrivacyInfo.xcprivacy added — no longer a hard rejection risk. Reading
resume functional: chapter.progress saved and restored. Pan-when-zoomed implemented in
MangaPageView with clamped DragGesture. Browse pagination: SourceBrowseView has "Load more"
for both Format A and Format B. All S22 planned items complete.

## Technical debt
| Area | Issue | Priority |
|------|-------|----------|
| PluginCatalogService concurrent fetches | .onAppear fires on every tab switch. fetchCatalog() must guard !isLoading and entries.isEmpty\|\|forceRefresh to prevent redundant network calls. | High |
| .tint() across .fullScreenCover | .tint applied to ContentView() may not propagate into OnboardingView (new presentation context). Needs runtime verification — if broken, add .tint inside OnboardingView. | Medium |
| Novel chapter read semantics | NovelQueries.markRead() called on HTML load, not scroll-to-end. Chapter is "read" before user reads a single word. | Medium |
| Downloads cleanup | DownloadManager never cleans up Documents/Downloads/{mangaId}/ on manga delete. Disk leaks indefinitely. | Medium |
| MAL token → Keychain | Currently in UserDefaults. Must migrate to Keychain before App Store submission. | Medium |
| App icon | ⏭ Still pending since S12. Required before submission. | Medium |
| Privacy policy URL | App Store Connect requires a privacy policy URL for any app connecting to the internet. | Medium |

## Session 5 — Core UX ✅ Complete
| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ Save to library | Heart button saves/removes manga from library. LibraryView loads from DB instead of hardcoded data |
| 2 | ✅ Mark chapter as read | On reaching the last page, isRead=true is set in DB |
| 3 | ✅ Chapter pagination | mangadex.js fetches all chapters with offset loop (limit=500, cap 20 iterations) |
| 4 | ✅ History tab | List of manga with lastReadAt != nil, sorted by date desc |
| 5 | ✅ Prev/next chapter | Buttons in reader overlay to navigate between chapters |
| 6 | ✅ Dedup plugin install | SHA256(URL).prefix(8) via CryptoKit as stable id |

## Session 6 — LNReader Compatibility ✅ Complete
| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ Real cheerio shim | Recursive HTML parser + CSS selector engine in pure JS |
| 2 | ✅ Novel model | NovelItem, SourceNovel, JSNovelChapter + novel and novel_chapter tables |
| 3 | ✅ NovelDetailView | Cover, author, status, chapter list |
| 4 | ✅ TextReaderView | WKWebView with font size slider, dark/light toggle, immersive overlay |
| 5 | ✅ BrowseView dual-format | Detects isLNReaderPlugin, shows manga or novels |

## Session 7 — Settings & Insights ✅ Complete
| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ NSFW filter | Toggle in PluginsView hides nsfw==1 entries from Keiyoushi catalog |
| 2 | ✅ Browse picker fix | Segmented picker moved under nav bar with .inline to avoid overlap |
| 3 | ✅ AppSettings | @Observable singleton with UserDefaults, 6 settings |
| 4 | ✅ SettingsView | General / Reader manga / Reader novel / Appearance |
| 5 | ✅ InsightsView | Total reading time and per-title (readingSeconds), formatTime helper |
| 6 | ✅ DB v4 migration | readingSeconds INTEGER on manga and novel |
| 7 | ✅ Time tracking in reader | onDisappear accumulates seconds in manga.readingSeconds |
| 8 | ✅ keepScreenOn + readerMode | AppSettings applied in reader |
| 9 | ✅ MoreView restructured | Settings, Plugins, Insights, About (with LicensesView) |

## Session 8 — Sync, Tracking & Polish ✅ Complete
| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ Backup & Restore | Export manga + chapters to JSON, import with upsert merge |
| 2 | ✅ MyAnimeList OAuth | PKCE plain login, yomi:// callback, automatic tracking on chapter finish |
| 3 | ✅ Prev/next chapter (refactor) | currentChapterIndex + activeChapter, navigateToChapter, hasPrev/hasNext |
| 4 | ✅ Per-chapter reading timer | Timer 1s, ChapterQueries.addReadingTime on disappear/nav |
| 5 | ✅ DB v4_reading_time | readingSeconds INTEGER on chapter |
| 6 | ✅ HistoryView rewrite | Task.detached + MainActor.run, clear button |
| 7 | ✅ InsightsView | Moved to Features/More, uses accumulated readingSeconds per chapter |
| 8 | ✅ SettingsView | Moved to Features/More, uses 6 real AppSettings properties |
| 9 | ✅ MangaDetailView | Heart with upsert/insert, merge isRead+readingSeconds from DB |
| 10 | ✅ MangaQueries | fetchRecentlyRead, upsert; removed fetchHistory (dead code) |
| 11 | ✅ PluginsView | SHA256 id to 32 chars (prefix(32)) |
| 12 | ✅ mangadex.js | getChapterList with limit=100, offset loop, cap 2000 |
| 13 | ✅ MoreView | Sections: App / Sources / Reading / Tracking / Data / Info |

## Session 9 — Polish & Real Data ✅ Complete
| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ Save to library | Heart → MangaQueries.toggleLibrary (upsert + lastUpdatedAt), @State var manga mutable |
| 2 | ✅ Mark chapter as read | Last page + onDisappear if currentPage > 0 |
| 3 | ✅ ChapterQueries complete CRUD | fetchAll, fetchOne, fetchByManga, fetchUnread, insert, upsert, upsertAll, markRead(id:), markRead(id:mangaId:), markAllRead, updateProgress, addReadingTime, delete, deleteAll |
| 4 | ✅ MangaQueries toggleLibrary + fetchHistory | Atomic toggleLibrary, fetchHistory without limit |
| 5 | ✅ History tab real data | MangaQueries.fetchHistory(), RelativeDateTimeFormatter, sourceId caption, refreshable |
| 6 | ✅ LibraryViewModel sort | lastReadAt DESC NULLS LAST, then title ASC in Swift |
| 7 | ✅ Search within source | BrowseView Search tab, client-side filter over getMangaList, source picker |
| 8 | ✅ Cover skeleton shimmer | Animated LinearGradient startPoint/endPoint sweep, showIcon on .failure |
| 9 | ✅ Double-tap zoom reset | simultaneousGesture(TapGesture(count:2)) + spring animation |
| 10 | ✅ asurascans.js | Format A plugin, HTML scraping with indexOf/split/substring, no cheerio |
| 11 | ✅ Fix Extension+Hashable | Picker requires Hashable on selection type |
| 12 | ✅ Fix Text+Text iOS 26 | Text("\(Text(date, style:.relative)) ago") replaces + operator |

## Session 10 — Server-side Search & Categories ✅ Complete
| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ searchManga in plugins | mangadex.js + asurascans.js — searchManga(query, page) with real endpoints |
| 2 | ✅ JSBridge.searchManga | searchManga(query:page:sourceId:) — Format A server-side, Format B returns [] |
| 3 | ✅ BrowseView server-side search | Replaces client-side filter with debounce 500ms + Task.detached + bridge.searchManga |
| 4 | ✅ Migration v5_categories | manga_category table (mangaId + categoryId, composite PK, ON DELETE CASCADE) |
| 5 | ✅ CategoryQueries.swift | Full CRUD: fetchAll, insert, rename, delete, updateSort, assign, unassign, categoriesForManga, mangaIds(inCategory:) |
| 6 | ✅ LibraryViewModel categories | selectedCategoryId, filteredIds (Set<String>), displayedManga, loadCategories() |
| 7 | ✅ LibraryView category chips | Horizontal ScrollView, "All" chip + per category, .safeAreaInset, hidden when no categories |
| 8 | ✅ CategoryView.swift | CRUD UI: create, rename, reorder, delete categories |
| 9 | ✅ MoreView Library section | NavigationLink → CategoryView |

## Session 11 — Polish & Updates ✅ Complete
| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ Assign manga to category | Sheet in MangaDetailView with checkboxes, tag button in toolbar (disabled if !inLibrary) |
| 2 | ✅ Chapter load more | displayedChapterCount=50, "Load N more" button, real index via firstIndex(where:) |
| 3 | ✅ Updates tab | UpdatesViewModel with withTaskGroup, checkUpdates per plugin, touchLastUpdated if hasNew |

## Session 12 — Downloads & Plugins ✅ Complete
| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ Aqua Manga plugin | Format A scraping, cheerio, getMangaList/getChapterList/getPageList/searchManga |
| 2 | ✅ Offline downloads | DownloadManager singleton @Observable, sequential queue, parallel pages x3, Documents/Downloads/{mangaId}/{chapterId}/, DownloadQueries, DownloadsView in More, badge + swipe in MangaDetailView, local fallback in ChapterReaderView |
| 3 | ⏭ App icon | Pending — user adds manually when design is ready |

## Session 13 — Audit & Fixes ✅ Complete
| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ seedBundledPlugins | mangadex, asurascans, aquamanga copied from bundle to Documents/Extensions/ on launch; SHA256(filename) as stable ID; DB upsert; skip if file already exists on disk |
| 2 | ✅ bridge(for:) URL fix | Reconstructs URL from extensionsDirectory + id instead of using stale ext.sourceListURL stored in DB |
| 3 | ✅ mangadex.js multi-language | getChapterList includes es/es-la/pt-br/pt in translatedLanguage[]; guard NaN on chapterNumber; fix empty title |
| 4 | ✅ SOURCE.fetch User-Agent | Default headers: User-Agent iPhone Safari + Accept + Accept-Language; plugins can override with their own headers |

## Session 14 — Plugins & UX fixes ✅ Complete
| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ Fix InsightsView crash | Active breakpoint disabled — not a real deadlock |
| 2 | ✅ Fix "Failed to load source plugin" | BrowseView + UpdatesView: bridge(for:) instead of ext.sourceListURL |
| 3 | ✅ royalroad.js | Format B, embedded JSON + HTML fallback |
| 4 | ✅ scribblehub.js | Format B, AJAX POST TOC |
| 5 | ✅ novelfire.js | Format B, chapter pagination |
| 6 | ✅ comick.js | Format A, public JSON API |
| 7 | ✅ LibraryView empty state | "Browse sources" button created (callback pending S15) |
| 8 | ✅ Source.swift removed | + FetchableRecord conformance removed from DatabaseManager |
| 9 | ✅ UpdatesView empty state icon | arrow.clockwise → bell.badge |
| 10 | ✅ AppSettings decimal locale | specifier: "%.1f" → String(format:locale:en_US) |

## Session 15 — Navigation, retention & infrastructure ✅ Complete
| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ AppRouter | @Observable module-level singleton, selectedTab: Int, tab index constants |
| 2 | ✅ ContentView TabView selection | Tab(value:) with AppRouter.selectedTab, @Bindable var router |
| 3 | ✅ LibraryView empty state navigation | appRouter.selectedTab = AppRouter.tabBrowse functional |
| 4 | ✅ JSBridge HTTP POST | SOURCE.fetch supports method/body/headers; _fetchSync receives 4 args |
| 5 | ✅ ContinueReadingRow | Horizontal scroll row in LibraryView, MangaQueries.fetchRecentlyRead, hides when empty |
| 6 | ✅ NotificationManager | @Observable singleton, UNUserNotificationCenter, requestPermission async, scheduleChapterNotification |
| 7 | ✅ AppSettings.hasRequestedNotifications | UserDefaults flag to request permission only once |
| 8 | ✅ Push notification trigger | MangaDetailView: requestPermission on first library save |
| 9 | ✅ TextReaderView typography | #E8E8E8, line-height 1.5, 18pt minimum font, sepia mode toggle |
| 10 | ✅ AppSettings.novelSepia | UserDefaults flag for sepia mode |
| 11 | ✅ Fix MangaDetailView loadChapters | bridge(for:) instead of stale ext.sourceListURL |
| 12 | ✅ Fix ContinueReadingRow .task | Single .task on Group container, removes duplicate |
| 13 | ✅ Fix Comick domain | comick.io → comick.fun |
| 14 | ✅ Debug prints cleanup | JSBridge.swift + ExtensionManager.swift |

## Session 16 — Plugin fixes ✅ Complete
| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ Fix seedBundledPlugins | Always overwrite bundled JS on launch — skip logic prevented fixes from deploying to simulator |
| 2 | ✅ Fix each() in all plugins | cheerio shim passes wrapped object to each() callback — use el.find() not $(el) |
| 3 | ✅ Fix aquamanga domain | aquamanga.com → aquareader.net |
| 4 | ✅ Fix aquamanga cover selector | div.item-thumb img → .item-thumb img (class is on container, not child div) |
| 5 | ✅ Royal Road working | Format B, popularNovels via div.fiction-list-item, verified selectors |
| 6 | ✅ ScribbleHub working | Format B, popularNovels via div.search_main_box, verified selectors |
| 7 | ✅ NovelFire working | Format B, popularNovels via li.novel-item, verified selectors |
| 8 | ✅ AquaManga working | Format A, getMangaList via div.page-item-detail, verified selectors |

## Session 17 — Insights v2 & Asura API ✅ Complete
| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ InsightsView v2 | 4 stat cards: streak, chapters read, time read, titles started. Streak from readAt dates. |
| 2 | ✅ asurascans.js | Full JSON API rewrite via api.asurascans.com. All 7 bundled plugins now working. |

## Session 18 — Plugin Catalog Infrastructure ✅ Complete
| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ AppSettings.pluginCatalogURL | UserDefaults, default https://yomi-plugins.web.app/index.json, overridable in Settings |
| 2 | ✅ PluginCatalogService.swift | NEW @Observable singleton. PluginCatalogEntry Codable struct (id, name, version, language, description, iconURL, fileURL, isNSFW). fetchCatalog() async via URLSession. isInstalled(_:) checks ExtensionManager.shared.installed |
| 3 | ✅ JSBridge require() shim | Functional shim injected before plugin eval. Handles: cheerio (routes to global), he (inline entity decoder: decode/encode, named + numeric + hex entities), node-fetch (stub routing to SOURCE._fetchSync, returns .text()/.json() promise-compatible), axios (get/post stubs), unknown modules (empty exports, no crash). Also injects: module, exports, process globals. Enables LNReader v2.x plugins without esbuild compilation. |
| 4 | ✅ PluginsView Browse tab | Replaced old Keiyoushi Android reference catalog. PluginsView now shows Installed and Browse sections. Browse: fetches PluginCatalogService, List with AsyncImage icon (40x40 rounded, puzzle piece fallback), name, LanguageBadge, NSFWBadge, version, Install button. installEntry() downloads and registers via ExtensionManager. NSFW toggle writes to AppSettings.shared.showNSFW. |
| 5 | ✅ SettingsView Developer section | TextField for pluginCatalogURL at bottom of form. Monospaced font. Caption + footer with default URL. |
| 6 | ✅ scripts/build-plugins.mjs | Node.js ESM esbuild script. Reads scripts/plugins-src/*.ts, bundles each to IIFE ES6, writes to Yomi/Resources/ + Firebase public dir (~/Desktop/yomi-firebase/public/). Auto-generates index.json with SHA256 IDs from metadata comments (@name, @version, @lang, @description, @icon, @nsfw). |
| 7 | ✅ scripts/catalog-output/index.json | Seeded catalog with all 7 plugins: MangaDex, Comick, Asura Scans, AquaManga, Royal Road, ScribbleHub (isNSFW:true), NovelFire. fileURL: https://yomi-plugins.web.app/{name}.js. SHA256(fileURL).prefix(32) as id. |

## Session 19 — App Store compliance + Onboarding + Reader UX (partial)
| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ App Store compliance | .js files removed from Xcode target membership. seedBundledPlugins() call removed from YomiApp.init. Method kept in ExtensionManager for dev use. Binary now ships zero plugin files. |
| 2 | ✅ OnboardingView | 3-page TabView(.page) fullScreenCover on #1C1C1E bg. Page 1: book.fill + "Welcome to Yomi". Page 2: "Install a Plugin" + yomi-plugins.web.app. Page 3: "You're all set" → appRouter.selectedTab = tabMore + dismiss(). Gated by AppSettings.hasSeenOnboarding UserDefaults flag. |
| 3 | ✅ ChapterReaderView immersive | Color.clear.contentShape(Rectangle()).onTapGesture { showOverlay.toggle() } added in ZStack behind reader content — tap toggles chrome without blocking scroll/pinch. |
| 4 | ✅ HistoryView plugin display name | HistoryRow: Text(manga.sourceId) replaced by ExtensionManager.shared.installed.first { $0.id == manga.sourceId }?.name ?? manga.sourceId. |
| 5 | ⚠️ Dark mode | preferredColorScheme applied at WindowGroup root in YomiApp.swift. colorScheme: ColorScheme? added to AppSettings. Compiled but not confirmed working — simulator stays light. Needs diagnostic read at S20 start. |
| 6 | ⚠️ TextReaderView font re-inject | Coordinator.lastHTML re-inject pattern in place. Colors updated (dark #1C1C1E/#E8E8E8, sepia #FFF8F0/#2C1810, light #FFFFFF/#1C1C1E), line-height 1.6. AppSettings.novelFontSize still disconnected from local @State fontSize slider — not the single source of truth. |

## Session 20 — Core reading experience fixes ✅ Complete
| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ Dark mode | @State private var settings = AppSettings.shared in YomiApp. @Observable tracking now fires on WindowGroup body re-evaluation. .preferredColorScheme(settings.colorScheme) reacts to theme changes at root. |
| 2 | ✅ PluginsView catalog | .task replaced by .onAppear { Task { await catalogService.fetchCatalog() } } — fires on every tab switch, not just first appear. Added: retry button on error, empty state with puzzle icon + "No plugins found", pull-to-refresh. |
| 3 | ✅ TextReaderView fontSize | @State fontSize initialized from AppSettings.shared.fontSize (was hardcoded 18). .onChange on Slider writes back to AppSettings.shared.fontSize. SettingsView Stepper and TextReaderView slider now share a single source of truth. |
| 4 | ✅ Accent color picker | AppSettings.accentColor: String (default #FF6B6B). 6-swatch picker in SettingsView Appearance section (Red, Blue, Green, Orange, Purple, Pink). Color(hex:) extension in AppSettings.swift. .tint(Color(hex: settings.accentColor)) applied at WindowGroup root alongside .preferredColorScheme. |

## Session 21 — Settings & Reader Fixes ✅ Complete
| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ Color+Hex.swift | New file Yomi/Core/Color+Hex.swift. Color(hex:) handles #RRGGBB and #RRGGBBAA. Color.hexString converts back to #RRGGBB via UIColor sRGB. Single definition — old duplicate in AppSettings removed. |
| 2 | ✅ fontSize unified | AppSettings default 16.0 → 18.0. max(18,...) clamp removed from styledHTML. Slider range 14–28 in both SettingsView and reader overlay. Single source of truth. |
| 3 | ✅ Dark mode + accent color wired | AppSettings gains colorScheme: ColorScheme? computed var and accentColor: String (default #FF6B6B). YomiApp: @State private var settings drives .preferredColorScheme + .tint on ContentView. |
| 4 | ✅ Accent color picker | SettingsView Appearance: 10 curated swatches + custom ColorPicker sheet (.presentationDetents .medium). hexString binding via Color+Hex.swift. |
| 5 | ✅ #if DEBUG seedBundledPlugins | YomiApp.init() calls ExtensionManager.shared.seedBundledPlugins() inside #if DEBUG. Plugins available in simulator. Release/App Store binary unaffected. |
| 6 | ✅ TextReaderView CSS re-injection | fontSize initialized from AppSettings.shared.fontSize. lineSpacing reads AppSettings.shared.lineSpacing. onChange(of: fontSize) persists back. ReaderWebView.updateUIView re-injects <style> via evaluateJavaScript on every render — avoids full page reload. |
| 7 | ⚠️ OnboardingView removed from YomiApp | fullScreenCover + showOnboarding @State were dropped in S21 (not in prompt scope). New users skip onboarding. Must be restored in S22. |
| 8 | ⚠️ NovelQueries.markRead() removed | TextReaderView.loadContent() no longer marks novel chapters as read. Silent regression from S21 rewrite. Must be restored in S22. |

## Session 22 — Regressions + Core UX ✅ Complete
| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ Restore OnboardingView | @State showOnboarding = !AppSettings.shared.hasSeenOnboarding in YomiApp. .fullScreenCover on ContentView(). |
| 2 | ✅ Restore markRead | Task { try? NovelQueries.markRead(chapterId: chapter.id) } after rawContent = html in TextReaderView.loadContent(). |
| 3 | ✅ PrivacyInfo.xcprivacy | Yomi/PrivacyInfo.xcprivacy. XML plist, NSPrivacyAccessedAPICategoryUserDefaults reason CA92.1. PBXFileSystemSynchronizedRootGroup auto-included — no manual Xcode step. |
| 4 | ✅ Reading resume | Task.detached reads ChapterQueries.fetchOne(id:) after pages load. Sets currentPage = Int(progress * Double(pageCount - 1)) on MainActor. |
| 5 | ✅ Pan when zoomed | MangaPageView: GeometryReader for dimensions, @State offset/lastOffset, DragGesture with clamping (maxX = (scale-1)*width/2). Guard scale > 1.0 to not intercept TabView swipes. Double-tap resets both scale and offset. |
| 6 | ✅ Browse pagination | SourceBrowseView: currentPage, isLoadingMore, hasMoreContent state. "Load more" button below LazyVGrid. Appends results for Format A and B. Hidden during local search filter and when last page returns empty. |

## App Store submission checklist
These items must ALL be complete before submitting to App Store Connect:

| Item | Status | Notes |
|------|--------|-------|
| PrivacyInfo.xcprivacy | ✅ Done S22 | NSPrivacyAccessedAPICategoryUserDefaults reason CA92.1. |
| Privacy policy URL | ❌ Missing | Required for any app connecting to the internet. Host a static page. |
| App icon | ❌ Missing | All required sizes. Use Asset Catalog. |
| Zero .js in binary | ✅ Done S19 | Confirmed — plugins on Firebase CDN only. |
| PrivacyInfo.xcprivacy | ✅ Done S22 | NSPrivacyAccessedAPICategoryUserDefaults reason CA92.1. |
| MAL token in Keychain | ❌ Pending | Currently in UserDefaults. Migrate before submission. |
| Age rating: 17+ | ❌ Pending | App enables NSFW content via user-installed plugins. Must declare. |
| App description | ❌ Missing | Frame as "extensible reader — user-installed JS plugins". No source names. |
| Screenshots | ❌ Missing | iOS 26 simulator. Neutral content only (no recognizable piracy sources). |
| Support URL | ❌ Missing | GitHub repo or a simple landing page is sufficient. |

## App Store compliance
Yomi is App Store compliant via the extension model:
- App binary ships with ZERO plugin files
- Users install plugins themselves from Firebase catalog (user action, not Apple's)
- Legal precedent: Paperback, Aidoku use identical model and are on App Store
- App Store description: "extensible reader with user-installed JavaScript plugins"
- Never reference specific source sites in App Store listing or screenshots
- Onboarding must make the install-a-source flow feel easy (under 60 seconds)

## iOS compatibility

**Deployment target: iOS 26.2** — no plan to lower to iOS 18.

The physical development device (Martin's iPhone, iOS 18.6.2) cannot run
the app until updating to iOS 26. The app depends on iOS 26-exclusive APIs:
`Tab()`, `ContentUnavailableView`, `.refreshable`, `.searchable`, `.ascNullsLast`.

If iOS 18 support is required in the future → branch `compat/ios18`, never on main.

## Target plugin sources
| Source | Format | Status |
|--------|--------|--------|
| MangaDex | Format A (JSON API) | ✅ Working — on Firebase |
| Comick | Format A (JSON API) | ✅ Working — on Firebase |
| Asura Scans | Format A (JSON API) | ✅ Working — on Firebase |
| AquaManga | Format A (scraping) | ✅ Working — on Firebase |
| Royal Road | Format B (LNReader) | ✅ Working — on Firebase |
| ScribbleHub | Format B (LNReader) | ✅ Working — on Firebase |
| NovelFire | Format B (LNReader) | ✅ Working — on Firebase |
| NovelUpdates | Format B (LNReader) | S20 backlog |

⚠️ Always verify current HTML of each source — selectors can change without notice.
