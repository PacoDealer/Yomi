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
| 1 | 2026-03-13 | Setup proyecto, Cursor, GitHub Desktop, documentación inicial, primer commit |

## Aprendizajes
- Tachimanga (iOS) es closed-source, arquitectura inferida de Mihon + LNReader
- LNReader usa Function() para ejecutar plugins JS — en iOS se usa JavaScriptCore
- El repo Suwayomi-Server era un fork de otro proyecto, no tenía nada útil — se descartó
- iOS 18+ permite usar APIs modernas de SwiftUI sin preocuparse por compatibilidad
- **iOS 26 TabView**: nueva API `Tab("título", systemImage:) {}` reemplaza a `.tabItem {}` — la API vieja no renderiza nada y falla silenciosamente
- **Xcode 16 PBXFileSystemSynchronizedRootGroup**: todos los archivos de la carpeta del proyecto se incluyen automáticamente en el bundle sin excepciones — nunca usar archivos placeholder (`.gitkeep`, `.gitignore`) en la carpeta del target
- **Swift 6 + GRDB**: los métodos `init(row:)` y `encode(to:)` de `FetchableRecord`/`PersistableRecord` requieren `nonisolated` cuando el proyecto tiene `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
- **DerivedData stale**: ante errores de Xcode que persisten tras cambios en archivos, limpiar con `rm -rf ~/Library/Developer/Xcode/DerivedData/Yomi-*` y luego ⇧⌘K en Xcode