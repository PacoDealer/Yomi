# Roadmap — Yomi

## Current state (post S19)
App Store compliant: .js files removed from Xcode target, seedBundledPlugins call removed,
all 7 plugins on Firebase CDN. OnboardingView gates first launch → tabMore.
ChapterReaderView fully immersive (tap-to-hide chrome). History shows plugin display name.
⚠️ Dark mode: preferredColorScheme applied at WindowGroup root but not confirmed working in sim.
⚠️ TextReaderView: font re-inject via Coordinator.lastHTML in place but AppSettings.novelFontSize
disconnected from local @State fontSize slider — not yet the single source of truth.

## Technical debt
| Area | Issue | Priority |
|------|-------|----------|
| Dark mode | Read YomiApp.swift before S20 to diagnose why preferredColorScheme at root doesn't apply in sim. Try explicit .dark/.light first — never use nil to verify. | High |
| TextReader font | AppSettings.novelFontSize disconnected from local @State fontSize in TextReaderView. Must become single source of truth. Re-inject CSS via evaluateJavaScript on .onChange. | High |
| PluginsView catalog | Error silently swallowed — Browse tab shows empty after onboarding. Needs explicit errorMessage + retry button. | High |
| Reading resume | chapter.progress IS saved (updateProgress on disappear) but ChapterReaderView always opens at currentPage = 0. The saved progress is never read back. Users always restart from page 1. | High |
| Browse pagination | SourceBrowseView calls getMangaList(page: 1) once and stops. No "load more". Users see only the first ~20 titles from any source. MangaDex has thousands. | High |
| Pan when zoomed | MangaPageView uses .scaleEffect only — no DragGesture for offset. At zoom > 1x the image is stuck centered. Pan is required for zoom to be useful. | High |
| Novel chapter read semantics | TextReaderView calls NovelQueries.markRead() immediately after HTML loads — not on scroll-to-end. A chapter is marked "read" before the user reads a single word. | Medium |
| Downloads cleanup | DownloadManager never cleans up Documents/Downloads/{mangaId}/ when a manga is removed from library or a downloaded chapter is deleted. Disk leaks indefinitely. | Medium |
| PrivacyInfo.xcprivacy | Required for all iOS 17+ App Store submissions. Must declare UserDefaults access (NSPrivacyAccessedAPICategoryUserDefaults) and any file timestamp API usage. Missing entirely — submission will be rejected without it. | High |
| MAL token → Keychain | Currently in UserDefaults. Must migrate to Keychain before App Store submission. | Medium |
| App icon | ⏭ Still pending since S12. Required before submission. | Medium |
| Privacy policy URL | App Store Connect requires a privacy policy URL for any app that connects to the internet. Yomi connects to Firebase, MAL, and plugin sources. | Medium |
| Theme + accent color | accentColor picker (6 swatches) + tint at WindowGroup root. Planned S20. | Low |

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

## Session 20 — Core reading experience fixes (planned)
| # | Feature | Detail |
|---|---------|--------|
| 1 | Reading resume | On open, read chapter.progress from DB via ChapterQueries.fetchOne(id:). Convert to page index: Int(progress * Double(pages.count - 1)). Set currentPage to that index after pages load. |
| 2 | Pan when zoomed | MangaPageView: add @State offset: CGSize + DragGesture. Clamp offset so image can't be dragged beyond its zoomed bounds. Reset offset to .zero when scale returns to 1.0 (double-tap or pinch out). |
| 3 | Browse source pagination | SourceBrowseView: @State currentPage = 1. After initial load, show "Load more" button at bottom of LazyVGrid. On tap: currentPage += 1, append getMangaList(page: currentPage) results to mangas. |
| 4 | Dark mode diagnostic | Read YomiApp.swift. Try explicit .dark to rule out nil issue. Fix and confirm in sim. |
| 5 | TextReaderView font source of truth | Remove local @State fontSize. Use AppSettings.novelFontSize. Re-inject CSS via evaluateJavaScript on .onChange. |
| 6 | PluginsView error state | Explicit errorMessage + retry button in Browse tab. |
| 7 | Novel chapter read semantics | Mark novel chapter as read on scroll-to-bottom (WKWebView scroll position via JS), not on load. |
| 8 | Webtoon as default reading mode | AppSettings.defaultReaderMode = "Webtoon". |
| 9 | Chapter sort toggle | MangaDetailView toolbar button toggles sort order. |
| 10 | Chapter 0,0 display fix | Filter/rename chapters where chapterNumber == 0 and name is empty. |

## Session 21 — Polish + App Store prep (planned)
| # | Feature | Detail |
|---|---------|--------|
| 1 | PrivacyInfo.xcprivacy | Create Yomi/PrivacyInfo.xcprivacy. Declare NSPrivacyAccessedAPICategoryUserDefaults (AppSettings, MAL token, onboarding flag). Required for all iOS 17+ App Store submissions — will be rejected without it. |
| 2 | Downloads cleanup | When a manga is removed from library or a chapter is deleted, call DownloadManager to remove Documents/Downloads/{mangaId}/ (or /{chapterId}/). Add cleanup to MangaQueries.delete and the swipe-delete handler in MangaDetailView. |
| 3 | MAL token → Keychain | Replace UserDefaults storage of MAL accessToken with Security framework Keychain. Add KeychainHelper wrapper. Update MALService read/write. |
| 4 | accentColor picker | 6 swatches in Appearance settings. Store as String in AppSettings. Apply tint at WindowGroup root. |
| 5 | Library unread badge | Show unread chapter count overlay on manga covers in LibraryView. Count from ChapterQueries.fetchUnread(mangaId:). |
| 6 | UpdatesViewModel push notifications | scheduleChapterNotification(manga:newChapters:) after checkUpdates completes. |
| 7 | iCloud Drive backup | Native UIDocumentPickerViewController, export/import JSON, no OAuth. |
| 8 | Browse source chips full names | Replace truncated chip labels with scrollable full-name chips or dropdown. |
| 9 | Library filter fix | Debug and fix filter/sort button in LibraryView. |

## App Store submission checklist
These items must ALL be complete before submitting to App Store Connect:

| Item | Status | Notes |
|------|--------|-------|
| PrivacyInfo.xcprivacy | ❌ Missing | Declare UserDefaults API. Hard rejection without it (iOS 17+). |
| Privacy policy URL | ❌ Missing | Required for any app connecting to the internet. Host a static page. |
| App icon | ❌ Missing | All required sizes. Use Asset Catalog. |
| Zero .js in binary | ✅ Done S19 | Confirmed — plugins on Firebase CDN only. |
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
