import SwiftUI

struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Sources") {
                    NavigationLink {
                        PluginsView()
                    } label: {
                        Label("Plugins", systemImage: "puzzlepiece.extension")
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
