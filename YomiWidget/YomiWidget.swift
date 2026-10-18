import WidgetKit
import SwiftUI

// MARK: - Shared data model (mirrors WidgetDataWriter.WidgetReadingItem in main app)

struct ReadingItem: Codable {
    let id: String
    let title: String
    let coverURLString: String?
    let lastChapter: String
    /// Cover saved by the app in the App Group's `widget-covers` folder (S182) — a widget can't download images.
    let coverFile: String?
}

// MARK: - Timeline Entry

struct ContinueReadingEntry: TimelineEntry {
    let date: Date
    let items: [ReadingItem]

    static let placeholder = ContinueReadingEntry(
        date: .now,
        items: [ReadingItem(id: "placeholder", title: "One Piece", coverURLString: nil, lastChapter: "Chapter 1100", coverFile: nil)]
    )
}

// MARK: - Timeline Provider

struct ContinueReadingProvider: TimelineProvider {
    private static let suiteName = "group.pacodealer.Yomi"
    private static let itemsKey  = "widgetReadingItems"

    func placeholder(in context: Context) -> ContinueReadingEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (ContinueReadingEntry) -> Void) {
        completion(context.isPreview ? .placeholder : makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ContinueReadingEntry>) -> Void) {
        let entry   = makeEntry()
        let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: entry.date) ?? entry.date
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func makeEntry() -> ContinueReadingEntry {
        guard let ud    = UserDefaults(suiteName: Self.suiteName),
              let data  = ud.data(forKey: Self.itemsKey),
              let items = try? JSONDecoder().decode([ReadingItem].self, from: data)
        else { return ContinueReadingEntry(date: .now, items: []) }
        return ContinueReadingEntry(date: .now, items: items)
    }
}

// MARK: - Widget View
//
// S182 redesign ("calm", RESEARCH §26 — Apple Music-like): covers come from files the app saves, nothing is drawn on
// a cover, titles get the full width.

struct ContinueReadingWidgetView: View {
    let entry: ContinueReadingEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if entry.items.isEmpty {
                emptyView
            } else {
                switch family {
                case .systemMedium: mediumView(Array(entry.items.prefix(3)))
                case .systemLarge:  largeView(Array(entry.items.prefix(5)))
                default:            smallView(entry.items[0])
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // MARK: Empty

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "books.vertical")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Open Yomi to start reading")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: Small — cover top-left, title across the whole width below

    private func smallView(_ item: ReadingItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                cover(item, height: 78)
                Spacer(minLength: 0)
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 6)
            Text(item.title)
                .font(.footnote.weight(.semibold))
                .lineLimit(3)
                .minimumScaleFactor(0.85)
            Text(item.lastChapter)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
    }

    // MARK: Medium — up to 3 covers side by side

    private func mediumView(_ items: [ReadingItem]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(items, id: \.id) { item in
                VStack(alignment: .leading, spacing: 4) {
                    cover(item, height: 84)
                    Text(item.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                    Text(item.lastChapter)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(items.count..<3, id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
        }
        .padding(14)
    }

    // MARK: Large — a list, like Apple Music's "Recently Played"

    private func largeView(_ items: [ReadingItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Continue Reading")
                .font(.subheadline.weight(.semibold))
            ForEach(items, id: \.id) { item in
                HStack(spacing: 12) {
                    cover(item, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                        Text(item.lastChapter)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    // MARK: Cover

    private static let coversDir = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: "group.pacodealer.Yomi")?
        .appending(path: "widget-covers", directoryHint: .isDirectory)

    /// A 2:3 cover of the given height from the saved file, or a plain tile.
    private func cover(_ item: ReadingItem, height: CGFloat) -> some View {
        let image = item.coverFile
            .flatMap { name in Self.coversDir.map { $0.appending(path: name) } }
            .flatMap { UIImage(contentsOfFile: $0.path) }
        return Group {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
                    .overlay { Image(systemName: "book.closed").foregroundStyle(.secondary) }
            }
        }
        .frame(width: height * 2 / 3, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5) }
    }
}

// MARK: - Widget

struct ContinueReadingWidget: Widget {
    let kind = "YomiContinueReading"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ContinueReadingProvider()) { entry in
            ContinueReadingWidgetView(entry: entry)
        }
        .configurationDisplayName("Continue Reading")
        .description("Pick up where you left off in Yomi.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Bundle

@main
struct YomiWidgetBundle: WidgetBundle {
    var body: some Widget {
        ContinueReadingWidget()
    }
}
