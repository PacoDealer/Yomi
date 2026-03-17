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
                                HistoryRow(manga: manga)
                            }
                        }
                        .onDelete { offsets in
                            mangas.remove(atOffsets: offsets)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await loadHistory() }
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
            (try? MangaQueries.fetchHistory()) ?? []
        }.value
        await MainActor.run {
            mangas = result
            isLoading = false
        }
    }
}

// MARK: - HistoryRow

private struct HistoryRow: View {
    let manga: Manga

    private static let relativeFmt: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: manga.coverURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
            }
            .frame(width: 40, height: 40)
            .cornerRadius(6)
            .clipped()

            VStack(alignment: .leading, spacing: 3) {
                Text(manga.title)
                    .font(.headline)
                    .lineLimit(1)
                if let d = manga.lastReadAt {
                    Text(Self.relativeFmt.localizedString(for: d, relativeTo: Date()))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(manga.sourceId)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#Preview {
    HistoryView()
}
