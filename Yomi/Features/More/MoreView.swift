import SwiftUI

struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Sources") {
                    NavigationLink {
                        ContentUnavailableView("Coming soon", systemImage: "puzzlepiece")
                    } label: {
                        Label("Plugins", systemImage: "puzzlepiece")
                    }
                }

                Section("General") {
                    NavigationLink {
                        ContentUnavailableView("Coming soon", systemImage: "gearshape")
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("More")
        }
    }
}

#Preview {
    MoreView()
}
