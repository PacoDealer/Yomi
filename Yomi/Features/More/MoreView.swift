import SwiftUI

// MARK: - MoreView
//
// Design spec: YOMI Screens.dc.html N.10 (More).

struct MoreView: View {
    @State private var catalogService   = PluginCatalogService.shared
    @State private var extensionManager = ExtensionManager.shared
    @State private var showPlugins      = false
    @Environment(\.yomiCanvas) private var canvas

    private var pluginUpdateCount: Int {
        extensionManager.installed.filter {
            catalogService.availableUpdate(for: $0) != nil
        }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("More")
                        .font(YomiTokens.Font.grotesk(26, weight: .medium))
                        .foregroundStyle(canvas.textPrimary)
                        .padding(.top, 8)

                    card("APP") {
                        MoreRow(icon: "gearshape", label: "Settings") { SettingsView() }
                    }

                    card("LIBRARY") {
                        MoreRow(icon: "folder", label: "Categories") { CategoryView() }
                    }

                    card("SOURCES") {
                        MoreRow(icon: "puzzlepiece.extension", label: "Plugins", badge: pluginUpdateCount > 0 ? "\(pluginUpdateCount)" : nil) {
                            PluginsView()
                        }
                    }

                    card("READING") {
                        MoreRow(icon: "chart.bar", label: "Insights") { InsightsView() }
                    }

                    card("TRACKING") {
                        MoreRow(icon: "person.crop.circle.badge.checkmark", label: "MyAnimeList") { MALView() }
                    }

                    card("DATA") {
                        MoreRow(icon: "arrow.down.circle", label: "Downloads") { DownloadsView() }
                        Divider().padding(.leading, 58).overlay(canvas.hairline)
                        MoreRow(icon: "externaldrive", label: "Backup") { BackupView() }
                    }

                    card("ABOUT") {
                        MoreRow(icon: "info.circle", label: "About", trailingText: appVersion) { AboutView() }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(canvas.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showPlugins) { PluginsView() }
        }
        .task { await catalogService.fetchCatalog() }
        .onChange(of: appRouter.openMorePlugins, initial: true) { _, open in
            if open {
                showPlugins = true
                appRouter.openMorePlugins = false
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    // MARK: - Card

    @ViewBuilder
    private func card<Content: View>(_ header: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(header)
                .font(YomiTokens.Font.mono(11))
                .tracking(0.6)
                .foregroundStyle(canvas.textSecondary)
                .padding(.horizontal, 4)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                content()
            }
            .background(canvas.surface1)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

// MARK: - MoreRow

private struct MoreRow<Destination: View>: View {
    let icon: String
    let label: String
    var badge: String? = nil
    var trailingText: String? = nil
    @ViewBuilder let destination: () -> Destination

    @Environment(\.yomiCanvas) private var canvas

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(canvas.textSecondary)
                    .frame(width: 29, height: 29)
                    .background(canvas.surface2, in: RoundedRectangle(cornerRadius: 8))

                Text(label)
                    .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.body))
                    .foregroundStyle(canvas.textPrimary)

                Spacer()

                if let badge {
                    Text(badge)
                        .font(YomiTokens.Font.mono(11, bold: true))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentColor, in: Capsule())
                }

                if let trailingText {
                    Text(trailingText)
                        .font(YomiTokens.Font.mono(12))
                        .foregroundStyle(canvas.textSecondary)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(canvas.textSecondary.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - AboutView

private struct AboutView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.yomiCanvas) private var canvas

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                aboutCard("VERSION") {
                    infoRow("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    Divider().padding(.leading, 14).overlay(canvas.hairline)
                    infoRow("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
                }

                aboutCard("LINKS") {
                    linkRow("GitHub", url: "https://github.com/PacoDealer/Yomi")
                    Divider().padding(.leading, 14).overlay(canvas.hairline)
                    linkRow("Report a bug", url: "https://github.com/PacoDealer/Yomi/issues")
                    Divider().padding(.leading, 14).overlay(canvas.hairline)
                    linkRow("Privacy Policy", url: "https://yomi-plugins.web.app/privacy")
                }

                aboutCard("OPEN SOURCE") {
                    NavigationLink {
                        LicensesView()
                    } label: {
                        HStack {
                            Text("Open Source Licenses")
                                .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.body))
                                .foregroundStyle(canvas.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(canvas.textSecondary.opacity(0.5))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 60)
            .padding(.bottom, 24)
        }
        .background(canvas.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                }
                .glassChip()
                Spacer()
                Text("About")
                    .font(YomiTokens.Font.grotesk(16, weight: .medium))
                    .foregroundStyle(canvas.textPrimary)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func aboutCard<Content: View>(_ header: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(header)
                .font(YomiTokens.Font.mono(11))
                .tracking(0.6)
                .foregroundStyle(canvas.textSecondary)
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
            VStack(spacing: 0) { content() }
                .background(canvas.surface1)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.body))
                .foregroundStyle(canvas.textPrimary)
            Spacer()
            Text(value)
                .font(YomiTokens.Font.mono(13))
                .foregroundStyle(canvas.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func linkRow(_ label: String, url: String) -> some View {
        Button {
            if let u = URL(string: url) { openURL(u) }
        } label: {
            HStack {
                Text(label)
                    .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.body))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12))
                    .foregroundStyle(canvas.textSecondary.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
