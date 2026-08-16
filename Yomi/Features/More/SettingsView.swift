import SwiftUI

// MARK: - ConnectionTestStatus

private enum ConnectionTestStatus: Equatable {
    case idle
    case loading
    case connected(Int)
    case failed(String)

    var label: String {
        switch self {
        case .idle:              return ""
        case .loading:          return "Connecting…"
        case .connected(let n): return "Connected — \(n) sources"
        case .failed(let msg):  return "Error: \(msg)"
        }
    }
    var color: Color {
        switch self {
        case .connected: return .green
        case .failed:    return .red
        default:         return .secondary
        }
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var newRepoURL: String = ""
    @State private var showAddRepo = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.yomiCanvas) private var canvas

    private var oledBinding: Binding<Bool> {
        Binding(
            get: { settings.canvas == "Midnight" },
            set: { settings.canvas = $0 ? "Midnight" : "Ink" }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                generalCard
                appearanceCard
                libraryCard
                readingCard
                sourcesCard
                advancedCard
                aboutCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 60)
            .padding(.bottom, 24)
        }
        .background(canvas.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) { glassNavBar }
        .sheet(isPresented: $showAddRepo) { addRepoSheet }
    }

    // MARK: - Glass nav bar

    private var glassNavBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
            }
            .glassChip()
            Spacer()
            Text("Settings")
                .font(YomiTokens.Font.grotesk(16, weight: .medium))
                .foregroundStyle(canvas.textPrimary)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    // MARK: - Card + row helpers

    @ViewBuilder
    private func card<Content: View>(_ header: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(header)
                .font(YomiTokens.Font.mono(11))
                .tracking(0.6)
                .foregroundStyle(canvas.textSecondary)
                .padding(.horizontal, 4)
            VStack(spacing: 0) { content() }
                .background(canvas.surface1)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func rowDivider() -> some View {
        Divider().padding(.leading, 14).overlay(canvas.hairline)
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>, subtitle: String? = nil) -> some View {
        HStack(alignment: subtitle == nil ? .center : .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.body))
                    .foregroundStyle(canvas.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(canvas.textSecondary)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn).labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func navRow<Destination: View>(_ label: String, trailing: String? = nil, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                Text(label)
                    .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.body))
                    .foregroundStyle(canvas.textPrimary)
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing)
                        .font(YomiTokens.Font.mono(11))
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

    private func stepperPill(value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 2) {
            Button {
                if value.wrappedValue > range.lowerBound { value.wrappedValue -= 1 }
            } label: {
                Text("−").font(.system(size: 18)).frame(width: 34, height: 30)
            }
            Text("\(value.wrappedValue)")
                .font(YomiTokens.Font.mono(14))
                .frame(width: 32)
            Button {
                if value.wrappedValue < range.upperBound { value.wrappedValue += 1 }
            } label: {
                Text("+").font(.system(size: 18)).frame(width: 34, height: 30)
            }
        }
        .foregroundStyle(canvas.textPrimary)
        .background(canvas.surface2, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - General

    private var generalCard: some View {
        card("GENERAL") {
            toggleRow("Show NSFW content", isOn: $settings.showNSFW)
            rowDivider()
            toggleRow("App Lock", isOn: $settings.appLockEnabled, subtitle: "Require Face ID / Touch ID when opening Yomi")
            rowDivider()
            toggleRow("Secure screen", isOn: $settings.secureScreenEnabled, subtitle: "Hide content in the App Switcher")
            rowDivider()
            toggleRow("Incognito mode", isOn: $settings.isIncognito, subtitle: "Reading progress and history won't be saved")
            rowDivider()
            toggleRow("24-hour clock", isOn: $settings.use24HourClock, subtitle: "14:20 instead of 2:20 PM")
            rowDivider()
            toggleRow("Day before month", isOn: $settings.dateOrderDayFirst, subtitle: "28 JUL instead of JUL 28")
        }
    }

    // MARK: - Reading

    private var readingCard: some View {
        card("READING") {
            navRow("Manga & Webtoon") { MangaReaderSettingsView() }
            rowDivider()
            navRow("Novels") { NovelReaderSettingsView() }
        }
    }

    // MARK: - Library

    private var libraryCard: some View {
        card("LIBRARY") {
            HStack {
                Text("Items per row")
                    .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.body))
                    .foregroundStyle(canvas.textPrimary)
                Spacer()
                stepperPill(value: $settings.libraryColumns, range: 2...6)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            rowDivider()
            toggleRow("Show unread count badge", isOn: $settings.showUnreadBadge)
            rowDivider()
            toggleRow("Show item count on category tabs", isOn: $settings.showCategoryItemCounts)
            rowDivider()
            defaultCategoryRow
            rowDivider()
            defaultTabRow
            rowDivider()
            toggleRow("Delete after reading", isOn: $settings.deleteDownloadAfterReading, subtitle: "Removes downloaded files when you finish a chapter")
            rowDivider()
            HStack {
                Text("Concurrent downloads")
                    .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.body))
                    .foregroundStyle(canvas.textPrimary)
                Spacer()
                stepperPill(value: $settings.concurrentDownloads, range: 1...5)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            rowDivider()
            toggleRow("Background auto-refresh", isOn: $settings.backgroundAutoRefreshEnabled, subtitle: "Periodically check for new chapters when the app isn't open. iOS decides the actual timing.")
            rowDivider()
            toggleRow("Background download", isOn: $settings.backgroundDownloadEnabled, subtitle: settings.backgroundAutoRefreshEnabled ? "Auto-download new manga chapters found during a background refresh" : "Requires background auto-refresh — otherwise nothing runs to find new chapters")
                .disabled(!settings.backgroundAutoRefreshEnabled)
                .opacity(settings.backgroundAutoRefreshEnabled ? 1 : 0.5)
            rowDivider()
            navRow("Update rules") { UpdatesSettingsView() }
        }
    }

    @State private var libraryCategories: [Category] = []

    private var defaultCategoryRow: some View {
        Menu {
            Button("None") { settings.defaultCategoryId = nil }
            ForEach(libraryCategories) { cat in
                Button(cat.name) { settings.defaultCategoryId = cat.id }
            }
        } label: {
            HStack {
                Text("Default category")
                    .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.body))
                    .foregroundStyle(canvas.textPrimary)
                Spacer(minLength: 8)
                Text(libraryCategories.first(where: { $0.id == settings.defaultCategoryId })?.name ?? "None")
                    .font(YomiTokens.Font.mono(11))
                    .foregroundStyle(canvas.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .task {
            libraryCategories = (try? CategoryQueries.fetchAll()) ?? []
        }
    }

    private var defaultTabRow: some View {
        Menu {
            Button("Library") { settings.defaultTab = AppRouter.tabLibrary }
            Button("Browse") { settings.defaultTab = AppRouter.tabBrowse }
            Button("History") { settings.defaultTab = AppRouter.tabHistory }
            Button("Updates") { settings.defaultTab = AppRouter.tabUpdates }
            Button("More") { settings.defaultTab = AppRouter.tabMore }
        } label: {
            HStack {
                Text("Default tab")
                    .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.body))
                    .foregroundStyle(canvas.textPrimary)
                Spacer(minLength: 8)
                Text(tabLabel(settings.defaultTab))
                    .font(YomiTokens.Font.mono(11))
                    .foregroundStyle(canvas.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
    }

    private func tabLabel(_ tab: Int) -> String {
        switch tab {
        case AppRouter.tabLibrary: return "Library"
        case AppRouter.tabBrowse:  return "Browse"
        case AppRouter.tabHistory: return "History"
        case AppRouter.tabUpdates: return "Updates"
        case AppRouter.tabMore:    return "More"
        default: return "Library"
        }
    }

    // MARK: - Appearance

    private var appearanceCard: some View {
        card("APPEARANCE") {
            navRow("Appearance Studio", trailing: "Canvas · Accent · Type") { AppearanceStudioView() }
            rowDivider()
            toggleRow("Pure black (OLED)", isOn: oledBinding)
        }
    }

    // MARK: - Sources & Servers

    private var sourcesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SOURCES & SERVERS")
                .font(YomiTokens.Font.mono(11))
                .tracking(0.6)
                .foregroundStyle(canvas.textSecondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(settings.pluginCatalogURLs.enumerated()), id: \.element) { index, url in
                    Text(url)
                        .font(YomiTokens.Font.mono(12))
                        .foregroundStyle(canvas.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button(role: .destructive) {
                                settings.pluginCatalogURLs.remove(at: index)
                                PluginCatalogService.shared.invalidateCache()
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    rowDivider()
                }

                Button {
                    newRepoURL = ""
                    showAddRepo = true
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("Add repository")
                            .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.body))
                        Spacer()
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                rowDivider()
                navRow("Suwayomi Server") { SuwayomiSettingsView() }
                rowDivider()
                navRow("OPDS Server (Kavita / Komga)") { OPDSSettingsView() }
            }
            .background(canvas.surface1)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Text("Catalogs are merged. Duplicate plugin IDs: first catalog wins.")
                .font(.caption)
                .foregroundStyle(canvas.textSecondary)
                .padding(.horizontal, 4)
        }
    }

    private var addRepoSheet: some View {
        NavigationStack {
            Form {
                Section("Catalog URL") {
                    TextField("https://example.com/index.json", text: $newRepoURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section {
                    Link(destination: URL(string: "https://github.com/PacoDealer/Yomi#plugin-repositories")!) {
                        HStack {
                            Label("Browse community repos", systemImage: "book")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Find repository URLs and setup instructions on GitHub.")
                }
            }
            .navigationTitle("Add Repository")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddRepo = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let trimmed = newRepoURL.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty, !settings.pluginCatalogURLs.contains(trimmed) {
                            settings.pluginCatalogURLs.append(trimmed)
                            PluginCatalogService.shared.invalidateCache()
                        }
                        showAddRepo = false
                    }
                    .disabled(newRepoURL.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Advanced

    private var advancedCard: some View {
        card("ADVANCED") {
            navRow("Advanced settings") { AdvancedSettingsView() }
        }
    }

    // MARK: - About
    //
    // Compact quick-reference (Version + GitHub only, matching N.07's mock exactly) — the
    // full detail (Build, Report a bug, Privacy Policy, Licenses) lives in More → About.

    private var aboutCard: some View {
        card("ABOUT") {
            HStack {
                Text("Version")
                    .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.body))
                    .foregroundStyle(canvas.textPrimary)
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    .font(YomiTokens.Font.mono(13))
                    .foregroundStyle(canvas.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            rowDivider()
            Button {
                openURL(URL(string: "https://github.com/PacoDealer/Yomi")!)
            } label: {
                HStack {
                    Text("GitHub")
                        .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.body))
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

}

// MARK: - MangaReaderSettingsView

private struct MangaReaderSettingsView: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        List {
            Section {
                Picker("Default mode", selection: $settings.readerMode) {
                    Text("Manga (RTL)").tag("Manga (RTL)")
                    Text("Manhwa (LTR)").tag("Manhwa (LTR)")
                    Text("Paged (Vertical)").tag("Paged (Vertical)")
                    Text("Continuous (RTL)").tag("Continuous (RTL)")
                    Text("Continuous (LTR)").tag("Continuous (LTR)")
                    Text("Webtoon").tag("Webtoon")
                }
                .pickerStyle(.menu)

                Toggle(isOn: $settings.autoWebtoonFromTags) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-detect webtoon")
                        Text("Switches to Webtoon mode for manhwa/manhua/long-strip titles")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("Page layout", selection: $settings.pageLayout) {
                    Text("Single page").tag("single")
                    Text("Double page (spreads)").tag("double")
                    Text("Automatic (spreads in landscape)").tag("automatic")
                }

                Picker("Tap zones", selection: $settings.tapZoneLayout) {
                    Text("Default (equal thirds)").tag("default")
                    Text("Edge (20 · 60 · 20%)").tag("sides")
                    Text("L-Shaped").tag("lShaped")
                    Text("Kindle-ish").tag("kindle")
                    Text("Right & Left (50 / 50)").tag("rightLeft")
                    Text("Disabled (swipe only)").tag("disabled")
                }

                Toggle("Keep screen on while reading", isOn: $settings.keepScreenOn)
            }

            Section("Webtoon") {
                Stepper(
                    "Auto-scroll speed: \(String(format: "%.0f", settings.autoScrollSpeed))s",
                    value: $settings.autoScrollSpeed,
                    in: 1...10,
                    step: 0.5
                )

                Picker("Horizontal margins", selection: $settings.webtoonHorizontalPadding) {
                    Text("None").tag(0)
                    Text("Small (8 pt)").tag(8)
                    Text("Normal (16 pt)").tag(16)
                    Text("Wide (24 pt)").tag(24)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Manga & Webtoon")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - NovelReaderSettingsView

private struct NovelReaderSettingsView: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Font size: \(Int(settings.fontSize))pt")
                        .font(.subheadline)
                    Slider(value: $settings.fontSize, in: 14...28, step: 1)
                        .tint(Color(hex: settings.accentColor))
                }
                .padding(.vertical, 4)

                Stepper(
                    "Line spacing: \(String(format: "%.1f", settings.lineSpacing))×",
                    value: $settings.lineSpacing,
                    in: 1.0...2.5,
                    step: 0.1
                )

                Picker("Font family", selection: $settings.novelFontFamily) {
                    Text("Serif (Georgia)").tag("Serif")
                    Text("System").tag("System")
                }

                Picker("Default theme", selection: $settings.novelTheme) {
                    ForEach(NovelTheme.allCases, id: \.rawValue) { theme in
                        Text(theme.rawValue).tag(theme.rawValue)
                    }
                }

                Picker("Margins", selection: $settings.novelHorizontalPadding) {
                    Text("Narrow").tag(8)
                    Text("Normal").tag(16)
                    Text("Wide").tag(28)
                }
            }

            Section("Text-to-Speech") {
                Slider(
                    value: Binding(
                        get: { Double(settings.ttsSpeechRate) },
                        set: { settings.ttsSpeechRate = Float($0) }
                    ),
                    in: 0.1...1.0,
                    step: 0.1
                ) {
                    Text("Speed: \(String(format: "%.1f×", settings.ttsSpeechRate))")
                } minimumValueLabel: {
                    Text("0.1×").font(.caption)
                } maximumValueLabel: {
                    Text("1.0×").font(.caption)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Novels")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - UpdatesSettingsView

struct UpdatesSettingsView: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        List {
            Section {
                Toggle(isOn: $settings.sendUpdateNotifications) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Chapter update notifications")
                        Text("Send a notification when new chapters are found")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $settings.readingReminderEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reading reminders")
                        Text("Remind you to read if you haven't opened Yomi in a while")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: settings.readingReminderEnabled) { _, enabled in
                    if !enabled {
                        NotificationManager.shared.cancelReadingReminder()
                    }
                }

                if settings.readingReminderEnabled {
                    Picker("Remind me after", selection: $settings.readingReminderDays) {
                        Text("1 day").tag(1)
                        Text("2 days").tag(2)
                        Text("3 days").tag(3)
                        Text("1 week").tag(7)
                    }
                }
            }

            Section {
                Toggle(isOn: $settings.skipUpdateWithUnread) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Skip if unread chapters exist")
                        Text("Don't check for updates when you already have unread content")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $settings.skipUpdateNotStarted) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Skip titles not started")
                        Text("Don't check titles you've never opened")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $settings.skipUpdateCompleted) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Skip completed titles")
                        Text("Don't check titles marked as Completed by the source")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                NavigationLink("Excluded categories") {
                    ExcludedCategoriesView(settings: settings)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Update Rules")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - SuwayomiSettingsView

private struct SuwayomiSettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var status: ConnectionTestStatus = .idle

    var body: some View {
        List {
            Section {
                TextField("http://192.168.1.x:4567", text: $settings.suwayomiURL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: settings.suwayomiURL) { _, _ in status = .idle }

                HStack {
                    Button("Test Connection") {
                        Task { await testConnection() }
                    }
                    .disabled(settings.suwayomiURL.trimmingCharacters(in: .whitespaces).isEmpty
                              || status == .loading)

                    if status == .loading {
                        ProgressView().scaleEffect(0.8)
                    } else if case .connected = status {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else if case .failed = status {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                    }

                    Spacer()

                    if !status.label.isEmpty {
                        Text(status.label)
                            .font(.caption)
                            .foregroundStyle(status.color)
                            .lineLimit(1)
                    }
                }

                Link(destination: URL(string: "https://github.com/Suwayomi/Suwayomi-Server#getting-started")!) {
                    HStack {
                        Label("Setup guide", systemImage: "book")
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Self-host Suwayomi to browse 1000+ Mihon/Keiyoushi sources. Install the server on your computer or NAS, then paste the local IP here.")
                    .font(.caption)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Suwayomi Server")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func testConnection() async {
        status = .loading
        do {
            let sources = try await SuwayomiService.shared.fetchSources()
            status = .connected(sources.count)
        } catch {
            let msg = (error as? URLError)?.localizedDescription ?? error.localizedDescription
            status = .failed(String(msg.prefix(60)))
        }
    }
}

// MARK: - OPDSSettingsView

private struct OPDSSettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var status: ConnectionTestStatus = .idle

    var body: some View {
        List {
            Section {
                TextField("http://192.168.1.x:5000/opds/v1.2/catalog", text: $settings.opdsURL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: settings.opdsURL) { _, _ in status = .idle }

                TextField("Username (optional)", text: $settings.opdsUsername)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                SecureField("Password (optional)", text: $settings.opdsPassword)

                HStack {
                    Button("Test Connection") {
                        Task { await testConnection() }
                    }
                    .disabled(settings.opdsURL.trimmingCharacters(in: .whitespaces).isEmpty
                              || status == .loading)

                    if status == .loading {
                        ProgressView().scaleEffect(0.8)
                    } else if case .connected = status {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else if case .failed = status {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                    }

                    Spacer()

                    if !status.label.isEmpty {
                        Text(status.label)
                            .font(.caption)
                            .foregroundStyle(status.color)
                            .lineLimit(1)
                    }
                }
            } footer: {
                Text("Connect to a local Kavita or Komga library server via its OPDS catalog URL. Appears as a source in Browse.")
                    .font(.caption)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("OPDS Server")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func testConnection() async {
        status = .loading
        do {
            let count = try await OPDSService.shared.testConnection()
            status = .connected(count)
        } catch {
            let msg = (error as? URLError)?.localizedDescription ?? error.localizedDescription
            status = .failed(String(msg.prefix(60)))
        }
    }
}

// MARK: - ExcludedCategoriesView

private struct ExcludedCategoriesView: View {
    let settings: AppSettings
    @State private var categories: [Category] = []

    var body: some View {
        List {
            if categories.isEmpty {
                Text("No categories yet. Create categories in your library to exclude them from update checks.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(categories) { cat in
                    Button {
                        var excluded = settings.excludedCategoryIds
                        if excluded.contains(cat.id) {
                            excluded.removeAll { $0 == cat.id }
                        } else {
                            excluded.append(cat.id)
                        }
                        settings.excludedCategoryIds = excluded
                    } label: {
                        HStack {
                            Text(cat.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if settings.excludedCategoryIds.contains(cat.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Excluded Categories")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            categories = (try? CategoryQueries.fetchAll()) ?? []
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SettingsView()
    }
}
