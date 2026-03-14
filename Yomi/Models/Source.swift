import Foundation

/// Representa una fuente o plugin desde donde se obtiene el contenido
struct Source: Identifiable, Codable {
    /// Identificador único de la fuente (ej: "es.manganelo")
    let id: String
    /// Nombre legible de la fuente (ej: "MangaNelo")
    var name: String
    /// Código de idioma BCP 47 del contenido de la fuente (ej: "es", "en", "ja")
    var language: String
    /// Versión del plugin en formato semántico (ej: "1.0.0")
    var version: String
    /// URL del ícono de la fuente para mostrar en la lista
    var iconURL: URL?
    /// URL base del sitio web de la fuente
    var baseURL: URL
    /// Indica si el plugin está instalado en la app
    var isInstalled: Bool
    /// Indica si la fuente contiene contenido para adultos (Not Safe For Work)
    var isNSFW: Bool
}
