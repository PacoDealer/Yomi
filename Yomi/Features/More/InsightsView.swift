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

    // MARK: - Body

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else {
                List {
                    cardsSection
                    byMangaSection
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadStats() }
    }

    // MARK: - Cards Section

    private var cardsSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    StatCard(title: "Reading Streak",
                             value: "\(streak) days",
                             systemImage: "flame")
                    StatCard(title: "Chapters Read",
                             value: "\(readChaptersCount)",
                             systemImage: "book.closed")
                    StatCard(title: "Time Read",
                             value: formatDuration(totalSeconds),
                             systemImage: "clock")
                    StatCard(title: "Titles Started",
                             value: "\(titlesStarted)",
                             systemImage: "square.stack")
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - By Manga Section

    private var byMangaSection: some View {
        Section("By manga") {
            if mangaStats.isEmpty {
                Text("No reading data yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(mangaStats, id: \.title) { stat in
                    LabeledContent(stat.title, value: formatDuration(stat.seconds))
                }
            }
        }
    }

    // MARK: - Load

    private func loadStats() async {
        let result = await Task.detached(priority: .userInitiated) { () -> (Int, Int, Int, Int, [(title: String, seconds: Int)]) in

            // Chapters with readAt for streak computation
            let readChapters = (try? appDatabase.read { db in
                try Chapter.filter(Column("readAt") != nil).fetchAll(db)
            }) ?? []

            // Distinct calendar days with reads
            let calendar = Calendar.current
            let days = Set(readChapters.compactMap { ch -> DateComponents? in
                guard let d = ch.readAt else { return nil }
                return calendar.dateComponents([.year, .month, .day], from: d)
            })

            // Count consecutive days ending today
            var streak = 0
            var checking = calendar.dateComponents([.year, .month, .day], from: Date())
            while days.contains(checking) {
                streak += 1
                let date = calendar.date(from: checking)!
                let prev = calendar.date(byAdding: .day, value: -1, to: date)!
                checking = calendar.dateComponents([.year, .month, .day], from: prev)
            }
            // If today has no reads yet, check from yesterday (streak still alive)
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

            // All chapters for time + read count
            let allChapters = (try? appDatabase.read { try Chapter.fetchAll($0) }) ?? []
            let totalSeconds = allChapters.reduce(0) { $0 + $1.readingSeconds }
            let readCount = allChapters.filter { $0.isRead }.count

            // Manga stats
            let allManga = (try? MangaQueries.fetchAll()) ?? []
            let chaptersByManga = Dictionary(grouping: allChapters, by: \.mangaId)
            let titlesStarted = allManga.filter { manga in
                (chaptersByManga[manga.id] ?? []).reduce(0) { $0 + $1.readingSeconds } > 0
            }.count
            let stats: [(title: String, seconds: Int)] = allManga.compactMap { manga in
                let secs = (chaptersByManga[manga.id] ?? []).reduce(0) { $0 + $1.readingSeconds }
                guard secs > 0 else { return nil }
                return (title: manga.title, seconds: secs)
            }.sorted { $0.seconds > $1.seconds }

            return (streak, totalSeconds, readCount, titlesStarted, stats)
        }.value

        await MainActor.run {
            streak = result.0
            totalSeconds = result.1
            readChaptersCount = result.2
            titlesStarted = result.3
            mangaStats = result.4
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
}

// MARK: - StatCard

private struct StatCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(14)
        .frame(width: 160, height: 100, alignment: .leading)
        .background(Color.accentColor)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        InsightsView()
    }
}
