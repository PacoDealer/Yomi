import SwiftUI

struct BrowseView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No sources installed",
                systemImage: "safari",
                description: Text("Install plugins from More to start browsing.")
            )
            .navigationTitle("Browse")
        }
    }
}

#Preview {
    BrowseView()
}
