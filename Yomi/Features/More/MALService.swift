import Foundation
import Observation

// MARK: - MALService

private let clientId    = AppSecrets.malClientId
private let redirectURI = "yomi://mal/callback"
private let baseURL     = "https://api.myanimelist.net/v2"

@Observable final class MALService: MangaTracker {
    static let shared = MALService()
    static let displayName = "MyAnimeList"
    static let callbackHost = "mal"
    private init() { loadToken() }

    // MARK: - State

    var isLoggedIn: Bool = false
    var username: String? = nil
    var errorMessage: String? = nil
    var pendingAuthState: String? = nil

    private(set) var accessToken: String? = nil
    private var refreshToken: String? = nil
    private var codeVerifier: String? = nil

    // MARK: - PKCE Auth URL

    func authorizationURL() -> URL? {
        let verifier = generateCodeVerifier()
        codeVerifier = verifier
        let challenge = verifier // MAL uses plain method for PKCE
        var components = URLComponents(string: "https://myanimelist.net/v1/oauth2/authorize")!
        components.queryItems = [
            .init(name: "response_type",        value: "code"),
            .init(name: "client_id",             value: clientId),
            .init(name: "redirect_uri",          value: redirectURI),
            .init(name: "code_challenge",        value: challenge),
            .init(name: "code_challenge_method", value: "plain"),
            // Was the constant "yomi" — an unguessable per-attempt value is the point of `state`.
            .init(name: "state",                 value: makeAuthState())
        ]
        return components.url
    }

    // MARK: - Handle Callback

    func handleCallback(url: URL) async {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
            let verifier = codeVerifier
        else { return }
        guard verifyAuthState(url: url, requireEcho: true) else {
            errorMessage = "MyAnimeList: ignored a login callback this app didn't start."
            return
        }

        do {
            try await exchangeCode(code: code, verifier: verifier)
            await fetchUserInfo()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Token Exchange

    private func exchangeCode(code: String, verifier: String) async throws {
        var request = URLRequest(url: URL(string: "https://myanimelist.net/v1/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "client_id":     clientId,
            "grant_type":    "authorization_code",
            "code":          code,
            "redirect_uri":  redirectURI,
            "code_verifier": verifier
        ]
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        yomiLogNetwork(request, response: response, data: data)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let access = json?["access_token"] as? String else {
            throw NSError(
                domain: "MAL", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "No access token"]
            )
        }
        accessToken  = access
        refreshToken = json?["refresh_token"] as? String
        isLoggedIn   = true
        saveToken()
    }

    // MARK: - Token Refresh

    /// MAL's access token is short-lived (~31 days); the refresh token was saved at login and never
    /// used until S120, so sync silently died forever once it expired (Known Issue #108).
    func refreshAccessToken() async -> Bool {
        guard let refresh = refreshToken else { return false }
        let outcome = await performTokenRefresh(
            url: URL(string: "https://myanimelist.net/v1/oauth2/token")!,
            form: [
                "client_id":     clientId,
                "grant_type":    "refresh_token",
                "refresh_token": refresh
            ]
        )
        switch outcome {
        case .refreshed(let access, let newRefresh):
            accessToken = access
            if let newRefresh { refreshToken = newRefresh }
            saveToken()
            errorMessage = nil
            return true
        case .rejected:
            logout()
            errorMessage = "MyAnimeList: session expired — please log in again."
            return false
        case .failed:
            return false
        }
    }

    // MARK: - User Info

    func fetchUserInfo() async {
        guard let token = accessToken else { return }
        var request = URLRequest(url: URL(string: "\(baseURL)/users/@me")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard
            let (data, _) = await sendAuthorized(request),
            let json      = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let name      = json["name"] as? String
        else { return }
        username = name
    }

    // MARK: - Search Manga

    func searchManga(title: String) async -> String? {
        guard
            let token   = accessToken,
            let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url     = URL(string: "\(baseURL)/manga?q=\(encoded)&limit=1&fields=id,title")
        else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard
            let (data, _) = await sendAuthorized(request),
            let json      = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let list      = json["data"]  as? [[String: Any]],
            let first     = list.first,
            let node      = first["node"] as? [String: Any],
            let id        = node["id"]    as? Int
        else { return nil }
        return String(id)
    }

    // MARK: - Update Progress

    func updateMangaProgress(trackerId: String, chaptersRead: Int) async {
        guard let token = accessToken, let malId = Int(trackerId) else { return }
        var request = URLRequest(url: URL(string: "\(baseURL)/manga/\(malId)/my_list_status")!)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let status = chaptersRead > 0 ? "reading" : "plan_to_read"
        request.httpBody = "status=\(status)&num_chapters_read=\(chaptersRead)".data(using: .utf8)
        await sendProgressUpdate(request)
    }

    // MARK: - Logout

    func logout() {
        accessToken  = nil
        refreshToken = nil
        username     = nil
        isLoggedIn   = false
        codeVerifier = nil
        KeychainHelper.delete(for: "mal_access_token")
        KeychainHelper.delete(for: "mal_refresh_token")
        // Clean up any legacy UserDefaults values
        UserDefaults.standard.removeObject(forKey: "mal_access_token")
        UserDefaults.standard.removeObject(forKey: "mal_refresh_token")
    }

    // MARK: - Persistence

    private func saveToken() {
        if let t = accessToken  { KeychainHelper.save(t, for: "mal_access_token")  }
        if let t = refreshToken { KeychainHelper.save(t, for: "mal_refresh_token") }
    }

    private func loadToken() {
        // Migrate from UserDefaults if keychain is empty
        if let legacy = UserDefaults.standard.string(forKey: "mal_access_token") {
            KeychainHelper.save(legacy, for: "mal_access_token")
            UserDefaults.standard.removeObject(forKey: "mal_access_token")
        }
        if let legacy = UserDefaults.standard.string(forKey: "mal_refresh_token") {
            KeychainHelper.save(legacy, for: "mal_refresh_token")
            UserDefaults.standard.removeObject(forKey: "mal_refresh_token")
        }
        accessToken  = KeychainHelper.load(for: "mal_access_token")
        refreshToken = KeychainHelper.load(for: "mal_refresh_token")
        isLoggedIn   = accessToken != nil
    }

    // MARK: - PKCE Helpers

    private func generateCodeVerifier() -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
        return String((0..<64).compactMap { _ in chars.randomElement() })
    }
}
