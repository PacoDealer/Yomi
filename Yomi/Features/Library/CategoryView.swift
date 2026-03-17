import SwiftUI

// MARK: - CategoryView

struct CategoryView: View {

    // MARK: - State

    @State private var categories: [Category] = []
    @State private var isAddingCategory: Bool = false
    @State private var newCategoryName: String = ""
    @State private var editingCategory: Category? = nil

    // MARK: - Body

    var body: some View {
        Group {
            if categories.isEmpty {
                ContentUnavailableView(
                    "No categories yet",
                    systemImage: "folder",
                    description: Text("Tap + to create your first category.")
                )
            } else {
                List {
                    ForEach(categories) { category in
                        Text(category.name)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingCategory = category
                            }
                    }
                    .onDelete { indexSet in
                        deleteCategories(at: indexSet)
                    }
                    .onMove { source, destination in
                        moveCategories(from: source, to: destination)
                    }
                }
            }
        }
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newCategoryName = ""
                    isAddingCategory = true
                } label: {
                    Image(systemName: "plus")
                }
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

    // MARK: - Load

    private func loadCategories() {
        Task.detached {
            let result = (try? CategoryQueries.fetchAll()) ?? []
            await MainActor.run { categories = result }
        }
    }

    // MARK: - Add

    private func addCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Task.detached {
            try? CategoryQueries.insert(name: name)
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

    private func deleteCategories(at indexSet: IndexSet) {
        let toDelete = indexSet.map { categories[$0] }
        categories.remove(atOffsets: indexSet)
        Task.detached {
            for cat in toDelete {
                try? CategoryQueries.delete(id: cat.id)
            }
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
