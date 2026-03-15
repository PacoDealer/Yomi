# Metodología de trabajo — Yomi

## Workflow
- **Claude.ai** → arquitectura, planificación, generación de código completo
- **Cursor** → edición de archivos, copiar/pegar código
- **Xcode** → compilar, correr en simulador, ver errores
- **GitHub Desktop** → commit y push después de cada bloque funcional

## Reglas del workflow
- Un archivo a la vez, confirmación entre cada uno
- Nunca crear múltiples archivos simultáneamente
- Siempre compilar en Xcode después de cada archivo nuevo
- Reportar errores exactos de Xcode a Claude antes de continuar

## Stack técnico
- Swift + SwiftUI (iOS 18+)
- GRDB para base de datos SQLite
- JavaScriptCore para ejecutar plugins JS
- Arquitectura inspirada en LNReader (React Native) y Mihon (Android)

## Sesiones
| # | Fecha | Qué se hizo |
|---|-------|-------------|
| 1 | 2026-03-13 | Setup completo: Homebrew, Node, Claude Code, estructura carpetas, 4 modelos, GRDB, tab bar 4 tabs funcionando en simulador |
| 2 | 2026-03-14 | LibraryView grid + ViewModel + MangaCoverCell + MangaDetailView + navegación desde grid + DatabaseManager inicializado en launch |
| 3 | 2026-03-14 | Sistema de extensiones/plugins JS: Extension model, ExtensionQueries, DatabaseManager v2 migration, JSBridge (JavaScriptCore), ExtensionManager, test-source.js, BrowseView con CTA + lista de extensiones instaladas. AdaptiveGrid en LibraryView. |

## Aprendizajes
- Tachimanga (iOS) es closed-source, arquitectura inferida de Mihon + LNReader
- LNReader usa Function() para ejecutar plugins JS — en iOS se usa JavaScriptCore
- El repo Suwayomi-Server era un fork de otro proyecto, no tenía nada útil — se descartó
- iOS 18+ permite usar APIs modernas de SwiftUI sin preocuparse por compatibilidad
- **iOS 26 TabView**: nueva API `Tab("título", systemImage:) {}` reemplaza a `.tabItem {}` — la API vieja no renderiza nada y falla silenciosamente
- **Xcode 16 PBXFileSystemSynchronizedRootGroup**: todos los archivos de la carpeta del proyecto se incluyen automáticamente en el bundle sin excepciones — nunca usar archivos placeholder (`.gitkeep`, `.gitignore`) en la carpeta del target
- **Swift 6 + GRDB**: los métodos `init(row:)` y `encode(to:)` de `FetchableRecord`/`PersistableRecord` requieren `nonisolated` cuando el proyecto tiene `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
- **DerivedData stale**: ante errores de Xcode que persisten tras cambios en archivos, limpiar con `rm -rf ~/Library/Developer/Xcode/DerivedData/Yomi-*` y luego ⇧⌘K en Xcode
- **Keiyoushi extensions**: Los plugins de Keiyoushi son .apk (Android). No corren nativamente en iOS. Tachimanga los ejecuta mediante un motor Android interno (closed-source, muy complejo de replicar). Yomi usa su propio formato de plugins JS ejecutados via JavaScriptCore.
- **Keiyoushi index JSON**: El índice público `https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json` lista todos los plugins disponibles con nombre, idioma, versión, nsfw y sources. Yomi puede consumirlo para mostrar el catálogo de extensiones en MoreView → Plugins como referencia visual.
- **Formato plugin Yomi**: Cada plugin JS debe exportar tres funciones globales: `getMangaList(page)` → array de manga, `getChapterList(mangaPath)` → array de capítulos, `getPageList(chapterPath)` → array de URLs de imágenes. JSBridge las llama via JavaScriptCore.
- **UX/UI audit sesión 3**: Grid fijo → AdaptiveGrid(.adaptive(minimum:100, maximum:160)). BrowseView vacío → CTA real con botón. MangaDetailView pendiente: hero cover con blur, botón "Add to Library" prominente, haptics. Reader pendiente: modo horizontal RTL (manga japonés), modo vertical scroll (webtoon/manhwa), UI inmersiva que se oculta al tocar.
- **Sesión 4 roadmap**: (1) Conectar test-source.js end-to-end en BrowseView via JSBridge, (2) MoreView Plugins con catálogo Keiyoushi como referencia, (3) Lector de capítulos horizontal RTL + vertical webtoon, (4) UX fixes: badges en covers, hero header en MangaDetailView, haptics.