import Foundation

actor AniListService {
    static let shared = AniListService()
    private var cache: [String: Int?] = [:]

    private init() {}

    func fetchScore(title: String, isManga: Bool = true) async -> Int? {
        if let cached = cache[title] { return cached }
        let type = isManga ? "MANGA" : "NOVEL"
        let query = """
        query ($search: String, $type: MediaType) {
          Media(search: $search, type: $type, sort: SEARCH_MATCH) {
            averageScore
          }
        }
        """
        let body: [String: Any] = [
            "query": query,
            "variables": ["search": title, "type": type]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let url = URL(string: "https://graphql.anilist.co") else {
            cache[title] = nil
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = data
        guard let (responseData, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let media = dataObj["Media"] as? [String: Any],
              let score = media["averageScore"] as? Int,
              score > 0 else {
            cache[title] = nil
            return nil
        }
        cache[title] = score
        return score
    }
}
