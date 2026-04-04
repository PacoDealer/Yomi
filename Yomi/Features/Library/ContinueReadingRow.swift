import SwiftUI

// MARK: - ContinueReadingRow

struct ContinueReadingRow: View {
    @State private var items: [Manga] = []

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Continue Reading")
                        .font(.headline)
                        .padding(.horizontal)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(items) { manga in
                                ContinueReadingCell(manga: manga)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
        .task {
            let loaded = await Task.detached(priority: .userInitiated) {
                (try? MangaQueries.fetchRecentlyRead(limit: 10)) ?? []
            }.value
            await MainActor.run { items = loaded }
        }
    }
}

// MARK: - ContinueReadingCell

private struct ContinueReadingCell: View {
    let manga: Manga

    var body: some View {
        NavigationLink(destination: MangaDetailView(manga: manga)) {
            VStack(spacing: 4) {
                AsyncImage(url: manga.coverURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(2 / 3, contentMode: .fill)
                    case .failure:
                        Rectangle()
                            .fill(.quaternary)
                            .aspectRatio(2 / 3, contentMode: .fill)
                            .overlay {
                                Image(systemName: "book.closed")
                                    .foregroundStyle(.secondary)
                            }
                    default:
                        Rectangle()
                            .fill(.quaternary)
                            .aspectRatio(2 / 3, contentMode: .fill)
                    }
                }
                .frame(width: 80)
                .cornerRadius(6)
                .clipped()

                Text(manga.title)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 80)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}
