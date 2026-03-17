import SwiftUI

// MARK: - MangaCoverCell

struct MangaCoverCell: View {
    let manga: Manga

    var body: some View {
        NavigationLink {
            MangaDetailView(manga: manga)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                AsyncImage(url: manga.coverURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(2 / 3, contentMode: .fill)
                    case .failure:
                        SkeletonView(showIcon: true)
                            .aspectRatio(2 / 3, contentMode: .fit)
                    default:
                        SkeletonView(showIcon: false)
                            .aspectRatio(2 / 3, contentMode: .fit)
                    }
                }
                .cornerRadius(8)
                .clipped()

                Text(manga.title)
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SkeletonView

private struct SkeletonView: View {
    let showIcon: Bool

    @State private var shimmerPhase: CGFloat = 0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 0)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.secondary.opacity(0.15),
                            Color.secondary.opacity(0.35),
                            Color.secondary.opacity(0.15)
                        ],
                        startPoint: UnitPoint(x: shimmerPhase - 0.5, y: 0),
                        endPoint:   UnitPoint(x: shimmerPhase + 0.5, y: 0)
                    )
                )
                .onAppear {
                    withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                        shimmerPhase = 1
                    }
                }

            if showIcon {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary.opacity(0.6))
            }
        }
    }
}

// MARK: - Preview

#Preview {
    MangaCoverCell(manga: Manga(
        id: "1", path: "/chainsaw-man", sourceId: "en.mangadex",
        title: "Chainsaw Man", coverURL: nil, summary: nil,
        author: "Tatsuki Fujimoto", artist: "Tatsuki Fujimoto",
        status: .ongoing, genres: ["Acción", "Horror"],
        inLibrary: true, isLocal: false, lastReadAt: nil, lastUpdatedAt: nil, readingSeconds: 0
    ))
    .frame(width: 160)
    .padding()
}
