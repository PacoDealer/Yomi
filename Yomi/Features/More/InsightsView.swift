import SwiftUI
import GRDB
import Kingfisher

// MARK: - InsightsView
//
// S146 calm pass (RESEARCH §26): system nav bar, numbers on the canvas instead of cards, bold sentence-case
// section titles, no mono caps. Same data as before.

struct InsightsView: View {

    @Environment(\.yomiCanvas) private var canvas

    // MARK: - State

    @State private var isLoading = true
    @State private var streak: Int = 0
    @State private var readChaptersCount: Int = 0
    @State private var totalSeconds: Int = 0
    @State private var titlesStarted: Int = 0
    @State private var mostRead: [(title: String, seconds: Int, coverURL: URL?, customCoverPath: String?)] = []
    @State private var readingCalendar: [DateComponents: Int] = [:]

    private let statColumns = [
        GridItem(.flexible(), spacing: 16, alignment: .leading),
        GridItem(.flexible(), spacing: 16, alignment: .leading)
    ]

    // MARK: - Body

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        LazyVGrid(columns: statColumns, alignment: .leading, spacing: 22) {
                            stat(num: "\(streak)", label: "Day streak")
                            stat(num: readChaptersCount.formatted(), label: "Chapters read")
                            stat(num: formatDuration(totalSeconds), label: "Time reading")
                            stat(num: titlesStarted.formatted(), label: "Titles started")
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 32)

                        sectionTitle("Activity")
                        ActivityHeatmap(calendarMap: readingCalendar)
                            .padding(.bottom, 32)

                        if !mostRead.isEmpty {
                            sectionTitle("Most read")
                            VStack(spacing: 16) {
                                ForEach(mostRead, id: \.title) { stat in
                                    MostReadRow(
                                        title: stat.title,
                                        seconds: stat.seconds,
                                        coverURL: stat.coverURL,
                                        customCoverPath: stat.customCoverPath,
                                        maxSeconds: mostRead.first?.seconds ?? 1
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, YomiTokens.Layout.screenMargin)
                    .padding(.bottom, 28)
                }
                .refreshable { await loadStats() }
            }
        }
        .background(canvas.bg.ignoresSafeArea())
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadStats() }
    }

    // MARK: - Pieces

    private func stat(num: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(num)
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .foregroundStyle(canvas.textPrimary)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(canvas.textSecondary)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .foregroundStyle(canvas.textPrimary)
            .padding(.bottom, 12)
    }

    // MARK: - Load

    private func loadStats() async {
        let result = await Task.detached(priority: .userInitiated) { () -> (
            Int, Int, Int, Int,
            [(title: String, seconds: Int, coverURL: URL?, customCoverPath: String?)],
            [DateComponents: Int]
        ) in

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

            let readCount = allMangaChapters.filter { $0.isRead }.count + allNovelChapters.filter { $0.isRead }.count

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

            // --- Most read (manga + novels merged, top 5 by time spent) ---
            let mangaStats: [(title: String, seconds: Int, coverURL: URL?, customCoverPath: String?)] = allManga.compactMap { manga in
                let secs = (chaptersByManga[manga.id] ?? []).reduce(0) { $0 + $1.readingSeconds }
                guard secs > 0 else { return nil }
                return (manga.title, secs, manga.coverURL, manga.resolvedCustomCoverPath)
            }
            let novelStats: [(title: String, seconds: Int, coverURL: URL?, customCoverPath: String?)] = allNovels.compactMap { novel in
                let secs = (chaptersByNovel[novel.id] ?? []).reduce(0) { $0 + $1.readingSeconds }
                guard secs > 0 else { return nil }
                return (novel.title, secs, novel.coverURL, novel.resolvedCustomCoverPath)
            }
            let mostRead = Array((mangaStats + novelStats).sorted { $0.seconds > $1.seconds }.prefix(5))

            // --- Reading activity calendar (day → chapters read) ---
            var calendarMap: [DateComponents: Int] = [:]
            for ch in readMangaChapters {
                guard let d = ch.readAt else { continue }
                let dc = calendar.dateComponents([.year, .month, .day], from: d)
                calendarMap[dc, default: 0] += 1
            }
            for ch in readNovelChapters {
                guard let d = ch.readAt else { continue }
                let dc = calendar.dateComponents([.year, .month, .day], from: d)
                calendarMap[dc, default: 0] += 1
            }

            return (streak, totalSeconds, readCount, titlesStarted, mostRead, calendarMap)
        }.value

        await MainActor.run {
            streak            = result.0
            totalSeconds      = result.1
            readChaptersCount = result.2
            titlesStarted     = result.3
            mostRead          = result.4
            readingCalendar   = result.5
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

// MARK: - ActivityHeatmap

private struct ActivityHeatmap: View {
    let calendarMap: [DateComponents: Int]

    @Environment(\.yomiCanvas) private var canvas

    private let weeks = 22
    private let gap: CGFloat = 3
    private let cal = Calendar.current

    private var days: [(date: Date, count: Int)] {
        let today = cal.startOfDay(for: Date())
        return (0..<(weeks * 7)).reversed().map { offset in
            let date = cal.date(byAdding: .day, value: -offset, to: today)!
            let dc = cal.dateComponents([.year, .month, .day], from: date)
            return (date, calendarMap[dc] ?? 0)
        }
    }

    private var maxCount: Int { days.map(\.count).max() ?? 0 }

    private func opacity(for count: Int) -> Double {
        guard count > 0, maxCount > 0 else { return 0.08 }
        let frac = Double(count) / Double(maxCount)
        if frac > 0.75 { return 1.0 }
        if frac > 0.5  { return 0.8 }
        if frac > 0.25 { return 0.45 }
        return 0.14
    }

    private var edgeMonths: (first: String, last: String) {
        let f = DateFormatter(); f.dateFormat = "MMM"
        let d = days
        return (f.string(from: d.first!.date), f.string(from: d.last!.date))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 10) {
                let dayCounts = days
                HStack(alignment: .top, spacing: gap) {
                    ForEach(0..<weeks, id: \.self) { weekIdx in
                        VStack(spacing: gap) {
                            ForEach(0..<7, id: \.self) { dayIdx in
                                let index = weekIdx * 7 + dayIdx
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.accentColor.opacity(opacity(for: dayCounts[index].count)))
                                    .aspectRatio(1, contentMode: .fit)
                            }
                        }
                    }
                }

                HStack {
                    Text(edgeMonths.first)
                    Spacer()
                    HStack(spacing: 5) {
                        Text("Less")
                        ForEach([0.14, 0.45, 0.8, 1.0], id: \.self) { op in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.accentColor.opacity(op))
                                .frame(width: 9, height: 9)
                        }
                        Text("More")
                    }
                    Spacer()
                    Text(edgeMonths.last)
                }
                .font(.caption)
                .foregroundStyle(canvas.textSecondary)
            }
        }
    }
}

// MARK: - MostReadRow

private struct MostReadRow: View {
    let title: String
    let seconds: Int
    let coverURL: URL?
    let customCoverPath: String?
    let maxSeconds: Int

    @Environment(\.yomiCanvas) private var canvas

    private var fraction: Double {
        guard maxSeconds > 0 else { return 0 }
        return min(Double(seconds) / Double(maxSeconds), 1.0)
    }

    var body: some View {
        HStack(spacing: 12) {
            cover

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(canvas.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Notation.readingTimeShort(seconds: seconds))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(canvas.textSecondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(canvas.hairline)
                        Capsule().fill(Color.accentColor).frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: 4)
            }
        }
    }

    private var cover: some View {
        Group {
            if let path = customCoverPath, let uiImage = UIImage(contentsOfFile: path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(2 / 3, contentMode: .fill)
                    .coverAspectSized()
            } else {
                CoverImage(url: coverURL)
            }
        }
        .frame(width: 40)
        .clipShape(RoundedRectangle(cornerRadius: YomiTokens.Radius.thumb))
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        InsightsView()
    }
}
