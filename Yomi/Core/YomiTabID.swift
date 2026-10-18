import Foundation

// MARK: - YomiTabID
//
// Stable identity for each bottom tab, independent of `Tab(value:)` (AppRouter's selection tag,
// which never changes) and independent of display order (AppSettings.tabOrder, which the user can
// rearrange via CustomizeTabsView). Adding a new tab means adding a case here plus a branch in
// ContentView's tab(for:) switch — AppSettings.tabOrder's init self-heals for the new id.

enum YomiTabID: String, CaseIterable {
    case library, browse, history, updates, more

    var title: String {
        switch self {
        case .library: String(localized: "Library")
        case .browse: String(localized: "Browse")
        case .history: String(localized: "History")
        case .updates: String(localized: "Updates")
        case .more: String(localized: "More")
        }
    }

    var systemImage: String {
        switch self {
        case .library: "books.vertical"
        case .browse: "safari"
        case .history: "clock"
        case .updates: "arrow.clockwise"
        case .more: "ellipsis.circle"
        }
    }

    var routerValue: Int {
        switch self {
        case .library: AppRouter.tabLibrary
        case .browse:  AppRouter.tabBrowse
        case .history: AppRouter.tabHistory
        case .updates: AppRouter.tabUpdates
        case .more:    AppRouter.tabMore
        }
    }
}
