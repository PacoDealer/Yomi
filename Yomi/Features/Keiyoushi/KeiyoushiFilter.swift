import Foundation

// MARK: - KeiyoushiFilter
//
// S157: one search filter an extension declares for a source (Mihon's `Filter`: sort, status, genres…).
// The bridge lists them (`filtersManga`) as `{"name": …, "state": …, "values": […]}` with NO kind field, so the
// kind is read from the shape of `state`. `getSearchManga` takes the chosen values back in another shape
// (`wire`) and matches them to the extension's own filters BY NAME.
//
// Bridge limits (M-Extension-Server `convertFilterList`): inside a group only check boxes, include/exclude
// boxes and pick-one lists are applied — a group, a sort or a text field inside a group is ignored, so Yomi
// doesn't offer those.

nonisolated struct KeiyoushiFilter: Decodable, Sendable, Identifiable, Equatable {
    enum Kind: Sendable, Equatable {
        case header
        case separator
        case select(options: [String], index: Int)
        case text(String)
        case checkbox(Bool)
        /// 0 = ignored, 1 = included, 2 = excluded (Mihon's `TriState` constants).
        case triState(Int)
        /// `index` is nil while the extension has no sort chosen.
        case sort(options: [String], index: Int?, ascending: Bool)
        case group([KeiyoushiFilter])
    }

    let name: String
    var kind: Kind
    /// Position-based (names repeat: every separator is ""), set by `numbered`.
    var id = ""

    private enum CodingKeys: String, CodingKey { case name, state, values, isIgnored }

    private struct SortState: Decodable {
        let index: Int?
        let ascending: Bool?
    }

    /// Never fails: a shape Yomi doesn't know becomes a header, so one odd filter doesn't hide the rest.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        let values = try? c.decode([String].self, forKey: .values)
        if let children = try? c.decode([KeiyoushiFilter].self, forKey: .state) {
            kind = .group(children)
        } else if let on = try? c.decode(Bool.self, forKey: .state) {
            kind = .checkbox(on)
        } else if let text = try? c.decode(String.self, forKey: .state) {
            kind = .text(text)
        } else if let number = try? c.decode(Int.self, forKey: .state) {
            if let values {
                kind = .select(options: values, index: number)
            } else if c.contains(.isIgnored) {
                kind = .triState(number)
            } else {
                kind = name.isEmpty ? .separator : .header
            }
        } else if let values {
            let sort = try? c.decode(SortState.self, forKey: .state)
            kind = .sort(options: values, index: sort?.index, ascending: sort?.ascending ?? false)
        } else {
            kind = name.isEmpty ? .separator : .header
        }
    }

    /// The list with ids filled in, groups included.
    static func numbered(_ filters: [KeiyoushiFilter], prefix: String = "") -> [KeiyoushiFilter] {
        filters.enumerated().map { index, filter in
            var filter = filter
            filter.id = "\(prefix)\(index)"
            if case .group(let children) = filter.kind {
                filter.kind = .group(numbered(children, prefix: "\(filter.id)."))
            }
            return filter
        }
    }

    /// Something the reader can change (and the bridge can apply at this level).
    var isEditable: Bool {
        switch kind {
        case .header, .separator: false
        case .group(let children): children.contains { $0.isEditableInGroup }
        default: true
        }
    }

    var isEditableInGroup: Bool {
        switch kind {
        case .checkbox, .triState, .select: true
        default: false
        }
    }

    /// How many choices are set in this filter — 1 for a single control, the chosen boxes for a group.
    func changes(from original: KeiyoushiFilter) -> Int {
        if case .group(let children) = kind, case .group(let before) = original.kind, children.count == before.count {
            return zip(children, before).filter { $0.kind != $1.kind }.count
        }
        return kind == original.kind ? 0 : 1
    }

    // MARK: Wire

    /// The `filterList` for `getSearchManga`: only what differs from the extension's own `defaults` — the bridge
    /// leaves every filter it isn't given as the extension made it.
    static func wire(_ filters: [KeiyoushiFilter], defaults: [KeiyoushiFilter]) -> [[String: Any]] {
        guard filters.count == defaults.count else { return [] }
        return zip(filters, defaults).compactMap { filter, original in
            filter.kind == original.kind ? nil : filter.wire(original: original)
        }
    }

    private func wire(original: KeiyoushiFilter) -> [String: Any]? {
        switch kind {
        case .header, .separator:
            return nil
        case .select(_, let index):
            return ["name": name, "type": "SelectFilter", "stateInt": index]
        case .text(let text):
            return ["name": name, "type": "TextFilter", "stateString": text]
        case .checkbox(let on):
            // The bridge reads a top-level check box from the first entry of `stateList`.
            return ["name": name, "type": "CheckBox",
                    "stateList": [["name": name, "type": "CheckBox", "stateBoolean": on]]]
        case .triState(let state):
            return ["name": name, "type": "TriState", "stateInt": state]
        case .sort(_, let index, let ascending):
            guard let index else { return nil }
            return ["name": name, "type": "SortFilter", "stateSort": ["index": index, "ascending": ascending]]
        case .group(let children):
            guard case .group(let before) = original.kind, before.count == children.count else { return nil }
            let changed: [[String: Any]] = zip(children, before).compactMap { child, was in
                guard child.kind != was.kind else { return nil }
                switch child.kind {
                case .checkbox(let on): return ["name": child.name, "type": "CheckBox", "stateBoolean": on]
                case .triState(let state): return ["name": child.name, "type": "TriState", "stateInt": state]
                case .select(_, let index): return ["name": child.name, "type": "SelectFilter", "stateInt": index]
                default: return nil
                }
            }
            return changed.isEmpty ? nil : ["name": name, "type": "GroupFilter", "stateList": changed]
        }
    }
}
