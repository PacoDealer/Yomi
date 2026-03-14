import SwiftUI

struct HistoryView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Sin historial",
                systemImage: "clock",
                description: Text("Las obras que leas aparecerán aquí.")
            )
            .navigationTitle("History")
        }
    }
}

#Preview {
    HistoryView()
}
