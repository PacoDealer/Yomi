import SwiftUI

struct LibraryView: View {
    @State private var viewModel: LibraryViewModel
    @State private var extensionManager = ExtensionManager.shared
    var onBrowseTap: (() -> Void)? = nil

    init(viewModel: LibraryViewModel = LibraryViewModel(), onBrowseTap: (() -> Void)? = nil) {
        _viewModel = State(initialValue: viewModel)
        self.onBrowseTap = onBrowseTap
    }

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 160), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.displayedManga.isEmpty && viewModel.searchText.isEmpty && viewModel.selectedCategoryId == nil {
                    if extensionManager.installed.isEmpty {
                        VStack(spacing: 16) {
                            ContentUnavailableView(
                                "No plugins installed",
                                systemImage: "puzzlepiece.extension",
                                description: Text("Plugins connect Yomi to manga and novel sources. Install one to start reading.")
                            )
                            Button("Get plugins") {
                                appRouter.openBrowseExtensions = true
                                appRouter.selectedTab = AppRouter.tabBrowse
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    } else {
                        VStack(spacing: 16) {
                            ContentUnavailableView(
                                "Your library is empty",
                                systemImage: "books.vertical",
                                description: Text("Browse sources and add titles to see them here.")
                            )
                            Button("Browse sources") {
                                appRouter.selectedTab = AppRouter.tabBrowse
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                } else if viewModel.displayedManga.isEmpty {
                    ContentUnavailableView.search(text: viewModel.searchText)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ContinueReadingRow()
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(viewModel.displayedManga) { manga in
                                    MangaCoverCell(manga: manga)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .safeAreaInset(edge: .top, spacing: 0) {
                categoryFilterBar
            }
            .searchable(text: $viewModel.searchText, prompt: "Search library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(SortOrder.allCases) { order in
                            Button {
                                viewModel.sortOrder = order
                            } label: {
                                Label(order.rawValue, systemImage: order.systemImage)
                                if viewModel.sortOrder == order {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle\(viewModel.sortOrder == .lastRead ? "" : ".fill")")
                    }
                }
            }
            .task {
                await viewModel.loadLibrary()
            }
        }
    }

    // MARK: - Category Filter Bar

    @ViewBuilder
    private var categoryFilterBar: some View {
        if !viewModel.categories.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // "All" chip
                    CategoryChip(
                        label: "All",
                        isSelected: viewModel.selectedCategoryId == nil
                    ) {
                        viewModel.selectedCategoryId = nil
                    }

                    ForEach(viewModel.categories) { category in
                        CategoryChip(
                            label: category.name,
                            isSelected: viewModel.selectedCategoryId == category.id
                        ) {
                            viewModel.selectedCategoryId = category.id
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(.bar)
        }
    }
}

// MARK: - CategoryChip

private struct CategoryChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .background {
                    if isSelected {
                        Capsule().fill(Color.accentColor)
                    } else {
                        Capsule().stroke(Color.secondary, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    LibraryView()
}
