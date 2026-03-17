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
│   └── Extension.swift      # Plugin JS instalado — Identifiable, Codable, Hashable
├── Database/
│   ├── DatabaseManager.swift        # Setup GRDB, migraciones, conformances FetchableRecord; appDatabase módulo-level var
│   └── Queries/
│       ├── MangaQueries.swift       # CRUD manga: fetchAll, fetchOne, fetchLibrary, fetchRecentlyRead, insert, update, upsert, touchLastRead, delete
│       ├── ChapterQueries.swift     # CRUD chapter: fetchAll(ASC NULLS LAST), fetchOne, insert, upsert, upsertAll, markRead, markAllRead, updateProgress, addReadingTime, delete, deleteAll
│       ├── NovelQueries.swift       # CRUD novel + novel_chapter
│       └── ExtensionQueries.swift   # CRUD extensiones
├── Features/
│   ├── Library/
│   │   ├── LibraryView.swift        # Grid de manga guardados
│   │   ├── LibraryViewModel.swift   # Estado, filtrado, sort por lastReadAt DESC NULLS LAST
│   │   ├── MangaCoverCell.swift     # Celda de portada + ShimmerView skeleton animado
│   │   └── MangaDetailView.swift    # Detalle + lista de capítulos + heart button (upsert) + DB merge
│   ├── Browse/
│   │   ├── BrowseView.swift         # Sources tab + SearchView (client-side filter) + SourceBrowseView (dual manga/novel)
│   │   └── NovelDetailView.swift    # Detalle de novela + lista de capítulos
│   ├── Reader/
│   │   ├── ChapterReaderView.swift  # RTL manga + webtoon, zoom, overlay, prev/next chapter via currentChapterIndex+navigateToChapter, timer lectura, MAL tracking; acepta chapters:[Chapter] para navegación
│   │   └── TextReaderView.swift     # Lector HTML para novelas (WKWebView, font size, dark/light)
│   ├── History/
│   │   └── HistoryView.swift        # Datos reales GRDB (lastReadAt IS NOT NULL, DESC), swipe-to-delete local
│   ├── More/
│   │   ├── MoreView.swift           # Root tab More (App / Sources / Reading / Tracking / Data / Info)
│   │   ├── PluginsView.swift        # Instalar plugins + catálogo Keiyoushi + NSFW filter
│   │   ├── SettingsView.swift       # General / Reader manga / Reader novel / Appearance / About
│   │   ├── InsightsView.swift       # Tiempo de lectura total y por manga
│   │   ├── BackupManager.swift      # Exportar/importar JSON (manga + chapters)
│   │   ├── BackupView.swift         # UI: ShareLink export + fileImporter import
│   │   ├── MALService.swift         # OAuth PKCE plain, searchManga, updateMangaProgress
│   │   └── MALView.swift            # Login/disconnect UI + SafariView
│   └── Extensions/
│       ├── JSBridge.swift           # JavaScriptCore bridge (Formato A + B, cheerio shim real)
│       └── ExtensionManager.swift   # Instalar/remover plugins
├── AppSettings.swift                # @Observable singleton, UserDefaults-backed, 6 propiedades
├── Resources/
│   ├── mangadex.js                  # Plugin MangaDex (Formato A, API JSON)
│   ├── asurascans.js                # Plugin Asura Scans (Formato A, scraping HTML)
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
│   ViewModels (@Observable) + AppSettings│  LibraryViewModel, BackupManager, MALService
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
              isDownloaded, readAt, progress,
              readingSeconds INTEGER NOT NULL DEFAULT 0)

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
- **v4_reading_insights**: `ALTER TABLE manga ADD COLUMN readingSeconds` / `ALTER TABLE novel ADD COLUMN readingSeconds`
- **v4_reading_time**: `ALTER TABLE chapter ADD COLUMN readingSeconds INTEGER NOT NULL DEFAULT 0`

> Nota: dos migraciones con prefijo v4_ coexisten sin conflicto — GRDB las trackea por nombre string, no por número. La siguiente migración debe usar prefijo `v5_`.

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
→ merge con DB (isRead, readingSeconds por capítulo)
→ List → ChapterRow → NavigationLink
→ ChapterReaderView(manga:bridge:chapters:chapterIndex:)
→ Task.detached { bridge.getPageList(chapterPath:) }
→ MangaReaderView (RTL TabView)  o
   WebtoonReaderView (ScrollView LazyVStack)

## Flujo mark-as-read + tracking
ChapterReaderView
→ .onChange(of: currentPage) { if newPage == pages.count - 1 }
→ Task { ChapterQueries.markRead(id:mangaId:) }
   → UPDATE chapter SET isRead=true, readAt=now, progress=1.0
   → MangaQueries.touchLastRead(mangaId:)
      → UPDATE manga SET lastReadAt=now
→ if MALService.isLoggedIn
   → MALService.searchManga(title:)
   → MALService.updateMangaProgress(malId:chaptersRead:)

## Flujo de lectura + tiempo
ChapterReaderView.onAppear
→ isIdleTimerDisabled = true
→ readingTimer = Timer(1s) { sessionSeconds += 1 }

ChapterReaderView.onDisappear / navigateToChapter
→ readingTimer.invalidate()
→ Task.detached { ChapterQueries.addReadingTime(id:seconds:) }
   → UPDATE chapter SET readingSeconds += seconds
→ Task.detached { MangaQueries.update(manga con readingSeconds acumulado) }
→ isIdleTimerDisabled = false

## Flujo Backup
BackupManager.exportBackup()
→ MangaQueries.fetchAll() + await appDatabase.read { Chapter.fetchAll }
→ JSONSerialization → Data
→ FileManager.temporaryDirectory → URL
→ BackupView lo presenta via ShareLink

BackupManager.importBackup(from:)
→ Data(contentsOf:) → JSONSerialization
→ decodeManga / decodeChapter
→ MangaQueries.upsert + ChapterQueries.upsert (merge, no reemplaza)

## Flujo MAL OAuth
MALService.authorizationURL()
→ genera code_verifier aleatorio (plain PKCE)
→ construye URL authorize MAL

BackupView / MALView → SFSafariViewController
→ usuario autoriza → MAL redirige a yomi://callback?code=...

YomiApp / MALView.onOpenURL
→ MALService.handleCallback(url:)
→ POST /oauth2/token (code + code_verifier)
→ GET /users/@me (username)
→ guarda accessToken en UserDefaults

## Concurrencia
- Todas las llamadas a JSBridge se hacen desde `Task.detached(priority: .userInitiated)`
- JSBridge y sus métodos son `nonisolated` para satisfacer Swift 6 con `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`
- SOURCE.fetch bloquea el thread con `DispatchSemaphore` — nunca llamar desde MainActor
- Resultado se entrega a la UI via `await MainActor.run { state = result }`
- `appDatabase` es un `nonisolated(unsafe) var` a nivel de módulo — accesible desde cualquier contexto sin actor hop
- `appDatabase.read` tiene overload async: desde contexto @MainActor requiere `try await appDatabase.read { ... }`

## Workflow de desarrollo

1. **Claude Code** — `find Yomi -name "*.swift" | sort` + `cat Yomi/ROADMAP.md`
2. Pegar output en **Claude.ai** → análisis del estado real del codebase
3. Claude.ai propone scope de la sesión → usuario confirma
4. Claude.ai genera prompts en orden de dependencias
5. **Claude Code** ejecuta un prompt por vez → Xcode compila → reportar errores exactos
6. Commit por bloque funcional, no por archivo
7. Fin de sesión: actualizar ROADMAP.md + METODOLOGIA.md + ARQUITECTURA.md

> ⚠️ No generar prompts hasta confirmar el estado real. Los prompts generados contra
> documentación desactualizada causan reescritura de trabajo existente (lección S9).

## Requisitos de plataforma

**Deployment target: iOS 26.2**
**Xcode:** 26+ (developer directory: `/Applications/Xcode.app`)
**Build para simulador:** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Yomi -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`

### APIs exclusivas de iOS 26 en uso

| API | Archivo | Nota |
|-----|---------|------|
| `Tab("…", systemImage:) {}` | ContentView.swift | Nueva sintaxis TabView; `.tabItem {}` no funciona |
| `ContentUnavailableView` | BrowseView, HistoryView, PluginsView | No existe en iOS 18 |
| `.refreshable` | HistoryView | No existe en iOS 18 |
| `.searchable` | BrowseView, SourceBrowseView | Existe desde iOS 15 pero el comportamiento difiere |
| `.ascNullsLast` (GRDB) | ChapterQueries | Helper GRDB que genera `ASC NULLS LAST` |
| `Text("\(Text(…)) …")` | HistoryView | Interpolación de Text en Text; `+` deprecado en iOS 26 |

### Por qué iOS 26 y no iOS 18
- El proyecto se inició sobre Xcode 26 beta desde la sesión 1
- `Tab()` es la única sintaxis que renderiza tabs en iOS 26; `.tabItem {}` produce tabs vacíos
- Bajar el target requeriría `#available(iOS 26, *)` en ≥6 archivos y mantener dos code paths
- iOS 26 es el OS de shipping en 2026; el dispositivo de desarrollo puede actualizarse

## Decisiones de diseño
| Decisión | Alternativa descartada | Motivo |
|----------|----------------------|--------|
| JavaScriptCore | WKWebView | Headless, sin UI, más liviano para plugins |
| GRDB | SwiftData | Control de esquema, migraciones, madurez |
| Plugins .js locales | API remota propia | Sin servidor, funciona offline |
| Formato A propio | Solo LNReader | LNReader no tiene plugins de manga, solo novelas |
| Keiyoushi como referencia | Intentar correr .apk | .apk Android no corren en iOS |
| GRDB acceso nonisolated | Propiedad en singleton MainActor | Module-level `nonisolated(unsafe) var appDatabase` es el patrón oficial GRDB para Swift 6 — evita actor hops en *Queries |
| UserDefaults para settings | CoreData / archivo JSON | Settings simples no necesitan DB |
| Token MAL en UserDefaults | Keychain | Suficiente para MVP; migrar a Keychain antes de App Store |
| Backup JSON manual | CloudKit / iCloud Drive sync | Sin dependencia de servicios Apple; portátil entre plataformas |
| MAL PKCE plain | PKCE S256 | MAL API solo soporta el método plain |
