import Foundation
import Security

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
    /// Single-use CSRF `state` for the login flow currently in progress — written by
    /// `makeAuthState()` when this app itself builds the authorization URL, consumed (and cleared)
    /// by `verifyAuthState(url:requireEcho:)` when the redirect comes back. `nil` means no login
    /// was started from this device, so any callback arriving is unsolicited.
    var pendingAuthState: String? { get set }

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

    // MARK: - OAuth CSRF state

    /// Generates a fresh 256-bit `state` value, stores it as this login attempt's pending state,
    /// and returns it for inclusion in the authorization URL.
    ///
    /// Without this, `handleCallback` had no way to tell a redirect it solicited from one an
    /// attacker delivered (`yomi://<host>/callback?code=<attacker's code>`) — the app would happily
    /// log the victim's device into the attacker's tracker account and push their real reading
    /// history into it. Known Issues #123/#124.
    func makeAuthState() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        // A failed SecRandomCopyBytes would leave an all-zero state; UUID is a weaker but still
        // unguessable-by-a-remote-attacker fallback rather than shipping a constant.
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            let fallback = UUID().uuidString + UUID().uuidString
            pendingAuthState = fallback
            return fallback
        }
        let state = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        pendingAuthState = state
        return state
    }

    /// Verifies an OAuth redirect belongs to a login *this app* started, and consumes the pending
    /// state so the same callback can never be replayed.
    ///
    /// - Parameter requireEcho: `true` for the three Authorization Code Grant services, whose
    ///   servers are spec-compliant and always echo `state` back. AniList's Implicit Grant passes
    ///   `false`: its docs don't guarantee the fragment carries `state`, so a missing value is
    ///   accepted, but only while a login this app started is genuinely pending — which still
    ///   blocks the cold "open this link and get silently logged in" attack.
    func verifyAuthState(url: URL, requireEcho: Bool) -> Bool {
        guard let expected = pendingAuthState else { return false }
        pendingAuthState = nil
        if let returned = Self.stateValue(in: url) { return returned == expected }
        return !requireEcho
    }

    /// Reads `state` from either the query (Authorization Code Grant) or the fragment (AniList's
    /// Implicit Grant, which returns everything after `#`).
    static func stateValue(in url: URL) -> String? {
        if let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "state" })?.value {
            return value
        }
        if let fragment = url.fragment,
           let value = URLComponents(string: "?\(fragment)")?
            .queryItems?.first(where: { $0.name == "state" })?.value {
            return value
        }
        return nil
    }

    // MARK: - Progress sync

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
