import SwiftUI

struct MangaCoverCell: View {
    let manga: Manga

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AsyncImage(url: manga.coverURL) { image in
                image
                    .resizable()
                    .aspectRatio(2 / 3, contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
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
}

#Preview {
    MangaCoverCell(manga: Manga(
        id: "1", path: "/chainsaw-man", sourceId: "en.mangadex",
        title: "Chainsaw Man", coverURL: nil, summary: nil,
        author: "Tatsuki Fujimoto", artist: "Tatsuki Fujimoto",
        status: .ongoing, genres: ["Acción", "Horror"],
        inLibrary: true, isLocal: false, lastReadAt: nil, lastUpdatedAt: nil
    ))
    .frame(width: 160)
    .padding()
}
