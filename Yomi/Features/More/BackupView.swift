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
    @State private var tachiyomiReport: BackupManager.TachiyomiImportReport? = nil
    @State private var exportedTachiyomiURL: URL? = nil
    @State private var showTachiyomiShareSheet = false
    @State private var showRestoreConfirm = false
    @State private var icloudBackups: [BackupManager.ICloudBackupEntry] = []
    @State private var restoreTarget: BackupManager.ICloudBackupEntry? = nil
    @State private var settings = AppSettings.shared

    @Environment(\.yomiCanvas) private var canvas

    // MARK: - Body
    //
    // S146 calm pass (RESEARCH §26): three groups — this iPhone's file, iCloud, Tachiyomi/Mihon — with
    // bold sentence-case titles, plain rows, notes under the action they explain, no separators.

    var body: some View {
        CalmList {
            fileSection
            iCloudSection
            tachiyomiSection
            errorSection
        }
        .navigationTitle("Backup")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            icloudBackups = await backupManager.listICloudBackups()
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedURL {
                ActivitySheet(items: [url])
            }
        }
        .sheet(isPresented: $showTachiyomiShareSheet) {
            if let url = exportedTachiyomiURL {
                ActivitySheet(items: [url])
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
                    tachiyomiReport = backupManager.lastTachiyomiImport
                }
            }
        }
        .confirmationDialog(
            "Restore from iCloud?",
            isPresented: $showRestoreConfirm,
            titleVisibility: .visible
        ) {
            Button("Restore", role: .destructive) {
                guard let target = restoreTarget else { return }
                Task {
                    await backupManager.downloadFromICloud(target)
                    icloudBackups = await backupManager.listICloudBackups()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will merge the iCloud backup into your current library.")
        }
        .alert("Import complete", isPresented: $showImportSuccess) {
            Button("OK", role: .cancel) {}
        }
        .sheet(item: $tachiyomiReport) { report in
            TachiyomiImportView(report: report)
        }
    }

    private var byteCountFormatter: ByteCountFormatter {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }

    // MARK: - Rows

    /// Accent action row with an optional grey note under it — the note says what the action does.
    private func actionRow(_ title: String, note: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(Color.accentColor)
                if let note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(canvas.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func busyRow(_ text: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(text)
                .foregroundStyle(canvas.textSecondary)
        }
    }

    // MARK: - File Section

    @ViewBuilder
    private var fileSection: some View {
        Section {
            if backupManager.isExporting {
                busyRow("Exporting…")
            } else if backupManager.isImporting {
                busyRow("Importing…")
            } else {
                actionRow("Export Backup", note: "Saves your library, categories and reading progress to a file.") {
                    Task {
                        if let url = await backupManager.exportBackup() {
                            exportedURL = url
                            showShareSheet = true
                        }
                    }
                }
                actionRow("Import Backup", note: "Merges a Yomi backup into your library — nothing is replaced.") {
                    showImportPicker = true
                }
                if let date = backupManager.lastBackupDate {
                    LabeledContent("Last backup") {
                        Text(date.formatted(.relative(presentation: .named)))
                            .foregroundStyle(canvas.textSecondary)
                    }
                }
            }
        } header: { CalmSectionHeader("File") }
    }

    // MARK: - iCloud Section

    @ViewBuilder
    private var iCloudSection: some View {
        Section {
            if !backupManager.isICloudAvailable {
                Label("iCloud isn't available", systemImage: "icloud.slash")
                    .foregroundStyle(canvas.textSecondary)
            } else {
                switch backupManager.iCloudStatus {
                case .uploading:
                    busyRow("Uploading to iCloud…")
                case .downloading:
                    busyRow("Downloading from iCloud…")
                case .error(let msg):
                    Text(msg)
                        .foregroundStyle(.red)
                        .font(.footnote)
                default:
                    actionRow("Back Up Now") {
                        Task {
                            await backupManager.uploadToICloud()
                            icloudBackups = await backupManager.listICloudBackups()
                        }
                    }

                    Toggle(isOn: $settings.iCloudAutoBackup) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Back up automatically")
                            Text("Each time you leave Yomi.")
                                .font(.footnote)
                                .foregroundStyle(canvas.textSecondary)
                        }
                    }

                    ForEach(icloudBackups) { entry in
                        Button {
                            restoreTarget = entry
                            showRestoreConfirm = true
                        } label: {
                            LabeledContent {
                                Text(byteCountFormatter.string(fromByteCount: entry.size))
                                    .foregroundStyle(canvas.textSecondary)
                                    .monospacedDigit()
                            } label: {
                                Label(entry.date.formatted(.relative(presentation: .named)),
                                      systemImage: "clock.arrow.circlepath")
                                    .foregroundStyle(canvas.textPrimary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task {
                                    await backupManager.deleteICloudBackup(entry)
                                    icloudBackups = await backupManager.listICloudBackups()
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red) // the app-wide accent tint would otherwise paint it blue
                        }
                    }
                }
            }
        } header: { CalmSectionHeader("iCloud") } footer: {
            if !icloudBackups.isEmpty {
                Text("Tap a backup to restore it — it merges into your library.")
                    .font(.footnote)
                    .foregroundStyle(canvas.textSecondary)
            }
        }
    }

    // MARK: - Tachiyomi / Mihon Section

    @ViewBuilder
    private var tachiyomiSection: some View {
        Section {
            if backupManager.isExporting {
                busyRow("Exporting…")
            } else if backupManager.isImporting {
                busyRow("Importing…")
            } else {
                actionRow("Import .tachibk",
                          note: "From Mihon, Tachiyomi or Tachimanga: your manga library, categories and read history.") {
                    showTachiyomiPicker = true
                }
                actionRow("Export .tachibk",
                          note: "For Mihon, Tachiyomi or a fork. Mihon-extension titles open there as they are; titles from Yomi's own sources come across as metadata only.") {
                    Task {
                        if let url = await backupManager.exportTachiyomiBackup() {
                            exportedTachiyomiURL = url
                            showTachiyomiShareSheet = true
                        }
                    }
                }
            }
        } header: { CalmSectionHeader("Mihon / Tachiyomi / Tachimanga") }
    }

    // MARK: - Error Section

    @ViewBuilder
    private var errorSection: some View {
        if let error = backupManager.errorMessage {
            Section {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
        }
    }
}

// MARK: - ActivitySheet

private struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    NavigationStack {
        BackupView()
    }
}
