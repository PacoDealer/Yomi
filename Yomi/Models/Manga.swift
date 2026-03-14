import Foundation

/// Estado de publicación del manga
enum MangaStatus: String, Codable {
    case unknown    = "unknown"
    case ongoing    = "ongoing"
    case completed  = "completed"
    case hiatus     = "hiatus"
    case cancelled  = "cancelled"
}

/// Representa una obra (manga, manhwa, manhua o novela ligera)
struct Manga: Identifiable, Codable {
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
    /// Nombre del artista (puede diferir del autor en algunas obras)
    var artist: String?
    /// Estado de publicación
    var status: MangaStatus
    /// Lista de géneros
    var genres: [String]
    /// Indica si el usuario agregó esta obra a su biblioteca
    var inLibrary: Bool
    /// Indica si la obra proviene de una fuente local (archivos del dispositivo)
    var isLocal: Bool
    /// Fecha y hora de la última vez que el usuario leyó esta obra
    var lastReadAt: Date?
    /// Fecha y hora de la última actualización de metadatos
    var lastUpdatedAt: Date?
}
