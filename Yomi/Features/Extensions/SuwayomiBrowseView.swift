import SwiftUI

// MARK: - SuwayomiBrowseView

struct SuwayomiBrowseView: View {
    let source: SuwayomiSource
    @State private var mangas: [Manga] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var currentPage = 1
    @State private var hasNextPage = true
    @State private var searchQuery = ""
    @State private var isSearching = false
    @State private var selectedManga: Manga? = nil
    @State private var showMangaDetail = false

    private let service = SuwayomiService.shared
    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 160), spacing: 12)]

    var body: some View {
        Group {
            if isLoading && mangas.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage, mangas.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") { Task { await loadMore() } }
                        .buttonStyle(.bordered)
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(mangas) { manga in
                            Button {
                                selectedManga = manga
                                showMangaDetail = true
                            } label: {
                                MangaCoverCell(manga: manga)
                            }
                            .buttonStyle(.plain)
                        }
                        if hasNextPage {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                                .onAppear { Task { await loadMore() } }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .navigationTitle(source.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchQuery, prompt: "Search \(source.name)")
        .onSubmit(of: .search) { Task { await runSearch() } }
        .onChange(of: searchQuery) { _, new in
            if new.isEmpty { Task { await reset() } }
        }
        .navigationDestination(isPresented: $showMangaDetail) {
            if let manga = selectedManga {
                MangaDetailView(manga: manga)
            }
        }
        .task { await loadMore() }
    }

    // MARK: - Load

    private func loadMore() async {
        guard !isLoading, hasNextPage else { return }
        isLoading = true
        errorMessage = nil
        do {
            let page = isSearching
                ? try await service.fetchSearch(sourceId: source.id, query: searchQuery, page: currentPage)
                : try await service.fetchPopular(sourceId: source.id, page: currentPage)
            let newMangas = page.mangaList.map { service.toManga(item: $0, sourceId: source.id) }
            await MainActor.run {
                mangas.append(contentsOf: newMangas)
                hasNextPage = page.hasNextPage
                currentPage += 1
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func runSearch() async {
        guard !searchQuery.isEmpty else { return }
        await reset(keepQuery: true)
        isSearching = true
        await loadMore()
    }

    private func reset(keepQuery: Bool = false) async {
        await MainActor.run {
            mangas = []
            currentPage = 1
            hasNextPage = true
            isSearching = keepQuery
            errorMessage = nil
        }
    }
}
