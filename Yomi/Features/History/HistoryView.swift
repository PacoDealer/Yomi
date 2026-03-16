import SwiftUI

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
                        description: Text("Manga you read will appear here.")
                    )
                } else {
                    List {
                        ForEach(mangas) { manga in
                            NavigationLink {
                                MangaDetailView(manga: manga)
                            } label: {
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
                                    .frame(width: 48, height: 72)
                                    .cornerRadius(6)
                                    .clipped()

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(manga.title)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .lineLimit(2)
                                        if let date = manga.lastReadAt {
                                            Text(date.formatted(.relative(presentation: .named)))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !mangas.isEmpty {
                        Button("Clear") { clearHistory() }
                            .foregroundStyle(.red)
                    }
                }
            }
            .task { await loadHistory() }
        }
    }

    // MARK: - Load

    private func loadHistory() async {
        isLoading = true
        let result = await Task.detached {
            (try? MangaQueries.fetchRecentlyRead()) ?? []
        }.value
        await MainActor.run {
            mangas = result
            isLoading = false
        }
    }

    // MARK: - Clear

    private func clearHistory() {
        for manga in mangas {
            var m = manga
            m.lastReadAt = nil
            Task.detached { try? MangaQueries.upsert(m) }
        }
        mangas = []
    }
}

// MARK: - Preview

#Preview {
    HistoryView()
}
