import SwiftUI
import UniformTypeIdentifiers

// MARK: - BackupView

struct BackupView: View {

    // MARK: - State

    @State private var backupManager = BackupManager.shared
    @State private var exportedURL: URL? = nil
    @State private var showShareSheet = false
    @State private var showImportPicker = false
    @State private var showImportSuccess = false
    @State private var showTachiyomiPicker = false
    @State private var showTachiyomiSuccess = false
    @State private var showRestoreConfirm = false
    @State private var iCloudBackupExists = false
    @State private var iCloudBackupDate: Date? = nil

    // MARK: - Body

    var body: some View {
        List {
            iCloudSection
            exportSection
            importSection
            tachiyomiImportSection
            errorSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Backup")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let result = await backupManager.checkICloudBackup()
            iCloudBackupExists = result.exists
            iCloudBackupDate = result.date
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedURL {
                ShareLink(
                    item: url,
                    subject: Text("Yomi Backup"),
                    message: Text("My Yomi library backup")
                )
            }
        }
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.json]
        ) { result in
            if case .success(let url) = result {
                Task {
                    await backupManager.importBackup(from: url)
                    if backupManager.errorMessage == nil { showImportSuccess = true }
                }
            }
        }
        .fileImporter(
            isPresented: $showTachiyomiPicker,
            allowedContentTypes: [UTType(filenameExtension: "tachibk") ?? .data]
        ) { result in
            if case .success(let url) = result {
                Task {
                    await backupManager.importTachiyomiBackup(from: url)
                    if backupManager.errorMessage == nil { showTachiyomiSuccess = true }
                }
            }
        }
        .confirmationDialog(
            "Restore from iCloud?",
            isPresented: $showRestoreConfirm,
            titleVisibility: .visible
        ) {
            Button("Restore", role: .destructive) {
                Task {
                    await backupManager.downloadFromICloud()
                    let result = await backupManager.checkICloudBackup()
                    iCloudBackupExists = result.exists
                    iCloudBackupDate = result.date
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will merge the iCloud backup into your current library.")
        }
        .alert("Import complete", isPresented: $showImportSuccess) {
            Button("OK", role: .cancel) {}
        }
        .alert("Tachiyomi import complete", isPresented: $showTachiyomiSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            if let summary = backupManager.lastTachiyomiImportSummary {
                Text(summary)
            }
        }
    }

    // MARK: - iCloud Section

    @ViewBuilder
    private var iCloudSection: some View {
        Section {
            if !backupManager.isICloudAvailable {
                Label("iCloud not available", systemImage: "icloud.slash")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                switch backupManager.iCloudStatus {
                case .uploading:
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Uploading to iCloud…")
                            .foregroundStyle(.secondary)
                    }
                case .downloading:
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Downloading from iCloud…")
                            .foregroundStyle(.secondary)
                    }
                case .error(let msg):
                    Text(msg)
                        .foregroundStyle(.red)
                        .font(.caption)
                default:
                    Button {
                        Task {
                            await backupManager.uploadToICloud()
                            let result = await backupManager.checkICloudBackup()
                            iCloudBackupExists = result.exists
                            iCloudBackupDate = result.date
                        }
                    } label: {
                        Label("Back up to iCloud", systemImage: "icloud.and.arrow.up")
                    }

                    if let date = iCloudBackupDate {
                        LabeledContent("Last iCloud backup") {
                            Text(date.formatted(.relative(presentation: .named)))
                                .foregroundStyle(.secondary)
                        }
                    } else if let date = backupManager.lastICloudUploadDate {
                        LabeledContent("Last iCloud backup") {
                            Text(date.formatted(.relative(presentation: .named)))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if iCloudBackupExists {
                        Button {
                            showRestoreConfirm = true
                        } label: {
                            Label("Restore from iCloud", systemImage: "icloud.and.arrow.down")
                        }
                    }
                }
            }
        } header: {
            Text("iCloud")
        } footer: {
            Text("iCloud backup merges into your library. Enable via Xcode → Target → Signing & Capabilities → iCloud → iCloud Documents.")
                .font(.caption)
        }
    }

    // MARK: - Export Section

    private var exportSection: some View {
        Section("Export") {
            if backupManager.isExporting {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Exporting...")
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Export library") {
                    Task {
                        if let url = await backupManager.exportBackup() {
                            exportedURL = url
                            showShareSheet = true
                        }
                    }
                }
                if let date = backupManager.lastBackupDate {
                    LabeledContent(
                        "Last backup",
                        value: date.formatted(.relative(presentation: .named))
                    )
                }
            }
        }
    }

    // MARK: - Import Section

    private var importSection: some View {
        Section("Import") {
            if backupManager.isImporting {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Importing...")
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Import backup") { showImportPicker = true }
                Text("Importing will merge with your existing library, not replace it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Tachiyomi Import Section

    private var tachiyomiImportSection: some View {
        Section("Import from Tachiyomi / Mihon") {
            if backupManager.isImporting {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Importing...")
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Import .tachibk backup") { showTachiyomiPicker = true }
                Text("Imports your manga library and read history from a Tachiyomi or Mihon backup file. Sources without a matching Yomi plugin are imported with a placeholder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Error Section

    @ViewBuilder
    private var errorSection: some View {
        if let error = backupManager.errorMessage {
            Section {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        BackupView()
    }
}
