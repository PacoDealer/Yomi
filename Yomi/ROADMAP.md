# Roadmap — Yomi

## Estado actual (post sesión 7)
Persistencia completa: biblioteca, historial, progreso de lectura, tiempo de lectura (readingSeconds). MangaDex trae todos los capítulos. Reader con navegación entre capítulos, modo configurable (RTL/webtoon), pantalla encendida. Settings persistidos en UserDefaults. InsightsView con tiempo total y por título. Soporte dual manga (Formato A) y novelas (Formato B) end-to-end.

## Sesión 5 — Core UX ✅ Completa
| # | Feature | Archivos afectados |
|---|---------|-------------------|
| 1 | ✅ **Save to library** — heart button guarda/quita manga de biblioteca. LibraryView carga desde DB en lugar de datos hardcodeados | MangaDetailView, LibraryView, LibraryViewModel, MangaQueries |
| 2 | ✅ **Mark chapter as read** — al llegar a la última página se marca isRead=true en DB | ChapterReaderView, nuevo ChapterQueries.markRead() |
| 3 | ✅ **Chapter pagination** — mangadex.js trae todos los capítulos con offset loop (limit=500, cap 20 iter) | mangadex.js |
| 4 | ✅ **History tab** — lista de manga con lastReadAt != nil, ordenado por fecha desc | HistoryView (reescritura), MangaQueries |
| 5 | ✅ **Prev/next chapter** — botones en overlay del reader para navegar entre capítulos | ChapterReaderView, ReaderOverlayView |
| 6 | ✅ **Dedup plugin install** — SHA256(URL).prefix(8) via CryptoKit como id estable | PluginsView |

## Sesión 6 — LNReader compatibility
Objetivo: correr plugins reales de LNReader sin modificación.

| # | Feature | Detalle |
|---|---------|---------|
| 1 | **Cheerio shim real** — implementar load(html) con selectores CSS básicos usando regex o parser propio en JS | JSBridge (injectCheerio) |
| 2 | **Novel model** — NovelItem, SourceNovel, NovelChapter en DB (tabla `novel` y `novel_chapter`) | DatabaseManager migración v3, nuevos modelos |
| 3 | **NovelDetailView** — equivalente a MangaDetailView para novelas (cover, author, status, chapter list) | nuevo archivo |
| 4 | **TextReaderView** — lector de texto HTML con fuente configurable, tamaño, interlineado, tema claro/oscuro | nuevo archivo |
| 5 | **Plugin repo URL** — instalar desde un index.json (como LNReader plugins branch) en lugar de URL directa | PluginsView, ExtensionManager |
| 6 | **Asura Scans plugin** — plugin Formato A con scraping básico | nuevo asurascans.js |

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

## Sesión 8 — Sync & Backup
| # | Feature | Detalle |
|---|---------|---------|
| 1 | **Backup & Restore** — exportar DB como JSON a Files.app | nuevo BackupManager |
| 2 | **AniList tracking** — OAuth + marcar capítulos leídos | nuevo AniListService |
| 3 | **iCloud sync** — backup automático a iCloud Drive | nuevo iCloudSyncManager |
| 4 | **Updates tab** — background refresh de capítulos nuevos | nuevo UpdateService |
| 5 | **Downloads** — guardar capítulos offline | nuevo DownloadManager |

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
| Asura Scans | Formato A (scraping) | Sesión 6 |
| Aqua Manga | Formato A (scraping) | Sesión 6 |
| Royal Road | Formato B (LNReader) | Sesión 6+ |
| NovelUpdates | Formato B (LNReader) | Sesión 6+ |
