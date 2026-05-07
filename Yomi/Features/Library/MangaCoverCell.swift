import SwiftUI

// MARK: - MangaCoverCell

struct MangaCoverCell: View {
    let manga: Manga
    var isSelecting: Bool = false
    var isSelected: Bool = false
    var onLongPress: (() -> Void)? = nil
    var onSelect: (() -> Void)? = nil
    var onReadingStatusChange: ((ReadingStatus) -> Void)? = nil
    var onRemoveFromLibrary: (() -> Void)? = nil
    @State private var unreadCount: Int = 0
    @State private var downloadedCount: Int = 0
    @State private var sourceName: String? = nil
    @State private var readProgress: Double = 0   // 0.0 – 1.0, 0 = not started
    @State private var dbInLibrary: Bool = false
    @State private var currentReadingStatus: ReadingStatus = .none

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
        .contextMenu {
            if !isSelecting {
                Menu {
                    ForEach(ReadingStatus.allCases) { status in
                        Button {
                            onReadingStatusChange?(status)
                            currentReadingStatus = status
                        } label: {
                            Label(status.label, systemImage: status.systemImage)
                            if currentReadingStatus == status {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                } label: {
                    Label("Reading Status", systemImage: "bookmark")
                }
                Divider()
                Button(role: .destructive) {
                    onRemoveFromLibrary?()
                } label: {
                    Label("Remove from Library", systemImage: "trash")
                }
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
            async let dbManga  = Task.detached { try? MangaQueries.fetchOne(id: manga.id) }.value
            let (u, d, all, fetched) = await (unread, dlCount, allChaps, dbManga)
            unreadCount            = u
            downloadedCount        = d
            dbInLibrary            = fetched?.inLibrary ?? false
            currentReadingStatus   = fetched?.readingStatus ?? manga.readingStatus
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
            .overlay(alignment: .topLeading) {
                if !manga.inLibrary && dbInLibrary && !isSelecting {
                    Image(systemName: "bookmark.fill")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Color.accentColor.opacity(0.9), in: RoundedRectangle(cornerRadius: 4))
                        .padding(5)
                }
            }
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

// MARK: - MangaListRow

struct MangaListRow: View {
    let manga: Manga
    let unreadCount: Int

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: manga.coverURL) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Color.secondary.opacity(0.15)
            }
            .frame(width: 48, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(manga.title)
                    .font(.body)
                    .lineLimit(2)
                Text(manga.author ?? manga.sourceId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if unreadCount > 0 {
                    Text("\(unreadCount) unread")
                        .font(.caption2)
                        .foregroundStyle(.tint)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
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
