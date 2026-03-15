# Roadmap — Yomi

## Estado actual (post sesión 7)
UX completa para uso real. Settings funcionales. Reading Insights operativo. Flujo completo manga y novelas end-to-end.

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
| 3 | ✅ **AppSettings** — @Observable singleton con UserDefaults (@ObservationIgnored), 10 settings | nuevo AppSettings.swift |
| 4 | ✅ **SettingsView** — 4 secciones: General, Reader manga, Reader novel, Appearance | nuevo SettingsView.swift |
| 5 | ✅ **InsightsView** — tiempo total y por título (readingSeconds), formatTime helper | nuevo InsightsView.swift |
| 6 | ✅ **DB v4 migration** — readingSeconds INTEGER en manga y novel | DatabaseManager |
| 7 | ✅ **Time tracking en reader** — onDisappear acumula segundos en manga.readingSeconds | ChapterReaderView |
| 8 | ✅ **keepScreenOn + defaultReaderMode** — AppSettings aplicados en reader | ChapterReaderView |
| 9 | ✅ **MoreView restructurada** — Settings, Insights, About (con LicensesView) | MoreView |

## Sesión 8 — Plugins & Discovery
| # | Feature | Detalle |
|---|---------|---------|
| 1 | **Asura Scans plugin** | Formato A, scraping HTML con cheerio |
| 2 | **Aqua Manga plugin** | Formato A, scraping HTML |
| 3 | **Plugin repo index.json** | Instalar desde URL de índice en lugar de URL directa |
| 4 | **Search within source** | BrowseView Search tab → getMangaList/searchNovels con query |
| 5 | **Cover skeleton loading** | Placeholder animado con .redacted(reason: .placeholder) |
| 6 | **Haptics** | UIImpactFeedbackGenerator en acciones clave |

## Sesión 9 — Sync & Offline
| # | Feature | Detalle |
|---|---------|---------|
| 1 | **Backup & Restore** | Exportar DB como JSON a Files.app |
| 2 | **Downloads** | Guardar capítulos offline, DownloadManager |
| 3 | **AniList tracking** | OAuth + marcar capítulos leídos |
| 4 | **Updates tab** | Background refresh de capítulos nuevos en biblioteca |

## Backlog (sin sesión asignada)
- App icon y splash screen
- iPad layout (sidebar en lugar de tab bar)
- Notificaciones de nuevos capítulos
- Gestos personalizables en el reader
- Plugin marketplace propio (index.json hosteado)
- TestFlight / App Store distribution

## Fuentes de plugins objetivo
| Fuente | Formato | Estado |
|--------|---------|--------|
| MangaDex | Formato A (API JSON) | ✅ Implementado |
| Asura Scans | Formato A (scraping) | Sesión 8 |
| Aqua Manga | Formato A (scraping) | Sesión 8 |
| Royal Road | Formato B (LNReader) | Sesión 6+ |
| NovelUpdates | Formato B (LNReader) | Sesión 6+ |
