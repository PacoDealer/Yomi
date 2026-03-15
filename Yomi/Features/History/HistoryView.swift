import SwiftUI

// MARK: - HistoryViewModel

@Observable
final class HistoryViewModel {
    var mangas: [Manga] = []

    func load() async {
        do {
            mangas = try MangaQueries.fetchHistory()
        } catch {
            mangas = []
        }
    }
}

// MARK: - HistoryView

struct HistoryView: View {
    @State private var viewModel = HistoryViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.mangas.isEmpty {
                    ContentUnavailableView(
                        "No history",
                        systemImage: "clock",
                        description: Text("Titles you read will appear here.")
                    )
                } else {
                    List(viewModel.mangas) { manga in
                        NavigationLink {
                            MangaDetailView(manga: manga)
                        } label: {
                            HistoryRow(manga: manga)
                        }
                    }
                }
            }
            .navigationTitle("History")
            .task { await viewModel.load() }
        }
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
                    .aspectRatio(2 / 3, contentMode: .fill)
            }
            .frame(width: 40, height: 60)
            .cornerRadius(6)
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(manga.title)
                    .font(.headline)
                    .lineLimit(2)

                if let readAt = manga.lastReadAt {
                    Text(readAt.formatted(.relative(presentation: .named)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#Preview {
    HistoryView()
}
