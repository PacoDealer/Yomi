import SwiftUI

// MARK: - CloudSyncView
//
// Distinct from BackupView on purpose (see Yomi/CLOUDKIT_SYNC_DESIGN.md) — this is live
// cross-device sync via CKSyncEngine, not the point-in-time iCloud Drive backup BackupView manages.

struct CloudSyncView: View {

    @State private var settings = AppSettings.shared
    @State private var sync = CloudSyncManager.shared

    var body: some View {
        List {
            Section {
                Toggle(isOn: $settings.cloudSyncEnabled) {
                    Label("Sync across devices", systemImage: "arrow.triangle.2.circlepath.icloud")
                }

                if settings.cloudSyncEnabled {
                    statusRow

                    if sync.status != .unavailable {
                        Button {
                            Task { await sync.syncNow() }
                        } label: {
                            Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(sync.status == .syncing)
                    }
                }
            } footer: {
                Text("Keeps your library, reading progress, and categories in sync across every device signed into the same iCloud account. Downloaded chapters and custom cover images stay on each device individually. Separate from the iCloud backup below, which is a point-in-time export you restore manually.")
                    .font(.caption)
            }
        }
        .listStyle(.insetGrouped)
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
                    .foregroundStyle(.secondary)
            }
        case .success:
            if let date = sync.lastSyncDate {
                LabeledContent("Last synced") {
                    Text(date.formatted(.relative(presentation: .named)))
                        .foregroundStyle(.secondary)
                }
            }
        case .unavailable:
            Label("iCloud account unavailable", systemImage: "icloud.slash")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        case .error(let message):
            Text(message)
                .foregroundStyle(.red)
                .font(.caption)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CloudSyncView()
    }
}
