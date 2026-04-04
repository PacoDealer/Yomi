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

    // MARK: - Init

    init() {}
}
