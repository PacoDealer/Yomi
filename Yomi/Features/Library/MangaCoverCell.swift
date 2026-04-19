import SwiftUI

// MARK: - MangaCoverCell

struct MangaCoverCell: View {
    let manga: Manga
    var isSelecting: Bool = false
    var isSelected: Bool = false
    var onLongPress: (() -> Void)? = nil
    var onSelect: (() -> Void)? = nil
    @State private var unreadCount: Int = 0
    @State private var downloadedCount: Int = 0
    @State private var sourceName: String? = nil
    @State private var readProgress: Double = 0   // 0.0 – 1.0, 0 = not started

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Navigation link — disabled while in selection mode
            NavigationLink {
                MangaDetailView(manga: manga)
            } label: {
                cellContent
            }
            .buttonStyle(.plain)
            .disabled(isSelecting)

            // Transparent tap target in selection mode
            if isSelecting {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect?() }
            }
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onLongPress?()
        }
        .overlay(alignment: .topLeading) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(isSelected ? .white : .white)
                    .background(
                        Circle()
                            .fill(isSelected ? Color.accentColor : Color.black.opacity(0.35))
                            .padding(1)
                    )
                    .padding(6)
            }
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: 2.5)
            }
        }
        .task(id: manga.id) {
            async let unread   = Task.detached { (try? ChapterQueries.fetchUnread(mangaId: manga.id))?.count ?? 0 }.value
            async let dlCount  = Task.detached { (try? ChapterQueries.downloadedCount(mangaId: manga.id)) ?? 0 }.value
            async let allChaps = Task.detached { (try? ChapterQueries.fetchAll(mangaId: manga.id)) ?? [] }.value
            let (u, d, all) = await (unread, dlCount, allChaps)
            unreadCount     = u
            downloadedCount = d
            sourceName = ExtensionManager.shared.installed.first(where: { $0.id == manga.sourceId })?.name
            if !all.isEmpty {
                let readCount = all.filter { $0.isRead }.count
                readProgress = Double(readCount) / Double(all.count)
            }
        }
    }

    private var cellContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if let customPath = manga.customCoverPath,
                   let uiImage = UIImage(contentsOfFile: customPath) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(2 / 3, contentMode: .fill)
                } else {
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
                }
            }
            .cornerRadius(8)
            .clipped()
            .overlay(alignment: .topTrailing) {
                if unreadCount > 0 && !isSelecting && AppSettings.shared.showUnreadBadge {
                    Text("\(unreadCount)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                        .padding(6)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if downloadedCount > 0 && !isSelecting {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Circle())
                        .padding(4)
                }
            }
            .overlay(alignment: .bottom) {
                if readProgress > 0 && readProgress < 1 && !isSelecting {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: geo.size.width * readProgress, height: 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 3)
                }
            }

            Text(manga.title)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(.primary)

            if let name = sourceName {
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
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
