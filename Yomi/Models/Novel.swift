import Foundation

// MARK: - Novel

/// Representa una novela ligera (light novel, web novel)
struct Novel: Identifiable, Codable {
    /// Identificador único local
    let id: String
    /// Ruta relativa dentro de la fuente (usada para construir URLs)
    let path: String
    /// ID de la fuente/plugin desde donde proviene
    let sourceId: String
    /// Título de la obra
    var title: String
    /// URL de la portada
    var coverURL: URL?
    /// Sinopsis o descripción
    var summary: String?
    /// Nombre del autor
    var author: String?
    /// Estado de publicación en formato libre ("ongoing", "completed", "hiatus", etc.)
    var status: String
    /// Lista de géneros
    var genres: [String]
    /// Indica si el usuario agregó esta obra a su biblioteca
    var inLibrary: Bool
    /// Fecha y hora de la última vez que el usuario leyó esta obra
    var lastReadAt: Date?
    /// Fecha y hora de la última actualización de metadatos
    var lastUpdatedAt: Date?
}

// MARK: - NovelChapter

/// Representa un capítulo de una novela ligera
struct NovelChapter: Identifiable, Codable {
    /// Identificador único local
    let id: String
    /// ID de la novela a la que pertenece este capítulo
    let novelId: String
    /// Ruta relativa dentro de la fuente (usada para obtener el contenido HTML)
    let path: String
    /// Nombre o título del capítulo
    var name: String
    /// Número de capítulo; puede ser nil si la fuente no lo provee
    var chapterNumber: Double?
    /// Indica si el usuario ya leyó este capítulo
    var isRead: Bool
    /// Fecha y hora en que el usuario terminó o marcó como leído el capítulo
    var readAt: Date?
    /// Fecha de publicación original del capítulo (texto libre según la fuente)
    var releaseTime: String?
}
