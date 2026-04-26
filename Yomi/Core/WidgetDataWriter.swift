import Foundation
import WidgetKit

// MARK: - WidgetReadingItem

struct WidgetReadingItem: Codable {
    let id: String
    let title: String
    let coverURLString: String?
    let lastChapter: String
}

// MARK: - WidgetDataWriter
// Writes continue-reading data to the App Group shared container.
// Widget reads the same UserDefaults suite to populate its timeline.

enum WidgetDataWriter {
    static let suiteName = "group.pacodealer.Yomi"
    static let itemsKey  = "widgetReadingItems"

    static func write(_ items: [WidgetReadingItem]) {
        guard let ud = UserDefaults(suiteName: suiteName) else { return }
        if let data = try? JSONEncoder().encode(Array(items.prefix(5))) {
            ud.set(data, forKey: itemsKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func read() -> [WidgetReadingItem] {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = ud.data(forKey: itemsKey),
              let items = try? JSONDecoder().decode([WidgetReadingItem].self, from: data)
        else { return [] }
        return items
    }
}
