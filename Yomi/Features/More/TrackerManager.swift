import Foundation

// MARK: - TrackerManager

/// Central registry for every `MangaTracker` plus the single OAuth-callback router for all of
/// them. Reader call-sites use `loggedInTrackers` to fan a chapter-finish event out to every
/// connected service without knowing which ones exist; `ContentView`'s one `.onOpenURL` uses
/// `route(url:)` to dispatch a callback to the right tracker by its `callbackHost`, instead of
/// each tracker's settings screen needing its own `.onOpenURL` (which only fires while that
/// screen happens to be on-screen).
@MainActor
enum TrackerManager {
    static var all: [any MangaTracker] {
        [MALService.shared, AniListTrackerService.shared, ShikimoriService.shared, BangumiService.shared]
    }

    static var loggedInTrackers: [any MangaTracker] {
        all.filter(\.isLoggedIn)
    }

    static func route(url: URL) {
        guard url.scheme == "yomi", let host = url.host,
              let tracker = all.first(where: { type(of: $0).callbackHost == host })
        else { return }
        Task { await tracker.handleCallback(url: url) }
    }
}
