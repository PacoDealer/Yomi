# Roadmap — Yomi

## Estado actual (post sesión 4)
Flujo completo funcionando: Browse → Source → Manga grid → Detail → Chapter list → Reader.
Plugins reales: mangadex.js conectado a la API pública de MangaDex.
Lector: modo RTL manga + modo webtoon scroll, zoom, overlay inmersivo.

## Sesión 5 — Core UX (próxima)
Prioridad: que la app se sienta completa para un usuario real.

| # | Feature | Archivos afectados |
|---|---------|-------------------|
| 1 | **Save to library** — heart button guarda/quita manga de biblioteca. LibraryView carga desde DB en lugar de datos hardcodeados | MangaDetailView, LibraryView, LibraryViewModel, MangaQueries |
| 2 | **Mark chapter as read** — al llegar a la última página se marca isRead=true en DB | ChapterReaderView, nuevo ChapterQueries.markRead() |
| 3 | **Chapter pagination** — mangadex.js solo trae 100 caps; implementar offset loop o paginación lazy | mangadex.js, MangaDetailView |
| 4 | **History tab** — lista de manga con lastReadAt != nil, ordenado por fecha desc | HistoryView (reescritura), MangaQueries |
| 5 | **Prev/next chapter** — botones en overlay del reader para navegar entre capítulos | ChapterReaderView, ReaderOverlayView |
| 6 | **Dedup plugin install** — usar hash de URL como id en lugar de UUID | PluginsView, ExtensionManager |

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

## Sesión 7 — Polish & Discovery
| # | Feature | Detalle |
|---|---------|---------|
| 1 | **Search dentro de fuente** — BrowseView Search tab conectado a getMangaList con query param | BrowseView, JSBridge, plugins |
| 2 | **Download chapter** — guardar imágenes localmente para lectura offline | nuevo DownloadManager, ChapterReaderView |
| 3 | **Categories** — organizar biblioteca en categorías (Leyendo, Completado, etc.) | LibraryView, CategoryView, nuevo modelo |
| 4 | **Cover skeleton loading** — placeholder animado mientras carga la imagen | MangaCoverCell |
| 5 | **Haptics** — feedback táctil en acciones clave (guardar, cambiar página, instalar plugin) | varios |
| 6 | **Double-tap zoom reset** en reader | ChapterReaderView |

## Sesión 8 — Sync & Tracking
| # | Feature | Detalle |
|---|---------|---------|
| 1 | **AniList tracking** — marcar capítulos leídos en AniList | nuevo AniListService |
| 2 | **iCloud backup** — exportar/importar biblioteca en JSON | nuevo BackupManager |
| 3 | **Library updates** — background refresh de capítulos nuevos | nuevo UpdateService |

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
