import SwiftUI

// MARK: - MoreView

struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                // MARK: App
                Section("App") {
                    NavigationLink { SettingsView() } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }

                // MARK: Library
                Section("Library") {
                    NavigationLink { CategoryView() } label: {
                        Label("Categories", systemImage: "folder")
                    }
                }

                // MARK: Sources
                Section("Sources") {
                    NavigationLink { PluginsView() } label: {
                        Label("Plugins", systemImage: "puzzlepiece.extension")
                    }
                }

                // MARK: Reading
                Section("Reading") {
                    NavigationLink { InsightsView() } label: {
                        Label("Insights", systemImage: "chart.bar")
                    }
                }

                // MARK: Tracking
                Section("Tracking") {
                    NavigationLink { MALView() } label: {
                        Label("MyAnimeList", systemImage: "person.crop.circle.badge.checkmark")
                    }
                }

                // MARK: Data
                Section("Data") {
                    NavigationLink(destination: DownloadsView()) {
                        Label("Downloads", systemImage: "arrow.down.circle")
                    }
                    NavigationLink { BackupView() } label: {
                        Label("Backup", systemImage: "externaldrive")
                    }
                }

                // MARK: Info
                Section {
                    NavigationLink { AboutView() } label: {
                        Label("About", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("More")
        }
    }
}

// MARK: - AboutView

private struct AboutView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                LabeledContent("Version", value: "1.0.0")
                LabeledContent("Build",   value: "1")
            }

            Section {
                Button {
                    openURL(URL(string: "https://github.com/PacoDealer/Yomi")!)
                } label: {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .foregroundStyle(.primary)
            }

            Section {
                NavigationLink("Open Source Licenses") { LicensesView() }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - LicensesView

private struct LicensesView: View {
    var body: some View {
        List {
            LicenseRow(
                name:    "GRDB.swift",
                license: "MIT License",
                url:     URL(string: "https://github.com/groue/GRDB.swift")!
            )
        }
        .navigationTitle("Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - LicenseRow

private struct LicenseRow: View {
    let name: String
    let license: String
    let url: URL

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(url)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(license)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    MoreView()
}
