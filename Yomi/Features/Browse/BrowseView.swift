import SwiftUI

struct BrowseView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Sin fuentes instaladas",
                systemImage: "safari",
                description: Text("Instalá plugins desde Más para empezar a explorar.")
            )
            .navigationTitle("Browse")
        }
    }
}

#Preview {
    BrowseView()
}
