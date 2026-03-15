import SwiftUI

struct NovelDetailView: View {
    let novel: Novel
    let bridge: JSBridge

    // MARK: - State

    @State private var synopsisExpanded = false
    @State private var chapters: [NovelChapter] = []
    @State private var isLoadingChapters = false
    @State private var isInLibrary: Bool

    init(novel: Novel, bridge: JSBridge) {
        self.novel = novel
        self.bridge = bridge
        _isInLibrary = State(initialValue: novel.inLibrary)
    }

    // MARK: - Body

    var body: some View {
        List {
            // MARK: Header
            Section {
                HStack(alignment: .top, spacing: 12) {
                    AsyncImage(url: novel.coverURL) { image in
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
                        Text(novel.title)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)

                        if let author = novel.author {
                            Text(author)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        NovelStatusBadge(status: novel.status)

                        if !novel.genres.isEmpty {
                            Text(novel.genres.joined(separator: ", "))
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
                    Text(novel.summary ?? "No synopsis available.")
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
                    Text("No chapters found.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(chapters) { chapter in
                        NavigationLink {
                            TextReaderView(chapter: chapter, novel: novel, bridge: bridge)
                        } label: {
                            NovelChapterRow(chapter: chapter)
                        }
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
        .navigationTitle(novel.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isInLibrary.toggle()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task { await toggleLibrary() }
                } label: {
                    Image(systemName: isInLibrary ? "heart.fill" : "heart")
                        .foregroundStyle(isInLibrary ? .red : .primary)
                }
            }
        }
        .task { await loadChapters() }
    }

    // MARK: - Toggle Library

    private func toggleLibrary() async {
        var updated = novel
        updated.inLibrary = isInLibrary
        try? NovelQueries.upsert(updated)
    }

    // MARK: - Load Chapters

    private func loadChapters() async {
        isLoadingChapters = true
        let path = novel.path

        let source = await Task.detached(priority: .userInitiated) {
            bridge.parseNovel(path: path)
        }.value

        if let source {
            chapters = source.chapters.enumerated().map { index, c in
                NovelChapter(
                    id:            "\(novel.id)-ch-\(index)",
                    novelId:       novel.id,
                    path:          c.path,
                    name:          c.name,
                    chapterNumber: c.chapterNumber,
                    isRead:        false,
                    readAt:        nil,
                    releaseTime:   c.releaseTime
                )
            }
        }
        isLoadingChapters = false
    }
}

// MARK: - NovelChapterRow

private struct NovelChapterRow: View {
    let chapter: NovelChapter

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(chapter.name)
                .font(.subheadline)
                .foregroundStyle(chapter.isRead ? .secondary : .primary)
            if let release = chapter.releaseTime {
                Text(release)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - NovelStatusBadge

private struct NovelStatusBadge: View {
    let status: String

    var body: some View {
        Text(status.capitalized)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch status.lowercased() {
        case "ongoing":   .green
        case "completed": .blue
        case "hiatus":    .orange
        case "cancelled": .red
        default:          .gray
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        NovelDetailView(
            novel: Novel(
                id: "1",
                path: "/novel/re-zero",
                sourceId: "en.royalroad",
                title: "Re:Zero − Starting Life in Another World",
                coverURL: nil,
                summary: "Subaru Natsuki is an ordinary high school student who is suddenly summoned to another world on his way home from a convenience store.",
                author: "Tappei Nagatsuki",
                status: "ongoing",
                genres: ["Fantasy", "Isekai", "Drama"],
                inLibrary: false,
                lastReadAt: nil,
                lastUpdatedAt: nil
            ),
            bridge: JSBridge(scriptURL: Bundle.main.url(forResource: "test-source", withExtension: "js")!)!
        )
    }
}
