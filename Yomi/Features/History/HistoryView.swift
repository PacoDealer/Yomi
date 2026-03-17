import SwiftUI
import GRDB

// MARK: - HistoryView

struct HistoryView: View {

    // MARK: - State

    @State private var mangas: [Manga] = []
    @State private var isLoading = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if mangas.isEmpty {
                    ContentUnavailableView(
                        "No history",
                        systemImage: "clock",
                        description: Text("Titles you've read will appear here.")
                    )
                } else {
                    List {
                        ForEach(mangas) { manga in
                            NavigationLink {
                                MangaDetailView(manga: manga)
                            } label: {
                                HistoryRow(manga: manga)
                            }
                        }
                        .onDelete { offsets in
                            mangas.remove(atOffsets: offsets)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
            .task { await loadHistory() }
        }
    }

    // MARK: - Load

    private func loadHistory() async {
        isLoading = true
        let result = await Task.detached {
            (try? appDatabase.read { db in
                try Manga
                    .filter(sql: "lastReadAt IS NOT NULL")
                    .order(sql: "lastReadAt DESC")
                    .fetchAll(db)
            }) ?? []
        }.value
        mangas = result
        isLoading = false
    }
}

// MARK: - HistoryRow

private struct HistoryRow: View {
    let manga: Manga

    var body: some View {
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
            .frame(width: 52, height: 78)
            .cornerRadius(6)
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(manga.title)
                    .font(.headline)
                    .lineLimit(1)
                if let d = manga.lastReadAt {
                    Text("\(Text(d, style: .relative)) ago")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
                .font(.caption)
        }
    }
}

// MARK: - Preview

#Preview {
    HistoryView()
}
