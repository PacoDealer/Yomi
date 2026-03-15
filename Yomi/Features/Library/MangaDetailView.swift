import SwiftUI

struct MangaDetailView: View {
    let manga: Manga

    @State private var synopsisExpanded = false
    @State private var chapters: [Chapter] = []
    @State private var bridge: JSBridge? = nil
    @State private var isLoadingChapters = false

    var body: some View {
        List {
            // MARK: Header
            Section {
                HStack(alignment: .top, spacing: 12) {
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
            Section {
                if isLoadingChapters {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 4)
                } else if chapters.isEmpty {
                    Text(bridge == nil ? "No source available for this manga." : "No chapters found.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(chapters) { chapter in
                        NavigationLink {
                            ChapterReaderView(chapter: chapter, manga: manga, bridge: bridge!)
                        } label: {
                            ChapterRow(chapter: chapter)
                        }
                        .disabled(bridge == nil)
                    }
                }
            } header: {
                HStack {
                    Text("Chapters")
                    if !chapters.isEmpty {
                        Text("(\(chapters.count))")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(manga.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // add/remove from library — coming soon
                } label: {
                    Image(systemName: manga.inLibrary ? "heart.fill" : "heart")
                        .foregroundStyle(manga.inLibrary ? .red : .primary)
                }
            }
        }
        .task { await loadChapters() }
    }

    // MARK: Load chapters

    private func loadChapters() async {
        let sourceId = manga.sourceId
        let mangaPath = manga.path
        let mangaId = manga.id

        let ext = ExtensionManager.shared.installed.first(where: { $0.id == sourceId })
        guard let ext else { return }

        isLoadingChapters = true

        let (loadedBridge, loadedChapters) = await Task.detached(priority: .userInitiated) {
            let b = JSBridge(scriptURL: ext.sourceListURL)
            let chapters = b?.getChapterList(mangaPath: mangaPath, mangaId: mangaId) ?? []
            return (b, chapters)
        }.value

        bridge = loadedBridge
        chapters = loadedChapters
        isLoadingChapters = false
    }
}

// MARK: - ChapterRow

private struct ChapterRow: View {
    let chapter: Chapter

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(chapter.name)
                .font(.subheadline)
                .foregroundStyle(chapter.isRead ? .secondary : .primary)
            if let number = chapter.chapterNumber {
                Text("Chapter \(number, specifier: "%.1f")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - StatusBadge

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

// MARK: - Preview

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
