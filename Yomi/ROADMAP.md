# Roadmap — Yomi

## Strategic Goal (defined S44 research audit, 2026-04-20)

> **Make Yomi the most source-diverse iOS manga + novel reader by running plugins from every existing ecosystem — without maintaining them ourselves.**

The research audit revealed that 800+ sources are already available across four compatible JS plugin formats. Yomi currently deploys 15 hand-written plugins from Firebase. The correct strategy is not to write more plugins — it is to unlock the community ecosystems that already exist:

| Ecosystem | Format | Sources available | Yomi status |
|-----------|--------|-------------------|-------------|
| Yomi Firebase | Format A | 15 | ✅ Live |
| LNReader | Format B | **500+ novels** | ✅ Native, needs UX/docs |
| Paperback | Format C | ~100 manga | ⚠️ Partial shim |
| Mangayomi | Format D (Dart) | 195+ manga+novel | ❌ Dart extensions — cannot run in JSC |
| keiyoushi/Suwayomi | Backend | Hundreds manga | ✅ S41 integrated |
| Kavita/Komga | OPDS | User's local library | ❌ Not yet |

**No architecture rebuild needed.** JSBridge already handles multi-format detection. Format D (Mangayomi) was attempted but Mangayomi extensions are all Dart (`.dart` files, `sourceCodeLanguage: 0`) — cannot execute in JSC. Catalog parser for Mangayomi index.json format remains in PluginCatalogService for metadata display.

**Novel support remains Yomi's exclusive differentiator.** Zero other iOS App Store apps support light novels with a plugin system. LNReader (Android, 500+ sources) has no iOS equivalent except Yomi.

---

## Current state (post S44 — 2026-04-20)

App is feature-rich and polished. S44: Format D Mangayomi JS shim (discovered Mangayomi is Dart — shim remains for future community JS plugins), multi-format catalog parser (Yomi→LNReader→Mangayomi), catalog UX overhaul (grouped multi-lang entries, repo badges, swipe-to-uninstall in Browse, repo filter chips, search), LNReader URL corrected, onboarding `AddRepoSheet`, `const source` lexical scope fix in JSBridge. S43: Tachiyomi/Mihon `.tachibk` backup import + tab reordering. S42: Manga Notes, App Lock, TTS for novels, Global Search. S40: multi-repo plugin catalog + 6 novel plugins. S41: Suwayomi. Firebase has 15 live plugins. App Store deferred.

**S36 shipped:** NovelFire restored to catalog (security incident resolved) + Firebase deployed. Pure black OLED mode (`AppSettings.pureBlack`, Settings toggle, black tab bar). Alternate icon infrastructure: `AppSettings.alternateIconName`, SettingsView icon picker (3 slots: Default/Dark/Minimal), `AppIconDark` + `AppIconMinimal` appiconsets as placeholders. **To activate alternates:** drop 1024×1024 PNGs into appiconsets + add `CFBundleAlternateIcons` in Xcode Target → Info tab.

**S37 shipped:** Full 44-file Swift audit. 3 bugs fixed:
1. **"Failed to load: cancelled"** — `PluginCatalogService.fetchCatalog()` was catching `CancellationError` from tab switches and displaying it as an error. Fixed: `catch is CancellationError` branch added.
2. **Novel IDs in Browse unstable** — `SourceBrowseView` was using `UUID().uuidString` for novel IDs on every `loadContent()` call, making DB lookups fail on re-entry. Fixed: stable `"\(sourceId)_\(item.path)"` ID.
3. **MangaDetailView.loadChapters() silent failure** — `guard let ext else { return }` fired without clearing `isLoadingChapters` (spinner stuck forever). Also `ChapterQueries.fetchAll` was called synchronously on MainActor. Both fixed.
4. **NovelFull plugin** added to Firebase catalog (novelfull.net — verified accessible, Format B).

**App Store blockers remaining (deferred):**
1. Apple Developer Program enrollment ($99/year) — user decided not to pay yet
2. App icon (1024×1024 PNG, 3 layers for iOS 26 Liquid Glass) — user designing
3. Age rating 18+, description, screenshots — App Store Connect

## Technical debt
| Area | Issue | Priority |
|------|-------|----------|
| Chapters from Browse (partial fix) | Defensive fixes applied in S37 but root cause not fully confirmed. Chapters may still fail for some sources. Needs device testing with live plugins to verify. | High |
| Firebase pending deploy | novelfull.js + updated index.json written but not deployed. User must run: `firebase login --reauth && firebase deploy --only hosting` in `~/Desktop/Yomi 2.0/yomi-firebase` | High |
| Alternate icons need Xcode step | AppIconDark + AppIconMinimal appiconsets are placeholders. Drop in PNGs + add CFBundleAlternateIcons in Xcode Target → Info to activate. | Low (after icon design) |
| Comick blocked by Cloudflare | api.comick.dev returns 403 from non-browser clients. Site-level block, not Yomi's fault. May resolve if Cloudflare changes policy. | Medium |
| LibraryViewModel DB reads on MainActor | loadLibrary() calls MangaQueries/NovelQueries synchronously on MainActor. Should use Task.detached. Works in practice but blocks main thread briefly. | Low |
| Extension.init(row:) force unwrap | sourceListURL = URL(string: row["sourceListURL"])! will crash on malformed DB value. | Low |

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
| 6 | ✅ Tachimanga DEX research | Architecture corrected: C-native DEX bytecode interpreter (no JIT, App Store compliant). |
| 7 | ✅ Mihon forks research | J2K/SY/AZ/Yōkai/Komikku — all Android-only, no new iOS paths. |

| 8 | ✅ Mangayomi `const source` bug fix | `injectMangayomiAdapter` used `global.source` — `const` at top-level is a lexical binding, NOT on globalThis. Fixed to use identifier lookup (`typeof source`) which checks lexical scope. Plugins now execute correctly. |
| 9 | ✅ Catalog UX overhaul | `PluginCatalogEntry.repoURL` (set post-fetch, excluded from Codable). `PluginCatalogGroup` (groups same-name multi-lang sources). Browse → Extensions: grouped list with "X langs" badge + language picker dialog, repo source badge (Yomi/LNReader/Mangayomi), search bar, pull-to-refresh. Browse → Sources: swipe-to-delete (uninstall), "Get more" header button, empty state navigates to Extensions. `CatalogGroupRow` shared between Browse and Plugins. |

**Outcome:** Yomi supports 4 JS plugin formats (A/B/C/D). 195+ Mangayomi sources + 500+ LNReader novels available via one-tap repos. Browse tab is now the primary plugin management surface.

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

## Planned: Session 46 — Power User Backends

| # | Feature | Detail |
|---|---------|--------|
| 1 | **Suwayomi onboarding** | Setup guide link + "Test connection" → show source count. Better UX for the self-hosted angle. |
| 2 | **OPDS client** | Connect to Kavita or Komga. `OPDSService.swift` — fetches catalog, maps to Manga model, reads local files. Appears as source in Browse. |
| 3 | **WidgetKit** | App Groups + shared flat JSON. `TimelineProvider` for ContinueReading widget. Cover image cached to App Group container. |

---

## Planned: Session 47 — Growth + Polish

| # | Feature | Detail |
|---|---------|--------|
| 1 | iCloud CloudKit sync | CloudKit container, `CKRecord` for manga/novel library state, conflict resolution |
| 2 | AniList tracking | OAuth, auto-update on chapter finish (mirrors MAL) |
| 3 | Volume button page-turn | Use `AVAudioSession` remote control events |
| 4 | Novel text justification toggle | `.textAlignment` in TextReaderView HTML CSS |
| 5 | Estimated reading time per chapter | Word count from HTML → WPM estimate |

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

## UX research findings (S23 basis)
Research covered: Tachiyomi, Paperback, Aidoku, MangaPlus, Webtoon, INKR, Azuki, Moon+ Reader,
ReadEra, Shosetsu. Sources: App Store reviews, Reddit (r/manga, r/manhwa, r/lightnovels),
GitHub issue trackers across all major reader apps.

### What users universally want (cross-app consensus)
1. **Bulk download** — #1 feature request on Paperback GitHub, Tachiyomi issues, Reddit threads
2. **Unread count badge** on library covers — visual scan without opening each title
3. **Continue reading → direct to reader** — extra tap to detail view is friction everyone notices
4. **Storage size indicator** — "how much space are my downloads using?"
5. **LTR mode** — manhwa/manhua audience is large and vocal

### What top apps do that Yomi doesn't yet
- Tachiyomi: unread badge, bulk operations via long-press multi-select, categories as tabs
- Paperback: unread badge, iOS-native feel, Collections
- Aidoku: MAL/AniList tracking status surfaced in library, filter/sort toolbar
- MangaPlus: smooth page-flip animation, haptic on page turn
- Moon+ Reader: EPUB export per book, storage visible per title

### Comment sections — research conclusion
Native in-app comments require moderation infrastructure + privacy policy update + Apple age gating.
Tachiyomi tested and removed a community tab. Paperback never shipped it.
**Correct approach for Yomi:** "Discuss" button in reader overlay → WKWebView bottom sheet → source's comment page.
For Disqus-powered sites (Flame Scans, MangaFire): Disqus API (`disqus.com/api/3.0/threads/listPosts.json`)
can return read-only comments natively — future feature, not S23.

### Plugin ecosystem — research conclusion
- **Keiyoushi (Tachiyomi):** Android APK / compiled Kotlin. Zero iOS compatibility path. Not fixable.
- **Aidoku:** Swift → WebAssembly (.aix). Requires WasmSwift runtime. Not compatible with Yomi.
- **Paperback:** TypeScript → esbuild JS bundle. Source class export. ~95% compatible with Yomi's JSBridge with a thin shim. Highest-value unlock.
- **LNReader:** Already works natively (Format B). ~20 more novel sources available today without any code changes — just need to write/deploy the plugins.
- **Most-wanted sources not yet in Yomi:** Flame Scans, Bato.to, LightNovelPub, WuxiaWorld, FreeWebNovel, NovelBin

### App icon research
- Mascot characters get genuine user affection (Tachiyomi octopus is cited in reviews)
- Warm colors (coral, amber, teal) outperform blue in App Store search differentiation
- "Yomi" (読み) = reading in Japanese; also references Japanese mythology → kitsune mascot fits culturally
- Recommendation: coral (#FF6B6B) to amber gradient + stylized 読 OR kitsune character
- Technical: 1024×1024 PNG, no alpha channel, corner radius applied by OS

## App Store submission checklist
These items must ALL be complete before submitting to App Store Connect:

| Item | Status | Notes |
|------|--------|-------|
| PrivacyInfo.xcprivacy | ✅ Done S22 | NSPrivacyAccessedAPICategoryUserDefaults reason CA92.1. |
| Privacy policy URL | ✅ Done S25 | yomi-plugins.web.app/privacy — linked from Settings → About. |
| App icon | ❌ Missing | All required sizes. Use Asset Catalog. User designing separately. |
| Zero .js in binary | ✅ Done S19 | Confirmed — plugins on Firebase CDN only. |
| MAL token in Keychain | ✅ Done S24 | KeychainHelper + auto-migration from UserDefaults on first load. |
| Age rating: 18+ | ❌ Pending | 2026 system uses 4/9/13/16/18+ (replaces old 17+). App enables NSFW content via user-installed plugins. Must declare in App Store Connect. |
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
