import Foundation
import Observation

// MARK: - BangumiService
//
// Bangumi's (bgm.tv) OAuth also requires a client_secret — no PKCE alternative, same tradeoff
// as Shikimori, accepted per Martin's call. OAuth endpoints live on bgm.tv; all REST calls live
// on the separate api.bgm.tv host. Every request needs a descriptive User-Agent or Bangumi may
// reject it. Docs verified live S114-tracker-session (2026-08-19): bangumi.github.io/api.

private let clientId     = AppSecrets.bangumiClientId
private let clientSecret = AppSecrets.bangumiClientSecret
private let redirectURI  = "yomi://bangumi/callback"
private let oauthHost    = "https://bgm.tv"
private let apiHost      = "https://api.bgm.tv"
private let userAgent    = "Yomi/1.0 (iOS manga reader)"

@Observable final class BangumiService: MangaTracker {
    static let shared = BangumiService()
    static let displayName = "Bangumi"
    static let callbackHost = "bangumi"
    private init() { loadToken() }

    // MARK: - State

    var isLoggedIn: Bool = false
    var username: String? = nil
    var errorMessage: String? = nil
    var pendingAuthState: String? = nil

    private(set) var accessToken: String? = nil
    private var refreshToken: String? = nil

    // MARK: - Auth URL

    func authorizationURL() -> URL? {
        var components = URLComponents(string: "\(oauthHost)/oauth/authorize")!
        components.queryItems = [
            .init(name: "client_id",     value: clientId),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri",  value: redirectURI),
            .init(name: "state",         value: makeAuthState())
        ]
        return components.url
    }

    // MARK: - Handle Callback

    func handleCallback(url: URL) async {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        else { return }
        guard verifyAuthState(url: url, requireEcho: true) else {
            errorMessage = "Bangumi: ignored a login callback this app didn't start."
            return
        }
        do {
            try await exchangeCode(code: code)
            await fetchUserInfo()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Token Exchange

    private func exchangeCode(code: String) async throws {
        var request = URLRequest(url: URL(string: "\(oauthHost)/oauth/access_token")!)
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
            throw NSError(domain: "Bangumi", code: 0, userInfo: [NSLocalizedDescriptionKey: "No access token"])
        }
        accessToken  = access
        refreshToken = json?["refresh_token"] as? String
        isLoggedIn   = true
        saveToken()
    }

    // MARK: - Token Refresh

    /// Bangumi access tokens last ~7 days; the refresh token was saved at login and never used
    /// before S120, so sync silently died a week in (Known Issue #108).
    func refreshAccessToken() async -> Bool {
        guard let refresh = refreshToken else { return false }
        let outcome = await performTokenRefresh(
            url: URL(string: "\(oauthHost)/oauth/access_token")!,
            form: [
                "grant_type":    "refresh_token",
                "client_id":     clientId,
                "client_secret": clientSecret,
                "refresh_token": refresh,
                "redirect_uri":  redirectURI
            ],
            userAgent: userAgent
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
            errorMessage = "Bangumi: session expired — please log in again."
            return false
        case .failed:
            return false
        }
    }

    // MARK: - User Info

    func fetchUserInfo() async {
        guard let token = accessToken else { return }
        var request = URLRequest(url: URL(string: "\(apiHost)/v0/me")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard
            let (data, _) = await sendAuthorized(request),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let name = (json["nickname"] as? String) ?? (json["username"] as? String)
        else { return }
        username = name
    }

    // MARK: - Search Manga

    func searchManga(title: String) async -> String? {
        guard let token = accessToken else { return nil }
        var request = URLRequest(url: URL(string: "\(apiHost)/v0/search/subjects")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let body: [String: Any] = ["keyword": title, "sort": "match", "filter": ["type": [1]]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard
            let (data, _) = await sendAuthorized(request),
            let json  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let list  = json["data"] as? [[String: Any]],
            let first = list.first,
            let id    = first["id"] as? Int
        else { return nil }
        return String(id)
    }

    // MARK: - Update Progress

    func updateMangaProgress(trackerId: String, chaptersRead: Int) async {
        guard let token = accessToken else { return }
        var request = URLRequest(url: URL(string: "\(apiHost)/v0/users/-/collections/\(trackerId)")!)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        // SubjectCollectionType: 1 Wish, 3 Doing — matches "reading" vs "plan to read" elsewhere.
        let collectionType = chaptersRead > 0 ? 3 : 1
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "type":      collectionType,
            "ep_status": chaptersRead
        ])
        await sendProgressUpdate(request)
    }

    // MARK: - Logout

    func logout() {
        accessToken  = nil
        refreshToken = nil
        username     = nil
        isLoggedIn   = false
        KeychainHelper.delete(for: "bangumi_access_token")
        KeychainHelper.delete(for: "bangumi_refresh_token")
    }

    // MARK: - Persistence

    private func saveToken() {
        if let t = accessToken  { KeychainHelper.save(t, for: "bangumi_access_token")  }
        if let t = refreshToken { KeychainHelper.save(t, for: "bangumi_refresh_token") }
    }

    private func loadToken() {
        accessToken  = KeychainHelper.load(for: "bangumi_access_token")
        refreshToken = KeychainHelper.load(for: "bangumi_refresh_token")
        isLoggedIn   = accessToken != nil
    }
}
