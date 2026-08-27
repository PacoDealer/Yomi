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

extension MangaTracker {

    /// Sends a progress-write request and records the outcome in `errorMessage`.
    ///
    /// Every service used to fire this call as `if let ... = try? await URLSession...`, which
    /// dropped 401s, 429 rate-limits and network errors on the floor identically — a tracker could
    /// silently stop recording progress forever while still reporting "Connected". A success also
    /// clears any stale message, so an old failure doesn't linger once sync starts working again.
    ///
    /// - Parameter graphQL: for AniList, whose GraphQL endpoint reports failures as an `errors`
    ///   array inside an HTTP 200 body rather than a non-2xx status.
    func sendProgressUpdate(_ request: URLRequest, graphQL: Bool = false) async {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            yomiLogNetwork(request, response: response, data: data)

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                errorMessage = "\(Self.displayName): progress sync failed (HTTP \(http.statusCode))"
                return
            }
            if graphQL,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errors = json["errors"] as? [[String: Any]], !errors.isEmpty {
                let detail = errors.first?["message"] as? String ?? "unknown error"
                errorMessage = "\(Self.displayName): progress sync failed — \(detail)"
                return
            }
            errorMessage = nil
        } catch {
            yomiLogNetwork(request, response: nil, data: nil, error: error)
            errorMessage = "\(Self.displayName): progress sync failed — \(error.localizedDescription)"
        }
    }
}
