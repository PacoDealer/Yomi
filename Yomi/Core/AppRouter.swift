import Foundation

// MARK: - appRouter

/// Module-level singleton accessible from any isolation context.
nonisolated(unsafe) var appRouter = AppRouter()

// MARK: - AppRouter

/// Manages global tab navigation and deep-link state.
@Observable
final class AppRouter {

    // MARK: - Tab index constants

    static let tabLibrary = 0
    static let tabBrowse  = 1
    static let tabHistory = 2
    static let tabUpdates = 3
    static let tabMore    = 4

    // MARK: - State

    var selectedTab: Int

    /// When true, MoreView will push PluginsView and reset this flag.
    var openMorePlugins: Bool = false

    /// Set by AppDelegate when a chapter-update notification is tapped; LibraryView observes and navigates.
    var pendingOpenMangaId: String? = nil
    var pendingOpenNovelId: String? = nil

    // MARK: - Init

    init() {
        selectedTab = AppSettings.shared.defaultTab
    }
}
