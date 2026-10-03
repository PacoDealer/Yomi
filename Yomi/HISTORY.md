# Session History — Yomi (archived detail log)

Full session-by-session build log, extracted from `ROADMAP.md` during the 2026-08-04 doc
restructure so ROADMAP.md can stay focused on current state + forward plan. This is historical
detail only — for current state see `ROADMAP.md`, for durable technical patterns/lessons see
`METODOLOGIA.md`.

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

## Session 23 — UX overhaul + core fixes ✅ Complete (2026-04-07)
Derived from deep UX research comparing Tachiyomi, Paperback, Aidoku, Moon+ Reader, MangaPlus,
Webtoon, and community feedback from r/manga, r/manhwa, r/lightnovels, GitHub issue trackers.

| # | Feature | Status | Detail |
|---|---------|--------|--------|
| 1 | Fix dark mode + accent color | ✅ Done | AppSettings: all 11 props converted from computed vars to stored properties with didSet. @Observable now tracks mutations. Changes apply instantly at runtime. |
| 2 | Plugin UX overhaul | ✅ Done | LibraryView empty state: if no plugins installed → "No plugins installed" + "Get plugins" → More tab. PluginsView installed empty: title + explanation text. Catalog empty: distinguishes search-no-results vs truly-empty (no spurious Retry). |
| 3 | LTR reading mode | ✅ Done | Added .horizontalLTR = "Manhwa (LTR)" to ReaderMode enum. MangaReaderView gains isRTL param (default true). LTR sets .environment(\.layoutDirection, .leftToRight). Picker in SettingsView updated. |
| 4 | Unread badge on library covers | ✅ Done | MangaCoverCell loads unread count via ChapterQueries.fetchUnread on .task. Shows accent-colored Capsule badge top-right of cover when unread > 0. |
| 5 | ContinueReading → open directly in reader | ✅ Done | ContinueReadingCell: tap → load chapters via JSBridge (Task.detached) → merge DB progress → find most-recently-touched chapter by readAt → navigationDestination(isPresented:) → ChapterReaderView. Spinner shown during load. |
| 6 | Bulk download | ✅ Done | "Download next N" button (max 10) in Chapters section header. Only shown when bridge available and unread+undownloaded chapters exist. Enqueues via DownloadManager.shared. |
| 7 | Storage size per manga | ✅ Done | MangaDetailView.computeStorageSize() enumerates Downloads/{mangaId}/ with FileManager, sums file sizes, formats via ByteCountFormatter. Displayed in Chapters header as "· X MB". |
| 8 | Page-jump slider in reader overlay | ✅ Done | ReaderOverlayView bottom bar: replaced static page text with Slider + "X / N" label. currentPage promoted to @Binding. Slider hidden in Webtoon mode. White tint on dark overlay. |
| 9 | Webtoon scroll position persistence | ⏭ S24 | WebtoonReaderView scroll not saved. ScrollViewReader + scrollTo on appear. |
| 10 | Library sort options | ⏭ S24 | No sort controls in LibraryViewModel. Add: Alphabetical, Last Read, Last Updated, Unread Count. |
| 11 | "Discuss" button in reader | ⏭ S24 | ReaderOverlayView → bottom sheet WKWebView → source's comment page. Plugin: optional getDiscussionURL(chapterPath). |
| 12 | Paperback compatibility shim | ⏭ S24 | JSBridge shim for Paperback-format extensions. Large (2-3 days). ~100 new sources. |
| 13 | App icon | ⏭ S24 | Coral-to-amber gradient + stylized 読 or kitsune. 1024×1024 PNG no alpha. App Store blocker. |

**Bonus fix (S23):** Accent color swatch row was overflowing off-screen (HStack with 10+ items).
Wrapped in ScrollView(.horizontal). Swatch size bumped 28→32pt. Custom picker button lost plain
buttonStyle — fixed.

## Session 24 — UX polish + App Store prep ✅ Complete (2026-04-07)

| # | Feature | Status | Detail |
|---|---------|--------|--------|
| 1 | Webtoon scroll persistence | ✅ Done | WebtoonReaderView: @Binding currentPage, ScrollViewReader + .scrollPosition(id:anchor:.top). On appear: scrollTo(currentPage). onChange(of: visibleId) updates currentPage. Removed premature markChapterRead on appear. |
| 2 | Library sort options | ✅ Done | SortOrder enum (Last Read / Alphabetical / Last Updated) in LibraryViewModel. displayedManga computed sort. LibraryView toolbar Menu with all options + checkmark on active. |
| 3 | "Discuss" button in reader | ✅ Done | JSBridge.getDiscussionURL(chapterPath:) calls optional plugin export. ReaderOverlayView: bubble icon button in top bar when URL available. DiscussWebSheet: NavigationStack + WKWebView, medium/large detents. |
| 4 | Paperback compatibility shim | ✅ Done | require('paperback-extensions-common') module in JSBridge. Source base class + App type constructors + RequestManager wrapping SOURCE._fetchSync. injectPaperbackAdapter() post-eval: detects Source subclass in exports, wires getMangaList/searchManga/getChapterList/getPageList adapters. Chapter paths encode mangaId|chapterId. |
| 5 | App icon | ⏭ S25 | Design task — coral-amber gradient + 読 or kitsune. App Store blocker. |
| 6 | MAL token → Keychain | ✅ Done | KeychainHelper (Core/KeychainHelper.swift): SecItemAdd/SecItemUpdate/SecItemCopyMatching/SecItemDelete. MALService.saveToken/loadToken migrated. loadToken auto-migrates legacy UserDefaults values. |
| 7 | Privacy policy URL | ⏭ S25 | Static page (GitHub Pages or Firebase). Required before App Store. |
| 8 | Novel read on scroll-to-end | ✅ Done | ReaderWebView: WKUserScript injected at documentEnd — scroll event listener fires readComplete message at 90% scroll ratio (once: true). Coordinator conforms to WKScriptMessageHandler. markRead moved from HTML-load to scroll event. |
| 9 | Downloads cleanup on delete | ✅ Done | MangaDetailView.toggleLibrary: when inLibrary becomes false, delete Documents/Downloads/{mangaId}/ via Task.detached + FileManager.removeItem. |

## Session 25 — ✅ Complete (2026-04-08)
| # | Feature | Detail |
|---|---------|--------|
| 1 | App icon | ⏭ Deferred — user designing separately |
| 2 | Privacy policy URL | ✅ privacy.html deployed to Firebase at yomi-plugins.web.app/privacy |
| 3 | Library unread count sort | ✅ SortOrder.unreadCount + ChapterQueries.fetchUnreadCountsByManga (single GROUP BY) |
| 4 | Multi-select long-press in library | ✅ MangaCoverCell: isSelecting/isSelected/onLongPress/onSelect. LibraryView: Cancel+SelectAll toolbar, bulk Remove from Library |
| 5 | Paperback plugin testing | ⏭ Deferred |
| 6 | PluginCatalogService cache guard | ✅ guard !isLoading at fetchCatalog() entry |
| 7 | Reading status field | ✅ ReadingStatus enum + v7_reading_status migration + MangaQueries.updateReadingStatus + ReadingStatusMenu pill in MangaDetailView |
| 8 | Extension catalog inline | ✅ Browse → Extensions sub-tab, YomiCatalogEntryRow reused. AppRouter.openBrowseExtensions deep link from Library |
| 9 | EXTENSIONS.md | ✅ Step-by-step install guide with copy-paste URLs for all 7 sources |

## Session 26 — ✅ Complete (2026-04-08)
| # | Feature | Detail |
|---|---------|--------|
| 1 | comick.js fix | Added COMICK_HEADERS (Referer + Origin). Fixed b2key image object format in getPageList. Deployed to Firebase. |
| 2 | Chapter selection mode | Long-press ChapterRow → isSelectingChapters + selectedChapterIds. Bottom action bar: mark read, mark unread, download, delete. Cancel button. |
| 3 | Download sub-menu | Chapters section header: ellipsis menu with Next / Next 5 / Next 10 / All unread / All chapters. Only shown when bridge available. |
| 4 | Per-chapter download button | Inline download icon on each ChapterRow. Taps DownloadManager.enqueue(). |
| 5 | Overflow menu | ellipsis.circle in MangaDetailView toolbar: Edit categories, Select chapters, heart toggle. |

## Session 27 — ✅ Complete (2026-04-08)
| # | Feature | Detail |
|---|---------|--------|
| 1 | Chapter.lastPageRead | New Int field on Chapter model. DB migration v8_last_page (ALTER TABLE chapter ADD COLUMN lastPageRead INTEGER DEFAULT 0). |
| 2 | completedDownloadCount | DownloadManager.completedDownloadCount Int observer. Increments after each successful download. MangaDetailView + DownloadsView observe via .onChange. |
| 3 | refreshChapterStates() | MangaDetailView: lightweight DB merge (isRead, isDownloaded, progress, lastPageRead, readAt) without JSBridge fetch. Called on .onAppear + download complete. |
| 4 | lastPageRead in reader | ChapterReaderView saves currentPage as lastPageRead on exit (onDisappear + navigateToChapter). Resumes from saved page on load. |
| 5 | ChapterRow progress | "Page N" subtitle for partially-read chapters. opacity 0.45 when isRead. |
| 6 | Browse source filter fix | BrowseView: extracted runSearch(query:debounce:). Both onChange(of: searchQuery) and onChange(of: selectedSource) call runSearch — source filter now immediately re-triggers search. |
| 7 | Settings: Items per row | AppSettings.libraryColumns: Int (UserDefaults, default 3). Stepper in SettingsView. LibraryView dynamic GridItem columns. |
| 8 | Settings: Keep screen on | AppSettings.keepScreenOn: Bool (UserDefaults, default true). Toggle in SettingsView. Applied in ChapterReaderView via isIdleTimerDisabled. |
| 9 | Settings: Clear image cache | Advanced section in SettingsView. URLCache.shared.removeAllCachedResponses() + haptic. |
| 10 | ChapterQueries.setRead | nonisolated static func setRead(chapterId: String, isRead: Bool) — used by bulk selection mark read/unread. |

## Session 28 — Full project audit (2026-04-08, no code shipped)
| # | Finding | Root Cause | Fix (S29) |
|---|---------|-----------|-----------|
| 1 | Downloads not showing | Chapters never INSERTed in DB; markDownloaded SQL UPDATE affects 0 rows | ChapterQueries.insertAllIgnoringConflicts() in loadChapters() |
| 2 | Read state not persisting | Same root cause — markRead SQL UPDATE affects 0 rows | Same fix |
| 3 | Novel reader overlay invisible | TextReaderView forces .preferredColorScheme(.dark) even in sepia; overlay gated on showOverlay bool | Remove forced dark colorScheme; redesign overlay |
| 4 | Novels not in Library | LibraryViewModel.loadLibrary() never calls NovelQueries.fetchLibrary() | Add novels field + call fetchLibrary() |
| 5 | No Popular/Latest tabs | Format A spec has no getPopularManga/getLatestManga; SourceBrowseView has no tab picker | Add optional functions to spec + Picker in SourceBrowseView |
| 6 | Comick broken | Code correct; Cloudflare or API change. Needs live diagnostic | curl test; update headers/endpoint |
| 7 | InsightsView ugly | Stat cards inside List row clips them awkwardly | Redesign as ScrollView with proper card layout |
| 8 | Settings incomplete | Many Tachimanga settings not yet in Yomi | Backup/Restore page, Reader settings sub-page, Incognito mode (P3) |

## Session 29 — Bug blitz + UX + Features (2026-04-09) ✅ Complete
All S28 P0/P1/P2/P3 items resolved.

| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ INSERT OR IGNORE chapters | ChapterQueries.insertAllIgnoringConflicts() added. Called in MangaDetailView.loadChapters() after JSBridge fetch, before DB merge. Fixes silent-fail root cause (downloads, read state, progress). |
| 2 | ✅ Chapter selection UX fix | Long-press ChapterRow enters selection mode. Tap navigates to reader (download button remains download-only). Chapter.Hashable conformance added for navigationDestination(item:). |
| 3 | ✅ Auto-delete download on mark-read | markSelected(read: Bool) auto-deletes downloaded files when marking chapters as read. |
| 4 | ✅ Auto-mark chapter as read | Chapter marked read automatically when: last page reached OR (multi-page chapter AND ≥80% read). No user action required. Fires in onDisappear and onChange(of: currentPage). |
| 5 | ✅ Post-read UI refresh | .onChange(of: chapterForNav) fires 500ms delayed refreshChapterStates() when returning from reader. Fixes race condition between onDisappear DB write and parent onAppear DB read. |
| 6 | ✅ InsightsView redesign | Full ScrollView-based layout: 2-column LazyVGrid StatCard (flame/book/clock/stack icons), by-manga VStack rows with rounded background and dividers. |
| 7 | ✅ Novel reader overlay fix | .opacity(showOverlay ? 1 : 0) + .allowsHitTesting(showOverlay) replaces if showOverlay gating — overlay animates smoothly because views stay in hierarchy. .animation(.easeInOut, value: showOverlay) added. |
| 8 | ✅ Novel reader colorScheme fix | .preferredColorScheme(isSepia ? .light : (isDarkMode ? .dark : .light)) replaces forced .dark. Sepia mode now shows correct light chrome. |
| 9 | ✅ Popular / Latest tabs in Browse | JSBridge: getLatestManga(page:sourceId:) + supportsLatest Bool (checks for undefined before calling). SourceBrowseView: FeedTab enum (.popular/.latest), segmented Picker shown only when supportsLatest && !isNovelSource. Bridge reused across tab switches (not recreated). |
| 10 | ✅ Incognito mode | AppSettings.isIncognito: Bool (UserDefaults, default false). Toggle in SettingsView → Reader — Manga with descriptive subtitle. ChapterReaderView: guard !isIncognito else { return } skips markChapterRead() and updateProgress(). |
| 11 | ✅ Unread badge toggle | AppSettings.showUnreadBadge: Bool (UserDefaults, default true). Toggle in SettingsView → Library section. MangaCoverCell gates badge on AppSettings.shared.showUnreadBadge. |
| 12 | ✅ Comick domain migration | API_BASE variable added to comick.js. Updated from api.comick.fun (DNS dead) to api.comick.dev. Mobile Safari User-Agent added to COMICK_HEADERS. Note: api.comick.dev returns 403 Cloudflare challenge from non-browser clients — site-level block outside Yomi control. |
| 13 | ✅ Code audit + 2 bugs fixed | Duplicate // MARK: - Library display in AppSettings removed. SourceBrowseView bridge recreation on tab switch fixed (reuse existing bridge). Build verified clean. |

## Session 30 — UI Polish + Bug Fixes + Reader UX (2026-04-11) ✅ Complete

| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ MangaDetailView header redesign | 110pt cover with shadow, title3.bold, Label author/source, genre chips (horizontal ScrollView), full-width Resume/Start Reading button (borderedProminent .large). Smart resume: in-progress → first unread → last chapter. |
| 2 | ✅ MangaCoverCell improvements | Read progress bar (accentColor, 3pt height at bottom of image). Moved download icon to image overlay (was covering title). async let parallel fetch for unread/downloaded/chapters in .task. |
| 3 | ✅ ContinueReadingCell improvements | 90pt cover, read progress bar, last-read chapter name subtitle. Loads via .task(id:). |
| 4 | ✅ NovelDetailView header redesign | Matches MangaDetailView: 110pt cover + shadow, title3.bold, Label author/source, NovelStatusBadge, genre chips. |
| 5 | ✅ HistoryView delete fix | swipe-to-delete now calls MangaQueries.clearLastRead() — manga no longer reappears on refresh. MangaQueries.clearLastRead(mangaId:) added. |
| 6 | ✅ UpdatesView redesign | Per-chapter rows grouped by manga: each manga = Section with MangaUpdateHeader (tiny cover + title + "N new chapters" + relative time) + UpdateChapterRow per unread chapter. Shows manga updated in last 30 days. NavigationLink to MangaDetailView. |
| 7 | ✅ UpdatesView refresh: persist + notify | checkUpdates now calls insertMangaAndChapters (persists new chapters to DB) and scheduleChapterNotification. bridge capture uses await MainActor.run. |
| 8 | ✅ TextReaderView chapter navigation | Signature changed to chapters:[NovelChapter] + startIndex:Int. activeChapter computed var. Prev/next chapter buttons in overlay (chevron.left.2 / chevron.right.2, greyed out when at boundary). navigateToChapter() marks current as read then switches. .task(id: activeChapter.id) reloads content on chapter change. |
| 9 | ✅ MoreView version/build from Bundle | CFBundleShortVersionString + CFBundleVersion read from Bundle.main.infoDictionary (was hardcoded). |

## Session 33 — Novel ReadingStatus parity (2026-04-14) ✅ Complete

| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ Novel ReadingStatus (v11_ migration) | ALTER TABLE novel ADD COLUMN readingStatus TEXT NOT NULL DEFAULT 'none'. Novel model: `readingStatus: ReadingStatus` field added. GRDB extension updated (init(row:) + encode(to:)). |
| 2 | ✅ NovelQueries.updateReadingStatus | nonisolated static; GRDB updateAll on readingStatus column. Mirrors MangaQueries.updateReadingStatus. |
| 3 | ✅ NovelDetailView ReadingStatusMenu | `ReadingStatusMenu` pill shown inline next to `NovelStatusBadge` when `isInLibrary`. Made `ReadingStatusMenu` struct non-private (was private to MangaDetailView) so NovelDetailView can reuse it. `@State private var novelReadingStatus: ReadingStatus` initialized from `novel.readingStatus`. `updateReadingStatus()` via Task.detached + haptic. |
| 4 | ✅ Library status chips apply to novels | LibraryView chip row guard changed from `!mangas.isEmpty` to `!mangas.isEmpty \|\| !novels.isEmpty`. LibraryViewModel.displayedNovels now applies statusFilter after category filter (same pattern as displayedManga). |
| 5 | ✅ Plugin catalog up to date | novelbin.js + lightnovelpub.js + lightnovelworld.js all written and in Firebase public folder. Firebase deploy pending (auth — see below). |
| 6 | ✅ App Store description drafted | Text ready to paste into App Store Connect (see session notes). |

**Firebase deploy pending:** Run `firebase login --reauth && firebase deploy --only hosting` in `~/Desktop/Yomi\ 2.0/yomi-firebase` to publish lightnovelpub.js, novelbin.js, lightnovelworld.js to yomi-plugins.web.app.

**App Store blockers remaining:**
1. App icon (1024×1024 PNG) — user working on design separately
2. Age rating **18+** declaration (App Store Connect — 2026 system)
3. App description + screenshots + support URL (App Store Connect)

## Session 34 — Plugin debugging + code review (2026-04-15) ✅ Complete

| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ freewebnovel.js chapter selector | Changed from `ul#chapter-list li a` to `a.con` (actual HTML structure). Added `/novel/` href filter to avoid matching unrelated links. |
| 2 | ✅ novelbin.js data-novel-id regex | Changed `\d+` to `[^'"]+` — NovelBin uses text slugs (e.g., `martial-peak`) not numeric IDs. The previous regex always failed, falling back to visible chapter list. |
| 3 | ✅ novelfire.js robustness | Added multiple fallback selectors for summary (`div.novel-synopsis`, `section.summary`, `div.description`) and status (`span.status`, `div.status`). Added `?page=1` to chapters URL. Added fallback chapter selectors (`li.chapter-item a`, `div.chapter-list a`). |
| 4 | ✅ Catalog cleanup | Removed `comick` (Cloudflare blocks SOURCE.fetch, returns 403), `lightnovelworld` (site permanently dead), `lightnovelpub` (Cloudflare blocks). Catalog now has 8 working sources: MangaDex, Asura Scans, AquaManga, Royal Road, ScribbleHub, NovelFire, FreeWebNovel, NovelBin. |
| 5 | ✅ BrowseView Swift concurrency fix | `self.selectedFeed` (MainActor @State) captured in `let currentFeed = selectedFeed` before `Task.detached` entry — eliminates Swift 6 isolation warning. |
| 6 | ✅ NovelCoverCell phase-based AsyncImage | Switched from two-closure to phase-based `AsyncImage(url:content:)`. Consistent placeholder sizing across loading/error states prevents LazyVGrid row height instability. |
| 7 | ✅ LazyVGrid bottom padding | Added `.padding(.bottom, 8)` to novel browse grid in `SourceBrowseView`. |
| 8 | ✅ UpdatesView: insert newChapters only | Was inserting `remoteChapters` (all) instead of `newChapters` (filtered). INSERT OR IGNORE is non-destructive but inserting all chapters on every update check is wasteful for large catalogs. |
| 9 | ✅ TextReaderView Task.detached priority | Added `priority: .background` to the `Task.detached` call that marks a chapter as read on navigation — was unspecified before. |
| 10 | ✅ Full code review | All *Queries methods nonisolated ✓, JSBridge calls in Task.detached ✓, results via MainActor.run ✓, INSERT OR IGNORE for chapters ✓, bridge(for:) never uses stale sourceListURL ✓. Build clean with zero warnings. |
| 11 | ✅ Xcode warnings fixed | HistoryView: sort moved from Task.detached to MainActor.run (fixes "Main actor-isolated lastReadAt" ×2). LibraryView: `_ = try? CategoryQueries.insert(name:)` (fixes unused Category? expression). |

**Firebase deploy needed:** Run `firebase login --reauth && firebase deploy --only hosting` in `~/Desktop/Yomi\ 2.0/yomi-firebase` to publish updated freewebnovel.js, novelbin.js, novelfire.js and updated index.json (3 plugins removed).

**App Store blockers remaining:**
1. App icon (1024×1024 PNG) — user working on design separately
2. Age rating **18+** declaration (App Store Connect — 2026 system)
3. App description + screenshots + support URL (App Store Connect)

## Session 35 — Deep Research (2026-04-15) ✅ Complete

| # | Topic | Finding |
|---|-------|---------|
| 1 | Tachiyomi/Mihon on iOS | ❌ Impossible — Kotlin APKs, Android-only runtime. No viable path. |
| 2 | Aidoku WASM (Rust SDK) | ❌ Not viable now — full rewrite, plugin authors need Rust. Revisit S40+. |
| 3 | Paperback TS ecosystem (~100 sources) | ✅ **S37 target** — JSBridge S24 shim already started; full Format C support planned. |
| 4 | iOS 26 Liquid Glass icons | ✅ 3-layer PNG format, Icon Composer tool in Xcode 26, alternate icon API unchanged. |
| 5 | App customization gaps vs Tachimanga | Pure black OLED, alternate icons, tab reordering. First two are S36. |
| 6 | JSContext architecture audit | ✅ Stay the course. `requiresWebView` flag for JS-rendered pages (NovelFire synopsis). |
| 7 | Claude Code MCP stack | ✅ Current stack optimal. Apple `xcrun mcpbridge` available as supplement. |
| 8 | RESEARCH.md created | Master research doc replaces all per-session research notes. |

## Planned: Session 36 — App Store Push + Customization Polish

**Goal:** Ship polish items + coordinate App Store submission blockers.

**Claude codes:**
| # | Feature | Files |
|---|---------|-------|
| 1 | Alternate app icons (asset catalog + `setAlternateIconName` + SettingsView picker) | Assets.xcassets, SettingsView.swift, Info.plist |
| 2 | Pure black OLED mode (`AppSettings.pureBlack: Bool`) | AppSettings.swift, SettingsView.swift, ContentView.swift, TextReaderView.swift |
| 3 | NovelFire synopsis fix: `requiresWebView` flag + targeted WKWebView fallback in JSBridge | JSBridge.swift, novelfire.js |
| 4 | App icon integration (when user delivers PNG) | Assets.xcassets |
| 5 | `xcrun mcpbridge` supplemental MCP | .mcp.json |

**User actions (do these in parallel):**
- [ ] Firebase deploy: `firebase login --reauth && firebase deploy --only hosting`
- [ ] Uninstall LightNovelWorld manually (Extensions tab → swipe)
- [ ] App icon: design 1024×1024 PNG (3 layers for iOS 26 Liquid Glass)
- [ ] App Store Connect: age rating 18+
- [ ] App Store Connect: paste S33 description + support URL
- [ ] Screenshots: 6.9" iPhone + iPad on simulator

## Planned: Session 37 — Paperback Ecosystem Unlock (~100 sources)

**Goal:** Enable Paperback TypeScript sources to run natively in Yomi.

**Claude codes:**
| # | Feature | Files |
|---|---------|-------|
| 1 | JSBridge Format C detection (Source class export post-eval) | JSBridge.swift |
| 2 | Source class bridge preamble + requestManager HTTP stub | JSBridge.swift |
| 3 | Test with 3 real Paperback sources | — |
| 4 | 5–10 curated Paperback catalog entries | ~/Desktop/Yomi\ 2.0/yomi-firebase/public/index.json |
| 5 | build-plugins.mjs Paperback TS compilation support | scripts/build-plugins.mjs |

**User actions:**
- [ ] Pick 2–3 Paperback sources to prioritize (browse Paperback community repos)
- [ ] Test on real device after deploy (Cloudflare behavior may differ from simulator)

## Session 38 — UX Feature Blitz (Tachimanga parity + exclusives) ✅ Complete

**Source:** Deep research into Tachimanga changelog (v1.1–v4.15) and full localization file (809 strings extracted from Weblate export). Yomi is already at parity on ~15 features. S38 closes the remaining quick-win gaps.

| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ Auto webtoon from tags | ChapterReaderView.init checks manga.genres for manhwa/manhua/long strip → overrides to .verticalScroll. Gated by AppSettings.autoWebtoonFromTags (default on). |
| 2 | ✅ Hold-to-scroll in WebtoonReaderView | Long-press (0.6s) toggles auto-scroll. Swift 6 `.task(id: isAutoScrolling)` loop advances visibleId every 600ms. Toast overlay shown while active. |
| 3 | ✅ Delete download after reading | AppSettings.deleteDownloadAfterReading (Bool, default true). markChapterRead() gates delete behind setting. Capture before Task.detached. |
| 4 | ✅ Concurrent downloads setting | AppSettings.concurrentDownloads (Int 1–5, default 3). DownloadManager.performDownload seeds initial batch with this value. |
| 5 | ✅ Smart update skip conditions | AppSettings.skipUpdateWithUnread / skipUpdateNotStarted / skipUpdateCompleted. Early returns in checkUpdates(for:) before network call. |
| 6 | ✅ Excluded categories from updates | AppSettings.excludedCategoryIds ([String]). CategoryQueries.categoriesForManga checked in checkUpdates. New ExcludedCategoriesView in SettingsView.swift. |
| 7 | ✅ Chapter sort by name | MangaDetailView.ChapterSortOption enum (.chapterNumber / .name). Sort menu replaces simple direction toggle. Both sorted vars updated. |
| 8 | ✅ Random entry button | Shuffle toolbar button in LibraryView. Sets randomMangaDest + showRandomManga, navigates to MangaDetailView. |
| 9 | ✅ Text selection on descriptions | .textSelection(.enabled) on synopsis Text in MangaDetailView and NovelDetailView. |

## Session 39 — Reader Polish + Scanlators + Custom Covers ✅ Complete (2026-04-19)

| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ Scanlator filter | v12_ migration (chapter.scanlator column). JSBridge Format A shim passes `ch.group \|\| ch.scanlator \|\| null`. MangaDetailView: scanlator chip row above chapter list (only shown when >1 scanlator). Filters displayed chapters. |
| 2 | ✅ Tap zone layouts | AppSettings.tapZoneLayout: String ("default"/"sides"/"disabled"). MangaReaderView tapZoneOverlay computed @ViewBuilder: default = equal thirds, sides = 20/60/20%, disabled = tap anywhere toggles overlay. Picker in SettingsView → Reader—Manga. |
| 3 | ✅ Webtoon horizontal padding | AppSettings.webtoonHorizontalPadding: Int (0/8/16/24 pt). Applied as `.padding(.horizontal,)` on WebtoonReaderView LazyVStack. Picker in SettingsView → Downloads section. |
| 4 | ✅ Auto-scroll speed | AppSettings.autoScrollSpeed: Double (default 3.0s). WebtoonReaderView hold-to-scroll uses `Task.sleep(for: .milliseconds(Int(settings.autoScrollSpeed * 1000)))`. Stepper in SettingsView → Downloads section. |
| 5 | ⏭ Saved searches | Deferred — too complex for this session. |
| 6 | ✅ Custom manga covers | v13_ migration (manga.customCoverPath column). MangaDetailView ellipsis menu: "Change cover" → PhotosPicker, saves JPEG to Documents/Covers/{id}.jpg, updates DB. MangaCoverCell shows custom cover if path set. |
| 7 | ⏭ Source settings per extension | Deferred — too complex for this session. |

## Session 40 — Novel Plugin Blitz + Multi-Repo Catalog ✅ Complete (2026-04-20)

**Source:** LNReader plugin ecosystem research + Suwayomi/Tachidesk architecture findings.

| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ Multi-repo catalog | `pluginCatalogURL: String` → `pluginCatalogURLs: [String]` with UserDefaults migration (JSONEncoder). PluginCatalogService fetches all URLs in parallel via `withThrowingTaskGroup`, merges dedup by id (first-wins), sorts by name. `invalidateCache()` public method. |
| 2 | ✅ Plugin Repositories settings UI | SettingsView "Plugin Repositories" section with swipe-to-delete + sheet to add new URL. `invalidateCache()` called on add/delete to force refresh. |
| 3 | ✅ 6 new novel TypeScript plugins | LightNovelPub, BoxNovel, MTLNovel, BabelNovel (JSON API), NovelHall, ReadWN. Pattern: TypeScript → esbuild IIFE → `(globalThis as any).plugin = plugin` for JSC global access. |
| 4 | ✅ build-plugins.mjs merge fix | Now merges with existing Firebase index.json instead of overwriting. Preserves hand-built entries (9 existing). Only overrides entries with matching fileURL. |
| 5 | ✅ npm/esbuild setup | `package.json` + `node_modules/` (gitignored). `npm run build` command. esbuild 0.28.x. |
| 6 | ✅ Firebase deployed | 15 plugins live: 3 manga (MangaDex, Asura, AquaManga) + 12 novel (RR, SH, NovelFire, FreeWebNovel, NovelBin, NovelFull + 6 new). |

## Session 41 — Suwayomi Integration + Library List View + Advanced Settings ✅ Complete (2026-04-20)

**Source:** Suwayomi REST API research + remaining S40 roadmap items.

| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ Suwayomi Server integration | `SuwayomiService.swift` REST client: `fetchSources()`, `fetchPopular()`, `fetchSearch()`, `fetchMangaDetail()`, `fetchChapters()`, `pageURLs()`, `toManga()`. ID format: `"suwayomi_{sourceId}_{mangaId}"` (underscores for safe last-underscore split). `AppSettings.suwayomiURL` stored in UserDefaults. |
| 2 | ✅ Suwayomi Browse UI | `SuwayomiBrowseView.swift`: full browse + search for one Suwayomi source. Infinite scroll with `loadMore()`/`hasNextPage`. Uses `isPresented:` navigation pattern (Manga is not Hashable). |
| 3 | ✅ Suwayomi in BrowseView | `Section("Suwayomi Server")` in sources tab when `SuwayomiService.shared.isEnabled`. `loadSuwayomiSources()` on appear. Rows navigate to `SuwayomiBrowseView`. |
| 4 | ✅ Library list view | `AppSettings.libraryDisplayMode: String` ("grid"/"list"). `MangaListRow` struct in MangaCoverCell.swift. Toolbar toggle button in LibraryView (grid.bullet/square.grid.2x2). `LazyVStack` list with `NavigationLink` + `Divider`. |
| 5 | ✅ Advanced settings screen | `AdvancedSettingsView.swift`: Cache section (clear image/plugin catalog/WebView cookies), Network section (UA + timeout read-only), Database section (diagnostic log export via `UIActivityViewController`), Build info (version, build, iOS, device). Reached via `NavigationLink` from SettingsView. |
| 6 | ✅ Suwayomi settings UI | `suwayomiSection` in SettingsView: URL TextField with `.URL` keyboard. |

**Not shipped this session:**
- Cloudflare bypass (CFBypassManager) — deferred to S42
- Tachiyomi backup import — deferred to S42

## Session 42 — Yomi Exclusives ✅ Complete (2026-04-20)

| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ Manga notes | `notes: String?` field on Manga. v14_manga_notes migration. `MangaQueries.updateNotes()`. Notes section in MangaDetailView (shows current note preview or "Add note…", opens `NotesEditorSheet`). BackupManager updated (encode/decode). Free — Tachimanga charges premium. |
| 2 | ✅ App Lock | `AppSettings.appLockEnabled: Bool`. New `AppLockView.swift`: LAContext `.deviceOwnerAuthentication`, auto-authenticates on appear, FaceID/TouchID icon detection, passcode fallback. YomiApp: `@State isLocked`, `.fullScreenCover` on `isLocked`, re-locks on `scenePhase == .background`. SettingsView toggle. Free — Tachimanga charges premium. |
| 3 | ✅ TTS for novels | `AppSettings.ttsSpeechRate: Float` (default 0.5). `TextReaderView`: HTML-stripping regex, `AVSpeechSynthesizer` + `TTSDelegate` (NSObject, AVSpeechSynthesizerDelegate, strong ref to synth to prevent ARC deallocation). Play/stop button in overlay Row 4. Stops on chapter navigation and view disappear. SettingsView TTS speed slider. Exclusive — Tachimanga has no TTS. |
| 4 | ✅ Global search | `GlobalSearchView` (replaces old `SearchView` in BrowseView). `withTaskGroup` queries all installed sources in parallel. Results stream per source as they arrive (MainActor.run on each result). Per-source section headers with `LazyVGrid` results. Handles Format A (`searchManga`) and Format B (`searchNovels`). `NovelCoverCell` for novel results. Pending count spinner while sources still loading. Unique to Yomi. |

**Deferred to S43 research:**
- Cloudflare bypass (WKWebView cookie bridge)
- Tachiyomi/Mihon backup import (`.tachibk` protobuf)
- WidgetKit ContinueReadingWidget (App Groups + shared SQLite)
- Tab reordering (iOS 26 TabView drag API)

## Session 43 — Tachiyomi Backup Import + Tab Reordering ✅ Complete (2026-04-20)

| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ Tachiyomi / Mihon backup import | `TachiyomiBackupParser.swift`: hand-written protobuf3 binary decoder + gzip decompressor (libz via bridging header). `ProtoReader` class parses varint/length-delimited/fixed32 wire types. Decodes `BackupManga` (fields 1–100) + `BackupChapter` (fields 1–10) matching Mihon proto schema. Source ID map: `[UInt64: String]` maps Tachiyomi int64 → Yomi plugin ID (currently MangaDex). Unmapped sources: `"tachiyomi_{id}"` placeholder — library fully imported, even without matching plugin. `BackupManager.importTachiyomiBackup(from:)` calls `MangaQueries.upsert()` + `ChapterQueries.upsert()` for each item. `BackupView.swift`: new "Import from Tachiyomi / Mihon" section with `fileImporter` accepting `.tachibk` files. Result alert shows summary string (N manga imported, M matched vs unrecognized). |
| 2 | ✅ Tab reordering | `ContentView.swift`: `@AppStorage("tabViewCustomization") private var customization = TabViewCustomization()`. Each `Tab(...)` gets `.customizationID("com.Yomi.<Tab>")`. `TabView` gets `.tabViewCustomization($customization)`. Users can long-press tabs and drag to reorder — persisted via `@AppStorage`. |
| 3 | ✅ Bridging header for zlib | `Yomi/Yomi-Bridging-Header.h` created (`#import <zlib.h>`). `SWIFT_OBJC_BRIDGING_HEADER` added to both Debug + Release `XCBuildConfiguration` blocks in `project.pbxproj`. Enables zlib C API (`z_stream`, `inflateInit2_`, `inflate`, `inflateEnd`, `Z_OK`, `Z_STREAM_END`, `uInt`, `ZLIB_VERSION`) in Swift. |

**Deferred to S44:**
- Cloudflare bypass (WKWebView cookie extraction → URLSession injection)
- WidgetKit ContinueReadingWidget (App Groups + shared JSON file)

## Session 44 — Onboarding + Catalog Fixes + Format D Mangayomi (2026-04-20) ✅ Complete

| # | Item | Detail |
|---|------|--------|
| 1 | ✅ New user onboarding | PluginsView: toolbar `+` → Menu → "Add Repository" opens `AddRepoSheet` (LNReader + Mangayomi featured repos, custom URL field, GitHub guide link). Empty installed state shows featured repos inline. |
| 2 | ✅ LNReader catalog format fix | `PluginCatalogService` multi-format parser: Yomi native → LNReader (`lang`/`url`/`iconUrl`) → Mangayomi (`id: Int`/`sourceCodeUrl`/`isNsfw`). Per-URL failures silent. Fixes "Failed to load" on non-Yomi repos. |
| 3 | ✅ README.md | GitHub README: Quick Start + 3-repo comparison table + step-by-step guide + Tachiyomi migration section. |
| 4 | ✅ Format D: Mangayomi JS shim | `JSBridge.injectMangayomiShims`: `Client` class (wraps `SOURCE._fetchSync`), `Document`/`Element` classes (built on cheerio, `.selectFirst`/`.select` API, computed `.text`/`.attr`), `String` prototype extensions (`substringAfter/Before/Between`), `Preferences` stub. `injectMangayomiAdapter`: detects `global.source.getPopular + getDetail` post-eval, maps to `getMangaList` / `searchManga` / `getChapterList` / `getPageList` / `getLatestManga`. `isMangayomiPlugin` var. |
| 5 | ✅ Mangayomi catalog parser | `MangayomiEntry: Decodable` added to `PluginCatalogService`; `parseEntries` tries all 3 formats. Mangayomi index URL added to `featuredRepos` in PluginsView. |
| 6 | ✅ Tachimanga DEX research (S44, corrected S52) | S44 description "C-native DEX bytecode interpreter" was unverified and likely wrong. S52 deep research: Tachimanga almost certainly bundles **OpenJDK Zero interpreter + Tachidesk-Server JAR running as a local process** (their fork: `github.com/tachimanga/Tachidesk-Server`). The Flutter UI connects to localhost. No standalone C DEX library exists in any open-source project. The correct framing: to replicate Tachimanga, embed OpenJDK Zero (thebaselab/codeapp has prebuilt iOS binaries, MIT-licensed) + slimmed Suwayomi-Server JAR. Effort: 8–12 weeks. Binary size: +100–200MB IPA. Yomi's Suwayomi REST integration (S41) already covers the same sources — the only gap is that Tachimanga is self-contained (no user-hosted server). Building a C DEX interpreter from scratch is 7–11 months of work, not the 2–4 months originally estimated. |
| 7 | ✅ Mihon forks research | J2K/SY/AZ/Yōkai/Komikku — all Android-only, no new iOS paths. |

| 8 | ✅ Mangayomi `const source` bug fix | `injectMangayomiAdapter` used `global.source` — `const` at top-level is a lexical binding, NOT on globalThis. Fixed to use identifier lookup (`typeof source`) which checks lexical scope. Plugins now execute correctly. |
| 9 | ✅ Catalog UX overhaul | `PluginCatalogEntry.repoURL` (set post-fetch, excluded from Codable). `PluginCatalogGroup` (groups same-name multi-lang sources). Browse → Extensions: grouped list with "X langs" badge + language picker dialog, repo source badge (Yomi/LNReader/Mangayomi), search bar, pull-to-refresh. Browse → Sources: swipe-to-delete (uninstall), "Get more" header button, empty state navigates to Extensions. `CatalogGroupRow` shared between Browse and Plugins. |

**Outcome:** Yomi supports 4 JS plugin formats (A/B/C/D). 195+ Mangayomi sources + 500+ LNReader novels available via one-tap repos. Browse tab is now the primary plugin management surface.

---

## Session 46 — Community Plugin Fixes: Cheerio + LNReader (2026-04-25) ✅ Complete

| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ AllNovel working | Root cause: cheerio shim `each`/`map` passed raw DOM nodes (breaking `el.find()` pattern). Fixed: pass wrapped cheerio objects; `$()` auto-detects wrapped vs raw. |
| 2 | ✅ Archive Of Our Own (AO3) working | Two bugs: (1) child combinator `>` in `"h4.heading > a"` was not handled — selector split on space only. Fixed: tokenize with `/\s*>\s*\|\s+/g`, apply direct-children-only logic for `>`. (2) `$(t).find(...)` inside `each` callback failed because `t` was a wrap object but `$()` tried to use it as a CSS string. Fixed: `$()` detects `typeof selector.find === 'function'` and returns it as-is. |
| 3 | ✅ Cheerio CSS selector engine: child combinator `>` | `select()` now tokenizes with `/\s*>\s*\|\s+/g` regex, producing `tokens[]` + `combinators[]`. For `>`: matches only direct `.children` of each matched node. For ` ` (space): matches all descendants (existing behavior). |
| 4 | ✅ ReadComicOnline + Mangapill — confirmed broken | Source files downloaded as "404: Not Found" from dead `entityJY/mangayomi-extensions-eJ` GitHub repo. Unfixable by code — user must uninstall from Extensions tab. |
| 5 | ✅ METODOLOGIA.md S46 entry | Documented root causes, each/map final contract (wrapped objects, not raw nodes), child combinator `>` fix pattern. |

---

## Session 47 — JSBridge Full Audit + FormData Shim (2026-04-25) ✅ Complete

| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ Scanned all 131 English LNReader v3 plugins | `require()` module usage: `@libs/fetch` (131), `cheerio` (122), `@libs/novelStatus` (110), `@libs/defaultCover` (79), `@libs/storage` (72), `dayjs` (59), `htmlparser2` (33), `@libs/filterInputs` (27). Also identified 3 unshimmed: `@libs/isAbsoluteUrl`, `@libs/aes`, `@/types/constants`. Found `FormData` global missing — used by 52+ plugins. |
| 2 | ✅ `FormData` global shim | Added to `injectWebAPIs`. Constructor with `_entries` array, `.append()`, `.get()`, `.has()`, `.set()`, `.toString()`. `@libs/fetch` `fetchApi` and global `fetchApi` both updated: detect `rawBody._entries`, serialize as `encodeURIComponent(k)=encodeURIComponent(v)` joined by `&`, inject `Content-Type: application/x-www-form-urlencoded` header. Fixes entire Madara/WordPress multisrc family (52+ plugins). |
| 3 | ✅ `@libs/isAbsoluteUrl` shim | Added to `injectRequireShim`. Returns `function(url) { var s = String(url); var c = s.indexOf('://'); return c > 0 && c < 20; }`. Fixes RoyalRoad plugin. |
| 4 | ✅ `@/types/constants` shim | Added to `injectRequireShim` (returns empty `{}`). Already safe for NovelFire — compiled output rebinds the variable immediately. |
| 5 | ✅ ReadComicOnline + Mangapill | Confirmed unfixable by code: both source files contain "404: Not Found" — downloaded from dead `entityJY/mangayomi-extensions-eJ` repo. User must uninstall from Extensions tab. |

---

## Session 45 — Cloudflare Auto-Bypass + Plugin Fixes (2026-04-23) ✅ Complete

| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ CFBypassView.swift (manual) | Full browser sheet (`UIViewRepresentable` WKWebView + URL bar). CF JS challenge runs in real browser engine. `WKHTTPCookieStore` polled every 0.8s for `cf_clearance`. All domain cookies copied to `HTTPCookieStorage.shared` on success. Success banner + "Done" button enabled. Manual fallback — kept as shield toolbar button. |
| 2 | ✅ CFBypassManager (auto-bypass) | Hidden 1×1pt `WKWebView` added to keyWindow for 10 seconds. `AutoBypassHelper` class polls for `cf_clearance` every 0.5s. If found → cookies copied to `HTTPCookieStorage.shared` → returns `true`. On timeout → returns `false`. No UI shown unless bypass fails. |
| 3 | ✅ JSBridge CF detection | `injectSourceFetch`: captures `ObjectIdentifier(ctx)` before block. URLSession callback detects Cloudflare response via `CF-RAY` header or (HTTP 403 + body contains "Just a moment"/"cf-mitigated"). Stores blocked URL in module-level `_cfBlockedByContext[ctxID]`. `JSBridge.cfBlockedURL` + `clearCFBlock()` instance properties for callers. |
| 4 | ✅ SourceBrowseView auto-bypass flow | `loadWithBypass()`: calls `loadContent()` first; if content is empty AND `cfBlockedURL` is set → auto-triggers `CFBypassManager.autoBypass(url:)`; if bypass succeeds → retries `loadContent()`. `isBypassing` overlay shown during hidden WKWebView phase. User sees "Bypassing Cloudflare…" only if blocked. `.task` changed from `loadContent()` to `loadWithBypass()`. |
| 5 | ✅ LNReader v3 module.exports fix | `injectLNReaderAdapter` JS now checks `module.exports` / `exports.default` as fallback if `globalThis.plugin` is not set. Fixes LNReader v3.0.0 plugins (DaoNovel etc.) that export via CommonJS rather than directly setting `globalThis.plugin`. |
| 6 | ✅ Mangayomi Dart filter | `PluginCatalogService.parseEntries` filters Mangayomi catalog entries to `.js`-only (`sourceCodeUrl.hasSuffix(".js")`). Prevents `.dart` Dart-only extensions from appearing in the catalog and being installed (they previously downloaded as `.js` but silently failed in JSC). |
| 7 | ✅ `@libs/fetch` require shim | Added `@libs/fetch` to `injectRequireShim`. Returns `{ fetchApi: fn }` where `fn` wraps `SOURCE._fetchSync` — matching LNReader v3 usage `(0, n.fetchApi)(url, opts)`. Previously shim returned `{}` causing `TypeError: n.fetchApi is not a function`. |
| 8 | ✅ `@libs/novelStatus` require shim | Added `@libs/novelStatus` stub: `{ NovelStatus: { Ongoing, Completed, Unknown } }`. LNReader v3 novel plugins use these constants for status display. Missing stub caused undefined reference at runtime. |
| 9 | ✅ `dayjs` require shim | Added lightweight `dayjs` stub to `injectRequireShim`. Implements `.subtract(n, unit)`, `.add(n, unit)`, `.format(fmt)`, `.isValid()`. Units: day/week/month/year. Used by LNReader v3 plugins for date formatting ("3 days ago" style). |
| 10 | ✅ CFBypassView URL pre-fill | `CFBypassView` now accepts `initialURL: String` parameter (via `init` to properly initialize `@State var urlText`). BrowseView passes `bridge?.cfBlockedURL ?? "https://"` — so the manual bypass sheet opens directly on the blocked domain, not a blank `https://` field the user must type into. |
| 11 | ✅ LNReader v3 async plugin fix (`callPluginMethod`) | Root cause of all LNReader v3 plugin failures: TypeScript `async/await` compiles to `__awaiter`/`__generator` — every plugin method returns a `Promise`. The old `_resolve` wrapper returned `undefined` before microtasks ran. Fix: `callPluginMethod` uses `evaluateScript` (which internally calls `drainMicrotasks()` before returning to Swift) + JS global `__lnr_result` to capture the resolved value. `popularNovels`/`searchNovels`/`parseNovel`/`parseChapter` all updated to use this pattern. |

**Cookie mechanism:** `HTTPCookieStorage.shared` is the session-level cookie jar. `URLSession.shared` reads it automatically (`httpShouldHandleCookies = true` by default on `URLRequest`). Bypass is transparent to the JS plugin pipeline once cookies are stored.

**Mangapill note:** `960321322.js` contains literally "404: Not Found" — broken download when first installed. Not fixable by code; user must uninstall it. Mangapill only has a Dart extension in Mangayomi catalog — no JS version exists.

**App Store submission (user actions — still pending):**
| # | Action | Notes |
|---|--------|-------|
| 1 | App icon (user delivers PNG) | 3-layer 1024×1024 for iOS 26 Liquid Glass |
| 2 | Age rating 18+ | App Store Connect |
| 3 | App description | Drafted S33 — frame as "extensible reader with community sources" |
| 4 | Screenshots 6.9" iPhone | Simulator, neutral content only |
| 5 | Support URL | GitHub repo |

---

## Session 48 — Power User Backends (2026-04-26) ✅ Complete

| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ Suwayomi onboarding UX | SettingsView: URL field + "Test Connection" button → async `fetchSources()` → shows source count or error. `ConnectionTestStatus` enum (idle/loading/connected(Int)/failed(String)). URL change resets status. Setup guide link (GitHub). Footer updated with practical setup instructions. |
| 2 | ✅ OPDS client | `OPDSService.swift`: Atom XML SAX parser (`XMLParserDelegate`), `OPDSFeed`/`OPDSEntry` models, navigation vs acquisition entry detection, Basic Auth support, absolute URL resolution. `OPDSBrowseView.swift`: recursive navigation (nav entries → drill-down list, acquisition entries → cover grid), `OPDSItemDetailView` sheet (cover, title, author, summary, download link). SettingsView: OPDS section with URL + username + password + test button. BrowseView: OPDS section in Sources tab, loads root feed on `.task`. AppSettings: `opdsURL`, `opdsUsername`, `opdsPassword` stored properties. |
| 3 | ✅ WidgetKit extension | `YomiWidget` target added to `project.pbxproj` (native target, `PBXFileSystemSynchronizedRootGroup`, entitlements, Info.plist). `YomiWidget.swift`: `ContinueReadingWidget` with small (cover+title+chapter)/medium (3 items)/large (2×3 grid) layouts, `AsyncImage` covers, `TimelineProvider` refreshes every 30 min. `WidgetDataWriter.swift`: reads recently-read manga from LibraryViewModel, writes to App Group `UserDefaults(suiteName: "group.pacodealer.Yomi")`, calls `WidgetCenter.shared.reloadAllTimelines()`. `Yomi.entitlements` + `YomiWidget.entitlements` created for App Groups. LibraryViewModel.writeWidgetData() called after every loadLibrary(). |

---

## Session 55 — Full Functional Audit ✅ Complete (2026-05-03)

| # | Fix | Detail |
|---|-----|--------|
| 1 | ✅ MangaDetailView DB fallback | `loadChapters()` was discarding DB chapters when API returned empty. `if loadedChapters.isEmpty { chapters = saved }` — users now see their saved chapters even when the source is unreachable. Critical: manga showed "No chapters found" despite 100+ DB entries and reading history. |
| 2 | ✅ Haptic guard on chapter reset | `onChange(of: currentPage)` fired haptic even when `navigateToChapter` reset `pages = []` then `currentPage = 0`. Guard added: `if pages.count > 0 { ... }` — pages is always empty at reset time. |
| 3 | ✅ `_ =` write consistency | `NovelQueries.swift` (6 calls) and `ExtensionQueries.swift` (2 calls) were missing `_ = try appDatabase.write { ... }` prefix required by CLAUDE.md. Fixed for codebase consistency. |
| 4 | ✅ Duplicate NovelBin removed | Two NovelBin plugins with different IDs were installed (Firebase catalog + a secondary repo). Removed the orphan via swipe-to-delete in Plugins view. |
| 5 | ✅ All flows verified live | Library tabs/filter/multi-select, Browse source content, History grouping, Novel reader, Extension install + remove cycle all confirmed functional in simulator. |

---

## Session 54 — UX Blitz ✅ Complete (2026-05-03)

| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ Category tab bar | Replaced horizontal chip scroll with underline-indicator tabs (Tachiyomi-style). `LibraryTab` struct: `VStack { Text + Rectangle(height:2, fill: accentColor or clear) }`. `ScrollViewReader` auto-scrolls active tab into view on selection change. |
| 2 | ✅ Swipe to change category | `.simultaneousGesture(DragGesture)` on library `ScrollView`. Horizontal swipe (1.5× width > height) navigates prev/next in `[nil] + categories.map { Optional($0.id) }`. |
| 3 | ✅ Status filter → sort menu | Removed second chip scroll row from library. Status filter merged as second section in the sort `Menu`. Filter icon fills when sort ≠ lastRead OR status ≠ nil. |
| 4 | ✅ Bulk mark as read | Multi-select action bar: "Mark Read" button calls `ChapterQueries.markAllRead(mangaId:)` for each selected ID, then `viewModel.loadLibrary()`. |
| 5 | ✅ Bulk download | Multi-select action bar: "Download" button captures `installed` on MainActor, fetches manga + unread chapters in `Task.detached`, enqueues each via `DownloadManager.shared.enqueue`. |
| 6 | ✅ Haptic on page turn | `UIImpactFeedbackGenerator(style: .light).impactOccurred()` added to `ChapterReaderView.onChange(of: currentPage)`. |

---

## Session 53 — Embedded JVM Feasibility + Firebase Deploy ✅ Complete (2026-05-02)

| # | Item | Detail |
|---|------|--------|
| 1 | ✅ Firebase deployed | babelnovel.js + lightnovelpub.js pushed to yomi-plugins.web.app. 15 plugins live. |
| 2 | ✅ Embedded JVM feasibility study | Full research into embedding OpenJDK Zero + Suwayomi-Server JAR inside Yomi to eliminate self-hosting friction. **Verdict: DEFERRED.** Hard blockers: (1) Java version gap — only proven iOS App Store JDK is OpenJDK 8 (thebaselab/Code App); Suwayomi v1.1+ dropped Java 8 and v2.x requires Java 21 — no confirmed-working combination exists. (2) NSExtension architecture required — Code App runs Java in a separate sandboxed process via NSExtension, not a simple framework embed; this doubles the scope. (3) +150–200MB binary, near cellular download limit. (4) No confirmed App Store precedent for a Suwayomi JAR specifically. `SuwayomiService.swift` is URL-agnostic and requires zero changes to point at localhost — the path remains viable if/when OpenJDK Mobile (Java 21, Gluon initiative, 2025) matures. |
| 3 | ✅ Tachimanga architecture note | App Store listing describes Tachimanga as native Swift, iOS 15+. Conflicts with S52 OpenJDK Zero conclusion. Architecture remains unconfirmed. The ROADMAP S44 entry has been updated accordingly. |

---

## Session 52 — Audit + Search ✅ Complete (2026-05-02)

| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ HistoryView search | `.searchable(text: $searchQuery, prompt: "Search history")`. `filteredItems` computed property filters by `localizedStandardContains`. `ContentUnavailableView.search(text:)` empty state when query returns no results. |
| 2 | ✅ Full codebase audit | 55 Swift files, ~16,000 lines. DB at v15 (16 migrations). All `*Queries` nonisolated ✅. All bridge calls Task.detached ✅. Novel parity gaps documented: missing custom cover + chapter multi-select. `UpdatesViewModel` promoted to singleton. Novel notes backup encode/decode fixed. `NotesEditorSheet` made non-private. `NovelDetailView` bridge made optional + lazy-resolved. |

## Session 51 — CF Bypass v2 + AniList + Settings UX + Novel Metadata Fix ✅ Complete (2026-04-29–30)

| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ Cloudflare bypass v2 | `AutoBypassHelper` WKWebView full-size off-screen (Turnstile needs real viewport), 30s timeout, poll restarts on server redirects, `CFBypassConstants.userAgent` shared constant, auto-bypass failure shows dismissible banner. |
| 2 | ✅ Settings UX restructure | 12→7 sections (General / Reading / Library / Appearance / Sources & Servers / Advanced / About). Manga + Novel Reader sub-screens. Suwayomi + OPDS as NavigationLink sub-screens. |
| 3 | ✅ AniList score badges | `AniListService.swift` (actor singleton, GraphQL, in-memory cache). `averageScore` badge in `MangaDetailView` + `NovelDetailView` headers. |
| 4 | ✅ Language filter | Moved to Extensions tab. `BrowseView.displayLanguage(_:)` deduplicates ISO codes + full names (15+ mappings). |
| 5 | ✅ Novel library list mode | `NovelLibraryListRow` struct. Both manga and novel sections switch grid/list in sync. |
| 6 | ✅ NovelDetailView metadata sync | `let novel` → `@State private var novel`. After `parseNovel` returns, updates summary/author/status/coverURL from source. Upserts to DB if in library. |
| 7 | ✅ LibraryViewModel.loadLibrary() detached | DB reads moved to `Task.detached` — no longer blocks MainActor. |
| 8 | ✅ Extension.init(row:) safe | Force-unwrap on `sourceListURL` replaced with throwing guard. |
| 9 | ✅ BabelNovel v1.1.0 | Adds `Origin`/`Referer`/`Accept`/`X-Requested-With` headers; HTML-response guard. |
| 10 | ✅ Mangayomi chapter extraction in JS | All chapter extraction moved to JS; handles `url`/`link`/`id`/`href`/`path` variants; caches `lastMangayomiMeta` for synopsis/status/cover. |

## Session 50 — Browse Tab UX + Novel Sources Latest Feed ✅ Complete (2026-04-28)

| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ Language filter for Sources tab | Chip bar with unique languages from installed extensions. |
| 2 | ✅ Latest feed for novel sources | `showLatestNovels: true` option; `latestNovels(page:)` added to JSBridge; picker visible for both manga and novel sources. |
| 3 | ✅ Dead code removal | `filteredMangas` alias removed from LibraryViewModel. |

## Session 49 — Mangayomi Format D Bug Blitz ✅ Complete (2026-04-27)

| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ Mangayomi detection fix | Handles `class DefaultExtension extends MProvider` + `mangayomiSources[]` pattern. |
| 2 | ✅ MProvider + SharedPreferences shims | Pre-eval base class + prefs injected. |
| 3 | ✅ getSrc/getHref getter fix | Changed from methods to getter properties (plugins access without `()`). |
| 4 | ✅ async/await microtask drain | `evaluateScript` drain (same pattern as LNReader `callPluginMethod`). |
| 5 | ✅ getLatestUpdates recognition | Alongside legacy `getLatest`. |
| 6 | ✅ `episodes` field recognition | Alongside `chapters` in `getDetail` return. |
| 7 | ✅ `_mapItem` field fixes | `item.link` for id/path, `item.imageUrl` for cover. |

## Session 32 — Library organization + Novel categories + Backup + New sources (2026-04-14) ✅ Complete

| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ Library ReadingStatus filter chips | Second horizontal chip row below category row in LibraryView. Chips: All / Reading / Plan to Read / On Hold / Completed / Dropped. Applies to manga only (novels have no status column). LibraryViewModel.statusFilter: ReadingStatus? drives displayedManga filter. |
| 2 | ✅ ContinueReadingRow shows novels | ContinueItem enum (manga/novel cases). Both fetched in parallel, merged by lastReadAt desc, top 10 shown. ContinueReadingNovelCell: 90pt cover + "N" badge + progress bar + last-chapter subtitle + tap→NovelDetailView via JSBridge bridge lookup. |
| 3 | ✅ Novel categories (v10_ migration) | v10_novel_category migration: novel_category join table (novelId FK→novel, categoryId FK→category, PK composite). CategoryQueries: assignNovel/unassignNovel/categoriesForNovel/novelIds(inCategory:). LibraryViewModel: filteredNovelIds + category filter applied to displayedNovels. NovelDetailView: category sheet via ellipsis.circle menu (mirrors MangaDetailView pattern). |
| 4 | ✅ Backup & Restore includes novels | BackupManager v2 format: adds novels, novelChapters, novelCategories arrays. Export fetches NovelQueries.fetchAll() + NovelChapter.fetchAll + novel_category rows. Import: NovelQueries.upsert() + insertAllIgnoringConflicts() + INSERT OR IGNORE for novel_category. encode/decodeNovel + encode/decodeNovelChapter helpers added. |
| 5 | ✅ Extensions tab TTL cache | PluginCatalogService: lastFetchedAt + 1-hour TTL. fetchCatalog(force:) skips network if data is fresh. Pull-to-refresh uses force: true. No redundant fetches on tab switches. |
| 6 | ✅ LNReader compat gaps documented | METODOLOGIA.md: Gap 1 (latestUpdates not called by UpdatesView), Gap 2 (plugin.options not surfaced in UI), Gap 3 (Cloudflare blocks WuxiaWorld/WebNovel). No code change needed — gaps are documented for future sessions. |
| 7 | ✅ New plugin: LightNovelPub | lightnovelpub.js (Format B). Selectors for popular/search/detail/chapter. Added to Firebase index.json. Deployed to yomi-plugins.web.app. |

**Deep research conducted (2026-04-14) — saved to memory, do not re-research:**
- Competitive: Mihon, Tachimanga, Paperback, LNReader, Aidoku, all source sites, community sentiment
- UX/reading science: typography, themes, sepia, novel-specific UX, TTS, glossary
- App Store 2026: new age rating system (4/9/13/16/18+, replaces 17+), rejection reasons, screenshot requirements

**App Store correction:** Age rating changed from 17+ to **18+** in 2026 system. Update in App Store Connect.

## Session 31 — Novel parity + UX improvements (2026-04-13) ✅ Complete

Full project audit before S31 revealed novels were second-class citizens: no read state persistence,
no reading time tracking, missing from History/Insights/Updates, wrong dark mode init.

| # | Feature | Detail |
|---|---------|--------|
| 1 | ✅ DB v9_novel_chapter_reading_time | ALTER TABLE novel_chapter ADD COLUMN readingSeconds INTEGER NOT NULL DEFAULT 0. NovelChapter model + GRDB conformance updated. |
| 2 | ✅ Novel chapter persistence | NovelDetailView.loadChapters(): after JSBridge fetch, calls NovelQueries.insertAllIgnoringConflicts() then re-fetches merged state from DB. NovelQueries.markRead() now hits real rows. |
| 3 | ✅ Novel resume button | NovelDetailView: Resume/Start Reading button (same pattern as MangaDetailView). resumeChapter logic: in-progress → first unread → last. touchLastReadAt() on chapter tap. |
| 4 | ✅ Novel reading time tracking | TextReaderView: sessionStart + readingTimer (Timer 1s). flushReadingTime() on onDisappear and navigateToChapter. Calls NovelQueries.addReadingTime(chapterId:novelId:seconds:) which accumulates readingSeconds in both chapter and novel rows + updates novel.lastReadAt. |
| 5 | ✅ TextReaderView isDarkMode fix | Was hardcoded to true. Now initialized from AppSettings.shared.theme == "Dark". Light-theme users no longer get dark novel reader on first open. |
| 6 | ✅ HistoryView: manga + novels | loadHistory() fetches both MangaQueries.fetchHistory() + NovelQueries.fetchHistory(). Unified HistoryItem enum. Merged and sorted by lastReadAt desc. Novel rows navigate via loadNovelDetail() (bridge lookup). Swipe-delete calls clearLastRead on correct type. Novel rows show "Novel" badge. |
| 7 | ✅ InsightsView: includes novels | Streak unions manga + novel chapter readAt dates. Chapters Read = manga + novel isRead counts. Time Read = manga + novel readingSeconds totals. Titles Started = manga + novels with readingSeconds > 0. "By Manga" → "By Title" section shows combined manga+novel stats sorted by time desc. |
| 8 | ✅ UpdatesView: novel updates | checkNovelUpdates(for:) mirrors checkUpdates(for:) using bridge.parseNovel(). Finds new chapters by path diff, calls insertAllIgnoringConflicts, touchLastUpdated, scheduleChapterNotification. novelGroups: [(novel: Novel, chapters: [NovelChapter])] added to ViewModel. Novel groups render in List below manga groups with NovelUpdateHeader + UpdateNovelChapterRow. |
| 9 | ✅ UpdatesView: direct chapter→reader | Manga chapter rows changed from NavigationLink→MangaDetailView to Button → loadMangaReader() (async: load bridge + full chapter list → find index → set MangaReaderDest). Novel chapter rows: Button → loadNovelReader() (same pattern → TextReaderView). navigationDestination(item:) for both. Section header NavigationLink to MangaDetailView kept. |
| 10 | ✅ LibraryViewModel: novel sort + search | displayedNovels computed var mirrors displayedManga: applies sortOrder (lastRead/alphabetical/lastUpdated/unreadCount) + searchText filter. novelUnreadCounts: [String: Int] loaded from NovelQueries.fetchUnreadCountsByNovel() in loadLibrary(). |
| 11 | ✅ LibraryView: displayedNovels | Novel grid uses viewModel.displayedNovels instead of viewModel.novels. Novel unread badge added to NovelLibraryCoverCell: accent-colored Capsule top-right, gated on AppSettings.showUnreadBadge, capped at 999. |
| 12 | ✅ NovelQueries additions | Added: fetchOne(id:), fetchHistory(), fetchRecentlyRead(limit:), clearLastRead(novelId:), touchLastUpdated(novelId:), fetchUnreadCountsByNovel(), insertAllIgnoringConflicts(), addReadingTime(chapterId:novelId:seconds:). |



---

# CLAUDE.md state archive (S96–S136)

Moved verbatim out of `CLAUDE.md` in S137 (2026-10-03). Newest first. The live state is in
`CLAUDE.md` → "Current state" and `ROADMAP.md`.

## Design track (S82-S95 — all 12 blocks complete)

All 16 screens designed and confirmed. Concept: **"reading instrument / living archive"** — warm editorial canvas, covers + user accent are the only color, monospace catalog notation, ink/screentone signature. Confirmed: default accent **Vermilion `#E5473A`**, default canvas **Ink (`#14110F`)**, Space Grotesk (UI) + Space Mono (notation), Newsreader serif (novel body) — *S136: the novel reader now has a font list (`Features/Reader/ReaderFonts.swift`: Apple faces + bundled Literata/Newsreader/Atkinson Hyperlegible Next/OpenDyslexic, built by `scripts/build-reader-fonts.sh`); the default is still Georgia, and `useSystemFont` (UI font) defaults on since S122.* Design tokens live in `DesignTokens.swift`; canvas colors are wired app-wide via `\.yomiCanvas` environment (`CanvasEnvironment.swift`, set from `AppSettings.canvasColors`); notation helpers in `Notation.swift`; Appearance Studio in `AppearanceStudioView.swift`. **Full design spec**: `Yomi/design/design_handoff_yomi/YOMI Screens.dc.html` — 16 screens as HTML with inline CSS. App icon assets: `AppIcon-Ink.png` + `AppIcon-Paper.png` in `Yomi/design/design_handoff_yomi/assets/`. **All 12 blocks complete as of S95 (2026-08-05).** Blocks 1-5 screenshot-verified S85; Block 6 (Browse) S86; Block 7 (History) S91; Block 8 (Updates) S92; Block 9 (Downloads) S93; Block 10 (Insights) S94; Blocks 11-12 (More/Settings/Onboarding/empty states) S95. **S96 (2026-08-06): the full functional audit Martin asked for, done.** App Store screenshot work is unblocked. **S97-S98: Tachimanga feature-parity pass, complete — see below.**

## Current state (post S136 — 2026-10-02 · perf batch done + reader typography pass)

**S136** — batch step 6: perf runs 1–5 hang-free on Martin's iPhone 17 (RESEARCH §23.6; `d15f611`, `2fe17c7`).
§25.10 #1 typography pass: font list (`Features/Reader/ReaderFonts.swift`, bundled WOFF2 via `yomi-font://`),
paragraph/letter spacing, column cap, hyphenation, Dynamic-Type default size; reader panel = nav + **Text · Look ·
Reading** tabs, following the reader theme's colorScheme. §25.10 #2 **Pages mode** (Reading → Layout; CSS columns +
native paging; `novelReadingMode`, `novelPagesContinue`). UI tests 12/12. Details: ROADMAP "S136". Next: #8 TTS, then #3 + #6.

## Prior state (post S133 — 2026-09-30 · batch step 4: novel reader controller)

**S133** — novel reader rebuilt around one persistent WKWebView + JS controller (`Features/Reader/NovelReaderWeb.swift`):
fixes Next-chapter-does-nothing (#1) and short-drag-opens-menu (#3), adds infinite scroll (#2, default on) and swipe
prev/next (#4), 1/2-tap menu option (Settings → Novels → Reading), hidden overlay out of the a11y tree. `YomiUITests`
5/5 pass. Details: ROADMAP "S133". Next: Martin ranks RESEARCH §25.10, reinstall on his phone, then batch step 5.

## Prior state (post S132 — 2026-09-29 · research audit + UX/UI evidence review, NO code changes)

**S132** (overnight, Martin asleep) — re-checked all Yomi research against primary sources and extended it:
**`Yomi/RESEARCH.md` §25** (claims audit table, "was it applied?" table, reading science for novels, manga/manhwa
evidence, cross-app review/GitHub/Reddit findings, new competitor **Eclipse**, corrected App Store reading, ranked
recommendations for Martin to dissect). Headlines: several §4/DESIGN_RESEARCH numbers were unsourced or misattributed
(NN/g "1.5:1", "41 % skipped", "+60 % streaks", personalization stats); App Store "primary purpose" test is DPLA
§3.3.1(B), not 2.5.2, and Guideline 4.7 now covers JS plug-ins; app has **no Dynamic Type**, no reader `max-width`,
no `hyphens` with justify, stale onboarding copy ("More → Plugins"). Part 2 (§25.13, Reddit): Lipex already runs
LNReader repos on the App Store; Keiyoushi officially supports only Android apps; bulk migration + lockable SFW mode
moved up; volume-button page turns violate Guideline 2.5.9. The S128 batch plan (step 4 reader controller)
is still next; §25.10 is a separate list for Martin to rank.

## Prior state (post S127 — 2026-09-25 · novel downloads + download-ahead)

**S127** — novel chapters download for offline reading (`Features/More/NovelDownloadManager.swift`): files keyed by
chapter path under `Documents/NovelDownloads/`, no DB column/migration; reader reads local first and keeps the next N
chapters downloaded (`AppSettings.novelDownloadAhead`, default 5, library novels only); detail selection bar
Download/Delete + ⋯ → Download; Downloads screen lists novels. Sim-verified end to end except network-off reading.
Also **"Download only on Wi-Fi"** (`Core/NetworkMonitor.swift`, `AppSettings.downloadOnlyOnWiFi`, default on):
manga + novel downloads wait on cellular/hotspot/Low Data Mode and resume on Wi-Fi; one-off "Download on cellular now"
on the Downloads screen; reading never gated. Simulate in the sim with launch arg `-yomiSimulateCellular` (DEBUG).
Next migration prefix still `v23_`. Next from the backlog: infinite scroll, then TTS (Martin picks).

## Prior state (post S126 — 2026-09-24 · WeTried plugin, Tachimanga chapter selection, ArcReader backlog)

**S126** — `wetriedtls.js` on Firebase (Martin's novel source), Read before / Select range / Invert on chapter
lists (`1f61fdb`), and a real bug fixed: hearting a novel then opening a chapter silently removed it from the
library (stale `novel` copy in `NovelDetailView.toggleLibrary`). **The ArcReader-parity backlog is in
`Yomi/ROADMAP.md` → "Backlog — novel reader parity with ArcReader" — work from that list, don't re-derive it.**
Martin picks the next item; suggested: novel downloads + download-ahead, then infinite scroll, then TTS.

## Prior state (post S125 — 2026-09-24 · one Extensions screen, Browse by type, novel-repo research)

**S125 (2026-09-24)** — Martin's feedback (he read in ArcReader for its translations, not Yomi): Browse was messy.
Commit `5ba8c7f`:
1. **Browse** = search pill + **Last used** (3, `AppSettings.recentSourceKeys`) + **Manga** + **Novels**, each
   alphabetical, plugins and Keiyoushi mixed (`BrowseSourceItem`). "Popular on <first plugin>" carousel and the
   segmented control removed; Migrate is a toolbar button. Same-named sources get "· YOMI PLUGIN"/"· KEIYOUSHI".
2. **Multi-language Keiyoushi extensions** are one row: `InstalledKeiyoushiExtension.enabledLangs` (nil = all),
   chosen at install (`KeiyoushiLanguageSheet`, phone language → English preselected); a row with >1 language opens
   `KeiyoushiLanguagesView`. `KeiyoushiExtensionsView` is gone (file now `KeiyoushiViews.swift`).
3. **Browse has Tachimanga's 3 tabs — Sources · Extensions · Migrate** (`BrowseView.BrowseTab`, update-count badge on
   Extensions; `PluginsView(embedded:)` / `MigrateView(embedded:)`, embedded Extensions puts its search field in the
   list so the tab strip doesn't jump). Extensions left More; "Get plugins" buttons set
   `appRouter.openBrowseExtensions` (was `openMorePlugins`). Storage → "Manage plugins" still pushes `PluginsView()`.
   The Extensions tab (`PluginsView`) replaces Plugins + Keiyoushi: merged Installed, a Repositories section (Add
   repository takes `.json` catalogs or `index.pb`), merged Available with a language filter; `SourceLanguage`
   normalizes codes vs LNReader's native names ("Español" → es).
Verified in the simulator (iOS 26.3 iPhone 17 Pro; the 26.0 one can't install — deployment target 26.2): Last used
appears after opening a source, MangaFire install → language sheet → saved `["en"]` → one Browse row; two languages
→ language list. Clean build, zero warnings, Yomi + YomiWidget.
4. **Research `RESEARCH.md` §22.14**: LNReader (280 plugins, MIT, active) *is* "Keiyoushi for novels" — Tsundoku
   (Android Mihon fork for novels) uses it too; IReader 143 / Shosetsu 58 / Mangayomi 9 aren't worth it. **Real
   cheerio (Tsundoku's bundle) runs in JavaScriptCore and passes every case the Yomi shim fails.** Recommended next:
   replace `JSBridge.injectCheerio` with an esbuild bundle of npm cheerio + real dayjs, then measure plugin pass rate.
5. **Real JS libraries for plugins** (Martin: "do the cheerio thing"). `scripts/build-js-libs.mjs` bundles npm cheerio
   1.2.0 + htmlparser2 + dayjs 1.11.23 (+customParseFormat/relativeTime/utc) + core-js 3.50.0 URL/URLSearchParams +
   atob/btoa/TextEncoder/setTimeout polyfills into `Resources/yomi-js-libs.js` (~450 KB, pinned devDependencies; rerun
   the script after bumping). `JSBridge.injectCheerio` evaluates it (replacing ~330 lines of hand-written cheerio +
   dayjs/htmlparser2/URL stubs); `global.cheerio.load` returns a Proxy that turns selector errors into an empty
   selection, and DOM nodes get `find/text/attr/…` forwarding methods because **12 of Yomi's 15 own Firebase plugins
   call `el.find()` inside each()** (the old shim passed wrapped elements). Also fixed: fetchApi now returns the real
   `status`/`ok`/`url` (after redirects)/`headers` via new `SOURCE._fetchResponse` (Madara plugins compare `res.url` to
   detect captcha); URLSearchParams POST bodies were JSON-stringified to "{}"; `@libs/fetch.fetchText`; `isUrlAbsolute`
   export; paged chapter lists (`totalPages` → `parsePage`, capped 150 pages); Mangayomi `Document.select`/children
   passed raw nodes to `_mkEl`. **Measured** with the DEBUG harness `LNReaderHarness` (launch arg `-lnreaderHarness`,
   options `-lnreaderHarnessOnly "A,B"`, `-lnreaderHarnessInstalled`, `-lnreaderHarnessLogFetches`; popular → novel →
   one chapter ≥200 chars): English LNReader plugins **7/157 → 67/157** end to end, no plugin that passed before fails
   now. Remaining: ~43 plugins parse 0 items from a 200 page (site layout changed upstream — e.g. Re:Library, Divine
   Dao), ~21 Cloudflare/captcha/403 (the harness doesn't run the in-app bypass), ~13 unreachable, a few one-offs
   (`Headers`, `fetchProto`). `JSBridge.lastPluginError`/`lastResultSummary` expose why a call returned nothing.
Translation (ArcReader's pull for Martin) is noted in §22.11 — Apple's Translation framework is the free candidate.

## Prior state (post S124 — 2026-09-24 · Keiyoushi (Mihon) extensions run inside Yomi on the iPhone)

**S124 (2026-09-24) — KEIYOUSHI RUNS INSIDE YOMI ON MARTIN'S iPHONE, no server.** Commits `c3c202b`…`680d9b2`.
1. **PoC Phase 1 passed** on the iPhone 17 (lab app `Labs/YomiBridgeLab`, table in `KEIYOUSHI_POC.md`). iOS HotSpot
   ignores `-Djava.home` → the runtime framework carries its Java home at `OpenJDKRuntime.framework/lib`.
2. **Converted extension jars persist** (bridge patch): first call after relaunch Asura 6.0 → 1.6 s, MangaFire 3.5 → 0.5 s (Mac).
3. **Personal build** (`Config/Personal.xcconfig`, `scripts/build-personal.sh`): free Personal Team, no push/iCloud/App
   Group (free team can't sign them — widget shows its placeholder), `YOMI_PERSONAL` disables CloudKit sync. Device-only.
4. **Keiyoushi in Yomi** (`Yomi/Features/Keiyoushi/`): `KeiyoushiJVMHost.mm` (dlopen'd runtime, embedded by the
   'Embed Keiyoushi runtime' build phase only when `YOMI_EMBED_KEIYOUSHI=YES`; stage with `scripts/keiyoushi/stage-vendor.sh`),
   `KeiyoushiRepository` (index.pb decode, install = APK to App Support), `KeiyoushiBridge` (POST /dalvik),
   `KeiyoushiBrowseView`, `KeiyoushiExtensionsView` (More → Keiyoushi). sourceId `keiyoushi_<Mihon id>`, chapter path
   `keiyoushi://…`. **Verified by Martin on device**: repo load, install, browse, read Asura + MangaFire.
5. **One translation per chapter** (MangaDetailView `readingChapters`, star chips = preferred group per title).
   MangaFire 1,516 → 924.
6. **Bug found on device + fixed**: History lost Keiyoushi reads — whole-row `MangaQueries.update` lost-update race on
   reader close + Browse-model rows overwriting saved state. Now `addReadingSeconds`/`updateSourceMetadata`/
   `updateCustomCover` + `adoptSavedState`. Affected JS/Suwayomi titles too.
**Next (Martin tests today):** his feedback first; then Updates/Downloads for Keiyoushi titles (not routed yet), Mihon
backup import mapping by source id, zstd stand-in, Asura tile pages (CoreGraphics Bitmap), MangaFire captcha via
WKWebView, dropping NewPipe (GPLv3) from the jar. Next migration prefix still `v23_`.

## Prior state (post S124 PoC phase)


**S124 (2026-09-24): Phase 1 of `Yomi/KEIYOUSHI_POC.md` PASSED.** New lab app `Labs/YomiBridgeLab/` (XcodeGen;
`prepare.sh` stages the gitignored `Vendor/` artefacts) hosts OpenJDK Zero + M-Extension-Server in-process on
Martin's iPhone 17; Asura Scans + MangaFire ran end to end (cold + warm), no crash, JVM start 45 ms, first
extension call 4.3–7.4 s, footprint peak 164 MB — table in KEIYOUSHI_POC.md, summary `RESEARCH.md` §22.13.
Fixes found on-device: iOS HotSpot **ignores `-Djava.home`** (Java home must be `OpenJDKRuntime.framework/lib`);
never name a bundle folder `Payload`; strip xattrs before codesign. **NEXT: Phase 2** (gaps: persist converted
jars, zstd stand-in, Bitmap via CoreGraphics, captcha via WKWebView cookies; then Yomi integration + one-translation
dedupe) — agree the order with Martin first. Yomi app code unchanged; next migration prefix still `v23_`.

## Prior state (post S123)

S123 (2026-09-24): (1) ArcReader deep-dive from its public Android APK → `RESEARCH.md` §22.11 (Flutter + Supabase,
server-shipped CSS-selector "recipes" + server resolver, sherpa-onnx TTS with 140 downloadable voices, coin
monetization). (2) Martin answered S122's questions: **PoC first; iPhone 17 / iOS 26.6.1; free Personal Team (7-day
builds); test with Asura Scans + MangaFire, never MangaDex.** (3) **Phase 0 verified on the Mac**: patched
M-Extension-Server on a java.base-only, interpreter-only JVM runs both extensions end to end (popular → search →
details → chapters → pages → image). Two real fixes were needed and are scripted: a `java.util.logging` stand-in (the
iOS runtime is `java.base` only) and a `NoZstdInterceptor` patch (Keiyoushi's new `KeiSource` requests zstd, whose
decoder is JNI-only). The OpenJDK Mobile runtime links into an iOS framework cleanly. Found that Keiyoushi sources
(MangaFire) also return duplicate translations → Yomi needs a "one translation per chapter" dedupe. Tooling installed:
Homebrew `openjdk@21` (keg-only, not on PATH) and `xcodegen`. Scripts: `scripts/keiyoushi-poc/` (README there);
research evidence: `RESEARCH.md` §22.12. No app code changed; next migration prefix still `v23_`.

## Prior state (post S122 — 2026-09-23 · DIRECTION RESET — research only, no code changes, read `RESEARCH.md` §22 first)

**S122 was a research-only session at Martin's explicit request** ("do not implement, don't assume, ask"). Goal: finish
and publish Yomi; make it as smooth as Tachimanga; drop the AI-looking Space Grotesk design; **top priority: Keiyoushi +
LNReader sources that work by pasting a repo URL, never maintained by Martin; ideally no server.** Full findings, numbers,
sources and URLs: **`Yomi/RESEARCH.md` §22** (§22.9 = open questions, §22.10 = things still UNVERIFIED — don't assume them).

**Corrections recorded (older docs were wrong):** Tachimanga does NOT use a remote server bridge (S89) nor a DEX
interpreter (§7b) — it runs a fork of Suwayomi ON THE PHONE (`tachimanga/Tachidesk-Server`, MPL-2.0) executing Keiyoushi
`.jar` builds in an embedded JVM. S47's "all LNReader plugins work at the JSBridge level" (§19) is false — the cheerio shim
throws on `.remove()` (147/280 plugins use it).

**Proposed direction (awaiting Martin):** (a) on-device Keiyoushi proof of concept on Martin's iPhone using the official
OpenJDK Mobile Zero runtime + an M-Extension-Server iOS build without its GPLv3 NewPipe part (§22.3); (b) replace the
cheerio/dayjs shims with the real libraries (§22.4); (c) performance pass driven by Instruments on device (§22.5 lists
6 code-read causes, incl. Kingfisher `backgroundDecode` off and zero tests); (d) design reset away from Space Grotesk
(§22.6); (e) Tachimanga `.tmb`/Mihon `.tachibk` backup import (§22.7, Madomi does it).

**Open questions for Martin:** (1) proof of concept first, or stutter fixes first? (2) which iPhone model?
Answered: Tachimanga repo URL = `https://github.com/keiyoushi/extensions/raw/repo/index.pb`; his Google account is
Workspace (no Cloud credits); Reddit posts reviewed (ArcReader, Bunori, Madomi).

**Not done this session:** no code, no builds, no Instruments profiling, no on-device test. Next migration prefix still `v23_`.

## Prior state (post S120 — 2026-08-27 · Suwayomi detail/reader fixed end-to-end, OAuth login-CSRF closed, token refresh + History gap fixed)

**S120 took the two items S119's handoff named as highest-value: #131 (Suwayomi manga detail shows
no chapters, ever) and #123/#124 (real tracker login-CSRF).** Clean zero-warning `build_sim`
throughout (`YomiWidget` not rebuilt — no shared files touched).

- **#131** — `MangaDetailView.loadChapters()` now has a Suwayomi branch (`loadSuwayomiChapters()`)
  that calls the REST methods that had zero call sites, fills in the detail metadata a browse-only
  manga lacks, persists + merges local read state, and sorts ascending per #50. Suwayomi chapters
  carry a `suwayomi://{mangaId}/{chapterIndex}` path; `ChapterReaderView.bridge` is now optional and
  a new `fetchPages(bridge:path:)` routes page loading to either the JS plugin (still on a detached
  task — `_fetchSync` blocks) or `SuwayomiService.fetchPageURLs`. **The filed finding was only half
  the bug**: two further `bridge != nil` gates in `MangaDetailView` hid the Start-reading button and
  made every chapter row's tap a silent no-op — found by live-testing the fix, not by reading. Both
  now go through one `canOpenReader` property. REST failures surface via a new `chapterLoadError`
  instead of an indistinguishable empty list.
- **#123/#124/#135** — new shared `MangaTracker.makeAuthState()`/`verifyAuthState(url:requireEcho:)`
  + a `pendingAuthState` protocol requirement. Every tracker now sends an unguessable 256-bit
  `state` generated when the app itself builds the authorization URL, and consumes it single-use on
  callback. Shikimori/Bangumi/MAL require an exact echo; AniList (Implicit Grant, whose docs don't
  promise the fragment echoes `state`) accepts a missing echo but rejects any callback arriving with
  no login pending on this device — which is the actual attack shape. MAL's constant `state: "yomi"`
  is gone. AniList also now sends `redirect_uri`, closing #135.

**Live verification**: #131 was verified end to end — no Docker or JDK 21 exists on this machine, so
a local stand-in server speaking Suwayomi's exact REST shapes stood in for the real one: Browse →
Stub Source → detail rendered author/genres/status/synopsis and all 5 chapters (previously: nothing,
ever) → Start reading → the reader fetched the chapter and all 3 page images and rendered them. That
exercises Yomi's own client code fully; it does not re-verify the real server's JSON shapes, which
come from S89's already-live-verified structs and were not changed. **#123/#124 are compile +
code-review only** — a real OAuth round-trip still needs registered client credentials for
AniList/Shikimori/Bangumi (#108/#115), which don't exist yet.

**Same session, continued — #108 and #114 (the two the handoff above named) are also fixed:**

- **#108** (MAL/Shikimori/Bangumi saved a `refresh_token` and never used it, so sync died forever
  once the access token expired while the screen still said "Connected") — new
  `MangaTracker.refreshAccessToken()` requirement on a shared `performTokenRefresh(url:form:)`, plus
  a `sendAuthorized(_:)` helper that refreshes and retries once on a 401. Every authenticated call
  in all 4 services now routes through it, `sendProgressUpdate` included. A refusal (400/401) logs
  the tracker out with "session expired — please log in again"; a network error changes nothing.
- **#114** (a title read but never finished never appeared in History) — `ChapterQueries.updateProgress`
  now touches `lastReadAt`, and `NovelQueries.updateScrollPercent` does the same through a new
  throttled `touchLastReadIfStale` folded into its existing transaction, so the ~400ms novel
  autosave doesn't multiply writes (#142).

**Live verification**: #114 confirmed end to end — read page 1 of 3, closed the reader, and History
listed the title as "CH. 001 · read to 33%" with `isRead = 0` (previously: nothing, ever); the novel
throttle's SQL was checked directly against a real GRDB row. #108 is compile + review only, same
credentials blocker as #123/#124.

**Third pass, same session — the dead-code batch plus the two next user-facing findings:**

- **#132/#133/#134/#136/#137** — six dead symbols removed after re-confirming zero call sites for
  each (`MangaDetailView.formatReadingTime`, `Notation`'s `volumeChapter`/`novelIndex`/`novelFooter`,
  `UpdatesViewModel`'s two single-chapter mark-read methods, `MigrateView.debounceTask`,
  `AdvancedSettingsView.showClearConfirm`). #136 was closed by deleting the state rather than adding
  the confirmation dialog it implies — clearing the plugin catalog cache destroys nothing a refetch
  doesn't restore.
- **#150** — a failed library read now renders "Couldn't load your library" with the real error and
  a **Try again** button, instead of the ordinary "Your library is empty" state. The novel half of
  the fetch moved from `try?` into the same `do/catch`.
- **#125** — chapter-update and reading-reminder notifications withhold the title while App Lock or
  Secure Screen is on (new `NotificationManager.shouldHideTitles`, the same guard #68 uses for the
  widget). The notification still fires and still deep-links; only the title is withheld.

**Live verification**: #150 confirmed end to end by renaming the `manga` table in the simulator's
`yomi.db` — the screen showed the real SQLite error instead of an empty library, and Try again
recovered cleanly once the table was restored. #125 is compile + review only (needs a real upstream
chapter update to fire); the dead-code removals are grep + clean-build.

**Fourth pass, same session — #129, #146 and the whole #139-144 performance batch:**

- **#129** — the widget's per-title subtitle is the real last-read chapter now, via two new bulk
  windowed queries (`fetchLastTouchedChapterNames`) run off MainActor for only the ≤5 ids shown.
- **#146** — Suwayomi/OPDS load failures in Browse show the real reason + **Try again** instead of
  the same "Load sources"/"Load library" button a never-loaded section shows.
- **#139/#140** — backup export's encode+serialize step and the Tachiyomi export's N+1 chapter
  fetch both moved off MainActor, the latter replaced by one `fetchAllGrouped(mangaIds:)` query;
  `.prettyPrinted` dropped from the machine-only JSON.
- **#141/#143** — new `setReadBatch`/`updateProgressBatch`/`markReadBatch` query functions; Updates'
  "mark all read" and a source migration now issue a couple of transactions instead of 4 per chapter
  (and migration indexes chapters by number once instead of re-scanning per chapter).
- **#142** — the novel reader's ~400ms scroll autosave skips any tick that hasn't moved ≥1%; the
  final position is still always written on chapter change and reader close.
- **#144** — new migration `v22_novel_chapter_unread_index`. **Next prefix is `v23_`.**

**Live verification**: #129 confirmed via the App Group plist (`"lastChapter": "Ch. 01"`, the real
chapter name); #146 confirmed by pointing `suwayomiURL` at a dead port and reading the error in
Browse; #144 confirmed by the migration applying to the existing DB and `EXPLAIN QUERY PLAN` now
reporting `USING COVERING INDEX idx_novel_chapter_unread`. #139-143 are compile + review only —
each needs a large library to show a measurable difference.

**Fifth pass (S121, 2026-08-28) — the accessibility batch, #120/#121/#122.** The fourth pass above
existed only in the working tree at the start of this session — reviewed, rebuilt clean on **both**
schemes, and committed as `e04ff83`. Then:

- **#120** — `YomiScrubber` is now a real accessible control: one `.accessibilityElement()` with a
  label, a spoken value, and an `.accessibilityAdjustableAction` stepping by its own `step`. Both
  call sites pass their own label/value formatter ("Page 3 of 20", "18 points").
- **#121** — every icon-only control in the novel reader's overlay labelled, plus
  `.accessibilityValue`/`.isSelected` on the toggles and swatches whose state was previously
  conveyed by colour alone.
- **#122** — the manga reader's 4 top-bar chips labelled.

**Live verification**: #122 confirmed in the real accessibility tree via `mobile_list_elements_on_screen`
(previously the raw SF Symbol names). #120/#121 are compile + review only — the manga scrubber only
renders at `totalPages > 1` and the novel reader wasn't reachable in this simulator; disclosed rather
than glossed.

**Sixth pass (S121) — the design-system batch #115-119, plus a real bug found doing it:**

- **#115/#116** — the 5 tracker screens and both OPDS screens now read `\.yomiCanvas`. New shared
  `.yomiListCanvas()` modifier (in `CanvasEnvironment.swift`) repaints a `List`'s chrome with the
  active canvas, since a `List` paints over the `.background(canvas.bg)` the ScrollView-based
  screens use. One modifier rather than 7 copies — the tracker screens alone are 5 identical Lists.
- **#117/#118/#119** — `Color(.systemGray5)`, `Color.secondary` (in `ChapterRow`/`ReadingStatusMenu`,
  plus the same duplicate in `NovelDetailView`) and `Color.gray` all replaced with canvas tokens.
- **#163 (new, HIGH)** — **OPDS drill-down has never worked.** `OPDSBrowseView`'s `body` is a
  `Group` whose branches are all false initially, and a `Group` distributes modifiers to its
  children — so `.task`/`.navigationTitle` attached to *nothing* and `load()` never ran. Confirmed
  pre-existing by reproducing it on a stashed, unmodified HEAD build before fixing.

**Live verification**: Trackers, the MAL login screen, the OPDS grid and the OPDS detail sheet all
screenshotted on **Paper** — warm cream throughout where they were previously cool system gray.
OPDS was verified against a ~40-line Python stand-in server (nav root + a deliberately cover-less
acquisition feed, so the placeholder path actually renders); the server log is what proved #163 —
zero requests before the fix, `GET /books` after.

**A verification gotcha worth remembering**: `xcrun simctl spawn <dev> defaults write` wrote to the
*device-level* prefs path, not the app's live data container, so the canvas never changed. Find the
real plist with `find .../Containers -name pacodealer.Yomi.plist` and `plutil -replace` that one —
and note the container UUID changes on reinstall.

**Next session**: ~9 substantive findings left (rows 109-110/112-113, 151-156) + 6 doc-only
(157-162). Nothing HIGH remains. Suggested: the doc-only rows (157-162, quick), then #151-156
(plugin-catalog integrity/validation) and the tracker-UX rows 109-110.

---

## Prior state (post S119 — 2026-08-27 · fixed all 5 HIGH findings from the S118 audit backlog)

**S119 started the audit fix backlog, taking the 5 HIGH-severity findings S118's own handoff named
first.** All fixed, clean zero-warning build on the `Yomi` scheme throughout (`YomiWidget` not
rebuilt — none of this session's files are shared with that target).

- **#138** (`BackupManager.importBackup` hung the UI): file read + JSON parse + model decoding moved
  off MainActor into a new `nonisolated static decodeBackup(at:)` returning a `Sendable`
  `DecodedBackup`; every restored row now writes inside **one** `appDatabase.write` transaction
  instead of one transaction per `*Queries.upsert`, with one `markCloudDirtyBatch` per record type
  replacing the per-row dirty-mark writes. ~24,000 main-thread transactions → one, off MainActor.
- **#145** (update check couldn't distinguish "nothing new" from "fetch failed"): both check
  functions now return whether their fetch genuinely failed, counted into a new
  `UpdatesViewModel.failedSourceChecks` and appended to the refresh banner.
- **#147** (tracker progress-sync failures invisible in all 4 services): new shared
  `MangaTracker.sendProgressUpdate(_:graphQL:)` protocol extension — real `do/catch`, HTTP-status
  check, AniList GraphQL `errors`-in-a-200 check, writes to `errorMessage` and clears it on success
  (which also closes the stale-banner half of #110); `TrackersView` rows now show that message.
- **#148** (failed migration deleted the working original): `MigrationService.migrate` fetches the
  new source's chapters *first* and throws `MigrationError.noChaptersFromNewSource` before any
  write, so nothing is touched when the fetch fails; the confirmation screen now always states the
  new source's real chapter count.
- **#149** (partial download marked "Downloaded"): a page counts only when both the fetch and the
  disk write succeed; `markDownloaded` runs only at zero failures, otherwise the chapter is marked
  not-downloaded and a new `failureMessage` is surfaced via `.yomiToast`. **Also closes #111** in
  the same code path (a cancelled download now cleans up instead of marking itself complete).

**Live verification**: `build_run_sim` + mobile-mcp. #145 was verified end-to-end — seeded a library
novel on the dead LightNovelPub source next to a working MangaDex manga via direct `sqlite3`,
relaunched, tapped Refresh, and the banner read **"No new chapters · 1 source failed"**, correctly
counting the dead source and not the healthy one (test rows removed afterward). The other four were
verified by clean compile + code review only — each needs state this dev simulator doesn't have (a
large backup file, two working sources for a migration, a flaky connection mid-download, real
tracker credentials, which #108/#115 note are still missing for 3 of the 4 services).

**Next session**: the backlog still has ~37 substantive findings — rows 108-110/112-122,
123-125/129/131-137, 139-144/146/150-156, plus rows 157-162 (6 quick doc-only fixes). Highest-value
remaining: **#131** (Suwayomi manga detail shows no chapters, ever) and **#123/#124** (real tracker
login-CSRF on Shikimori/Bangumi/AniList).

---

## Prior state (post S118 — 2026-08-22 · finished the full 23-dimension audit: verified all 15 UNVERIFIED S117 findings, then ran the last 4 uncovered dimensions)

**S118 had two phases, both continuing the S116→S117 full-project audit to its actual completion.**

**Phase 2 — ran the 4 dimensions that never got their finder agent to complete in S116/S117**
(Performance, Docs-vs-code, Error handling, Backend/Firebase — the last of the original 23), per
Martin's "finish the audit" ask. Used parallel `Agent` calls (not the `Workflow` tool, to stay
clear of the rate limit that hit S116/S117 four times) — one finder per dimension, each briefed on
the project's own established conventions (including the `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
setting that caused Phase 1's false positives) so they wouldn't repeat that mistake. **Every one of
the 25 findings produced was then independently re-verified by direct file-reading before being
trusted** — reading the exact cited lines, and for the Backend/Firebase dimension, live `curl -I`
against the production Firebase Hosting domain and a direct `diff` against a stale duplicate
directory found on disk. **All 25 confirmed true**, logged as Known Issues rows #138-162. Headline
findings: `BackupManager.importBackup` restores a whole library on the main thread with one
DB-write transaction per row — 24,000+ sequential synchronous transactions for a realistic library,
fully hanging the UI (#138, HIGH); a chapter-update check silently reports "No new chapters"
identically whether nothing is new or the fetch itself failed, since every JS-side plugin exception
is swallowed with no distinction (#145, HIGH); all 4 tracker services' progress-sync call never
surfaces failure anywhere, not even to their own `errorMessage` (#147, HIGH); a source migration
whose new-source chapter fetch silently fails still reports success and can delete the old library
entry + downloaded files, stranding the user with a chapterless manga (#148, HIGH);
`DownloadManager` marks a chapter "Downloaded" even when individual pages silently failed to fetch
(#149, HIGH); and no integrity/authenticity check exists anywhere between the Firebase-hosted
plugin catalog and JSCore execution — the only protection is TLS, and a compromised deploy or a
trusted-cert MITM (e.g. school/corporate TLS inspection) could silently modify plugin code with zero
user-visible signal (#151, MEDIUM). Also found a live, verified CDN-cache-staleness gap the S87
client-side fix (#9) never closed (#153) and a stale duplicate `Firebase/yomi-firebase/` scaffold
directory with 4 of 6 overlapping plugin files older than production (#156) — both confirmed via
direct external checks (`curl -I`, `diff`), not just code-reading. **No fixes applied — audit only.**

**This completes the full 23-dimension audit Martin originally asked for in S116** ("absolutely
everything," 2026-08-21). Final tally: 8 dimensions fully audited with adversarial re-verification
(S116) + 1 done directly by hand (live build+simulator walkthrough, S117) + 14 dimensions that got
a finder pass and are now all independently verified (10 from S117 + 4 from this session) = 23/23
covered. **Total real, verified findings from the whole audit: 34 (S116, rows 74-107, already fixed
S117) + 30 (S117, rows 108-137 — 15 fixed-worthy already confirmed, 15 more confirmed this session,
4 refuted) + 25 (this session, rows 138-162) = 89 findings logged, of which 4 were refuted and the
rest are real.**

**Next session should work through the fix backlog**: rows 108-122 (15) + 123-125/129/131-137 (8)
+ 138-156 (19 real, non-docs) = 42 substantive findings ready to fix, plus rows 157-162 (6 doc-only
fixes, quick). Suggest starting with the 5 HIGH-severity error-handling/performance findings from
this session (#138, #145, #147, #148, #149) — they're all real user-facing correctness gaps, not
just cleanup. Committed and pushed.

---

## Prior state (post S118 phase 1 — 2026-08-22 · independently verified all 15 UNVERIFIED S117 findings)

**S118 phase 1 — picked up exactly where S117 left off: independently verify Known Issues rows 123-137
before trusting/fixing any of them, starting with #130 given the stakes, per S117's own explicit
handoff note.** Done entirely by direct file-reading (no subagents/`Workflow` — avoids the
account rate-limit that hit S116/S117 four times), reading each cited file (and, for the two
highest-stakes claims, the surrounding project config) rather than trusting the finder agent's
prose.

**11 of 15 confirmed true**, table rows updated with the verification evidence: #123/#124
(Shikimori/Bangumi/AniList OAuth login-CSRF — confirmed by direct code contrast against MAL's
real PKCE `codeVerifier` check, which genuinely blocks the same attack the other 3 trackers are
exposed to), #125 (notifications ignore App Lock/Secure Screen, same gap #68 already fixed for
the widget), #129 (widget's "last chapter" field is a hardcoded literal), #132-137 (6 dead-code
items, each re-confirmed by grep). **#131 upgraded from MEDIUM/dead-code to HIGH/correctness** —
turned out to be a real functional bug, not just unused REST methods: `SuwayomiService.toManga`
sets `sourceId: "suwayomi_\(sourceId)"`, which can never match an entry in
`ExtensionManager.shared.installed` (real plugin ids), so `MangaDetailView.loadChapters()`'s guard
always fails for a Suwayomi-sourced manga — tapping into one from Browse shows no chapters, ever.

**4 of 15 refuted — real false positives from the finder agent, not just unconfirmed leads**:
**#130** (the highest-stakes one, claiming all 15 plugin `.js` files ship in the binary) had the
mechanics backwards — `membershipExceptions` inside a `PBXFileSystemSynchronizedBuildFileExceptionSet`
is an *exclusion* list, not an inclusion list (confirmed against S78's own changelog wording and
`seedBundledPlugins()`'s own doc comment). CLAUDE.md's/ARQUITECTURA.md's "zero plugin files ship in
the binary" compliance claim holds. **#126/#127/#128** (concurrency findings for
DownloadManager/BackupManager/the 4 tracker services, "same bug class as #82") missed that
`project.pbxproj` sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` project-wide (Xcode 26
"Approachable Concurrency") — none of those classes are `nonisolated` at the type level, so every
method on them is MainActor-isolated by default and correctly resumes on MainActor after any
`await`, no explicit hop needed. **All 4 refutations share one root cause: the finder agent never
checked the project's actual build settings before asserting a violation** — worth remembering for
any future audit dimension that reasons about bundling/build-phase or actor-isolation without first
reading `project.pbxproj`'s build settings directly.

**No fixes applied this session** — verification only, per the S117 handoff's own two-step plan
((a) verify, then (b) fix). **Next session should work through the now-fully-verified backlog**:
rows 108-122 (15, confirmed S117) plus rows 123-125/129/131-137 (8, confirmed S118) — 23 real,
verified findings ready to fix, headlined by #131 (Suwayomi manga detail is fully broken) and
#123/#124 (real tracker-login CSRF). Rows 126-128/130 are closed as false positives, not carried
forward. Committed and pushed.

---

## Prior state (post S117 — 2026-08-22 · S116 backlog fixed + remaining 15-dimension audit run, 30 new findings)

**S117 — Martin asked to fix the S116 backlog and then continue the remaining 15 dimensions in the
same session.** Fixed 32 of the 34 confirmed findings from Known Issues rows 74-107 directly (no
subagents — a large, mostly-mechanical fix sweep across ~19 files, done inline). The 2 left
unfixed are both deliberate architecture-tradeoff calls, not skipped for lack of time: #78 (iPad's
two independent tab-visibility stores — needs a real product decision on which wins, plus an iPad
device this environment doesn't have to verify either direction) and #106 (`ChapterReaderView.swift`
file split — safer as its own dedicated pass since several of this session's own fixes just touched
that exact file). Both left with an explicit rationale in the table below rather than silently
dropped.

**Notable fixes**: `ChapterQueries.upsert`/backup-restore now correctly marks CloudKit-dirty
(#75/#79, closes the silent-desync gap); the novel-reader soft-lock on re-tapping the current
chapter is gone (#92); `ReaderWebView`'s `Coordinator` now implements `decidePolicyFor` to block
navigation out of the reader from unsanitized scraped HTML (#95); tracker auto-update no longer
fires redundant API calls per chapter (#89); short chapters that don't need scrolling now correctly
fire the 90%-completion/scroll-percent signals instead of staying stuck at 0% forever (#93); OPDS
pagination is now consumed with a "Load More" affordance in both the root and drill-down views
(#87); the Tachiyomi-import "0 matched sources" miscount is fixed (#80).

**Verification**: clean zero-warning `build_sim` on the `Yomi` scheme, a live `build_run_sim` +
mobile-mcp pass confirming Library/Browse/Plugins/Sync all render and function post-changes (no
regression from the Query-layer, Extensions, or Reader changes). Did not separately rebuild
`YomiWidget` — none of this session's changes touched `AppSettings.swift`/`WidgetDataWriter.swift`
or any other file the widget target shares.

**Then ran the remaining 15 audit dimensions** (leaner single-pass `Workflow`, no high-severity-
recheck/completeness-critic stages, per Martin's own suggestion) — did the live-simulator-walkthrough
dimension directly instead of via subagent. **Hit the account's usage/rate limit twice more mid-run**,
same as S116 — resumed once via `resumeFromRunId`; after the second hit Martin asked to stop
spending more usage on it rather than resume a third time. **14 of 15 dimensions got their finder
agent to run** (only Tracker sync, Settings/storage, History/onboarding, Design system,
Accessibility, Security/privacy, App Store compliance, Concurrency, YomiWidget, and Dead code
actually produced findings — Performance, Docs-vs-code, Error handling, and Backend/Firebase never
got their finder to complete before the second rate-limit hit). **30 new findings logged as Known
Issues rows 108-137**: **15 independently adversarially verified** (rows 108-122 — headline items: a
tracker OAuth refresh-token that's saved but never used, silently killing MAL/Shikimori/Bangumi sync
forever once the access token expires, #108; a manga/novel that's opened and partially read but
never crosses the 80%/90% completion threshold never appearing in History at all, #114; `YomiScrubber`
— the reader's page/font-size slider — having zero VoiceOver support, #120) and **15 found by the
finder but never independently re-verified before the rate limit hit a second time** (rows 123-137,
explicitly marked UNVERIFIED in the table — most notably #130, a claim that all 15 production plugin
`.js` files are bundled directly into the shipped binary, contradicting this repo's own "App binary
ships zero plugin files (App Store compliance)" claim stated in both this file and ARQUITECTURA.md;
and #123/#124, claimed OAuth login-CSRF vulnerabilities in Shikimori/Bangumi/AniList's tracker flows
with no `state` param or PKCE). **The unverified rows are leads, not settled findings — confirm each
one by reading the cited file before trusting or fixing it**, starting with #130 given the stakes if
true. **No fixes applied to any of the 30 new rows this session** — audit-only, matching S99/S112/
S116's own precedent. Committed and pushed, per Martin's explicit ask to stop and not lose the work.

---

## Prior state (post S116 — 2026-08-21 · partial full-project audit, 8/23 dimensions fully verified)

**S116 — Martin asked for an "absolutely everything" audit, more thorough than S99/S112, explicitly authorizing
unlimited agent spend.** Run as a 23-dimension multi-agent `Workflow` (core/db, app lifecycle, CloudKit sync,
extensions/plugins, browse, manga reader, novel reader, library, trackers, settings, history/onboarding, design
system, accessibility, security/privacy, App Store compliance, concurrency, error handling, dead code,
performance, widget, docs-vs-code, backend/Firebase, live build+simulator walkthrough) — every finding
independently re-verified by a second adversarial agent before being trusted, matching S112's method but scaled
up. **Interrupted twice by the account's own session/usage limit mid-run** (not a bug in the audit itself), each
time resumed via `Workflow`'s `resumeFromRunId` (completed agents replay from cache, only the rest re-run) —
worth remembering this recovers cleanly, but **`resumeFromRunId` only works within the same chat session**, so a
run this large should be seen through to completion in one sitting rather than assumed resumable across a context
switch. Also caught and fixed a real bug in the workflow script itself mid-run: a double-wrapped `parallel()`
call in the high-severity recheck stage passed already-invoked promises instead of thunks.

**8 of 23 dimensions ran to full completion with independent verification** (Core & Database, App lifecycle,
CloudKit sync & backup, Extensions & plugin architecture, Browse & source detail, Manga reader, Novel reader,
Library & migration) before Martin asked to pause and continue in a fresh chat to conserve usage, rather than
risk losing the completed work to a third interruption. **34 new confirmed findings** logged below as Known
Issues rows 74-107 (23 medium, 11 low; the single high-severity candidate that surfaced didn't survive its
second-opinion recheck and was correctly discarded, not just dropped). Headline items: a wrong "0 matched
sources" count in the Tachiyomi-import summary (#80) that misleads every migrating user regardless of whether
the import actually worked; `ChapterQueries.upsert` never marking CloudKit-dirty (#75/#79), so backup-restored
read-state silently never syncs; a soft-lock in the novel reader when tapping the currently-open chapter in its
own chapter list (#92); tracker auto-update firing multiple redundant API calls near a chapter's end with no
guard (#89); and a WKWebView in the novel reader with no `decidePolicyFor` navigation interception over
unsanitized scraped third-party HTML (#95). **No fixes applied yet — catalog only, matching S99/S112's own
precedent of auditing and fixing in separate sessions.**

**15 dimensions never got their finder agent to complete and are NOT yet covered**: Tracker sync (the S115
code — highest-priority remaining slice, was deliberately scheduled hardest but the finder never finished),
Settings/storage/downloads/appearance, History/onboarding/App Lock, Design system & visual consistency,
Accessibility, Security & privacy, App Store compliance, Concurrency & Swift 6 actor isolation, Error handling &
silent failures, Dead code & unused assets, Performance, YomiWidget target, Documentation accuracy vs. code,
Backend service & Firebase plugin hosting, and the live build+simulator walkthrough. **Next session picking this
up should either (a) fix the 34 confirmed findings below first, since that's real known work, or (b) re-run the
audit workflow for just the 15 uncovered dimensions** (the full script, dimension list, and schemas are in this
session's transcript — a smaller single-pass version without the high-severity recheck/completeness-critic
stages would be cheaper and is probably sufficient for a second pass).

---

## Prior state (post S115 — 2026-08-19 · novel chapter-preload + full tracker-sync generalization)

**S115 picked up two S114-research items Martin chose directly: novel chapter-preload (small) and
tracker sync (large), both shipped same session.**

**Novel chapter-preload** — `TextReaderView.swift` now backgrounds a `bridge.parseChapter` fetch for
the next chapter once scroll progress passes 70%, cached in `chapterContentCache` and consumed by
`loadContent()` on nav instead of re-fetching; a jump-to-chapter (not just linear next/prev) evicts any
stale cached entry. Mirrors the manga reader's S109-111 boundary-preload intent without needing the
seamless in-scroll crossing that feature has (the novel reader is single-document-per-chapter, not
continuous-scroll).

**Tracker sync — S114's premise was wrong, corrected before building anything.** RESEARCH.md §20 claimed
"Yomi has zero tracker integration today"; it doesn't — real, working MAL (MyAnimeList) OAuth+auto-update
already existed (`MALService.swift`, wired into `ChapterReaderView.swift`), the research session just
never checked Yomi's own code before comparing against Aidoku's tracker list. Flagged this to Martin
directly rather than building a redundant "first tracker."

**What actually shipped**: a new `MangaTracker` protocol (`Features/More/MangaTracker.swift`) generalizing
MAL's existing shape (authURL/handleCallback/searchManga/updateProgress/logout/isLoggedIn), `MALService`
refactored to conform, and three new trackers built against it — **AniList** (`AniListTrackerService.swift`
— named distinctly from the pre-existing, unrelated `Features/Extensions/AniListService.swift` score-badge
actor, a real naming collision caught before it shipped), **Shikimori**, and **Bangumi** (Martin's picks,
research-verified live against each service's real API — see `RESEARCH.md` §21). AniList uses the
Implicit Grant (no client_secret needed, the only one of the four with that option); Shikimori and Bangumi
both require a `client_secret` embedded client-side (no PKCE alternative exists in either API) — flagged
directly to Martin, who confirmed embedding it is fine, same as every other open-source tracker client.
New `AppSecrets.swift` placeholders (`aniListClientId`/`shikimoriClientId`+`Secret`/`bangumiClientId`+
`Secret`) need real registered app credentials before any of the 3 new trackers can actually authenticate
— MAL is unaffected and keeps working as before. New `TrackerManager` (`Features/More/TrackerManager.swift`)
centralizes both the tracker registry (`loggedInTrackers`, fanned out from both readers on chapter-finish)
and OAuth-callback routing by host (`ContentView`'s one `.onOpenURL`, replacing MAL's old per-view handler).
New `TrackersView.swift` (More → Trackers) replaces the old single MyAnimeList row with all 4 trackers plus
a new `AppSettings.trackerAutoUpdate` toggle — previously always-on with no opt-out (Known Issue #72, now
fixed same session).

**Real pre-existing bug found and fixed as a prerequisite**: `Info.plist` had no `CFBundleURLTypes` entry
at all — the `yomi://` custom URL scheme was never registered with iOS, so MAL's own OAuth callback
(`yomi://mal/callback`) could never have actually reached the app. Likely broken since MAL login was
first built; every tracker's OAuth depends on this, so it had to be fixed regardless of scope (#73, fixed).

**A confusing red herring during this session, resolved**: after adding the new tracker files, a clean
build reported a nonsensical error inside `ChapterReaderView.swift` — a 2-argument `.onChange` closure
"expects 1 argument." Spent real time bisecting file-by-file assuming a whole-module-compilation/batch
bug (`SWIFT_COMPILATION_MODE=singlefile` didn't change it, which should have been the tell). The error
was real the whole time: `MALService`'s protocol-conforming signature change
(`searchManga`'s return type, `updateMangaProgress`'s parameter) broke `ChapterReaderView.swift`'s old
call site, and Swift's diagnostics for other still-broken files (missing `TrackerManager` etc.) were
simply suppressing/reordering when that particular error got surfaced. Fixed by updating the call site
to loop `TrackerManager.loggedInTrackers` (which was the real task-3 work anyway). **Lesson**: when a
build error looks structurally impossible for an unrelated file, check for a stale call site against a
signature you just changed before suspecting the toolchain.

Zero-warning clean build on both `Yomi` and `YomiWidget` schemes (AppSettings.swift is shared). Live-
verified via `build_run_sim` + mobile-mcp: Trackers screen renders all 4 services with correct
not-connected state, the auto-update toggle is live, and MyAnimeList's own login screen is unchanged.
Full OAuth round-trips for AniList/Shikimori/Bangumi remain unverified — they need real client
credentials from Martin first (see `AppSecrets.swift`'s comments for each registration URL).

**Follow-up same session — real tracker logos** (Martin's ask, and his call to use real logos over
a monogram fallback). Each service's own official icon, sourced from: MAL — `cdn.myanimelist.net`'s
own SVG favicon; AniList — `anilist.co`'s own apple-touch-icon PNG; Shikimori —
`shikimori.io`'s own apple-touch-icon PNG; Bangumi — no square icon exists anywhere, including their
own site (`bgm.tv` blocks non-browser requests entirely) — used the wordmark PNG from Wikimedia
Commons instead, tagged `{{PD-textlogo}}` (public domain — simple text/geometric logos don't clear
copyright's threshold of originality; still carries a standard trademark notice, which nominative
fair use for service-identification covers, same basis every "Login with X" button relies on).
New `Assets.xcassets/TrackerLogo{MAL,AniList,Shikimori,Bangumi}.imageset` entries, wired via a new
shared `TrackerLogo`/`TrackerHeaderLogoSection` (`TrackersView.swift`). **Real bug caught live,
not assumed**: Bangumi's wordmark PNG is solid black — invisible against the app's dark-mode row
background until rendered as `.template` + `.foregroundStyle(.primary)`. Also needed a wider,
non-square frame (72×28 in the list, 176×64 in its own header) since it's a ~3.6:1 wordmark, not a
square mark like the other three — flagged to Martin directly as a real tradeoff (his call: keep
the real wordmark honestly-sized over forcing it into a square that made it unreadable). Live-verified
all 4 renders via mobile-mcp screenshots. Zero-warning build both schemes.

---

## Prior state (post S114 — 2026-08-18 · external competitor/architecture research, no code changes)

**S114 was a research-only session in a general conversation, not a Yomi coding session — no code
touched.** Martin asked about Swift-ecosystem competitors, then went deeper on specific architecture
questions, then asked to commit+push the findings so they're not lost. Full detail in
`Yomi/RESEARCH.md` §20. Headlines: Ito/Nyora surveyed as new (not-yet-threatening) competitors in
Yomi's exact niche; a real code-level comparison found Aidoku's WASM plugin model has **no meaningful
performance edge** over Yomi's JSCore/JSBridge model, but surfaced a real, unrelated, unfixed bug —
Yomi's `CFBypassManager.autoBypass` only auto-retries Cloudflare blocks in `BrowseView.swift`, not in
`MangaDetailView.swift`/`NovelDetailView.swift`; Yuedu-reader's "Legado declarative rules" were ruled
out as a lower-App-Store-review-risk alternative (it's a JS engine underneath); Yomi's WKWebView-based
novel reader was re-confirmed correct and found to de-risk the backlogged Yomitan-dictionary-lookup
feature idea; Keiyoushi-via-Suwayomi (S89/S90) was re-confirmed as the right source strategy against
real current numbers for two alternatives; and hands-on builds confirmed Nyora can never run on
Simulator (device-only native engine) while Aidoku builds clean, with Aidoku's own UI surfacing a
shipped OCR dictionary-lookup feature, tracker sync Yomi lacks, and independent validation of the
Suwayomi-bridge strategy. **No Known Issues added, nothing fixed** — this was research, not a bugfix
session. Next session touching any of this starts at `RESEARCH.md` §20.

---

**S113 (2026-08-17) — worked through the S112 audit backlog** (Martin's "work through the S112 backlog" ask).
Scoped down to what's code-fixable in this repo, matching S111's precedent: excluded #47 (CloudKit
container provisioning — still blocked on paid Apple Developer Program enrollment) and #69 (MangaDex
plugin bug — source lives in a separate repo not present on this machine). Left #55 as-is (informational
only, no actual bug — GRDB keys migrations by string name, harmless). **Fixed all other 17 items**:
the silently-swallowed `DatabaseManager.setup()` failure now `fatalError`s loudly with the real error
(#52); `clearLastRead`/`touchLastUpdated` now mark Manga/Novel dirty for CloudKit sync (#53-54); the
Home Screen widget now stays empty while App Lock/Secure Screen is on, both via a write-time guard and
an immediate clear the moment either setting flips on (#68); two `SourceBrowseView`/`BrowseView`
concurrency bugs around the shared `JSBridge` (#57-58); orphaned downloaded files on source migration
(#60); a `Customize Tabs` bug where hiding your current default tab was a no-op exactly when that tab
was Library, for both `defaultTab` and `router.selectedTab` (#61); 5 dead-code functions removed
(#56/#59); a missing accessibility label on the reader's chapter-nav buttons (#70); and all 6 stale doc
citations (#62-67). Clean **zero-warning build** on both the `Yomi` and `YomiWidget` schemes throughout.
Live-verified: app launches cleanly with the new fail-loud DB path; the widget write-guard confirmed
end-to-end via direct `sqlite3` seeding + App Group plist inspection (empty when protected, real data
when not). The symmetric `didSet`-triggered immediate clear wasn't separately live-tap-verified — hit
the same known `mobile-mcp`/`XcodeBuildMCP` tap-tooling limitation documented since S109 trying to
toggle App Lock in the live UI. Full narrative in `Yomi/ROADMAP.md`'s S113 entry.

---

**S112 (2026-08-17) — full project audit, documentation-only.** Ran as an explicit multi-agent
`Workflow` — 7 parallel research dimensions (core/DB/app-entry/sync, extensions/plugins/browse/reader,
library/more/history/onboarding, docs-vs-code, App Store compliance, security/privacy, live
simulator+build-health walkthrough), each with its own adversarial verify pass re-checking every
finding against the live file before it was trusted. **Deliberately no fixes — findings only**,
catalogued as new Known Issues rows 52-71 above (all but #47/#55/#69 fixed S113, see above).
**No regressions found** in any S99-S111 fix spot-checked (S104's plugin allowlist, S105's CloudKit
dirty-marking, S109-S111's chapter-boundary preload chain, S101's contrast/placeholder work all still
hold). App Store compliance re-verified live and stayed clean.

---

## Prior state (post S111 — 2026-08-17 · backlog cleared: chapter-boundary preload root-caused+fixed, AquaManga pagination fixed, 3 new parity features shipped)

**S111 — Martin asked to "fix everything from the backlog."** Scoped down to code-fixable items
(excluded CloudKit provisioning, App Store Connect data entry, dead-repo plugin cleanup, and
anything needing Martin's physical device — all genuinely out of reach this session), then cleared
all six: (1) **S110's chapter-boundary preload trigger — root-caused for real, not tooling.** Apple's
own docs for `.scrollPosition(id:)` require pairing it with `.scrollTargetLayout()` on the scrolled
container; neither `WebtoonReaderView` nor `ContinuousHorizontalReaderView` had it, so `visibleId`
never tracked the actively-scrolled page regardless of input source — S110's mixed-API theory was
adjacent but missed the actual missing modifier. Added it to both, live-verified end-to-end via swipe
+ temporary `NSLog`: `visibleId` correctly progressed `cur:19→cur:20→boundary→next:0`, the preload
fired, and the reader crossed into Ch.7 with no tap. (2) **AquaManga runaway pagination (#9b)** —
`BrowseView.loadMore()` now dedups each page against already-loaded ids (terminates the moment a page
returns nothing new) plus a `maxPage=300` hard backstop. (3) **Rotation-follows-device setting** — new
`AppSettings.rotationFollowDevice`, wired into `AppDelegate.supportedInterfaceOrientationsFor` in
`YomiApp.swift`; live-verified the lock direction (toggled off, rotated the simulator to landscape,
app correctly stayed portrait). (4) **Repair Database action** — `DatabaseManager.repair()` runs
`PRAGMA integrity_check` + `VACUUM` (outside a transaction, via `writeWithoutTransaction`, confirmed
against context7's GRDB docs), new button in `StorageView.swift`; live-verified, alert showed "No
issues found. Database optimized." (5) **AppLockView restyled** to the Ink/Space-Grotesk design
system (was plain `Color(.systemBackground)`/system font, predating S79) — live-verified via
`appLockEnabled` + a cold relaunch, caught the frame before the simulator's system passcode sheet
took over. (6) **Tachiyomi-compatible backup *export*** — new `TachiyomiBackupExporter.swift`, the
reverse of the existing import parser (same protobuf3 field layout, gzip via libz), wired into
`BackupManager`/`BackupView`. **Verified byte-for-byte**, not just "compiles": hand-decoded the
exported `.tachibk`'s protobuf in Python, confirmed title/url/artist/status/favorite and all 9
chapters' read-state/lastPageRead/chapterNumber matched the live DB exactly.

**New tooling finding, worth remembering**: `mobile-mcp`'s `mobile_set_orientation` can desync its
internal orientation state from the simulator's actual rendered orientation — every tap coordinate
was silently wrong for several minutes mid-session until `mobile_get_orientation` was checked and
found stuck on `landscape` from an earlier rotation test, well after the visible UI (and a fresh
`mobile_get_orientation` re-query) had returned to portrait. If taps start landing on the wrong
element with no other explanation, check `mobile_get_orientation` before suspecting the app.

Zero build warnings throughout, live-verified where the simulator allowed it. Next session picking
up rotation-follows-device's positive direction (unlocked → device rotates) should try a real device
or `XcodeBuildMCP`'s `snapshot_ui`/tap tools if enabled — `mobile_set_orientation` couldn't be
confirmed to trigger a live rotation once unlocked, only the restrictive (locked) direction was
provably correct in this session.

---

## Prior state (post S110 — 2026-08-17 · Customize Tabs fully verified; found+fixed a real chapter-ordering bug; boundary-preload trigger still unconfirmed)

**S110 re-attempted S109's "verify on Martin's device" items in the simulator anyway**, using a
`sqlite3`-seeded near-chapter-end resume position and Pulse's Network Console as ground truth.
**Customize Tabs is now fully live-verified**: found that a short, off-center swipe reaches a partial
scroll position where a full fling always overshoots; toggled History off, watched the bottom tab bar
rebuild live and correctly re-space, confirmed the hidden state survives a full app relaunch, then
restored the default 5 tabs. **Found and fixed a real, pre-existing bug, unrelated to S109's own
code**: `MangaDetailView.swift` and `ContinueReadingRow.swift`'s two reader-launch paths built the
`chapters` array straight from the source plugin's native return order — confirmed via a live `curl`
against AsuraScans' real API that this is newest-first, not ascending — while `ChapterReaderView`'s
prev/next-chapter logic (`chapters[index ± 1]`) assumes ascending order. Result: "Next Chapter" (and
the new boundary-preload) silently targeted the *previous* chapter instead, for any source that
returns newest-first (most of them). Fixed by sorting `chapters` ascending by `chapterNumber`
immediately after each load, matching `ChapterQueries.fetchAll`'s own convention (`UpdatesView.swift`'s
reader-launch path was already correct). Live-verified via the in-reader Chapters sheet: Ch.1→Ch.9 now
lists in order. **The boundary-preload's own trigger still couldn't be confirmed firing** — Pulse's
Network Console showed zero request for the next chapter's page list across 3 separate seeded/organic
attempts crossing the documented threshold. Temporary `NSLog` instrumentation (removed before
committing) showed `WebtoonReaderView`'s `.onChange(of: visibleId)` never fires at all during
`mobile-mcp` swipes in this environment, even though content visibly scrolls — `WebtoonReaderView`
mixes the older `ScrollViewReader.scrollTo` API (for resume-to-page) with the newer
`.scrollPosition(id:)` reactive binding (for detecting the visible page) on the same `ScrollView`, an
undocumented combination that's a plausible cause, but a genuine code bug isn't ruled out either.
**Next session should verify on Martin's real device** whether the boundary card appears under real
touch input before assuming this is tooling-only.

---

## Prior state (post S109 — 2026-08-17 · chapter-boundary transition + Customize Tabs screen shipped)

**S109 shipped the two items S108 explicitly deferred.** (1) **Chapter-boundary transition**
(`ChapterReaderView.swift`) — Webtoon/Continuous reader now preloads the next chapter in the
background as the user nears the end and appends a `ChapterBoundaryCard` + its pages directly
into the same scroll content, crossing with a state swap instead of a reload/jump, matching
Tachimanga's reference screenshots from S108. **Found + fixed a real bug live**: the preload's
background fetch (`SOURCE._fetchSync`, `JSBridge.swift`) blocks synchronously on a
`DispatchSemaphore` with no timeout — an existing app-wide pattern, but firing it silently in the
background while the user keeps reading meant a slow/rate-limited source could peg the CPU at 99%
and freeze the UI (confirmed via CPU sampling, reproduced twice). Fixed with a 12s timeout race.
**Verified**: CPU stayed normal (0–20%) across many repeated scroll/scrub ops post-fix.
**Not verified**: the boundary card's actual on-screen appearance/crossing — `mobile-mcp`'s swipe
doesn't respect its `distance` parameter in this environment (every swipe resolves to a full fling
to the nearest scroll bound, tested 30–2000 with identical results — a sharper characterization of
the swipe unreliability noted since S87), compounded by the standing reader-header tap flakiness
(S101/S108). (2) **Customize Tabs settings screen** (new `YomiTabID.swift`,
`CustomizeTabsView.swift`, `AppSettings.tabOrder`/`hiddenTabIDs`, `ContentView.swift` rebuilt to
construct `Tab`s via `ForEach` — confirmed against live Apple docs as a sanctioned pattern) —
drag-to-reorder + toggle-to-hide, "More" locked visible since it's the only way back to Settings.
**Verified**: clean build, app launches with all 5 tabs correctly ordered. **Not verified**: the
drag/toggle UI itself — same swipe-imprecision block, couldn't scroll far enough down Settings to
reach the row. Zero build warnings throughout. Commits pushed to `main`. **Next session touching
either should re-verify visually on Martin's own device**, not fight this simulator's swipe tooling.

---

## Prior state (post S108 — 2026-08-16 · branch reconciliation + 3 parity items shipped)

**S108: reconciled a real branch split first** — `main` had unrelated dev-tooling commits
(SwiftLint/fastlane/Pulse, 8/14) while S106/S107's CloudKit investigation lived unmerged on
`worktree-cloudkit-verify-s106` (8/11). Merged cleanly (docs-only, no code conflicts), pushed,
removed the now-redundant worktree/branch. **CloudKit sync stays out of scope** — still blocked on
Apple Developer Program enrollment (#47), Martin's call not to enroll yet. Worked the buildable
half of `TACHIMANGA_PARITY.md`'s backlog instead:

1. **Dated iCloud backup list** — `BackupManager` now writes timestamped files and keeps the last
   8 instead of overwriting one fixed `YomiBackup.json`; `BackupView.swift` shows a real list
   (date + size, swipe-to-delete, restore-a-specific-entry). **Not live end-to-end verified** — the
   dev simulator's iCloud session had lapsed (password re-auth dialog blocking the home screen at
   session start); code review + clean build only.
2. **Color-blend slider** — new `AppSettings.colorBlendLevel` + `Color.mix(with:amount:)`, blends
   `bg`/`surface1`/`surface2` toward the accent app-wide via `blendedCanvasColors`
   (`\.yomiCanvas`, not just a preview). **Live-verified at 60% on Paper**: tints consistently
   everywhere, and the pre-existing AA badge correctly drops to "Fail" — surfaces the Paper/Sepia
   contrast tension from S101 rather than hiding it.
3. **Date format picker** — new `use24HourClock`/`dateOrderDayFirst` settings, threaded as
   parameters into `Notation.historyTimestamp(_:use24Hour:dayFirst:)` (kept `Notation`
   `nonisolated`-safe, no `AppSettings.shared` read inside it). **Live-verified both axes** via a
   seeded `sqlite3` `lastReadAt`: "20:30"↔"8:30 PM", "JUL 20"↔"20 JUL".
4. **Customize Tabs — root-caused, not fixed.** `ContentView.swift` had `.customizationID`s +
   `.tabViewCustomization($customization)` since S43 but was missing
   `.tabViewStyle(.sidebarAdaptable)` (required per Apple's docs) — added it, no visual regression.
   But the real finding (from watching WWDC24's actual talk, titled "...**in iPadOS**"): the
   system's drag/hide editing UI only exists in the sidebar, which only renders in regular-width
   contexts — **iPhone gets a plain tab bar with zero built-in customization affordance**,
   confirmed live (long-press just selects, no jiggle/menu). Needs a real custom settings screen to
   deliver on iPhone at all; logged for a future session rather than built this one.

Zero build warnings throughout. Commits pushed to `main`. Full narrative in `Yomi/ROADMAP.md`'s
S108 entry.

---

## Prior state (post S107 — 2026-08-11 · Known Issues backlog re-check, no code changes)

**S107: CloudKit sync stays blocked pending Apple Developer Program enrollment (Martin's call — not
done yet), so this session re-verified 3 lower-priority open Known Issues instead.** (1) **Novel-source
status (#21) re-checked live via `curl` with a real iOS UA**: LightNovelPub and BabelNovel are still
genuinely Cloudflare-gated (403, "Just a moment"/"Attention Required" markers present) — unchanged. But
**BoxNovel is a new, worse failure mode than previously recorded**: it no longer serves any real site at
all — `boxnovel.com` now returns HTTP 200 but the body is a domain-parking/ad-redirect shell posting to
`router.parklogic.com` (classic expired-domain-squatting pattern), not a JS-anti-bot challenge. The
domain has effectively changed owners; no plugin fix is possible against a parked domain. NovelBin
(`novelarrow.com` backend) reconfirmed HTTP 200, still working. (2) **Duplicate-extension self-heal
(#12) re-checked** via direct `sqlite3` against the primary dev simulator's `yomi.db`: `SELECT name,
COUNT(*) FROM extension GROUP BY name HAVING COUNT(*) > 1` returned zero rows — no duplicates present.
Not a strong test (this simulator only has 2 extensions installed, neither NovelFire/NovelBin/
FreeWebNovel — the plugins that hit the old id-scheme migration), but consistent with the S88 fix
holding. **The user's real device was never checked and still might have legacy duplicates** — this
remains a "worth a glance" item, not fully closed. (3) **Suwayomi Latest tab (#8)**: no local Suwayomi
server was available to re-run a live end-to-end test, and standing one up from scratch (Docker/JVM,
per `ROADMAP.md`'s S89 setup notes) was judged disproportionate for a tab whose risk was already rated
low. Did a targeted code read instead: `SuwayomiService.fetchLatest` and `fetchPopular` both route
through the exact same generic `fetch<T>()` helper (same request construction, same 200...299 status
check, same JSON decode), differing only in the URL path segment (`/latest/` vs `/popular/`); the view
wiring in `SuwayomiBrowseView.swift` (`selectedFeed == .latest` branch, `loadMore()`) is structurally
identical to the already-verified Popular path. No divergent logic found — confidence raised without a
live server, but a real end-to-end fetch against a running server is still technically unverified.
**Also confirmed no build regressions**: clean `build_run_sim`, zero warnings/errors.

---

## Prior state (post S106 — 2026-08-11 · CloudKit sync blocked on Apple Developer Program enrollment)

**S106: picked up the S103/S105 real-iCloud-account verification, found the real blocker.** Signed a
real Apple ID into two simulators (iPhone 17 Pro + iPhone 17 Pro Max, iOS 26.3), built and launched Yomi
on both. `CKContainer.accountStatus()` now correctly resolves `.available` on both — the account/
entitlements path works exactly as designed. But enabling sync immediately fails on both:
`CKSyncEngine.sendChanges()`/`fetchChanges()` throw `CKError "Bad Container" (5/1014)` — **the CloudKit
container `iCloud.pacodealer.Yomi` has never been provisioned on Apple's servers**, confirmed via
`xcrun simctl spawn <device> log show` and cross-checked against Apple's own `CKError.Code.badContainer`
docs + developer-forum precedent (WebSearch). Root cause, confirmed directly with Martin: **the project
isn't enrolled in the paid Apple Developer Program ($99/yr)** — flagged as an unpurchased cost item back
in S90, not previously connected to CloudKit specifically. Container creation requires that enrollment
regardless of entitlements content (a free/personal team can't provision CloudKit containers at all),
and S103's entitlements were hand-written rather than added through Xcode's Signing & Capabilities UI,
which is the only thing that actually registers a container server-side. No code changes needed —
**next session touching this feature starts with**: enroll in the Program, open `Yomi.xcodeproj` →
Signing & Capabilities → add iCloud/CloudKit → use "+" under Containers to provision
`iCloud.pacodealer.Yomi`, then re-run this exact two-simulator test. Full detail in
`Yomi/CLOUDKIT_SYNC_DESIGN.md`'s new "What was verified, and what wasn't (S106)" section.

---

## Prior state (post S105 — 2026-08-07 · CloudKit sync code-review findings fixed)

**S105: fixed all 6 code-review findings from S104's pass over the S102-S103 CloudKit sync code**
(Known Issues #41-46 above — full detail there). Two were real sync-correctness bugs: an UPDATE-only
remote-apply that silently dropped chapter read-state for manga not yet locally cached (fixed with a
new pending-state stash-and-replay table, since a true upsert isn't possible without the full chapter
row) and category deletion not propagating join-table deletes to CloudKit (fixed by reading the join
rows before the CASCADE delete). The other four: a durable dirty-mark queue closing the async window
during `enable()`'s account-status check (new `cloud_sync_map.pendingChange` column, drained into the
engine right after it's created), an `isEnabling` guard closing `enable()`'s double-call race, reverting
a `try?` regression that had silently swallowed 2 bulk mark-read functions' DB-write errors, and a
Release-only `Yomi-Release.entitlements` file (production `aps-environment`) so the correct APNs
environment no longer depends on automatic-signing rewrite behavior. New migration
`v21_cloud_sync_pending` — next must be `v22_`. All fixes live-verified: clean Debug **and** Release
`build_sim`, `build_run_sim` launch with no crash, direct `sqlite3` inspection confirming the migration
applied and new tables/column exist, and both entitlements files confirmed picked correctly via each
config's `ProcessProductPackaging` build-log line. **Still queued, not touched this session**: the
S103 real-iCloud-account verification (this dev simulator still has no account signed in — an actual
CloudKit send/fetch round-trip and multi-device convergence remain unverified).

Committed and pushed to `main`.

---

## Prior state (post S104 — 2026-08-07 · piracy/App-Store-compliance audit + first-party catalog fix)

**S104: Martin asked directly whether Yomi complies with App Store piracy regulations.** Fetched the
live current guideline text from developer.apple.com rather than trusting `RESEARCH.md`'s existing
summary (stale in two ways — corrected, see `RESEARCH.md` §5), then did a fresh-user walkthrough (S96's
`cfprefsd`-clear procedure). **Finding**: the applicable rule is Guideline 5.2.2 (Third-Party
Sites/Services — "specifically permitted... under the service's terms of use"), and Yomi's own
first-party Plugins catalog (`yomi-plugins.web.app/index.json`, fetched automatically, pointed at
directly from onboarding page 2/3) one-tap-installed 12 unlicensed scanlation/scrape sources alongside
3 lower-risk ones (MangaDex, Royal Road, Scribble Hub) — a bigger reviewer-exposure surface than the
LNReader repo risk S96 already mitigated, never covered by that fix. **Fixed** (Martin's call: match
the LNReader treatment): new client-side `instantInstallSourceIDs` allowlist in `PluginsView.swift` —
only those 3 stay one-tap Install; the other 12 now require Copy URL + manual add, same interaction
`FeaturedRepoRow` already used for LNReader. Deliberately kept as a compiled-in allowlist, not a remote
JSON flag (a server-controlled compliance switch would itself look like review-evasion if found). Zero
build warnings, live-verified via `build_run_sim` + mobile-mcp. Full narrative + the corrected 2.5.2/
5.2.2/precedent research in `Yomi/ROADMAP.md`'s S104 entry and `Yomi/RESEARCH.md` §5.

**Also this session**: a `/code-review` pass on the S102-S103 CloudKit sync code surfaced 6 findings
(2 real sync-correctness bugs — an UPDATE-only remote-apply that silently drops chapter state for
manga not yet locally cached, and category-deletion not propagating join-table deletes to CloudKit;
plus a `markCloudDirty` no-op window during `enable()`'s async account-status check, a double-`enable()`
race, `try?`-swallowed DB-write errors in 2 bulk mark-read functions, and a hardcoded `development`
`aps-environment`) — **not yet triaged or fixed**. Next session should start here, alongside the
real-account CloudKit verification already queued from S103.

Committed and pushed to `main`.

---

## Prior state (post S103 — 2026-08-06 · CloudKit sync implemented)

**S103: implemented the full multi-device CloudKit sync feature designed in S102**, same session-day.
New `Yomi/Sync/CloudSyncManager.swift` (`CKSyncEngine` + delegate, `Manga`/`Novel`/`Category`/
`MangaChapterState`/`NovelChapterState`/`MangaCategoryLink`/`NovelCategoryLink` CKRecord mapping),
new `cloud_sync_map` GRDB table (migration `v20_cloud_sync_map`, next must be `v21_`) as a reverse
recordName→(type,key) index plus a cached-CKRecord store for real change-tag conflict detection,
`markCloudDirty`/`markCloudDeleted` hooked into ~20 call sites across `MangaQueries`/`ChapterQueries`/
`NovelQueries`/`CategoryQueries`, a new distinct Settings → More → **Sync** screen
(`CloudSyncView.swift`, separate from the existing iCloud Backup screen on purpose), and
`AppSettings.cloudSyncEnabled` driving engine enable/disable. **One real deviation from the S102
design, caught mid-implementation by checking Apple's actual docs rather than assumption**:
`CKSyncEngine`'s own class documentation states it requires the Remote Notifications entitlement, not
just CloudKit — added it (background mode + gated `registerForRemoteNotifications()`, only when sync
is on) rather than gamble on undocumented behavior; this doesn't change the product decision that sync
only visibly happens on foreground/background, no real-time UI was built. Zero build warnings.
**Live-verified only as far as this dev simulator allows — it has no iCloud account signed in**: clean
build, no crash launching with the new entitlements, the Sync toggle correctly drives a real
`CKContainer.accountStatus()` call and lands on the `.unavailable` state exactly as designed. **Not
verified**: an actual record reaching CloudKit, the fetch/merge path, or real two-device convergence —
needs a signed-in account next. Full as-built notes, what was/wasn't verified, and the real
`CKSyncEngine` API names (several differ from the WWDC23 talk's own code sample) are all in
`Yomi/CLOUDKIT_SYNC_DESIGN.md`, updated in place rather than duplicated here.

**Prior state (post S102 — 2026-08-06 · CloudKit sync architecture scoped, not implemented)**

S102 designed the full multi-device CloudKit sync architecture (not yet built at the time) — the last
big item on `TACHIMANGA_PARITY.md`'s backlog, scoped the same way S90 scoped the Suwayomi-server
design before writing code. Key finding: `Manga.id`/`Chapter.id` are already content-derived (traced
through `JSBridge.swift`), not local UUIDs — meaning (1) chapter lists never need to sync, only the
small per-chapter state a user actually touches, and (2) first-sync bootstrap on an existing library
needs no special merge logic. `CKSyncEngine` chosen over `NSPersistentCloudKitContainer` (Core
Data-only, ruled out — Yomi is GRDB) and raw `CKDatabase` calls. See `Yomi/ROADMAP.md`'s S102 entry
for the scoping narrative — superseded by S103's implementation above.

**Prior state (post S101 — 2026-08-06 · rows 31-33 shipped + theme/contrast audit)**

**S101: shipped the 3 features S100 deferred, plus a canvas×accent contrast audit that found 3 real
bugs (live-testing, not just math).** Background auto-refresh (real `BGTaskScheduler` wiring —
`com.yomi.refresh` registered in `AppDelegate`, scheduled on `scenePhase == .background`, handler
reuses `UpdatesViewModel.refresh()` verbatim), background download (gated on auto-refresh, hooks into
`UpdatesViewModel.checkUpdates(for:)`'s new-chapter discovery to auto-enqueue via `DownloadManager`,
manga only), and an in-reader source-URL globe icon (new `JSBridge.resolveSourceURL(path:)` —
best-effort, no plugin changes: reads a plugin's own top-level `BASE_URL`/`BASE` JS global back out
of the JSContext when `path` isn't already absolute; works for ~7 of 15 plugins + Mangayomi-format
sources, hides the icon rather than guessing for the rest). Toggles in `SettingsView`'s Data section,
both default off.

**Theme audit (Martin's ask: "revise how the different app themes look with every possible accent
combination"), computed first, then live-verified — found the audit's own math was too optimistic
until live-tested.** WCAG contrast across all 4 canvases × 11 accents flagged: (1) most accents are
barely visible as icons/progress-bars on Paper/Sepia (as low as 1.24:1) — a real, unresolved tension
between "accent is always exactly the user's chosen color" and legibility, flagged for Martin rather
than silently recolored; (2) every accent's hardcoded white button-label text was failing WCAG AA
except Indigo — confirmed live (Ink + Yellow: "Resume" text genuinely unreadable). Fixed with
`YomiTokens.Accent.foreground(for:on:)`, applied at ~12 real sites app-wide. **First version of that
fix was itself wrong, caught by Martin from a live screenshot**: a blanket "pick whichever of
white/black wins" formula flipped even passing defaults (Vermilion on Ink) to black, breaking the
card's all-one-ink-color convention — corrected to keep the canvas's own ink color whenever it clears
a 3:1 threshold, only flipping for accents that genuinely fail. Martin's screenshot also caught 2 more
real bugs missed by the math-only pass: `CoverImage.swift`'s no-cover placeholder used `Color.secondary`
(system light/dark only) instead of canvas tokens, and — root-caused while fixing — Kingfisher's
`KFImage.placeholder` doesn't live-repaint on an environment-only change (`.id(canvas.name)` forces a
remount on canvas switch); and a novel-indicator badge rendered two different ways on two screens
(Library grid's "NOVEL" pill vs. the Continue shelf's chunky "N" square), unified to the pill. **Lesson
for future theme/design passes: WCAG math alone missed real bugs a live screenshot caught in seconds —
always live-verify at least the worst-case combos the math flags, don't stop at the calculator.**

Full narrative in `Yomi/ROADMAP.md`'s S101 entry. All fixes live-verified via `build_run_sim` +
mobile-mcp/XcodeBuildMCP screenshots across multiple canvas×accent combos, zero build warnings.

**Prior state (post S100 — 2026-08-06 · S99 audit backlog cleared)**

**S100: worked through S99's Known Issues backlog end to end** (rows 24-30, 25, 26, 34, 35 — age
rating, doc cleanup, OPDS→Keychain, silent-failure toasts, the AquaManga reader-page bug, list-mode
multi-select), per Martin's "let's go through all the known issues and fix them." Rows 31-33
(background auto-refresh/download toggles, in-reader source-URL icon) are real new features, not bugs —
explicitly deferred to a future dedicated session at Martin's call, backlog now lives in
`Yomi/TACHIMANGA_PARITY.md`'s S100 addendum. Headline fix: the AquaManga reader-page bug (#34) and the
long-unverified cover-loading fix (#9) turned out to share one deeper root cause — Kingfisher's
`ImageDownloader` defaults to an `.ephemeral` session with its own private cookie store, invisible to
the `HTTPCookieStorage.shared` that `CFBypassView` writes `cf_clearance` into, so the S89 UA
`requestModifier` alone was never sufficient. Fixed by pointing Kingfisher's session config at `.shared`
— verified live, both covers and reader pages render real art now. Full narrative in
`Yomi/ROADMAP.md`'s S100 entry, technical lessons in `Yomi/METODOLOGIA.md`'s S100 section. All fixes
live-verified via `build_run_sim` + `mobile-mcp` + direct `sqlite3`/`defaults read` inspection, zero
build warnings throughout.

**Prior state (post S99 — 2026-08-06 · full project audit, documentation-only)**

S99 ran a full audit of the whole project — code quality, docs consistency, live simulator
verification, and App Store/security readiness — as 4 parallel research passes plus a manual
live-simulator spot-check, deliberately making no fixes, only cataloguing findings as new Known Issues
rows 24-36 for S100 to work through (see above). Code/quality was otherwise genuinely clean after 98
sessions (zero TODO/FIXME, zero unsafe force-unwraps, zero Swift-6 isolation violations, clean build).

**Prior state (post S98 — 2026-08-06 · Tachimanga parity pass complete)**

S97-S98 worked through `Yomi/TACHIMANGA_PARITY.md` (a source-verified feature audit against Tachimanga,
produced S97) end to end — **every item the audit itself flagged as high-value is now shipped.**
S98 alone shipped 4 items, in order of increasing complexity:
1. **Storage composition view** (`StorageManager.swift`/`StorageView.swift`, Advanced → Storage) — real
   byte-accurate breakdown (Downloads/Image cache/Plugins/Custom covers/Web cache/Database/Other) with
   Manage/Clear actions. Found + fixed a real SwiftUI bug live: a `GeometryReader` used directly as
   List row content destabilized every row below it (untappable, accessibility-tree/scroll desync) —
   moved the summary bar entirely outside the `List`.
2. **Library/Settings round-out**: category item counts on Library's tab bar, Default Category
   (auto-assign on add), Default Tab (launch tab), editable request timeout in Advanced → Network
   (User Agent stays fixed — bound to the Cloudflare-bypass WebView's solved-challenge cookie), tap
   zones expanded 3→6 presets, and a real double-tap-to-zoom fix (previously just reset to 1x).
3. **Double-page spreads** for the manga reader (Single/Double/Automatic-in-landscape). `currentPage`
   keeps meaning "a real page index" everywhere (progress/resume/scrubber) — `MangaReaderView`'s
   `TabView` selection goes through a proxy `Binding` that snaps to the enclosing spread's start.
4. **Migrate tab** (Browse → Migrate) — move a library manga to a different installed source,
   transferring status/notes/categories/per-chapter read-state (matched by `chapterNumber`). **Real bug
   found live, looked exactly like a dead button from the outside**: the confirmation dialog's
   `isPresented` binding cleared `migrationTarget` as part of the same transaction as the button tap's
   auto-dismiss, so re-reading `migrationTarget` inside the button's `async` closure (after a
   suspension point) raced and saw `nil`. Fixed by capturing the target by value in the closure instead.

All 4 live-verified via `build_run_sim` + mobile-mcp (Migrate also cross-checked via direct sqlite
inspection of the simulator's `yomi.db`), zero build warnings throughout. See `Yomi/ROADMAP.md`'s S98
entry for full detail, and `Yomi/TACHIMANGA_PARITY.md` for the updated per-feature status table and
remaining (now genuinely long-tail) backlog — full multi-device CloudKit sync is the only big item left,
and needs its own architecture-scoping session like S90 gave the Suwayomi-server design.

**Tooling note**: this session hit real `mobile-mcp` tap-delivery flakiness on plain `Button`s several
navigation levels deep (confirmed via an untouched pre-existing button failing identically) —
`NavigationLink`s stayed reliable throughout. Don't assume a dead-looking button is this tooling issue
without first checking for a state race like the Migrate one above; they can look identical.


Full session-by-session history (S1-S90) lives in `Yomi/ROADMAP.md` (recent) and `Yomi/HISTORY.md`
(archived) — not duplicated here. This file keeps only the single most-recent state above.
