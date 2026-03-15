import SwiftUI

struct LibraryView: View {
    @State private var viewModel: LibraryViewModel

    init(viewModel: LibraryViewModel = LibraryViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 160), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.filteredMangas.isEmpty && viewModel.searchText.isEmpty {
                    ContentUnavailableView(
                        "Your library is empty",
                        systemImage: "books.vertical",
                        description: Text("Browse sources and add titles to see them here.")
                    )
                } else if viewModel.filteredMangas.isEmpty {
                    ContentUnavailableView.search(text: viewModel.searchText)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(viewModel.filteredMangas) { manga in
                                MangaCoverCell(manga: manga)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                    }
                }
            }
            .navigationTitle("Library")
            .searchable(text: $viewModel.searchText, prompt: "Search library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // filtros — próximamente
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .task {
                await viewModel.loadLibrary()
            }
        }
    }
}

#Preview {
    LibraryView()
}
