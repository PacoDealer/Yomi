import Foundation
import Observation

// MARK: - AniListTrackerService
//
// Named distinctly from the pre-existing Features/Extensions/AniListService.swift, an unrelated
// unauthenticated actor that fetches an average-score badge for Detail views — different
// purpose, would otherwise collide as a duplicate build-product basename.
// AniList's Implicit Grant is the only OAuth flow that fits a client-only iOS app — no
// client_secret required, unlike the Authorization Code Grant. The access token comes back in
// the redirect URL's *fragment* (`#access_token=...`), not a query param, and is long-lived
// (~1 year) with no refresh token — re-auth is the only path once it expires.
// Docs verified live S114-tracker-session (2026-08-19): docs.anilist.co.

private let clientId    = AppSecrets.aniListClientId
private let redirectURI = "yomi://anilist/callback"
private let graphQLURL  = URL(string: "https://graphql.anilist.co")!

@Observable final class AniListTrackerService: MangaTracker {
    static let shared = AniListTrackerService()
    static let displayName = "AniList"
    static let callbackHost = "anilist"
    private init() { loadToken() }

    // MARK: - State

    var isLoggedIn: Bool = false
    var username: String? = nil
    var errorMessage: String? = nil
    var pendingAuthState: String? = nil

    private(set) var accessToken: String? = nil

    // MARK: - Auth URL

    /// `redirect_uri` is sent explicitly (it must match the one registered for this client on
    /// anilist.co) and `state` is included for CSRF protection — see `handleCallback` for what
    /// this flow can and can't verify.
    func authorizationURL() -> URL? {
        var components = URLComponents(string: "https://anilist.co/api/v2/oauth/authorize")!
        components.queryItems = [
            .init(name: "client_id",     value: clientId),
            .init(name: "response_type", value: "token"),
            .init(name: "redirect_uri",  value: redirectURI),
            .init(name: "state",         value: makeAuthState())
        ]
        return components.url
    }

    // MARK: - Handle Callback

    /// The implicit-grant token arrives in the URL *fragment* — `URLComponents` only parses the
    /// query, so the fragment is parsed by hand as its own query-string.
    ///
    /// Implicit Grant has no code-exchange step, so there's no PKCE-style check available even in
    /// principle: `state` is the flow's only defense (Known Issue #124). AniList's docs don't
    /// promise the fragment echoes `state` back, so a missing value isn't treated as an attack —
    /// but a callback arriving with no login pending on this device is rejected outright, which is
    /// the actual attack shape (attacker's token delivered via a `yomi://anilist/callback#...` link).
    func handleCallback(url: URL) async {
        guard
            let fragment = url.fragment,
            let token = URLComponents(string: "?\(fragment)")?.queryItems?.first(where: { $0.name == "access_token" })?.value
        else { return }
        guard verifyAuthState(url: url, requireEcho: false) else {
            errorMessage = "AniList: ignored a login callback this app didn't start."
            return
        }
        accessToken = token
        isLoggedIn  = true
        saveToken()
        await fetchUserInfo()
    }

    // MARK: - GraphQL

    private func graphQLRequest(query: String, variables: [String: Any]) -> URLRequest {
        var request = URLRequest(url: graphQLURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        return request
    }

    // MARK: - User Info

    func fetchUserInfo() async {
        let query = "query { Viewer { id name } }"
        let request = graphQLRequest(query: query, variables: [:])
        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataObj = json["data"]   as? [String: Any],
            let viewer  = dataObj["Viewer"] as? [String: Any],
            let name    = viewer["name"] as? String
        else { return }
        yomiLogNetwork(request, response: response, data: data)
        username = name
    }

    // MARK: - Search Manga

    func searchManga(title: String) async -> String? {
        guard accessToken != nil else { return nil }
        let query = """
        query ($search: String!) {
          Page(perPage: 1) {
            media(search: $search, type: MANGA) { id }
          }
        }
        """
        let request = graphQLRequest(query: query, variables: ["search": title])
        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataObj = json["data"] as? [String: Any],
            let page    = dataObj["Page"] as? [String: Any],
            let list    = page["media"] as? [[String: Any]],
            let first   = list.first,
            let id      = first["id"] as? Int
        else { return nil }
        yomiLogNetwork(request, response: response, data: data)
        return String(id)
    }

    // MARK: - Update Progress

    func updateMangaProgress(trackerId: String, chaptersRead: Int) async {
        guard accessToken != nil, let mediaId = Int(trackerId) else { return }
        let mutation = """
        mutation ($mediaId: Int, $progress: Int, $status: MediaListStatus) {
          SaveMediaListEntry(mediaId: $mediaId, progress: $progress, status: $status) { id }
        }
        """
        let status = chaptersRead > 0 ? "CURRENT" : "PLANNING"
        let request = graphQLRequest(query: mutation, variables: [
            "mediaId":  mediaId,
            "progress": chaptersRead,
            "status":   status
        ])
        await sendProgressUpdate(request, graphQL: true)
    }

    // MARK: - Logout

    func logout() {
        accessToken = nil
        username    = nil
        isLoggedIn  = false
        KeychainHelper.delete(for: "anilist_access_token")
    }

    // MARK: - Persistence

    private func saveToken() {
        if let t = accessToken { KeychainHelper.save(t, for: "anilist_access_token") }
    }

    private func loadToken() {
        accessToken = KeychainHelper.load(for: "anilist_access_token")
        isLoggedIn  = accessToken != nil
    }
}
