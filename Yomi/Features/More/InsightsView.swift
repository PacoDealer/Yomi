import SwiftUI
import GRDB

// MARK: - InsightsView

struct InsightsView: View {

    // MARK: - State

    @State private var isLoading = true
    @State private var totalSeconds: Int = 0
    @State private var readChaptersCount: Int = 0
    @State private var mangaStats: [(title: String, seconds: Int)] = []

    // MARK: - Body

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else {
                List {
                    totalSection
                    byMangaSection
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadStats() }
    }

    // MARK: - Sections

    private var totalSection: some View {
        Section("Total") {
            LabeledContent("Time read", value: formatDuration(totalSeconds))
            LabeledContent("Chapters read", value: "\(readChaptersCount)")
        }
    }

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
        let (seconds, readCount, stats) = await Task.detached(priority: .userInitiated) {
            let allChapters = (try? appDatabase.read { try Chapter.fetchAll($0) }) ?? []
            let total = allChapters.reduce(0) { $0 + $1.readingSeconds }
            let readCount = allChapters.filter { $0.isRead }.count

            let allManga = (try? MangaQueries.fetchAll()) ?? []
            let chaptersByManga = Dictionary(grouping: allChapters, by: \.mangaId)
            let stats: [(title: String, seconds: Int)] = allManga.compactMap { manga in
                let secs = (chaptersByManga[manga.id] ?? []).reduce(0) { $0 + $1.readingSeconds }
                guard secs > 0 else { return nil }
                return (title: manga.title, seconds: secs)
            }
            .sorted { $0.seconds > $1.seconds }

            return (total, readCount, stats)
        }.value

        await MainActor.run {
            totalSeconds = seconds
            readChaptersCount = readCount
            mangaStats = stats
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
        if seconds >= 60 {
            return "\(seconds / 60)m"
        }
        return "\(seconds)s"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        InsightsView()
    }
}
