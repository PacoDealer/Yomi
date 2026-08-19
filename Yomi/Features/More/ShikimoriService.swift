import Foundation
import Observation

// MARK: - ShikimoriService
//
// Shikimori's Authorization Code Grant requires a client_secret (no PKCE alternative exists) —
// embedded here the same way every open-source tracker client (Tachiyomi, Aidoku) handles it,
// per Martin's call. Every request needs a descriptive User-Agent or Shikimori may ban the IP.
// `shikimori.one` permanently redirects to `shikimori.io` — using `.io` directly.
// Docs verified live S114-tracker-session (2026-08-19): shikimori.io/api/doc.

private let clientId     = AppSecrets.shikimoriClientId
private let clientSecret = AppSecrets.shikimoriClientSecret
private let redirectURI  = "yomi://shikimori/callback"
private let baseURL      = "https://shikimori.io"
private let userAgent    = "Yomi/1.0 (iOS manga reader)"

@Observable final class ShikimoriService: MangaTracker {
    static let shared = ShikimoriService()
    static let displayName = "Shikimori"
    static let callbackHost = "shikimori"
    private init() { loadToken() }

    // MARK: - State

    var isLoggedIn: Bool = false
    var username: String? = nil
    var errorMessage: String? = nil

    private(set) var accessToken: String? = nil
    private var refreshToken: String? = nil
    private var userId: String? = nil

    // MARK: - Auth URL

    func authorizationURL() -> URL? {
        var components = URLComponents(string: "\(baseURL)/oauth/authorize")!
        components.queryItems = [
            .init(name: "client_id",     value: clientId),
            .init(name: "redirect_uri",  value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope",         value: "user_rates")
        ]
        return components.url
    }

    // MARK: - Handle Callback

    func handleCallback(url: URL) async {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        else { return }
        do {
            try await exchangeCode(code: code)
            await fetchUserInfo()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Token Exchange

    private func exchangeCode(code: String) async throws {
        var request = URLRequest(url: URL(string: "\(baseURL)/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let body = [
            "grant_type":    "authorization_code",
            "client_id":     clientId,
            "client_secret": clientSecret,
            "code":          code,
            "redirect_uri":  redirectURI
        ]
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        yomiLogNetwork(request, response: response, data: data)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let access = json?["access_token"] as? String else {
            throw NSError(domain: "Shikimori", code: 0, userInfo: [NSLocalizedDescriptionKey: "No access token"])
        }
        accessToken  = access
        refreshToken = json?["refresh_token"] as? String
        isLoggedIn   = true
        saveToken()
    }

    // MARK: - User Info

    func fetchUserInfo() async {
        guard let token = accessToken else { return }
        var request = URLRequest(url: URL(string: "\(baseURL)/api/users/whoami")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let id   = json["id"] as? Int,
            let nick = json["nickname"] as? String
        else { return }
        yomiLogNetwork(request, response: response, data: data)
        userId   = String(id)
        username = nick
        saveToken()
    }

    // MARK: - Search Manga

    func searchManga(title: String) async -> String? {
        guard
            let token   = accessToken,
            let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url     = URL(string: "\(baseURL)/api/mangas?search=\(encoded)&limit=1")
        else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            let list  = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
            let first = list.first,
            let id    = first["id"] as? Int
        else { return nil }
        yomiLogNetwork(request, response: response, data: data)
        return String(id)
    }

    // MARK: - Update Progress

    func updateMangaProgress(trackerId: String, chaptersRead: Int) async {
        guard let token = accessToken, let uid = userId else { return }
        var request = URLRequest(url: URL(string: "\(baseURL)/api/v2/user_rates")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let status = chaptersRead > 0 ? "watching" : "planned"
        let body: [String: Any] = [
            "user_rate": [
                "user_id":     Int(uid) ?? 0,
                "target_id":   Int(trackerId) ?? 0,
                "target_type": "Manga",
                "status":      status,
                "chapters":    chaptersRead
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        if let (data, response) = try? await URLSession.shared.data(for: request) {
            yomiLogNetwork(request, response: response, data: data)
        }
    }

    // MARK: - Logout

    func logout() {
        accessToken  = nil
        refreshToken = nil
        userId       = nil
        username     = nil
        isLoggedIn   = false
        KeychainHelper.delete(for: "shikimori_access_token")
        KeychainHelper.delete(for: "shikimori_refresh_token")
        KeychainHelper.delete(for: "shikimori_user_id")
    }

    // MARK: - Persistence

    private func saveToken() {
        if let t = accessToken  { KeychainHelper.save(t, for: "shikimori_access_token")  }
        if let t = refreshToken { KeychainHelper.save(t, for: "shikimori_refresh_token") }
        if let u = userId       { KeychainHelper.save(u, for: "shikimori_user_id")       }
    }

    private func loadToken() {
        accessToken  = KeychainHelper.load(for: "shikimori_access_token")
        refreshToken = KeychainHelper.load(for: "shikimori_refresh_token")
        userId       = KeychainHelper.load(for: "shikimori_user_id")
        isLoggedIn   = accessToken != nil
    }
}
