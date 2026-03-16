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

    // MARK: - Body

    var body: some View {
        List {
            exportSection
            importSection
            errorSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Backup")
        .navigationBarTitleDisplayMode(.inline)
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
                Task { await backupManager.importBackup(from: url) }
            }
        }
        .alert("Import complete", isPresented: $showImportSuccess) {
            Button("OK", role: .cancel) {}
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
