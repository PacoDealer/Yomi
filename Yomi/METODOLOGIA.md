# Metodología de trabajo — Yomi

## Workflow
- **Claude.ai (Desktop app)** → arquitectura, planificación, generación de prompts optimizados para Claude Code
- **Claude Code (terminal)** → ejecuta los prompts, escribe archivos Swift/JS, hace git commit/push
- **Xcode** → compilar, correr en simulador, ver errores exactos
- **GitHub Desktop** → revisar diffs, push manual cuando se requiere

## Reglas del workflow
- Un archivo a la vez, compilación después de cada archivo nuevo
- Nunca crear múltiples archivos simultáneamente
- Reportar errores exactos de Xcode a Claude.ai antes de continuar
- Claude.ai genera el prompt → se pega en Claude Code → Claude Code escribe el archivo
- Commits después de cada bloque funcional completo (no después de cada archivo)

## Stack técnico
- Swift + SwiftUI (iOS 26)
- GRDB para base de datos SQLite local
- JavaScriptCore para ejecutar plugins JS (formato Yomi y formato LNReader)
- Arquitectura inspirada en LNReader (Android, plugins TypeScript) y Mihon (Android)

## Estructura de plugins JS
Yomi soporta dos formatos de plugins:

**Formato A — Yomi/Manga** (funciones globales):
  getMangaList(page) → [{id, path, title, coverURL, summary, author, artist, status, genres}]
  getChapterList(mangaPath) → [{id, path, name, chapterNumber}]
  getPageList(chapterPath) → [urlString]

**Formato B — LNReader/Novel** (clase exportada en global `plugin`):
  plugin.popularNovels(pageNo, options) → [{name, path, cover}]
  plugin.parseNovel(novelPath) → {path, name, cover, author, summary, status, chapters}
  plugin.parseChapter(chapterPath) → String (HTML)
  plugin.searchNovels(searchTerm, pageNo) → [{name, path, cover}]

JSBridge detecta el formato automáticamente: si existe `plugin.popularNovels` → Formato B, si no → Formato A.

## Shims inyectados por JSBridge
- SOURCE.fetch(url, options) → HTTP GET sincrónico via DispatchSemaphore
- cheerio.load(html) → stub (pendiente implementación real)
- localStorage / sessionStorage → in-memory JS objects
- console.log/warn/error → Swift print()

## Sesiones
| # | Fecha | Qué se hizo |
|---|-------|-------------|
| 1 | 2026-03-13 | Setup completo: Homebrew, Node, Claude Code, estructura carpetas, 4 modelos (Manga, Chapter, Category, Source), GRDB, tab bar 4 tabs funcionando en simulador |
| 2 | 2026-03-14 | LibraryView grid adaptativo + ViewModel + MangaCoverCell + MangaDetailView básico + navegación grid→detail + DatabaseManager inicializado en launch |
| 3 | 2026-03-14 | Sistema de extensiones JS: Extension model, ExtensionQueries, DatabaseManager migración v2, JSBridge v1 (JavaScriptCore), ExtensionManager, test-source.js, BrowseView con CTA + lista de extensiones instaladas, AdaptiveGrid en LibraryView |
| 4 | 2026-03-15 | JSBridge v2 (dual format Yomi+LNReader, SOURCE.fetch semaphore, cheerio stub, localStorage shim), mangadex.js plugin real (API MangaDex), BrowseView end-to-end con SourceBrowseView, PluginsView (install from URL + catálogo Keiyoushi de referencia), ChapterReaderView (RTL manga + webtoon scroll, pinch zoom 1-4x, overlay inmersivo), MangaDetailView con lista de capítulos real |

## Aprendizajes técnicos
- **iOS 26 TabView**: nueva API `Tab("título", systemImage:) {}` — la API vieja `.tabItem {}` no renderiza nada
- **Xcode PBXFileSystemSynchronizedRootGroup**: todos los archivos de la carpeta se incluyen automáticamente — nunca usar `.gitkeep` o `.gitignore` dentro del target
- **Swift 6 + GRDB**: `init(row:)` y `encode(to:)` de FetchableRecord/PersistableRecord requieren `nonisolated` con `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`
- **DerivedData stale**: limpiar con `rm -rf ~/Library/Developer/Xcode/DerivedData/Yomi-*` y ⇧⌘K en Xcode
- **JSBridge async**: JSContext es síncrono; SOURCE.fetch bloquea con DispatchSemaphore; llamar siempre desde Task.detached, nunca desde MainActor
- **Keiyoushi plugins**: son .apk Android, no corren en iOS; se muestran como catálogo de referencia únicamente
- **LNReader plugins**: son TypeScript compilado a JS — compatibles con JavaScriptCore si se implementan los shims correctos (fetch, cheerio, storage)
- **Cheerio**: los plugins LNReader usan cheerio para parsear HTML; el shim actual es un stub vacío — implementación real pendiente para sesión 5+

## Decisiones de arquitectura
- GRDB sobre SwiftData: control total del esquema, más maduro, compatible con migraciones incrementales
- JavaScriptCore sobre WKWebView: más liviano, no requiere UI, mejor para plugins headless
- Formato de plugins propio (Formato A) + compatibilidad LNReader (Formato B): máxima flexibilidad sin depender de ecosistema Android
- Plugins instalados en Documents/Extensions/ como archivos .js locales
