import Foundation

/// Representa una categoría para organizar la biblioteca del usuario
struct Category: Identifiable, Codable {
    /// Identificador único local
    let id: String
    /// Nombre visible de la categoría (ej: "Favoritos", "Leyendo")
    var name: String
    /// Posición de orden entre categorías; menor número aparece primero
    var sort: Int
}
