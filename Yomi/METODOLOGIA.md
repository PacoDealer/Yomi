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
| 5 | 2026-03-15 | Save to library (heart button → MangaQueries.update, inLibrary toggle + haptics). ChapterQueries (markRead: isRead=true, readAt=now, progress=1.0, touchLastRead en manga padre). mangadex.js pagination loop (offset hasta json.total, limit=500, cap 20 iteraciones). HistoryView real con MangaQueries.fetchHistory() (lastReadAt != nil, desc). Prev/next chapter en ReaderOverlayView (displayedChapter state, loadPages() extraído). Dedup plugin install con SHA256(URL).prefix(8) via CryptoKit. |
| 7 | 2026-03-15 | UX audit (visual + code). NSFW filter default off en PluginsView, BrowseView picker bajo el título. AppSettings singleton (@Observable + UserDefaults, 6 propiedades). SettingsView (General / Reader manga / Reader novel / Appearance / About). InsightsView (total reading time + per-manga list). DB migration v4_reading_insights (readingSeconds INTEGER en manga + novel). ChapterReaderView: time tracking en onDisappear, keepScreenOn via isIdleTimerDisabled, readerMode desde AppSettings. MoreView restructurada: Settings + Plugins + Insights + About. |
| 8 | 2026-03-15 | BackupManager + BackupView (JSON export/import a Files.app). MALService + MALView (OAuth PKCE plain, yomi:// callback, tracking automático). ChapterReaderView: refactor a currentChapterIndex + activeChapter, navigateToChapter, Timer 1s → addReadingTime. DB migration v4_reading_time (readingSeconds en chapter). HistoryView: reescritura sin ViewModel, Task.detached + MainActor.run, clear button. SettingsView + InsightsView movidos a Features/More. MangaDetailView: upsert/insert en heart button, merge isRead+readingSeconds desde DB. MangaQueries: fetchRecentlyRead, upsert, eliminado fetchHistory. PluginsView: SHA256 id a 32 chars. mangadex.js: limit=100, offset loop, cap 2000. MoreView: 6 secciones (App / Sources / Reading / Tracking / Data / Info). |
| 9 | 2026-03-16 | Save to library (heart → GRDB upsert + UIImpactFeedbackGenerator). Mark chapter read on last page + onDisappear. ChapterQueries CRUD completo (fetchAll, fetchOne, insert, upsert, upsertAll, markRead, markAllRead, updateProgress, addReadingTime, delete, deleteAll). MangaQueries.fetchOne/upsert. HistoryView datos reales desde GRDB ordenados por lastReadAt DESC con swipe-to-delete. Prev/next chapter via navigateToChapter en-lugar (in-place state mutation). BrowseView Search tab funcional con filtro client-side sobre getMangaList + source picker. MangaCoverCell shimmer skeleton animado. Double-tap zoom reset en MangaPageView con simultaneousGesture. Fix: Extension+Hashable para Picker. Fix: Text interpolación iOS 26 (reemplazó Text+Text). |

## Aprendizajes técnicos
- **iOS 26 TabView**: nueva API `Tab("título", systemImage:) {}` — la API vieja `.tabItem {}` no renderiza nada
- **Xcode PBXFileSystemSynchronizedRootGroup**: todos los archivos de la carpeta se incluyen automáticamente — nunca usar `.gitkeep` o `.gitignore` dentro del target
- **Swift 6 + GRDB**: `init(row:)` y `encode(to:)` de FetchableRecord/PersistableRecord requieren `nonisolated` con `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`
- **DerivedData stale**: limpiar con `rm -rf ~/Library/Developer/Xcode/DerivedData/Yomi-*` y ⇧⌘K en Xcode
- **JSBridge async**: JSContext es síncrono; SOURCE.fetch bloquea con DispatchSemaphore; llamar siempre desde Task.detached, nunca desde MainActor
- **Keiyoushi plugins**: son .apk Android, no corren en iOS; se muestran como catálogo de referencia únicamente
- **LNReader plugins**: son TypeScript compilado a JS — compatibles con JavaScriptCore si se implementan los shims correctos (fetch, cheerio, storage)
- **Cheerio**: los plugins LNReader usan cheerio para parsear HTML; el shim actual es un stub vacío — implementación real pendiente
- **db.write unused result**: GRDB db.write retorna el valor del closure — usar `_ = try appDatabase.write { ... }` para silenciar el warning "Result of call to 'write' is unused"
- **GRDB bulk column update**: usar `Model.filter(Column("id") == id).updateAll(db, [Column("field").set(to: value)])` en lugar de fetch-mutate-save para updates parciales
- **SHA256 stable IDs**: `CryptoKit.SHA256.hash(data: Data(url.utf8)).compactMap { String(format: "%02x", $0) }.joined().prefix(32).lowercased()` — genera IDs de 32 chars reproducibles desde una URL
- **MangaDex pagination**: usar limit=100 con offset loop; capear en 2000 para evitar loops infinitos en series con muchos capítulos
- **@Observable + UserDefaults**: usar `@ObservationIgnored` en el ivar `defaults`; las computed properties con get/set a UserDefaults funcionan correctamente como bindings
- **UIApplication.isIdleTimerDisabled**: siempre resetear a `false` en `.onDisappear` — de lo contrario la pantalla queda encendida globalmente aunque el usuario salga del reader. Debe ser `true` en `.onAppear`
- **GRDB + Swift 6 strict concurrency**: exponer DatabaseQueue como un `nonisolated(unsafe) var appDatabase: DatabaseQueue!` a nivel de módulo. Patrón oficial GRDB para `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`. Todos los métodos de `*Queries` acceden a `appDatabase` directamente — sin actor hop
- **\*Queries enums**: todos los métodos static deben ser `nonisolated` o el compilador infiere aislamiento MainActor y bloquea las llamadas desde `Task.detached`
- **Dos migraciones v4\_ coexisten**: GRDB trackea migraciones por nombre de string, no por prefijo numérico. `v4_reading_insights` y `v4_reading_time` son independientes y coexisten sin conflicto. La próxima migración debe usar prefijo `v5_`
- **appDatabase.read async overload**: desde un contexto `@MainActor` (como `exportBackup()` en `BackupManager`), `appDatabase.read` resuelve al overload async. Requiere `try await appDatabase.read { ... }`
- **MAL OAuth PKCE plain**: MAL no soporta S256, solo el método `plain` (code_challenge == code_verifier). El verifier es una cadena aleatoria de 43-128 chars
- **Timer en SwiftUI**: `@State private var readingTimer: Timer?` iniciado en `.onAppear` y siempre invalidado en `.onDisappear` + en toda función de navegación antes de crear el siguiente timer
- **ChapterReaderView activeChapter pattern**: usar `currentChapterIndex: Int` como `@State` + `var activeChapter: Chapter { chapters[currentChapterIndex] }` como computed property, en lugar de almacenar el capítulo directamente — permite navegación prev/next sin re-init de la vista
- **Extension debe ser Hashable para Picker + .tag()**: iOS 26 `Picker` requiere que el tipo de selección conforme a `Hashable`. `Extension` solo tenía `Identifiable + Codable` — agregar `Hashable` a la lista de conformances es suficiente; el compilador lo sintetiza automáticamente porque todas las stored properties (`String`, `URL?`, `Bool`, `[String]`) ya conforman
- **Text + Text deprecado en iOS 26**: el operador `+` sobre `Text` fue removido. Old: `Text(date, style: .relative) + Text(" ago")`. New: `Text("\(Text(date, style: .relative)) ago")`. SwiftUI `Text` soporta interpolar otros `Text` (incluidos los con formatters especiales como `.relative`) dentro de string interpolation — el comportamiento live-updating de `.relative` se preserva
- **simultaneousGesture para multi-tap**: double-tap + single-tap sobre el mismo view requiere `.simultaneousGesture` en el gesto de doble tap; sin él SwiftUI rutea todos los taps al handler de single tap
- **Shimmer con GeometryReader + LinearGradient animado**: animar una variable `@State private var phase: CGFloat` de -1 a 1 con `.linear(duration:).repeatForever(autoreverses: false)`, usarla como offset en los `location` de los `Gradient.Stop` — crea un efecto de barrido horizontal sin dependencias externas

## Decisiones de arquitectura
- GRDB sobre SwiftData: control total del esquema, más maduro, compatible con migraciones incrementales
- JavaScriptCore sobre WKWebView: más liviano, no requiere UI, mejor para plugins headless
- Formato de plugins propio (Formato A) + compatibilidad LNReader (Formato B): máxima flexibilidad sin depender de ecosistema Android
- Plugins instalados en Documents/Extensions/ como archivos .js locales
- Token MAL en UserDefaults (no Keychain): suficiente para MVP; migrar a Keychain antes de App Store
