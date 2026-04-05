# Roadmap — Yomi

## Current state (post session 16)
All 7 bundled plugins working in simulator.
MangaDex (✅), Comick (✅), Royal Road (✅), ScribbleHub (✅), NovelFire (✅), AquaManga (✅).
Asura Scans (❌ React SSR — needs internal API via Network tab DevTools).
Root fix: seedBundledPlugins now overwrites existing files on every launch.
Plugin each() callbacks fixed to use el.find() directly (cheerio shim contract).

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

## Technical debt
| Item | Description | Priority |
|------|-------------|----------|
| Asura Scans | React SSR — HTML shell has no content. Needs internal API via Network tab DevTools | Medium |
| LNReader v2.x compat | require() shim ~50 lines + esbuild script to compile TS plugins | Medium |
| Firebase Hosting | index.json + .js plugins as CDN for OTA updates without App Store releases | Medium |
| iCloud Drive backup | Replaces export to Files.app, native with no extra OAuth | Low |
| InsightsView stats | Reading streak + chapters read — cut from S15 scope | Medium |
| UpdatesViewModel notifications | scheduleChapterNotification after checkUpdates | Low |

## iOS compatibility

**Deployment target: iOS 26.2** — no plan to lower to iOS 18.

The physical development device (Martin's iPhone, iOS 18.6.2) cannot run
the app until updating to iOS 26. The app depends on iOS 26-exclusive APIs:
`Tab()`, `ContentUnavailableView`, `.refreshable`, `.searchable`, `.ascNullsLast`.

If iOS 18 support is required in the future → branch `compat/ios18`, never on main.

## Backlog (no session assigned)
- Plugin marketplace UI (PluginsView "Browse catalog" fetches index.json from Firebase)
- esbuild script to compile LNReader v2.x TypeScript plugins to vanilla JS
- AniList tracking (alternative to MAL)
- Custom reader gestures
- TestFlight / App Store distribution
- iPad layout (sidebar instead of tab bar)

## Target plugin sources
| Source | Format | Status |
|--------|--------|--------|
| MangaDex | Format A (JSON API) | ✅ Working |
| Comick | Format A (JSON API) | ✅ Working |
| Royal Road | Format B (LNReader) | ✅ Working |
| ScribbleHub | Format B (LNReader) | ✅ Working |
| NovelFire | Format B (LNReader) | ✅ Working |
| AquaManga | Format A (scraping) | ✅ Working |
| Asura Scans | Format A (scraping) | ❌ React SSR — needs internal API |
| NovelUpdates | Format B (LNReader) | Backlog |

⚠️ Always verify current HTML of each source — selectors can change without notice.
