import WidgetKit
import SwiftUI

// MARK: - Shared data model (mirrors WidgetDataWriter.WidgetReadingItem in main app)

struct ReadingItem: Codable {
    let id: String
    let title: String
    let coverURLString: String?
    let lastChapter: String
}

// MARK: - Timeline Entry

struct ContinueReadingEntry: TimelineEntry {
    let date: Date
    let items: [ReadingItem]

    static let placeholder = ContinueReadingEntry(
        date: .now,
        items: [ReadingItem(id: "placeholder", title: "One Piece", coverURLString: nil, lastChapter: "Chapter 1100")]
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

struct ContinueReadingWidgetView: View {
    let entry: ContinueReadingEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.items.isEmpty {
            emptyView
        } else {
            switch family {
            case .systemSmall:  smallView(entry.items[0])
            case .systemMedium: mediumView(Array(entry.items.prefix(3)))
            case .systemLarge:  largeView(Array(entry.items.prefix(6)))
            default:            smallView(entry.items[0])
            }
        }
    }

    // MARK: Empty

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "books.vertical")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Open Yomi to start reading")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .containerBackground(.fill, for: .widget)
    }

    // MARK: Small — single item, cover left + text right

    private func smallView(_ item: ReadingItem) -> some View {
        HStack(spacing: 0) {
            coverImage(urlString: item.coverURLString, width: 70)
                .frame(width: 70)
                .clipped()

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.caption).fontWeight(.semibold)
                    .lineLimit(3)
                Text(item.lastChapter)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Label("Continue", systemImage: "play.fill")
                    .font(.caption2).fontWeight(.medium)
                    .foregroundStyle(.tint)
                    .labelStyle(.titleAndIcon)
            }
            .padding(10)
            Spacer(minLength: 0)
        }
        .containerBackground(.fill, for: .widget)
    }

    // MARK: Medium — up to 3 items in a row

    private func mediumView(_ items: [ReadingItem]) -> some View {
        HStack(spacing: 10) {
            ForEach(items, id: \.id) { item in
                mediumCell(item)
            }
            if items.count < 3 { Spacer() }
        }
        .padding(12)
        .containerBackground(.fill, for: .widget)
    }

    private func mediumCell(_ item: ReadingItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            coverImage(urlString: item.coverURLString, aspectRatio: 2.0 / 3.0)
                .cornerRadius(6)
                .frame(height: 90)
                .clipped()
            Text(item.title)
                .font(.caption2).fontWeight(.semibold)
                .lineLimit(2)
            Text(item.lastChapter)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Large — 2 × 3 grid

    private func largeView(_ items: [ReadingItem]) -> some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(items, id: \.id) { item in
                largeCell(item)
            }
        }
        .padding(12)
        .containerBackground(.fill, for: .widget)
    }

    private func largeCell(_ item: ReadingItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            coverImage(urlString: item.coverURLString, aspectRatio: 2.0 / 3.0)
                .cornerRadius(6)
                .clipped()
            Text(item.title)
                .font(.caption2).fontWeight(.semibold)
                .lineLimit(2)
            Text(item.lastChapter)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: Cover helper

    @ViewBuilder
    private func coverImage(urlString: String?, width: CGFloat? = nil, aspectRatio: CGFloat? = nil) -> some View {
        if let urlStr = urlString, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    if let ar = aspectRatio {
                        img.resizable().aspectRatio(ar, contentMode: .fill)
                    } else {
                        img.resizable().scaledToFill()
                    }
                default:
                    coverPlaceholder(aspectRatio: aspectRatio)
                }
            }
        } else {
            coverPlaceholder(aspectRatio: aspectRatio)
        }
    }

    @ViewBuilder
    private func coverPlaceholder(aspectRatio: CGFloat?) -> some View {
        if let ar = aspectRatio {
            Color.secondary.opacity(0.3).aspectRatio(ar, contentMode: .fill)
        } else {
            Color.secondary.opacity(0.3)
        }
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
