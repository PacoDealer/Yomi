import Foundation

// MARK: - MangaTracker

/// Shared interface for external reading-progress trackers (MyAnimeList, AniList, Shikimori,
/// Bangumi). Reader call-sites and the Trackers settings screen talk to every tracker only
/// through this protocol, so adding a new service never touches reader code.
protocol MangaTracker: AnyObject {
    /// Shown in the Trackers list and the tracker's own settings screen.
    static var displayName: String { get }
    /// The host segment of this tracker's `yomi://<host>/callback` redirect URI — lets a single
    /// `.onOpenURL` dispatch a callback to the right service without guessing.
    static var callbackHost: String { get }

    var isLoggedIn: Bool { get }
    var username: String? { get }
    var errorMessage: String? { get set }

    func authorizationURL() -> URL?
    func handleCallback(url: URL) async
    /// Returns the tracker's own id for the best title match, as a string (each service's id
    /// type differs — MAL/AniList/Shikimori/Bangumi are all numeric, kept as String here so the
    /// protocol stays type-agnostic).
    func searchManga(title: String) async -> String?
    func updateMangaProgress(trackerId: String, chaptersRead: Int) async
    func logout()
}
