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
    @State private var tachiyomiReport: BackupManager.TachiyomiImportReport? = nil
    @State private var showRestoreConfirm = false
    @State private var icloudBackups: [BackupManager.ICloudBackupEntry] = []
    @State private var restoreTarget: BackupManager.ICloudBackupEntry? = nil
    @State private var localBackups: [BackupManager.ICloudBackupEntry] = []
    @State private var localRestoreTarget: BackupManager.ICloudBackupEntry? = nil
    @State private var settings = AppSettings.shared

    @Environment(\.yomiCanvas) private var canvas
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Body
    //
    // S146 calm pass (RESEARCH §26): bold sentence-case titles, plain rows, notes under the action they explain,
    // no separators. S155 (Martin): ONE Import and ONE Export for every format — the separate Mihon / Tachiyomi /
    // Tachimanga group is gone. It also fixes a dead "Import Backup": with two `.fileImporter`s on one view only
    // the last one presents.

    var body: some View {
        CalmList {
            fileSection
            localSection
            iCloudSection
            errorSection
        }
        .navigationTitle("Backup")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            localBackups = await backupManager.listLocalBackups()
            icloudBackups = await backupManager.listICloudBackups()
        }
        // The automatic backup is written while the app is in the background — show it on return.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { localBackups = await backupManager.listLocalBackups() } }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedURL {
                ActivitySheet(items: [url])
            }
        }
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: TachiyomiBackupParser.backupFileTypes
        ) { result in
            if case .success(let url) = result {
                Task {
                    await backupManager.importAnyBackup(from: url)
                    if let report = backupManager.lastTachiyomiImport {
                        tachiyomiReport = report
                    } else if backupManager.errorMessage == nil {
                        showImportSuccess = true
                    }
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
        // `presenting:` — a second isPresented dialog on this view would be the two-`.fileImporter`s trap again.
        .alert("Restore this backup?", isPresented: Binding(get: { localRestoreTarget != nil },
                                                             set: { if !$0 { localRestoreTarget = nil } }),
               presenting: localRestoreTarget) { target in
            Button("Restore") {
                Task {
                    await backupManager.importBackup(from: target.url)
                    if backupManager.errorMessage == nil { showImportSuccess = true }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It merges into your current library — nothing is replaced.")
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
    private func actionRow(_ title: LocalizedStringKey, note: LocalizedStringKey? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) { actionLabel(title, note: note) }
            .buttonStyle(.plain)
    }

    private func actionLabel(_ title: LocalizedStringKey, note: LocalizedStringKey?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .foregroundStyle(Color.accentColor)
            if let note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(canvas.textSecondary)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func export(_ make: @escaping () async -> URL?) {
        Task {
            if let url = await make() {
                exportedURL = url
                showShareSheet = true
            }
        }
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
                busyRow(String(localized: "Exporting…"))
            } else if backupManager.isImporting {
                busyRow(String(localized: "Importing…"))
            } else {
                Menu {
                    Button { export { await backupManager.exportBackup() } } label: {
                        Text("Yomi Backup")
                        Text("Everything, novels included")
                    }
                    Button { export { await backupManager.exportTachiyomiBackup() } } label: {
                        Text(".tachibk")
                        Text("Manga only — for Mihon, Tachiyomi, Tachimanga")
                    }
                } label: {
                    actionLabel("Export Backup",
                                note: "Saves your library, categories and reading progress to a file — as a Yomi backup, or a .tachibk for other readers.")
                }
                .buttonStyle(.plain)
                actionRow("Import Backup",
                          note: "A Yomi backup, a .tachibk from Mihon or Tachiyomi, or a Tachimanga .tmb. It merges into your library — nothing is replaced.") {
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

    // MARK: - On This iPhone Section (S156)

    @ViewBuilder
    private var localSection: some View {
        Section {
            if backupManager.isSavingLocalBackup {
                busyRow(String(localized: "Backing up…"))
            } else {
                actionRow("Back Up Now") {
                    Task {
                        await backupManager.saveLocalBackup()
                        localBackups = await backupManager.listLocalBackups()
                    }
                }
            }
            Toggle(isOn: $settings.localAutoBackup) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Back up automatically")
                    Text("Once a day, when you leave Yomi. The last 8 are kept.")
                        .font(.footnote)
                        .foregroundStyle(canvas.textSecondary)
                }
            }
            ForEach(localBackups) { entry in
                Button {
                    localRestoreTarget = entry
                } label: {
                    LabeledContent {
                        Text(byteCountFormatter.string(fromByteCount: entry.size))
                            .foregroundStyle(canvas.textSecondary)
                            .monospacedDigit()
                    } label: {
                        Label(entry.date.formatted(date: .abbreviated, time: .shortened),
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
                            localBackups = await backupManager.listLocalBackups()
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                }
            }
        } header: { CalmSectionHeader("On This iPhone") } footer: {
            Text(localBackups.isEmpty
                 ? "Kept inside Yomi. Deleting the app deletes them — use Export or iCloud for a copy elsewhere."
                 : "Tap a backup to restore it. Kept inside Yomi: deleting the app deletes them — use Export or iCloud for a copy elsewhere.")
                .font(.footnote)
                .foregroundStyle(canvas.textSecondary)
        }
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
                    busyRow(String(localized: "Uploading to iCloud…"))
                case .downloading:
                    busyRow(String(localized: "Downloading from iCloud…"))
                default:
                    // The error sits above the actions — it used to replace them, so one failure hid "Back Up Now".
                    if case .error(let msg) = backupManager.iCloudStatus {
                        Text(msg)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
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
