import CryptoKit
import Foundation
import Kingfisher
import UIKit
import WidgetKit

// MARK: - WidgetReadingItem

struct WidgetReadingItem: Codable {
    let id: String
    let title: String
    let coverURLString: String?
    let lastChapter: String
    /// File name of the cover saved in the App Group's `widget-covers` folder (S182), nil = none.
    var coverFile: String? = nil
    /// "manga" or "novel" — the widget's tap link opens that title (S182); nil in data written before.
    var kind: String? = nil
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
        if items.isEmpty { removeCovers(keeping: []) }
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func read() -> [WidgetReadingItem] {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = ud.data(forKey: itemsKey),
              let items = try? JSONDecoder().decode([WidgetReadingItem].self, from: data)
        else { return [] }
        return items
    }

    // MARK: Covers (S182)
    //
    // A widget can't download anything while it draws (AsyncImage never loads there — Martin's phone showed grey boxes),
    // so the app saves each shown cover as a small JPEG in the App Group and the widget reads the file.

    private static var coversDir: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName)?
            .appending(path: "widget-covers", directoryHint: .isDirectory)
    }

    /// Saves the covers of `items` (a custom/local cover file, else Kingfisher's cache or a download) and returns the
    /// items with `coverFile` set. `customCovers`: item id → custom cover file path.
    static func withSavedCovers(_ items: [WidgetReadingItem], customCovers: [String: String] = [:]) async -> [WidgetReadingItem] {
        guard let dir = coversDir else { return items }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var out: [WidgetReadingItem] = []
        for var item in items {
            let custom = customCovers[item.id]
            // A replaced custom cover keeps its path, so its date is part of the name.
            let customDate = custom.flatMap { try? FileManager.default.attributesOfItem(atPath: $0)[.modificationDate] as? Date }
            let source = custom.map { "\($0)|\(customDate?.timeIntervalSince1970 ?? 0)" } ?? (item.coverURLString ?? "")
            let name = SHA256.hash(data: Data((item.id + "|" + source).utf8))
                .prefix(12).map { String(format: "%02x", $0) }.joined() + ".jpg"
            let file = dir.appending(path: name)
            if FileManager.default.fileExists(atPath: file.path) {
                item.coverFile = name
            } else if let custom, let image = UIImage(contentsOfFile: custom).flatMap(widgetSized),
                      let data = image.jpegData(compressionQuality: 0.85),
                      (try? data.write(to: file, options: .atomic)) != nil {
                item.coverFile = name
            } else if let url = item.coverURLString.flatMap(URL.init(string:)), let image = await coverImage(url),
                      let data = image.jpegData(compressionQuality: 0.85),
                      (try? data.write(to: file, options: .atomic)) != nil {
                item.coverFile = name
            }
            out.append(item)
        }
        removeCovers(keeping: Set(out.compactMap(\.coverFile)))
        return out
    }

    /// The cover at widget size (2:3, 300 px tall is enough for the large widget's cells at 3×).
    private static func coverImage(_ url: URL) async -> UIImage? {
        let options: KingfisherOptionsInfo = [.processor(DownsamplingImageProcessor(size: CGSize(width: 200, height: 300))),
                                              .scaleFactor(1), .backgroundDecode]
        if let image = try? await KingfisherManager.shared.retrieveImage(with: url, options: options).image { return image }
        // Keiyoushi covers that need the bridge (same fallback as `keiyoushiCoverFallback`).
        guard let proxy = KeiyoushiCovers.shared.proxy(for: url) else { return nil }
        return try? await KingfisherManager.shared.retrieveImage(with: proxy, options: options).image
    }

    /// At most 300 px tall, same shape.
    private static func widgetSized(_ image: UIImage) -> UIImage? {
        let h = min(300, image.size.height)
        guard image.size.height > 0 else { return nil }
        return image.preparingThumbnail(of: CGSize(width: image.size.width * h / image.size.height, height: h))
    }

    private static func removeCovers(keeping keep: Set<String>) {
        guard let dir = coversDir,
              let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        for f in files where !keep.contains(f) { try? FileManager.default.removeItem(at: dir.appending(path: f)) }
    }
}
