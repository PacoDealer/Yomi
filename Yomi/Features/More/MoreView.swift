import SwiftUI

// MARK: - MoreView
//
// S142 calm pass (RESEARCH §26): large system title, plain rows like Apple Music's Library list — accent
// SF Symbol, label, chevron. No cards, no mono headers, no separators (Martin, S141). Groups are separated by
// space only: what you use while reading, your data, the app.

struct MoreView: View {
    @Environment(\.yomiCanvas) private var canvas
    @State private var downloads = DownloadManager.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MoreRow(icon: "arrow.down.circle", label: "Downloads",
                            trailing: downloads.queue.isEmpty ? nil : "\(downloads.queue.count)") { DownloadsView() }
                    MoreRow(icon: "folder", label: "Categories") { CategoryView() }
                    MoreRow(icon: "chart.bar", label: "Insights") { InsightsView() }
                }
                Section {
                    MoreRow(icon: "person.crop.circle.badge.checkmark", label: "Trackers") { TrackersView() }
                    MoreRow(icon: "externaldrive", label: "Backup") { BackupView() }
                    MoreRow(icon: "arrow.triangle.2.circlepath.icloud", label: "Sync") { CloudSyncView() }
                }
                Section {
                    MoreRow(icon: "gearshape", label: "Settings") { SettingsView() }
                    MoreRow(icon: "info.circle", label: "About", trailing: appVersion) { AboutView() }
                }
            }
            .listStyle(.plain)
            .listSectionSpacing(28)
            .yomiListCanvas()
            .navigationTitle("More")
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
}

// MARK: - MoreRow

/// Accent icon · label · optional grey trailing text · chevron. Shared by More and About.
private struct MoreRow<Destination: View>: View {
    let icon: String
    let label: String
    var trailing: String? = nil
    @ViewBuilder let destination: () -> Destination

    @Environment(\.yomiCanvas) private var canvas

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            MoreRowLabel(icon: icon, label: label, trailing: trailing)
        }
        .moreRowStyle()
    }
}

private struct MoreRowLabel: View {
    let icon: String?
    let label: String
    var trailing: String? = nil
    var labelColor: Color? = nil

    @Environment(\.yomiCanvas) private var canvas

    var body: some View {
        HStack(spacing: 14) {
            if let icon {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
            }
            Text(label)
                .font(.body)
                .foregroundStyle(labelColor ?? canvas.textPrimary)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.body)
                    .foregroundStyle(canvas.textSecondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

private extension View {
    func moreRowStyle() -> some View {
        listRowInsets(EdgeInsets(top: 4, leading: YomiTokens.Layout.screenMargin,
                                 bottom: 4, trailing: YomiTokens.Layout.screenMargin))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

// MARK: - AboutView

private struct AboutView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.yomiCanvas) private var canvas

    var body: some View {
        List {
            Section {
                MoreRowLabel(icon: nil, label: "Version",
                             trailing: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    .moreRowStyle()
                MoreRowLabel(icon: nil, label: "Build",
                             trailing: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
                    .moreRowStyle()
            }
            Section {
                linkRow("GitHub", icon: "chevron.left.forwardslash.chevron.right", url: "https://github.com/PacoDealer/Yomi")
                linkRow("Report a Bug", icon: "ladybug", url: "https://github.com/PacoDealer/Yomi/issues")
                linkRow("Privacy Policy", icon: "hand.raised", url: "https://yomi-plugins.web.app/privacy")
            }
            Section {
                MoreRow(icon: "doc.text", label: "Open Source Licenses") { LicensesView() }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(28)
        .yomiListCanvas()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func linkRow(_ label: String, icon: String, url: String) -> some View {
        Button {
            if let u = URL(string: url) { openURL(u) }
        } label: {
            HStack {
                MoreRowLabel(icon: icon, label: label)
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(canvas.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .moreRowStyle()
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
