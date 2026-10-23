import Foundation

/// Known Issue #208 (S188): a source that changes how it stores chapter URLs makes every chapter look new — Yomi's
/// chapter ids hash the URL, so a refresh adds a second copy of each chapter with no read state (Keiyoushi Madara,
/// `39e8efc`: slug + memo instead of a full URL). Mihon's answer (`SyncChaptersWithSource`): a chapter the source no
/// longer lists and a new chapter with the same recognized number are the same chapter — the new one takes the old
/// one's read state and the old row goes.
///
/// Yomi's version is stricter, because a wrong match would mark a chapter read that the user never read:
/// - only chapters with a known number (≥ 0) — no number, no match;
/// - one old and one new chapter for that number, or else pairs that share the same group (scanlator) one-to-one;
///   anything still ambiguous is left alone (a duplicate is better than lost or invented progress);
/// - downloaded old chapters are never moved (their files are stored under the old id).
/// Pure Foundation so `scripts/chapter-carry-over-tests` can compile it on macOS.
enum ChapterCarryOver {
    struct Item: Sendable {
        let id: String
        let number: Double?
        let scanlator: String?
        let isDownloaded: Bool

        nonisolated init(id: String, number: Double?, scanlator: String? = nil, isDownloaded: Bool = false) {
            self.id = id
            self.number = number
            self.scanlator = scanlator
            self.isDownloaded = isDownloaded
        }
    }

    struct Move: Equatable, Sendable {
        let oldId: String
        let newId: String
    }

    /// Which saved chapters (`local`) the fresh list (`remote`, the source's whole list) replaces, and by which id.
    nonisolated static func moves(local: [Item], remote: [Item]) -> [Move] {
        let remoteIds = Set(remote.map(\.id))
        let localIds = Set(local.map(\.id))
        let gone = local.filter { !remoteIds.contains($0.id) && !$0.isDownloaded && isKnown($0.number) }
        let added = remote.filter { !localIds.contains($0.id) && isKnown($0.number) }
        guard !gone.isEmpty, !added.isEmpty else { return [] }

        let addedByNumber = Dictionary(grouping: added, by: { $0.number! })
        var moves: [Move] = []
        for (number, olds) in Dictionary(grouping: gone, by: { $0.number! }) {
            guard let news = addedByNumber[number] else { continue }
            if olds.count == 1, news.count == 1 {
                moves.append(Move(oldId: olds[0].id, newId: news[0].id))
                continue
            }
            let newsByGroup = Dictionary(grouping: news, by: { group($0) })
            for (name, oldsInGroup) in Dictionary(grouping: olds, by: { group($0) }) where oldsInGroup.count == 1 {
                guard let match = newsByGroup[name], match.count == 1 else { continue }
                moves.append(Move(oldId: oldsInGroup[0].id, newId: match[0].id))
            }
        }
        return moves.sorted { $0.newId < $1.newId }
    }

    nonisolated private static func isKnown(_ number: Double?) -> Bool {
        guard let number else { return false }
        return number >= 0
    }

    nonisolated private static func group(_ item: Item) -> String {
        (item.scanlator ?? "").trimmingCharacters(in: .whitespaces).lowercased()
    }
}
