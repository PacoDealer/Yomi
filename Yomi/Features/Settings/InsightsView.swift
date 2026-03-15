import SwiftUI

// MARK: - InsightsView

struct InsightsView: View {
    @State private var tracked: [Manga] = []

    var body: some View {
        Group {
            if tracked.isEmpty {
                ContentUnavailableView(
                    "No reading data",
                    systemImage: "chart.bar",
                    description: Text("Start reading to track your time.")
                )
            } else {
                List {
                    totalSection
                    byTitleSection
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Reading Insights")
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
    }

    // MARK: - Sections

    private var totalSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatTime(totalSeconds))
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Total reading time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var byTitleSection: some View {
        Section("By title") {
            ForEach(tracked) { manga in
                HStack(spacing: 12) {
                    AsyncImage(url: manga.coverURL) { image in
                        image
                            .resizable()
                            .aspectRatio(2 / 3, contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .aspectRatio(2 / 3, contentMode: .fit)
                    }
                    .frame(width: 40, height: 60)
                    .cornerRadius(4)
                    .clipped()

                    VStack(alignment: .leading, spacing: 3) {
                        Text(manga.title)
                            .font(.subheadline)
                        Text(formatTime(manga.readingSeconds))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Computed

    private var totalSeconds: Int {
        tracked.reduce(0) { $0 + $1.readingSeconds }
    }

    // MARK: - Load

    private func load() {
        let all = (try? MangaQueries.fetchAll()) ?? []
        tracked = all
            .filter { $0.readingSeconds > 0 }
            .sorted { $0.readingSeconds > $1.readingSeconds }
    }

    // MARK: - Formatting

    private func formatTime(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds) s"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes) m"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return "\(hours) h \(remainingMinutes) m"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        InsightsView()
    }
}
