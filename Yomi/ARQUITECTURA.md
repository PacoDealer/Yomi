# Arquitectura — Yomi

## Visión general
Yomi es un lector de manga, manhwa, manhua y novelas ligeras para iOS.
Arquitectura inspirada en Mihon (Android) y LNReader (Android).
Contenido obtenido via plugins JavaScript ejecutados en JavaScriptCore.

## Estructura de carpetas
Yomi/
├── Models/
│   ├── Manga.swift          # Manga/manhwa/manhua — modelo principal
│   ├── Chapter.swift        # Capítulo de una obra
│   ├── Category.swift       # Categorías de biblioteca
│   ├── Source.swift         # Metadatos de fuente (legacy, reemplazado por Extension)
│   └── Extension.swift      # Plugin JS instalado
├── Database/
│   ├── DatabaseManager.swift        # Setup GRDB, migraciones, conformances FetchableRecord; appDatabase módulo-level var
│   └── Queries/
│       ├── MangaQueries.swift       # CRUD manga: fetchAll, fetchOne, fetchLibrary, fetchHistory, insert, update, touchLastRead, delete
│       ├── ChapterQueries.swift     # CRUD chapter: fetchAll(mangaId:), upsert, markRead, delete
│       ├── NovelQueries.swift       # CRUD novel + novel_chapter
│       └── ExtensionQueries.swift   # CRUD extensiones
├── Features/
│   ├── Library/
│   │   ├── LibraryView.swift        # Grid de manga guardados
│   │   ├── LibraryViewModel.swift   # Estado y filtrado
│   │   ├── MangaCoverCell.swift     # Celda de portada
│   │   └── MangaDetailView.swift    # Detalle + lista de capítulos
│   ├── Browse/
│   │   ├── BrowseView.swift         # Sources tab + SourceBrowseView (dual manga/novel)
│   │   └── NovelDetailView.swift    # Detalle de novela + lista de capítulos
│   ├── Reader/
│   │   ├── ChapterReaderView.swift  # RTL manga + webtoon, zoom, overlay, prev/next chapter, time tracking
│   │   └── TextReaderView.swift     # Lector HTML para novelas (WKWebView, font size, dark/light)
│   ├── History/
│   │   └── HistoryView.swift        # Historial con HistoryViewModel inline, lista manga por lastReadAt desc
│   ├── More/
│   │   ├── MoreView.swift           # Root tab More (Settings, Insights, About + LicensesView)
│   │   └── PluginsView.swift        # Instalar plugins + catálogo Keiyoushi + NSFW filter
│   ├── Settings/
│   │   ├── AppSettings.swift        # @Observable singleton, UserDefaults-backed
│   │   ├── SettingsView.swift       # General / Reader manga / Reader novel / Appearance
│   │   └── InsightsView.swift       # Tiempo de lectura total y por manga
│   └── Extensions/
│       ├── JSBridge.swift           # JavaScriptCore bridge (Formato A + B, cheerio shim real)
│       └── ExtensionManager.swift   # Instalar/remover plugins
├── Resources/
│   ├── mangadex.js                  # Plugin MangaDex (Formato A)
│   └── test-source.js               # Plugin de prueba (Formato A)
├── ContentView.swift                # TabView raíz
├── YomiApp.swift                    # Entry point, setup DB
├── ARQUITECTURA.md
├── METODOLOGIA.md
└── ROADMAP.md

## Capas de la arquitectura
┌─────────────────────────────────────────┐
│            SwiftUI Views                │  Features/
├─────────────────────────────────────────┤
│   ViewModels (@Observable) + AppSettings│  LibraryViewModel, HistoryViewModel, etc.
├─────────────────────────────────────────┤
│    ExtensionManager + JSBridge          │  Features/Extensions/
├──────────────────┬──────────────────────┤
│   GRDB (SQLite)  │  JavaScriptCore      │
│   appDatabase    │  Plugins JS          │
│   *Queries       │  (mangadex.js, etc.) │
└──────────────────┴──────────────────────┘

## Base de datos (SQLite via GRDB)

### Tablas actuales (migración v4)
```sql
manga        (id, path, sourceId, title, coverURL, summary, author, artist,
              status, genres JSON, inLibrary, isLocal, lastReadAt, lastUpdatedAt,
              readingSeconds INTEGER NOT NULL DEFAULT 0)

chapter      (id, mangaId FK→manga, path, name, chapterNumber, isRead,
              isDownloaded, readAt, progress)

category     (id, name, sort)

source       (id, name, language, version, iconURL, baseURL, isInstalled, isNSFW)

extension    (id, name, version, language, iconURL, sourceListURL,
              isInstalled, isNSFW, sourceIds JSON)

novel        (id, path, sourceId, title, coverURL, summary, author, status,
              genres JSON, inLibrary, lastReadAt, lastUpdatedAt,
              readingSeconds INTEGER NOT NULL DEFAULT 0)

novel_chapter (id, novelId FK→novel, path, name, chapterNumber, isRead,
               readAt, releaseTime)
```

### Migraciones
- **v1_initial**: manga, chapter, category, source
- **v2_extensions**: extension
- **v3_novels**: novel, novel_chapter
- **v4_reading_insights**: `ALTER TABLE manga ADD COLUMN readingSeconds INTEGER NOT NULL DEFAULT 0` / `ALTER TABLE novel ADD COLUMN readingSeconds INTEGER NOT NULL DEFAULT 0`

### Por qué GRDB y no SwiftData
- Control total del esquema SQL y migraciones incrementales
- Más maduro y estable
- Compatible con esquemas inspirados en LNReader/Mihon

## Sistema de plugins JS

### Ciclo de vida
Usuario ingresa URL del .js
↓
ExtensionManager.install(_:)
→ descarga el archivo via URLSession
→ guarda en Documents/Extensions/{id}.js
→ persiste metadatos en tabla extension (GRDB)
↓
ExtensionManager.bridge(for: ext)
→ JSBridge(scriptURL: localURL)
↓
JSBridge.init
→ crea JSContext
→ inyecta shims (SOURCE.fetch, cheerio, localStorage, console)
→ evalúa el script JS
→ detecta formato (A o B)
↓
Vista llama bridge.getMangaList() / bridge.popularNovels()
→ JSBridge llama función JS via JSContext
→ JS llama SOURCE.fetch → Swift hace HTTP → devuelve String al JS
→ JS parsea y devuelve objeto
→ JSBridge mapea a structs Swift

### Formato A — Yomi/Manga
Funciones globales. Usado para manga, manhwa, manhua.
```javascript
getMangaList(page)        → [{id, path, title, coverURL, summary, author, artist, status, genres}]
getChapterList(mangaPath) → [{id, path, name, chapterNumber}]
getPageList(chapterPath)  → [urlString]
```

### Formato B — LNReader/Novel
Clase exportada en global `plugin`. Compatible con plugins del ecosistema LNReader.
```javascript
plugin.popularNovels(pageNo, options) → [{name, path, cover}]
plugin.parseNovel(novelPath)          → {path, name, cover, author, summary, status, chapters}
plugin.parseChapter(chapterPath)      → String (HTML del capítulo)
plugin.searchNovels(searchTerm, page) → [{name, path, cover}]
```

### Detección automática de formato
```swift
var isLNReaderPlugin: Bool {
    context.objectForKeyedSubscript("plugin")
           .objectForKeyedSubscript("popularNovels")
           .isObject
}
```

### Shims inyectados por JSBridge
| Shim | Implementación | Estado |
|------|---------------|--------|
| `SOURCE.fetch(url, opts)` | URLSession + DispatchSemaphore (blocking, 30s timeout) | ✅ Funcional |
| `console.log/warn/error` | Swift print() | ✅ Funcional |
| `localStorage` / `sessionStorage` | In-memory JS object con get/set/removeItem | ✅ Funcional |
| `cheerio.load(html)` | Parser HTML recursivo + motor CSS selectores en JS puro | ✅ Funcional |

## Flujo de datos — Browse → Reader
BrowseView
→ SourceBrowseView(ext)
→ Task.detached { bridge.getMangaList(page:1) }  // background
→ await MainActor { mangas = result }
→ LazyVGrid → MangaCoverCell → NavigationLink
→ MangaDetailView(manga)
→ Task.detached { bridge.getChapterList(mangaPath:) }
→ List → ChapterRow → NavigationLink
→ ChapterReaderView(chapter, manga, bridge, chapters, currentIndex)
→ Task.detached { bridge.getPageList(chapterPath:) }
→ MangaReaderView (RTL TabView)  o
WebtoonReaderView (ScrollView LazyVStack)

## Flujo mark-as-read
ChapterReaderView
→ .onChange(of: currentPage) { if newPage == pages.count - 1 }
→ Task { ChapterQueries.markRead(id:mangaId:) }
   → UPDATE chapter SET isRead=true, readAt=now, progress=1.0
   → MangaQueries.touchLastRead(mangaId:)
      → UPDATE manga SET lastReadAt=now

## Concurrencia
- Todas las llamadas a JSBridge se hacen desde `Task.detached(priority: .userInitiated)`
- JSBridge y sus métodos son `nonisolated` para satisfacer Swift 6 con `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`
- SOURCE.fetch bloquea el thread con `DispatchSemaphore` — nunca llamar desde MainActor
- Resultado se entrega a la UI via `await MainActor.run { state = result }`
- `appDatabase` es un `nonisolated(unsafe) var` a nivel de módulo — accesible desde cualquier contexto sin actor hop

## Decisiones de diseño
| Decisión | Alternativa descartada | Motivo |
|----------|----------------------|--------|
| JavaScriptCore | WKWebView | Headless, sin UI, más liviano para plugins |
| GRDB | SwiftData | Control de esquema, migraciones, madurez |
| Plugins .js locales | API remota propia | Sin servidor, funciona offline |
| Formato A propio | Solo LNReader | LNReader no tiene plugins de manga, solo novelas |
| Keiyoushi como referencia | Intentar correr .apk | .apk Android no corren en iOS |
| GRDB acceso nonisolated | Propiedad en singleton MainActor | Module-level `nonisolated(unsafe) var appDatabase` es el patrón oficial GRDB para Swift 6 strict concurrency — evita actor hops en *Queries |
| UserDefaults para settings | CoreData / archivo JSON | Settings simples no necesitan DB — UserDefaults con @Observable wrapper es suficiente |
