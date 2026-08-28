import SwiftUI

// MARK: - TrackersView

struct TrackersView: View {
    @Environment(\.yomiCanvas) private var canvas
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
                row("TrackerLogoMAL", MALService.displayName, isLoggedIn: mal.isLoggedIn, username: mal.username, error: mal.errorMessage) { MALView() }
                row("TrackerLogoAniList", AniListTrackerService.displayName, isLoggedIn: aniList.isLoggedIn, username: aniList.username, error: aniList.errorMessage) { AniListView() }
                row("TrackerLogoShikimori", ShikimoriService.displayName, isLoggedIn: shikimori.isLoggedIn, username: shikimori.username, error: shikimori.errorMessage) { ShikimoriView() }
                row("TrackerLogoBangumi", BangumiService.displayName, wordmark: true, isLoggedIn: bangumi.isLoggedIn, username: bangumi.username, error: bangumi.errorMessage) { BangumiView() }
            }
        }
        .listStyle(.insetGrouped)
        .yomiListCanvas()
        .navigationTitle("Trackers")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func row<Destination: View>(
        _ logo: String, _ name: String, wordmark: Bool = false, isLoggedIn: Bool, username: String?,
        error: String? = nil,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    TrackerLogo(name: logo, width: wordmark ? 72 : 28, height: 28)
                    Text(name)
                        .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.body))
                        .foregroundStyle(canvas.textPrimary)
                    Spacer()
                    Text(isLoggedIn ? (username ?? "Connected") : "Not connected")
                        .foregroundStyle(canvas.textSecondary)
                        .font(YomiTokens.Font.mono(12))
                }
                // A failed progress sync is otherwise invisible — "Connected" alone used to be
                // shown even when every write to the service had been failing for months.
                if isLoggedIn, let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}

// MARK: - TrackerLogo

/// Each service's own official logo. MAL/AniList/Shikimori ship full-color square marks and get a
/// rounded clip like a normal app icon; Bangumi's only available official asset is a solid-black
/// wordmark (no square icon exists anywhere, including their own site) — passing a wider,
/// non-square `width` keeps it legible instead of collapsing to a sliver, and `.template`
/// rendering + `.primary` recolors it so it doesn't vanish against a dark row background (a solid
/// black PNG is otherwise nearly invisible in dark mode — caught live, not assumed).
struct TrackerLogo: View {
    let name: String
    var width: CGFloat = 28
    var height: CGFloat = 28

    private var isWordmark: Bool { width != height }

    var body: some View {
        Image(name)
            .renderingMode(isWordmark ? .template : .original)
            .resizable()
            .scaledToFit()
            .frame(width: width, height: height)
            .foregroundStyle(.primary)
            .clipShape(isWordmark ? AnyShape(Rectangle()) : AnyShape(RoundedRectangle(cornerRadius: 6)))
    }
}

// MARK: - TrackerHeaderLogoSection

/// Large centered logo at the top of each tracker's own login/account screen. A `Section` (not a
/// bare view) so it composes into each screen's existing `List` without extra wrapping.
struct TrackerHeaderLogoSection: View {
    let name: String
    var wordmark: Bool = false

    var body: some View {
        Section {
            HStack {
                Spacer()
                TrackerLogo(name: name, width: wordmark ? 176 : 64, height: 64)
                Spacer()
            }
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }
}

#Preview {
    NavigationStack { TrackersView() }
}
