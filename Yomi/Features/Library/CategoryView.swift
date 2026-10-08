import SwiftUI

// MARK: - CategoryView
//
// S146 calm pass (RESEARCH §26): plain rows on the canvas, no separators (Martin, S141). Tap = rename,
// swipe → red trash = delete (like Extensions and Downloads), Edit = reorder.

struct CategoryView: View {

    // MARK: - State

    @State private var categories: [Category] = []
    @State private var itemCounts: [String: Int] = [:]
    @State private var isAddingCategory: Bool = false
    @State private var newCategoryName: String = ""
    @State private var editingCategory: Category? = nil
    @Environment(\.yomiCanvas) private var canvas

    // MARK: - Body

    var body: some View {
        Group {
            if categories.isEmpty {
                YomiEmptyState(
                    systemImage: "folder",
                    title: "No categories yet",
                    message: "Tap + to create your first category."
                )
            } else {
                CalmList {
                    Section {
                        ForEach(categories) { category in
                            Button {
                                editingCategory = category
                            } label: {
                                HStack {
                                    Text(category.name)
                                        .font(.body)
                                        .foregroundStyle(canvas.textPrimary)
                                    Spacer()
                                    Text(itemCount(category.id))
                                        .font(.body)
                                        .foregroundStyle(canvas.textSecondary)
                                        .monospacedDigit()
                                }
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    delete(category)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(.red) // the app-wide accent tint would otherwise paint it blue
                            }
                        }
                        .onMove { source, destination in
                            moveCategories(from: source, to: destination)
                        }
                    } footer: {
                        Text("Tap a category to rename it. Deleting one keeps its titles in your library.")
                            .font(.footnote)
                            .foregroundStyle(canvas.textSecondary)
                            .padding(.top, 8)
                    }
                }
                .contentMargins(.top, 0, for: .scrollContent)
            }
        }
        .background(canvas.bg.ignoresSafeArea())
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !categories.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newCategoryName = ""
                    isAddingCategory = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New category")
            }
        }
        .onAppear { loadCategories() }
        // MARK: Add alert
        .alert("New Category", isPresented: $isAddingCategory) {
            TextField("Category name", text: $newCategoryName)
            Button("Add") { addCategory() }
            Button("Cancel", role: .cancel) {}
        }
        // MARK: Rename alert
        .alert("Rename Category", isPresented: Binding(
            get: { editingCategory != nil },
            set: { if !$0 { editingCategory = nil } }
        )) {
            TextField("Category name", text: Binding(
                get: { editingCategory?.name ?? "" },
                set: { editingCategory?.name = $0 }
            ))
            Button("Save") { renameCategory() }
            Button("Cancel", role: .cancel) { editingCategory = nil }
        }
    }

    private func itemCount(_ id: String) -> String {
        let n = itemCounts[id] ?? 0
        return n == 0 ? "Empty" : "\(n)"
    }

    // MARK: - Load

    private func loadCategories() {
        Task.detached {
            let result = (try? CategoryQueries.fetchAll()) ?? []
            let counts = (try? CategoryQueries.fetchItemCounts()) ?? [:]
            await MainActor.run { categories = result; itemCounts = counts }
        }
    }

    // MARK: - Add

    private func addCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Task.detached {
            _ = try? CategoryQueries.insert(name: name)
            let result = (try? CategoryQueries.fetchAll()) ?? []
            await MainActor.run { categories = result }
        }
    }

    // MARK: - Rename

    private func renameCategory() {
        guard let cat = editingCategory else { return }
        let name = cat.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { editingCategory = nil; return }
        Task.detached {
            try? CategoryQueries.rename(id: cat.id, name: name)
            let result = (try? CategoryQueries.fetchAll()) ?? []
            await MainActor.run {
                categories = result
                editingCategory = nil
            }
        }
    }

    // MARK: - Delete

    private func delete(_ category: Category) {
        categories.removeAll { $0.id == category.id }
        Task.detached {
            try? CategoryQueries.delete(id: category.id)
        }
    }

    // MARK: - Reorder

    private func moveCategories(from source: IndexSet, to destination: Int) {
        categories.move(fromOffsets: source, toOffset: destination)
        let reordered = categories
        Task.detached {
            for (index, cat) in reordered.enumerated() {
                try? CategoryQueries.updateSort(id: cat.id, sort: index)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CategoryView()
    }
}
