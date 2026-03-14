import SwiftUI

struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Fuentes") {
                    NavigationLink {
                        ContentUnavailableView("Próximamente", systemImage: "puzzlepiece")
                    } label: {
                        Label("Plugins", systemImage: "puzzlepiece")
                    }
                }

                Section("General") {
                    NavigationLink {
                        ContentUnavailableView("Próximamente", systemImage: "gearshape")
                    } label: {
                        Label("Ajustes", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("Más")
        }
    }
}

#Preview {
    MoreView()
}
