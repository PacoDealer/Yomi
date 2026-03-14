import SwiftUI

struct LibraryView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Tu biblioteca está vacía",
                systemImage: "books.vertical",
                description: Text("Explorá fuentes y agregá obras para verlas aquí.")
            )
            .navigationTitle("Library")
        }
    }
}

#Preview {
    LibraryView()
}
