import SwiftUI
import GRDB

// MARK: - InsightsView

struct InsightsView: View {

    // MARK: - State

    @State private var isLoading = true
    @State private var streak: Int = 0
    @State private var readChaptersCount: Int = 0
    @State private var totalSeconds: Int = 0
    @State private var titlesStarted: Int = 0
    @State private var mangaStats: [(title: String, seconds: Int)] = []

    // Manga vs novel split
    @State private var mangaChaptersRead: Int = 0
    @State private var novelChaptersRead: Int = 0
    @State private var mangaSeconds: Int = 0
    @State private var novelSeconds: Int = 0

    private let cardColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    // MARK: - Body

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // MARK: Stat cards grid
                        LazyVGrid(columns: cardColumns, spacing: 12) {
                            StatCard(title: "Reading Streak",
                                     value: "\(streak)",
                                     unit: streak == 1 ? "day" : "days",
                                     systemImage: "flame.fill",
                                     color: .orange)
                            StatCard(title: "Chapters Read",
                                     value: "\(readChaptersCount)",
                                     unit: "chapters",
                                     systemImage: "book.closed.fill",
                                     color: .accentColor)
                            StatCard(title: "Time Read",
                                     value: formatDuration(totalSeconds),
                                     unit: nil,
                                     systemImage: "clock.fill",
                                     color: .purple)
                            StatCard(title: "Titles Started",
                                     value: "\(titlesStarted)",
                                     unit: "titles",
                                     systemImage: "square.stack.fill",
                                     color: .green)
                        }
                        .padding(.horizontal, 16)

                        // MARK: Manga vs Novel breakdown
                        if mangaChaptersRead > 0 || novelChaptersRead > 0 {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Breakdown")
                                    .font(.headline)
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 10)

                                VStack(spacing: 0) {
                                    breakdownRow(label: "Manga",
                                                 icon: "book.closed.fill",
                                                 chapters: mangaChaptersRead,
                                                 seconds: mangaSeconds)
                                    Divider().padding(.leading, 16)
                                    breakdownRow(label: "Novel",
                                                 icon: "text.book.closed.fill",
                                                 chapters: novelChaptersRead,
                                                 seconds: novelSeconds)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal, 16)
                            }
                        }

                        // MARK: By manga
                        if !mangaStats.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("By Title")
                                    .font(.headline)
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 10)

                                VStack(spacing: 0) {
                                    let maxSeconds = mangaStats.first?.seconds ?? 1
                                    ForEach(Array(mangaStats.enumerated()), id: \.element.title) { index, stat in
                                        ZStack(alignment: .leading) {
                                            GeometryReader { geo in
                                                Rectangle()
                                                    .fill(Color.accentColor.opacity(0.12))
                                                    .frame(width: geo.size.width * min(Double(stat.seconds) / Double(maxSeconds), 1.0))
                                            }
                                            HStack {
                                                Text(stat.title)
                                                    .font(.subheadline)
                                                    .lineLimit(1)
                                                Spacer()
                                                Text(formatDuration(stat.seconds))
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                                    .monospacedDigit()
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 12)
                                        }
                                        .frame(height: 44)
                                        .background(Color(.secondarySystemGroupedBackground))

                                        if index < mangaStats.count - 1 {
                                            Divider()
                                                .padding(.leading, 16)
                                        }
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                    .padding(.vertical, 16)
                }
                .background(Color(.systemGroupedBackground))
                .refreshable { await loadStats() }
            }
        }
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadStats() }
    }

    // MARK: - Load

    private func loadStats() async {
        let result = await Task.detached(priority: .userInitiated) { () -> (Int, Int, Int, Int, [(title: String, seconds: Int)], Int, Int, Int, Int) in

            let calendar = Calendar.current

            // --- Manga chapters ---
            let readMangaChapters = (try? appDatabase.read { db in
                try Chapter.filter(Column("readAt") != nil).fetchAll(db)
            }) ?? []

            // --- Novel chapters ---
            let readNovelChapters = (try? appDatabase.read { db in
                try NovelChapter.filter(Column("readAt") != nil).fetchAll(db)
            }) ?? []

            // --- Streak: union of both ---
            var days = Set(readMangaChapters.compactMap { ch -> DateComponents? in
                guard let d = ch.readAt else { return nil }
                return calendar.dateComponents([.year, .month, .day], from: d)
            })
            days.formUnion(readNovelChapters.compactMap { ch -> DateComponents? in
                guard let d = ch.readAt else { return nil }
                return calendar.dateComponents([.year, .month, .day], from: d)
            })

            var streak = 0
            var checking = calendar.dateComponents([.year, .month, .day], from: Date())
            while days.contains(checking) {
                streak += 1
                let date = calendar.date(from: checking)!
                let prev = calendar.date(byAdding: .day, value: -1, to: date)!
                checking = calendar.dateComponents([.year, .month, .day], from: prev)
            }
            if streak == 0 {
                let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
                var yc = calendar.dateComponents([.year, .month, .day], from: yesterday)
                while days.contains(yc) {
                    streak += 1
                    let date = calendar.date(from: yc)!
                    let prev = calendar.date(byAdding: .day, value: -1, to: date)!
                    yc = calendar.dateComponents([.year, .month, .day], from: prev)
                }
            }

            // --- Chapters read + time ---
            let allMangaChapters = (try? appDatabase.read { try Chapter.fetchAll($0) }) ?? []
            let allNovelChapters = (try? appDatabase.read { try NovelChapter.fetchAll($0) }) ?? []

            let mangaSeconds = allMangaChapters.reduce(0) { $0 + $1.readingSeconds }
            let novelSeconds = allNovelChapters.reduce(0) { $0 + $1.readingSeconds }
            let totalSeconds = mangaSeconds + novelSeconds

            let mangaReadCount = allMangaChapters.filter { $0.isRead }.count
            let novelReadCount = allNovelChapters.filter { $0.isRead }.count
            let readCount = mangaReadCount + novelReadCount

            // --- Titles started ---
            let allManga = (try? MangaQueries.fetchAll()) ?? []
            let allNovels = (try? NovelQueries.fetchAll()) ?? []
            let chaptersByManga = Dictionary(grouping: allMangaChapters, by: \.mangaId)
            let chaptersByNovel = Dictionary(grouping: allNovelChapters, by: \.novelId)

            let mangaTitlesStarted = allManga.filter { manga in
                (chaptersByManga[manga.id] ?? []).reduce(0) { $0 + $1.readingSeconds } > 0
            }.count
            let novelTitlesStarted = allNovels.filter { novel in
                (chaptersByNovel[novel.id] ?? []).reduce(0) { $0 + $1.readingSeconds } > 0
            }.count
            let titlesStarted = mangaTitlesStarted + novelTitlesStarted

            // --- By title (manga + novels merged) ---
            let mangaStats: [(title: String, seconds: Int)] = allManga.compactMap { manga in
                let secs = (chaptersByManga[manga.id] ?? []).reduce(0) { $0 + $1.readingSeconds }
                guard secs > 0 else { return nil }
                return (title: manga.title, seconds: secs)
            }
            let novelStats: [(title: String, seconds: Int)] = allNovels.compactMap { novel in
                let secs = (chaptersByNovel[novel.id] ?? []).reduce(0) { $0 + $1.readingSeconds }
                guard secs > 0 else { return nil }
                return (title: novel.title, seconds: secs)
            }
            let stats = (mangaStats + novelStats).sorted { $0.seconds > $1.seconds }

            return (streak, totalSeconds, readCount, titlesStarted, stats, mangaReadCount, novelReadCount, mangaSeconds, novelSeconds)
        }.value

        await MainActor.run {
            streak              = result.0
            totalSeconds        = result.1
            readChaptersCount   = result.2
            titlesStarted       = result.3
            mangaStats          = result.4
            mangaChaptersRead   = result.5
            novelChaptersRead   = result.6
            self.mangaSeconds   = result.7
            self.novelSeconds   = result.8
            isLoading = false
        }
    }

    // MARK: - Formatting

    private func formatDuration(_ seconds: Int) -> String {
        if seconds >= 3600 {
            let h = seconds / 3600
            let m = (seconds % 3600) / 60
            return "\(h)h \(m)m"
        }
        if seconds >= 60 { return "\(seconds / 60)m" }
        return "\(seconds)s"
    }

    @ViewBuilder
    private func breakdownRow(label: String, icon: String, chapters: Int, seconds: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
            Text(label)
                .font(.subheadline)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(chapters) chapters")
                    .font(.subheadline)
                    .monospacedDigit()
                if seconds > 0 {
                    Text(formatDuration(seconds))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
    }
}

// MARK: - StatCard

private struct StatCard: View {
    let title: String
    let value: String
    let unit: String?
    let systemImage: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                if let unit {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(title)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        InsightsView()
    }
}
