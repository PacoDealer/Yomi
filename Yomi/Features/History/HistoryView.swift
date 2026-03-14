import SwiftUI

struct HistoryView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No history",
                systemImage: "clock",
                description: Text("Titles you read will appear here.")
            )
            .navigationTitle("History")
        }
    }
}

#Preview {
    HistoryView()
}
