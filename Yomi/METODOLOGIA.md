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