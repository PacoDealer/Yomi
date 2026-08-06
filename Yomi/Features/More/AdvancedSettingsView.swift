import SwiftUI
import WebKit
import Kingfisher

// MARK: - AdvancedSettingsView

struct AdvancedSettingsView: View {
    @State private var showClearConfirm = false
    @State private var settings = AppSettings.shared

    var body: some View {
        List {
            cacheSection
            networkSection
            databaseSection
            aboutSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Cache

    private var cacheSection: some View {
        Section("Cache") {
            NavigationLink("Storage") { StorageView() }

            Button("Clear plugin catalog cache") {
                PluginCatalogService.shared.invalidateCache()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            .foregroundStyle(.primary)
        }
    }

    // MARK: - Network

    private var networkSection: some View {
        Section {
            LabeledContent("User Agent") {
                Text("iPhone Safari")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
            Stepper(
                "Request timeout: \(Int(settings.requestTimeout))s",
                value: $settings.requestTimeout,
                in: 10...60,
                step: 5
            )
        } header: {
            Text("Network")
        } footer: {
            Text("User agent is fixed — it must match the Cloudflare bypass browser's, or solved challenges won't carry over to source requests.")
                .font(.caption)
        }
    }

    // MARK: - Database

    private var databaseSection: some View {
        Section("Database") {
            Button("Export diagnostic log") {
                exportLog()
            }
            .foregroundStyle(.primary)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("Build") {
            LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
            LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
            LabeledContent("iOS", value: UIDevice.current.systemVersion)
            LabeledContent("Device", value: UIDevice.current.model)
        }
    }

    // MARK: - Log export

    private func exportLog() {
        let info = [
            "Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")",
            "Build: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")",
            "iOS: \(UIDevice.current.systemVersion)",
            "Installed plugins: \(ExtensionManager.shared.installed.count)",
            "Suwayomi enabled: \(SuwayomiService.shared.isEnabled)",
        ].joined(separator: "\n")

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("yomi-diagnostic.txt")
        try? info.write(to: url, atomically: true, encoding: .utf8)

        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(av, animated: true)
        }
    }
}
