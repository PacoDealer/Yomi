import SwiftUI

// MARK: - CloudSyncView
//
// Distinct from BackupView on purpose (see Yomi/CLOUDKIT_SYNC_DESIGN.md) — this is live
// cross-device sync via CKSyncEngine, not the point-in-time iCloud Drive backup BackupView manages.
// S146 calm pass (RESEARCH §26): plain rows on the canvas, the explanation as a note, no separators.

struct CloudSyncView: View {

    @State private var settings = AppSettings.shared
    @State private var sync = CloudSyncManager.shared
    @Environment(\.yomiCanvas) private var canvas

    var body: some View {
        CalmList {
            Section {
                Toggle(isOn: $settings.cloudSyncEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sync across devices")
                        Text("Library, reading progress and categories, on every device with your iCloud account.")
                            .font(.footnote)
                            .foregroundStyle(canvas.textSecondary)
                    }
                }

                if settings.cloudSyncEnabled {
                    statusRow

                    if sync.status != .unavailable {
                        Button {
                            Task { await sync.syncNow() }
                        } label: {
                            Text("Sync Now")
                                .foregroundStyle(sync.status == .syncing ? canvas.textSecondary : Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        .disabled(sync.status == .syncing)
                    }
                }
            } footer: {
                Text("Downloads and custom covers stay on each device. This is live sync — a backup you restore by hand is in More → Backup.")
                    .font(.footnote)
                    .foregroundStyle(canvas.textSecondary)
                    .padding(.top, 8)
            }
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .navigationTitle("Sync")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if settings.cloudSyncEnabled {
                await sync.syncNow()
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch sync.status {
        case .idle:
            EmptyView()
        case .syncing:
            HStack(spacing: 12) {
                ProgressView()
                Text("Syncing…")
                    .foregroundStyle(canvas.textSecondary)
            }
        case .success:
            if let date = sync.lastSyncDate {
                LabeledContent("Last synced") {
                    Text(date.formatted(.relative(presentation: .named)))
                        .foregroundStyle(canvas.textSecondary)
                }
            }
        case .unavailable:
            Label("iCloud account unavailable", systemImage: "icloud.slash")
                .foregroundStyle(canvas.textSecondary)
        case .error(let message):
            Text(message)
                .foregroundStyle(.red)
                .font(.footnote)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CloudSyncView()
    }
}
