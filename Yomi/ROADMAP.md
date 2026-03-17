# Roadmap — Yomi

## Estado actual (post sesión 9)
UX completa para uso real. Biblioteca con guardado real en GRDB. Capítulos marcados como leídos al terminar. Historial real desde DB. Búsqueda dentro de fuentes (client-side). Skeleton shimmer en portadas. Double-tap zoom reset. Backup JSON, MAL tracking, insights.

## Sesión 5 — Core UX ✅ Completa
| # | Feature | Archivos afectados |
|---|---------|-------------------|
| 1 | ✅ **Save to library** — heart button guarda/quita manga de biblioteca. LibraryView carga desde DB en lugar de datos hardcodeados | MangaDetailView, LibraryView, LibraryViewModel, MangaQueries |
| 2 | ✅ **Mark chapter as read** — al llegar a la última página se marca isRead=true en DB | ChapterReaderView, nuevo ChapterQueries.markRead() |
| 3 | ✅ **Chapter pagination** — mangadex.js trae todos los capítulos con offset loop (limit=500, cap 20 iter) | mangadex.js |
| 4 | ✅ **History tab** — lista de manga con lastReadAt != nil, ordenado por fecha desc | HistoryView (reescritura), MangaQueries |
| 5 | ✅ **Prev/next chapter** — botones en overlay del reader para navegar entre capítulos | ChapterReaderView, ReaderOverlayView |
| 6 | ✅ **Dedup plugin install** — SHA256(URL).prefix(8) via CryptoKit como id estable | PluginsView |

## Sesión 6 — LNReader compatibility ✅ Completa
| # | Feature | Detalle |
|---|---------|---------|
| 1 | ✅ **Cheerio shim real** — parser HTML recursivo + motor CSS en JS puro | JSBridge (injectCheerio) |
| 2 | ✅ **Novel model** — NovelItem, SourceNovel, JSNovelChapter + tablas novel y novel_chapter | DatabaseManager migración v3, nuevos modelos |
| 3 | ✅ **NovelDetailView** — cover, author, status, lista de capítulos | nuevo archivo |
| 4 | ✅ **TextReaderView** — WKWebView con font size slider, dark/light toggle, overlay inmersivo | nuevo archivo |
| 5 | ✅ **BrowseView dual-format** — detecta isLNReaderPlugin, muestra manga o novelas | BrowseView, NovelCoverCell |

## Sesión 7 — Settings & Insights ✅ Completa
| # | Feature | Detalle |
|---|---------|---------|
| 1 | ✅ **NSFW filter** — toggle en PluginsView oculta entradas nsfw==1 del catálogo Keiyoushi | PluginsView |
| 2 | ✅ **Browse picker fix** — segmented picker movido bajo nav bar con .inline para evitar superposición | BrowseView |
| 3 | ✅ **AppSettings** — @Observable singleton con UserDefaults, 6 settings | nuevo AppSettings.swift |
| 4 | ✅ **SettingsView** — General / Reader manga / Reader novel / Appearance | nuevo SettingsView.swift |
| 5 | ✅ **InsightsView** — tiempo total y por título (readingSeconds), formatTime helper | nuevo InsightsView.swift |
| 6 | ✅ **DB v4 migration** — readingSeconds INTEGER en manga y novel | DatabaseManager |
| 7 | ✅ **Time tracking en reader** — onDisappear acumula segundos en manga.readingSeconds | ChapterReaderView |
| 8 | ✅ **keepScreenOn + readerMode** — AppSettings aplicados en reader | ChapterReaderView |
| 9 | ✅ **MoreView restructurada** — Settings, Plugins, Insights, About (con LicensesView) | MoreView |

## Sesión 8 — Sync, Tracking & Polish ✅ Completa
| # | Feature | Detalle |
|---|---------|---------|
| 1 | ✅ **Backup & Restore** — exportar manga + capítulos a JSON, importar con upsert merge | BackupManager, BackupView |
| 2 | ✅ **MyAnimeList OAuth** — login PKCE plain, yomi:// callback, tracking automático al terminar capítulo | MALService, MALView |
| 3 | ✅ **Navegación prev/next chapter (refactor)** — currentChapterIndex + activeChapter, navigateToChapter, hasPrev/hasNext | ChapterReaderView |
| 4 | ✅ **Timer de lectura por capítulo** — Timer 1s, ChapterQueries.addReadingTime en disappear/nav | ChapterReaderView, ChapterQueries |
| 5 | ✅ **DB v4_reading_time** — readingSeconds INTEGER en chapter | DatabaseManager |
| 6 | ✅ **HistoryView reescritura** — Task.detached + MainActor.run, clear button | HistoryView |
| 7 | ✅ **InsightsView** — movido a Features/More, usa readingSeconds acumulado por capítulo | InsightsView |
| 8 | ✅ **SettingsView** — movido a Features/More, usa 6 propiedades reales de AppSettings | SettingsView |
| 9 | ✅ **MangaDetailView** — heart con upsert/insert, merge isRead+readingSeconds desde DB | MangaDetailView |
| 10 | ✅ **MangaQueries** — fetchRecentlyRead, upsert; eliminado fetchHistory (dead code) | MangaQueries |
| 11 | ✅ **PluginsView** — SHA256 id a 32 chars (prefix(32)) | PluginsView |
| 12 | ✅ **mangadex.js** — getChapterList con limit=100, offset loop, cap 2000 | mangadex.js |
| 13 | ✅ **MoreView** — secciones: App / Sources / Reading / Tracking / Data / Info | MoreView |

## Sesión 9 — Polish & Real Data ✅ Completa
| # | Feature | Detalle |
|---|---------|---------|
| 1 | ✅ **Save to library** — heart → MangaQueries.toggleLibrary (upsert + lastUpdatedAt), @State var manga mutable | MangaDetailView, MangaQueries |
| 2 | ✅ **Mark chapter as read** — última página + onDisappear si currentPage > 0 | ChapterReaderView, ChapterQueries.markRead |
| 3 | ✅ **ChapterQueries CRUD completo** — fetchAll, fetchOne, fetchByManga, fetchUnread, insert, upsert, upsertAll, markRead(id:), markRead(id:mangaId:), markAllRead, updateProgress, addReadingTime, delete, deleteAll | ChapterQueries |
| 4 | ✅ **MangaQueries toggleLibrary + fetchHistory** — toggleLibrary atómico, fetchHistory sin límite | MangaQueries |
| 5 | ✅ **History tab datos reales** — MangaQueries.fetchHistory(), RelativeDateTimeFormatter, sourceId caption, refreshable | HistoryView |
| 6 | ✅ **LibraryViewModel sort** — lastReadAt DESC NULLS LAST, luego title ASC en Swift | LibraryViewModel |
| 7 | ✅ **Search within source** — BrowseView Search tab, filtro client-side sobre getMangaList, source picker | BrowseView, SearchView |
| 8 | ✅ **Cover skeleton shimmer** — LinearGradient animado startPoint/endPoint sweep, showIcon en .failure | MangaCoverCell, SkeletonView |
| 9 | ✅ **Double-tap zoom reset** — simultaneousGesture(TapGesture(count:2)) + spring animation | MangaPageView |
| 10 | ✅ **asurascans.js** — plugin Formato A, scraping HTML con indexOf/split/substring, sin cheerio | asurascans.js |
| 11 | ✅ **Fix Extension+Hashable** — Picker requiere Hashable en tipo de selección | Extension.swift |
| 12 | ✅ **Fix Text+Text iOS 26** — Text("\(Text(date, style:.relative)) ago") reemplaza operador + | HistoryView |

## Sesión 10 — Server-side search & categories
| # | Feature | Detalle |
|---|---------|---------|
| 1 | **Server-side search por plugin** | Agregar searchManga(query:page:) a JSBridge + plugins Formato A (mangadex.js usa /manga?title=...) |
| 2 | **Categories** | LibraryView category filter tabs, CategoryView CRUD, tabla join manga↔category (migración v5_) |
| 3 | **Chapter pagination** | mangadex.js offset loop, botón "load more" en MangaDetailView |
| 4 | **Plugin dedup en install** | Verificar si ya existe extensión con mismo sourceListURL antes de instalar |
| 5 | **App icon** | Diseñar y configurar AppIcon en Assets.xcassets |
| 6 | **Downloads** | Guardar capítulos offline, DownloadManager, badge en ChapterRow |

## Compatibilidad iOS

**Deployment target: iOS 26.2** — no se planea bajar a iOS 18.

El dispositivo físico de desarrollo (iPhone de Martin, iOS 18.6.2) no puede correr
la app hasta actualizar a iOS 26. La app depende de APIs exclusivas de iOS 26:
`Tab()`, `ContentUnavailableView`, `.refreshable`, `.searchable`, `.ascNullsLast`.

Si en el futuro se requiere iOS 18 support → branch `compat/ios18`, nunca en main.

## Backlog (sin sesión asignada)
- iPad layout (sidebar en lugar de tab bar)
- Updates tab (background refresh de capítulos nuevos en biblioteca)
- AniList tracking (alternativa a MAL)
- Gestos personalizables en el reader
- Plugin marketplace propio (index.json hosteado)
- Notificaciones de nuevos capítulos
- TestFlight / App Store distribution

## Fuentes de plugins objetivo
| Fuente | Formato | Estado |
|--------|---------|--------|
| MangaDex | Formato A (API JSON) | ✅ Implementado |
| Asura Scans | Formato A (scraping) | ✅ Implementado |
| Aqua Manga | Formato A (scraping) | Backlog |
| Royal Road | Formato B (LNReader) | Sesión 6+ |
| NovelUpdates | Formato B (LNReader) | Sesión 6+ |

⚠️ Verificar siempre el HTML actual de cada fuente — los selectores pueden cambiar sin aviso.
