import SwiftUI

struct MangaDetailView: View {
    let manga: Manga

    @State private var synopsisExpanded = false

    var body: some View {
        List {
            // MARK: Header
            Section {
                HStack(alignment: .top, spacing: 12) {
                    // Portada
                    AsyncImage(url: manga.coverURL) { image in
                        image
                            .resizable()
                            .aspectRatio(2 / 3, contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .aspectRatio(2 / 3, contentMode: .fit)
                    }
                    .frame(width: 120)
                    .cornerRadius(8)
                    .clipped()

                    // Metadata
                    VStack(alignment: .leading, spacing: 6) {
                        Text(manga.title)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)

                        if let author = manga.author {
                            Text(author)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        StatusBadge(status: manga.status)

                        if !manga.genres.isEmpty {
                            Text(manga.genres.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // MARK: Synopsis
            Section("Synopsis") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(manga.summary ?? "No synopsis available.")
                        .font(.subheadline)
                        .lineLimit(synopsisExpanded ? nil : 4)

                    Button(synopsisExpanded ? "Less" : "More") {
                        synopsisExpanded.toggle()
                    }
                    .font(.subheadline)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
            }

            // MARK: Chapters
            Section("Chapters") {
                Text("No chapters available.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(manga.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // agregar/quitar de biblioteca — próximamente
                } label: {
                    Image(systemName: manga.inLibrary ? "heart.fill" : "heart")
                        .foregroundStyle(manga.inLibrary ? .red : .primary)
                }
            }
        }
    }
}

// MARK: - Status Badge

private struct StatusBadge: View {
    let status: MangaStatus

    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch status {
        case .ongoing:   .green
        case .completed: .blue
        case .hiatus:    .orange
        case .cancelled: .red
        case .unknown:   .gray
        }
    }
}

#Preview {
    NavigationStack {
        MangaDetailView(manga: Manga(
            id: "1", path: "/berserk", sourceId: "en.mangadex",
            title: "Berserk",
            coverURL: nil,
            summary: "Guts, a former mercenary now known as the 'Black Swordsman', is on a hunt for revenge. After a tumultuous childhood, he finally finds someone he respects and admires: Griffith, the leader of a mercenary band called the Band of the Hawk.",
            author: "Kentaro Miura", artist: "Kentaro Miura",
            status: .hiatus,
            genres: ["Action", "Dark Fantasy", "Adventure"],
            inLibrary: true, isLocal: false, lastReadAt: nil, lastUpdatedAt: nil
        ))
    }
}
