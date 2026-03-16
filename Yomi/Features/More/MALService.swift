import Foundation
import Observation

// MARK: - MALService

private let clientId    = "05f23cb2e297b7d0d65cd6ce1ffd6e1d"
private let redirectURI = "yomi://mal/callback"
private let baseURL     = "https://api.myanimelist.net/v2"

@Observable final class MALService {
    static let shared = MALService()
    private init() { loadToken() }

    // MARK: - State

    var isLoggedIn: Bool = false
    var username: String? = nil
    var errorMessage: String? = nil

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
            .init(name: "state",                 value: "yomi")
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

        let (data, _) = try await URLSession.shared.data(for: request)
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

    // MARK: - User Info

    func fetchUserInfo() async {
        guard let token = accessToken else { return }
        var request = URLRequest(url: URL(string: "\(baseURL)/users/@me")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard
            let (data, _) = try? await URLSession.shared.data(for: request),
            let json      = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let name      = json["name"] as? String
        else { return }
        username = name
    }

    // MARK: - Search Manga

    func searchManga(title: String) async -> Int? {
        guard
            let token   = accessToken,
            let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url     = URL(string: "\(baseURL)/manga?q=\(encoded)&limit=1&fields=id,title")
        else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard
            let (data, _) = try? await URLSession.shared.data(for: request),
            let json      = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let list      = json["data"]  as? [[String: Any]],
            let first     = list.first,
            let node      = first["node"] as? [String: Any],
            let id        = node["id"]    as? Int
        else { return nil }
        return id
    }

    // MARK: - Update Progress

    func updateMangaProgress(malId: Int, chaptersRead: Int) async {
        guard let token = accessToken else { return }
        var request = URLRequest(url: URL(string: "\(baseURL)/manga/\(malId)/my_list_status")!)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let status = chaptersRead > 0 ? "reading" : "plan_to_read"
        request.httpBody = "status=\(status)&num_chapters_read=\(chaptersRead)".data(using: .utf8)
        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - Logout

    func logout() {
        accessToken  = nil
        refreshToken = nil
        username     = nil
        isLoggedIn   = false
        codeVerifier = nil
        UserDefaults.standard.removeObject(forKey: "mal_access_token")
        UserDefaults.standard.removeObject(forKey: "mal_refresh_token")
    }

    // MARK: - Persistence

    private func saveToken() {
        UserDefaults.standard.set(accessToken,  forKey: "mal_access_token")
        UserDefaults.standard.set(refreshToken, forKey: "mal_refresh_token")
    }

    private func loadToken() {
        accessToken  = UserDefaults.standard.string(forKey: "mal_access_token")
        refreshToken = UserDefaults.standard.string(forKey: "mal_refresh_token")
        isLoggedIn   = accessToken != nil
    }

    // MARK: - PKCE Helpers

    private func generateCodeVerifier() -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
        return String((0..<64).compactMap { _ in chars.randomElement() })
    }
}
