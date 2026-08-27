import Foundation
import Security

// MARK: - TokenRefreshOutcome

/// Outcome of a `grant_type=refresh_token` POST — a server that explicitly refuses the refresh
/// token is a terminal, user-visible state (re-login required), while a network failure is not and
/// must never log anyone out. Declared at file scope because a protocol extension can't nest a type.
enum TokenRefreshOutcome {
    case refreshed(access: String, refresh: String?)
    case rejected
    case failed
}

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
    /// The bearer token every authenticated request carries. Exposed on the protocol so
    /// `sendAuthorized(_:)` can re-sign a request after a refresh.
    var accessToken: String? { get }

    func authorizationURL() -> URL?
    func handleCallback(url: URL) async
    /// Exchanges this service's stored `refresh_token` for a new access token.
    ///
    /// Returns `true` only when a new token was actually obtained and saved. The default
    /// implementation returns `false` — correct for AniList, whose Implicit Grant issues no refresh
    /// token at all (re-auth is the only path once its ~1-year token expires).
    func refreshAccessToken() async -> Bool
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

    // MARK: - Token refresh

    func refreshAccessToken() async -> Bool { false }

    /// Shared `grant_type=refresh_token` exchange for the three Authorization Code Grant services.
    ///
    /// Before this existed, all three saved a `refresh_token` at login and never used it: once the
    /// short-lived access token expired, every `searchManga`/`updateMangaProgress` silently no-op'd
    /// forever while the Trackers screen kept showing "Connected" (Known Issue #108).
    func performTokenRefresh(url: URL, form: [String: String], userAgent: String? = nil) async -> TokenRefreshOutcome {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        if let userAgent { request.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
        request.httpBody = form
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            yomiLogNetwork(request, response: response, data: data)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let access = json?["access_token"] as? String, (200...299).contains(status) {
                return .refreshed(access: access, refresh: json?["refresh_token"] as? String)
            }
            // 400/401 here means the refresh token itself is dead (revoked, expired, or already
            // rotated) — the only fix is a fresh login. Anything else is treated as transient.
            return (400...401).contains(status) ? .rejected : .failed
        } catch {
            yomiLogNetwork(request, response: nil, data: nil, error: error)
            return .failed
        }
    }

    // MARK: - Authenticated requests

    /// Performs a request carrying this tracker's bearer token, refreshing the token and retrying
    /// once when the server answers 401.
    ///
    /// Returns `nil` on any failure, matching the `try?` shape every call site already had — the
    /// difference is that an expired token now recovers itself instead of failing forever, and a
    /// genuinely dead session says so in `errorMessage` instead of staying silently "Connected".
    func sendAuthorized(_ request: URLRequest) async -> (Data, URLResponse)? {
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        yomiLogNetwork(request, response: response, data: data)
        guard (response as? HTTPURLResponse)?.statusCode == 401 else { return (data, response) }

        guard await refreshAccessToken(), let token = accessToken else {
            // No refresh available (AniList) or the refresh itself was refused — refreshAccessToken
            // already reported the latter, so only the former needs a message here.
            if errorMessage == nil {
                errorMessage = "\(Self.displayName): session expired — please log in again."
            }
            return nil
        }
        var retry = request
        retry.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (retryData, retryResponse) = try? await URLSession.shared.data(for: retry) else { return nil }
        yomiLogNetwork(retry, response: retryResponse, data: retryData)
        return (retryData, retryResponse)
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
        // Routed through sendAuthorized so an expired access token refreshes and retries once
        // instead of failing every write from here on (#108).
        guard let (data, response) = await sendAuthorized(request) else {
            if errorMessage == nil {
                errorMessage = "\(Self.displayName): progress sync failed."
            }
            return
        }
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
    }
}
