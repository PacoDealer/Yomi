import SwiftUI

// MARK: - MangaCoverCell

struct MangaCoverCell: View {
    let manga: Manga

    var body: some View {
        NavigationLink {
            MangaDetailView(manga: manga)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                AsyncImage(url: manga.coverURL) { image in
                    image
                        .resizable()
                        .aspectRatio(2 / 3, contentMode: .fill)
                } placeholder: {
                    ShimmerView()
                        .aspectRatio(2 / 3, contentMode: .fit)
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

// MARK: - ShimmerView

private struct ShimmerView: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            let _ = geo.size.width
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.secondary.opacity(0.15), location: 0),
                            .init(color: Color.secondary.opacity(0.35), location: 0.3 + phase * 0.3),
                            .init(color: Color.secondary.opacity(0.15), location: 0.6 + phase * 0.3),
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                phase = 1
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
