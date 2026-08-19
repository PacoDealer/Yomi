import SwiftUI

// MARK: - TrackersView

struct TrackersView: View {
    @State private var settings  = AppSettings.shared
    @State private var mal       = MALService.shared
    @State private var aniList   = AniListTrackerService.shared
    @State private var shikimori = ShikimoriService.shared
    @State private var bangumi   = BangumiService.shared

    var body: some View {
        List {
            Section {
                Toggle("Auto-update on chapter finish", isOn: $settings.trackerAutoUpdate)
            } footer: {
                Text("Sends your reading progress to every connected tracker below whenever you finish a chapter.")
            }

            Section("Connect") {
                row(MALService.displayName, isLoggedIn: mal.isLoggedIn, username: mal.username) { MALView() }
                row(AniListTrackerService.displayName, isLoggedIn: aniList.isLoggedIn, username: aniList.username) { AniListView() }
                row(ShikimoriService.displayName, isLoggedIn: shikimori.isLoggedIn, username: shikimori.username) { ShikimoriView() }
                row(BangumiService.displayName, isLoggedIn: bangumi.isLoggedIn, username: bangumi.username) { BangumiView() }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Trackers")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func row<Destination: View>(
        _ name: String, isLoggedIn: Bool, username: String?,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack {
                Text(name)
                Spacer()
                Text(isLoggedIn ? (username ?? "Connected") : "Not connected")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        }
    }
}

#Preview {
    NavigationStack { TrackersView() }
}
