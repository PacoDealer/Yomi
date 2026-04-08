import Foundation

// MARK: - appRouter

/// Module-level singleton accesible desde cualquier contexto de aislamiento.
nonisolated(unsafe) var appRouter = AppRouter()

// MARK: - AppRouter

/// Gestiona la navegación global entre tabs de la app.
@Observable
final class AppRouter {

    // MARK: - Tab index constants

    static let tabLibrary = 0
    static let tabBrowse  = 1
    static let tabHistory = 2
    static let tabUpdates = 3
    static let tabMore    = 4

    // MARK: - State

    var selectedTab: Int = 0

    /// When true, BrowseView will switch its sub-tab to Extensions and reset this flag.
    var openBrowseExtensions: Bool = false

    // MARK: - Init

    init() {}
}
