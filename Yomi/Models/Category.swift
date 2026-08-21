import Foundation

/// Represents a category for organizing the user's library
struct Category: Identifiable, Codable {
    /// Local unique identifier
    let id: String
    /// Visible category name (e.g. "Favorites", "Reading")
    var name: String
    /// Sort position among categories; lower numbers appear first
    var sort: Int
}
