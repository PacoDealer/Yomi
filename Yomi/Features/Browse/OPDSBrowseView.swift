import SwiftUI
import Kingfisher

// MARK: - OPDSBrowseView
// Fetches and displays one OPDS feed (navigation or acquisition).
// Navigation entries drill down; acquisition entries open a detail sheet.

struct OPDSBrowseView: View {
    @Environment(\.yomiCanvas) private var canvas
    let title: String
    let feedHref: String

    @State private var feed: OPDSFeed? = nil
    @State private var allEntries: [OPDSEntry] = []
    @State private var nextHref: String? = nil
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String? = nil
    @State private var selectedEntry: OPDSEntry? = nil

    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 160), spacing: 12)]

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                YomiEmptyState(
                    systemImage: "exclamationmark.triangle",
                    title: "Failed to load",
                    message: error
                )
            } else if feed != nil {
                feedView(allEntries)
            } else {
                // MUST stay non-empty. A `Group` distributes its modifiers to its children, so
                // when every branch above was false — which is exactly the initial state, since
                // `isLoading` starts false and `feed` starts nil — the Group had *zero* children
                // and `.task`/`.navigationTitle` below attached to nothing. `load()` therefore
                // never ran, nothing ever set `isLoading`, and the view stayed empty forever:
                // drilling into any OPDS navigation entry showed a permanently blank screen with
                // no title and no network request at all (Known Issue #163).
                Color.clear
            }
        }
        // Covers the loading/error/grid paths; the two List paths paint their own via
        // `.yomiListCanvas()` (Known Issue #116).
        .background(canvas.bg.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(item: $selectedEntry) { entry in
            OPDSItemDetailView(entry: entry)
        }
    }

    // MARK: Feed content

    @ViewBuilder
    private func feedView(_ entries: [OPDSEntry]) -> some View {
        if entries.isEmpty {
            YomiEmptyState(systemImage: "tray", title: "No items", message: "This feed has nothing to show yet.")
        } else if entries.allSatisfy({ $0.isNavigation }) {
            // All navigation → show as list (can drill deeper)
            navigationList(entries: entries)
        } else if entries.allSatisfy({ !$0.isNavigation }) {
            // All acquisition → show as cover grid
            acquisitionGrid(entries: entries)
        } else {
            // Mixed — split into two sections
            List {
                if let navEntries = nonEmptyFilter(entries, isNav: true) {
                    Section("Categories") {
                        ForEach(navEntries) { entry in
                            navRow(entry)
                        }
                    }
                }
                if let acqEntries = nonEmptyFilter(entries, isNav: false) {
                    Section("Books (\(acqEntries.count))") {
                        ForEach(acqEntries) { entry in
                            acqRow(entry)
                        }
                    }
                }
                loadMoreRow
            }
            .listStyle(.insetGrouped)
        .yomiListCanvas()
        }
    }

    /// Any paginated OPDS catalog (Calibre-Web/Komga page by default) needs this — without it the
    /// browse view silently truncates to page 1 with no indication more content exists. See #87.
    @ViewBuilder
    private var loadMoreRow: some View {
        if nextHref != nil {
            HStack {
                Spacer()
                if isLoadingMore {
                    ProgressView()
                } else {
                    Button("Load More") { Task { await loadMore() } }
                }
                Spacer()
            }
        }
    }

    private func nonEmptyFilter(_ entries: [OPDSEntry], isNav: Bool) -> [OPDSEntry]? {
        let filtered = entries.filter { $0.isNavigation == isNav }
        return filtered.isEmpty ? nil : filtered
    }

    // MARK: Navigation list

    private func navigationList(entries: [OPDSEntry]) -> some View {
        List {
            ForEach(entries) { entry in
                if let navHref = entry.navigationHref {
                    NavigationLink {
                        OPDSBrowseView(title: entry.title, feedHref: navHref)
                    } label: {
                        navRow(entry)
                    }
                } else {
                    navRow(entry)
                }
            }
            loadMoreRow
        }
        .listStyle(.insetGrouped)
        .yomiListCanvas()
    }

    private func navRow(_ entry: OPDSEntry) -> some View {
        HStack(spacing: 12) {
            if let coverURL = OPDSService.shared.coverURL(for: entry) {
                KFImage(coverURL)
                    .placeholder { Image(systemName: "folder").foregroundStyle(canvas.textSecondary) }
                    .fade(duration: 0.2)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "folder")
                    .frame(width: 40, height: 40)
                    .foregroundStyle(canvas.textSecondary)
            }
            Text(entry.title).font(.body)
        }
    }

    // MARK: Acquisition grid

    private func acquisitionGrid(entries: [OPDSEntry]) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(entries) { entry in
                    Button {
                        selectedEntry = entry
                    } label: {
                        acquisitionCell(entry)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            loadMoreRow
                .padding(.bottom, 12)
        }
    }

    private func acquisitionCell(_ entry: OPDSEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if let coverURL = OPDSService.shared.coverURL(for: entry) {
                    CoverImage(url: coverURL)
                } else {
                    canvas.surface2.aspectRatio(2 / 3, contentMode: .fit)
                }
            }
            .cornerRadius(8)
            .clipped()

            Text(entry.title)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(canvas.textPrimary)

            if let author = entry.author {
                Text(author)
                    .font(.caption2)
                    .foregroundStyle(canvas.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private func acqRow(_ entry: OPDSEntry) -> some View {
        Button {
            selectedEntry = entry
        } label: {
            HStack(spacing: 12) {
                if let coverURL = OPDSService.shared.coverURL(for: entry) {
                    KFImage(coverURL)
                        .placeholder { canvas.surface2 }
                        .fade(duration: 0.2)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 55)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    canvas.surface2
                        .frame(width: 40, height: 55)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title).font(.body)
                    if let author = entry.author {
                        Text(author).font(.caption).foregroundStyle(canvas.textSecondary)
                    }
                }
            }
            .foregroundStyle(canvas.textPrimary)
        }
        .buttonStyle(.plain)
    }

    // MARK: Load

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await OPDSService.shared.fetchFeed(href: feedHref)
            await MainActor.run {
                feed = result
                allEntries = result.entries
                nextHref = result.nextPageHref
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func loadMore() async {
        guard !isLoadingMore, let href = nextHref else { return }
        isLoadingMore = true
        do {
            let result = try await OPDSService.shared.fetchFeed(href: href)
            await MainActor.run {
                allEntries.append(contentsOf: result.entries)
                nextHref = result.nextPageHref
                isLoadingMore = false
            }
        } catch {
            await MainActor.run { isLoadingMore = false }
        }
    }
}

// MARK: - OPDSItemDetailView

struct OPDSItemDetailView: View {
    @Environment(\.yomiCanvas) private var canvas
    let entry: OPDSEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Cover + metadata header
                    HStack(alignment: .top, spacing: 16) {
                        if let coverURL = OPDSService.shared.coverURL(for: entry) {
                            KFImage(coverURL)
                                .placeholder { canvas.surface2 }
                                .fade(duration: 0.2)
                                .resizable()
                                .aspectRatio(2 / 3, contentMode: .fill)
                                .frame(width: 100, height: 150)
                                .cornerRadius(8)
                                .clipped()
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.title)
                                .font(.headline)
                                .lineLimit(4)
                            if let author = entry.author {
                                Text(author)
                                    .font(.subheadline)
                                    .foregroundStyle(canvas.textSecondary)
                            }
                            if let href = entry.acquisitionHref {
                                let fullURL = OPDSService.shared.absoluteURL(href: href)
                                if let url = URL(string: fullURL) {
                                    Link(destination: url) {
                                        Label("Download", systemImage: "arrow.down.circle")
                                            .font(.subheadline)
                                    }
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal)

                    if let summary = entry.summary, !summary.isEmpty {
                        Divider()
                        Text(summary)
                            .font(.body)
                            .foregroundStyle(canvas.textSecondary)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .background(canvas.bg.ignoresSafeArea())
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
