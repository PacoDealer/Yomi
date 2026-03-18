import Foundation

/// Representa un capítulo de una obra
struct Chapter: Identifiable, Codable {
    /// Identificador único local
    let id: String
    /// ID del manga al que pertenece este capítulo
    let mangaId: String
    /// Ruta relativa dentro de la fuente (usada para obtener las páginas)
    let path: String
    /// Nombre o título del capítulo (ej: "Capítulo 1" o "Prólogo")
    var name: String
    /// Número de capítulo; puede ser nil si la fuente no lo provee
    var chapterNumber: Double?
    /// Indica si el usuario ya leyó este capítulo
    var isRead: Bool
    /// Indica si el capítulo está descargado para lectura sin conexión
    var isDownloaded: Bool
    /// Fecha y hora en que se completó la descarga del capítulo (nil si no está descargado)
    var downloadedAt: Date?
    /// Fecha y hora en que el usuario terminó o marcó como leído el capítulo
    var readAt: Date?
    /// Progreso de lectura entre 0.0 (sin leer) y 1.0 (completado)
    var progress: Double
    /// Segundos totales de tiempo de lectura registrado para este capítulo
    var readingSeconds: Int
}
