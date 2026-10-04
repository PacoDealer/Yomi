import SwiftUI
import LocalAuthentication

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

/// S142 calm pass (RESEARCH §26): one plain list with the system nav bar, bold sentence-case section titles,
/// native controls, no cards or separators. Regrouped by what each setting is about — the old "Library" card
/// mixed grid, tabs, downloads and background refresh. The duplicate About card is gone (More → About has it).
struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var notifications = NotificationManager.shared
    @State private var libraryCategories: [Category] = []
    @State private var appLockError: String?
    @Environment(\.openURL) private var openURL

    var body: some View {
        CalmList {
            Section {
                NavigationLink {
                    AppearanceStudioView()
                } label: {
                    valueLabel("Appearance", themeName)
                }
            }

            Section {
                NavigationLink("Manga & Webtoon") { MangaReaderSettingsView() }
                NavigationLink("Novels") { NovelReaderSettingsView() }
                toggle("Keep screen on", isOn: $settings.keepScreenOn, note: "While a reader is open.")
            } header: { CalmSectionHeader("Reading") }

            Section {
                Stepper(value: $settings.libraryColumns, in: 2...6) {
                    valueLabel("Items per row", "\(settings.libraryColumns)")
                }
                Toggle("Show unread count", isOn: $settings.showUnreadBadge)
                Toggle("Item count on categories", isOn: $settings.showCategoryItemCounts)
                Picker("Default category", selection: $settings.defaultCategoryId) {
                    Text("None").tag(String?.none)
                    ForEach(libraryCategories) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("Open on", selection: $settings.defaultTab) {
                    Text("Library").tag(AppRouter.tabLibrary)
                    Text("Browse").tag(AppRouter.tabBrowse)
                    Text("History").tag(AppRouter.tabHistory)
                    Text("Updates").tag(AppRouter.tabUpdates)
                    Text("More").tag(AppRouter.tabMore)
                }
                NavigationLink("Customize tabs") { CustomizeTabsView() }
            } header: { CalmSectionHeader("Library") }

            Section {
                toggle("Only on Wi-Fi", isOn: $settings.downloadOnlyOnWiFi,
                       note: "Downloads wait for Wi-Fi and pause in Low Data Mode. Reading is never blocked.")
                    .onChange(of: settings.downloadOnlyOnWiFi) { _, _ in NetworkMonitor.shared.settingsChanged() }
                toggle("Delete manga after reading", isOn: $settings.deleteDownloadAfterReading,
                       note: "Removes a manga chapter's pages when you finish it.")
                Stepper(value: $settings.concurrentDownloads, in: 1...5) {
                    valueLabel("Manga chapters at once", "\(settings.concurrentDownloads)")
                }
            } header: { CalmSectionHeader("Downloads") } footer: {
                Text("Novel chapters are saved ahead while you read — see Novels. Keiyoushi downloads need Yomi open.")
            }

            Section {
                toggle("Check in the background", isOn: $settings.backgroundAutoRefreshEnabled,
                       note: "iOS decides when. Keiyoushi titles are checked when you refresh in Updates.")
                toggle("Download what's found", isOn: $settings.backgroundDownloadEnabled,
                       note: "New manga chapters from plugin sources.")
                    .disabled(!settings.backgroundAutoRefreshEnabled)
                NavigationLink("Update rules") { UpdatesSettingsView() }
            } header: { CalmSectionHeader("Updates") }

            Section {
                toggle("New chapters", isOn: notificationBinding($settings.sendUpdateNotifications),
                       note: "When a refresh finds chapters for your library.")
                toggle("Reading reminder", isOn: notificationBinding($settings.readingReminderEnabled),
                       note: "If you haven't opened Yomi in a while.")
                    .onChange(of: settings.readingReminderEnabled) { _, on in
                        if !on { NotificationManager.shared.cancelReadingReminder() }
                    }
                if settings.readingReminderEnabled {
                    Picker("Remind me after", selection: $settings.readingReminderDays) {
                        Text("1 day").tag(1)
                        Text("2 days").tag(2)
                        Text("3 days").tag(3)
                        Text("1 week").tag(7)
                    }
                }
                if notifications.isDenied && (settings.sendUpdateNotifications || settings.readingReminderEnabled) {
                    Button("Notifications are off for Yomi — turn them on in iOS Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                }
            } header: { CalmSectionHeader("Notifications") }

            Section {
                NavigationLink {
                    RepositoriesView()
                } label: {
                    valueLabel("Repositories", repositoryCount == 0 ? "None" : "\(repositoryCount)")
                }
                NavigationLink("Kavita / Komga (OPDS)") { OPDSSettingsView() }
            } header: { CalmSectionHeader("Sources") }

            Section {
                toggle("Incognito", isOn: $settings.isIncognito, note: "Reading progress and history aren't saved.")
                toggle("App Lock", isOn: appLockBinding, note: "Face ID or passcode when you open Yomi.")
                toggle("Hide in App Switcher", isOn: $settings.secureScreenEnabled)
                toggle("Show 18+ content", isOn: $settings.showNSFW, note: "Extensions marked 18+ in Browse.")
            } header: { CalmSectionHeader("Privacy") }

            Section {
                toggle("Rotate with device", isOn: $settings.rotationFollowDevice, note: "Off keeps Yomi in portrait.")
                    .onChange(of: settings.rotationFollowDevice) { _, _ in applyRotationSetting() }
                Picker("Time", selection: $settings.use24HourClock) {
                    Text("Like iPhone").tag(Bool?.none)
                    Text("14:20").tag(Bool?.some(true))
                    Text("2:20 PM").tag(Bool?.some(false))
                }
                Picker("Date", selection: $settings.dateOrderDayFirst) {
                    Text("Like iPhone").tag(Bool?.none)
                    Text("28 Jul").tag(Bool?.some(true))
                    Text("Jul 28").tag(Bool?.some(false))
                }
                NavigationLink("Advanced") { AdvancedSettingsView() }
            } header: { CalmSectionHeader("General") }
        }
        .navigationTitle("Settings")
        .task {
            libraryCategories = (try? CategoryQueries.fetchAll()) ?? []
            await NotificationManager.shared.checkAuthorizationStatus()
        }
        .alert("App Lock wasn't turned on", isPresented: Binding(
            get: { appLockError != nil }, set: { if !$0 { appLockError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appLockError ?? "")
        }
    }

    private var themeName: String {
        switch settings.canvas {
        case AppSettings.automaticCanvas: "Automatic"
        case "Midnight": "Black"
        case "Paper": "Light"
        case "Sepia": "Sepia"
        default: "Dark"
        }
    }

    /// Turning a notification on asks iOS for permission (S142 audit: Yomi only asked when a *manga* was added to
    /// the library, so a novel-only reader never got notifications even with these on).
    private func notificationBinding(_ value: Binding<Bool>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue }, set: { on in
            value.wrappedValue = on
            if on { Task { await NotificationManager.shared.requestPermission() } }
        })
    }

    /// App Lock only turns on after one successful unlock (S142 audit: on an iPhone without a passcode the lock
    /// screen said "Authentication not available" with no way past it).
    private var appLockBinding: Binding<Bool> {
        Binding(get: { settings.appLockEnabled }, set: { on in
            guard on else { settings.appLockEnabled = false; return }
            let context = LAContext()
            var error: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
                appLockError = "Set a passcode for this iPhone first (iOS Settings → Face ID & Passcode)."
                return
            }
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Turn on App Lock") { ok, _ in
                DispatchQueue.main.async { if ok { settings.appLockEnabled = true } }
            }
        })
    }

    /// The orientation mask is only read on rotation — ask iOS to re-read it now, and snap back to portrait.
    private func applyRotationSetting() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        if !settings.rotationFollowDevice {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
        }
    }

    private var repositoryCount: Int {
        settings.pluginCatalogURLs.count + settings.mihonRepoURLs.count
    }

    /// Toggle with a one-line grey note under the title (instead of the old caption paragraphs).
    private func toggle(_ title: String, isOn: Binding<Bool>, note: String? = nil) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
            if let note { Text(note) }
        }
    }

    private func valueLabel(_ title: String, _ value: String) -> some View {
        LabeledContent(title, value: value)
    }
}

// MARK: - MangaReaderSettingsView

/// Defaults for new titles; the reader's own menu changes the mode for the title you're in.
private struct MangaReaderSettingsView: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        CalmList {
            Section {
                // Stored values are the old labels (ReaderMode raw values) — only the shown names changed (S142).
                Picker("Reading mode", selection: $settings.readerMode) {
                    Text("Right to left (manga)").tag("Manga (RTL)")
                    Text("Left to right").tag("Manhwa (LTR)")
                    Text("Vertical pages").tag("Paged (Vertical)")
                    Text("Long strip (webtoon)").tag("Webtoon")
                    Text("Continuous right to left").tag("Continuous (RTL)")
                    Text("Continuous left to right").tag("Continuous (LTR)")
                }
                Toggle(isOn: $settings.autoWebtoonFromTags) {
                    Text("Long strip for manhwa and manhua")
                    Text("Uses the title's genre tags.")
                }
                Picker("Two-page spreads", selection: $settings.pageLayout) {
                    Text("Off").tag("single")
                    Text("Always").tag("double")
                    Text("In landscape").tag("automatic")
                }
                Picker("Tap zones", selection: $settings.tapZoneLayout) {
                    Text("Thirds").tag("default")
                    Text("Edges").tag("sides")
                    Text("L-shaped").tag("lShaped")
                    Text("Kindle").tag("kindle")
                    Text("Left and right halves").tag("rightLeft")
                    Text("Off (swipe only)").tag("disabled")
                }
            } header: { CalmSectionHeader("Pages") } footer: {
                Text("Tap zones turn the page in paged modes; the middle shows the menu.")
            }

            Section(calm: "Long Strip") {
                Stepper(value: $settings.autoScrollSpeed, in: 1...10, step: 0.5) {
                    LabeledContent("Auto-scroll", value: "1 page / \(settings.autoScrollSpeed.formatted()) s")
                }
                Picker("Side margins", selection: $settings.webtoonHorizontalPadding) {
                    Text("None").tag(0)
                    Text("Small").tag(8)
                    Text("Medium").tag(16)
                    Text("Large").tag(24)
                }
            }
        }
        .navigationTitle("Manga & Webtoon")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - NovelReaderSettingsView

/// Reading behaviour, offline and listening. Text size, font, page colour and spacing live in the reader panel
/// only (Martin, S136) — the copies that used to be here offered different steps than the panel (line spacing in
/// 0.1 steps vs Tight/Normal/Airy), so a value set here showed as nothing selected there (S142 audit).
private struct NovelReaderSettingsView: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        CalmList {
            Section {
                Picker("Layout", selection: $settings.novelReadingMode) {
                    Text("Scroll").tag("scroll")
                    Text("Pages").tag("pages")
                }
                if settings.novelReadingMode == "pages" {
                    Toggle(isOn: $settings.novelPagesContinue) {
                        Text("Continue into next chapter")
                        Text("Off ends each chapter on a Next chapter page.")
                    }
                } else {
                    Toggle(isOn: $settings.novelInfiniteScroll) {
                        Text("Infinite scroll")
                        Text("Carries on into the next chapter.")
                    }
                    Toggle(isOn: $settings.novelSwipeChapters) {
                        Text("Swipe to change chapter")
                        Text("Left for next, right for previous.")
                    }
                }
                Picker("Show menu with", selection: $settings.novelMenuTaps) {
                    Text("One tap").tag(1)
                    Text("Two taps").tag(2)
                }
            } header: { CalmSectionHeader("Reading") } footer: {
                Text("Text size, font, page colour and spacing: tap the middle of a page while reading.")
            }

            Section {
                Picker("Save ahead", selection: $settings.novelDownloadAhead) {
                    Text("Off").tag(0)
                    ForEach([5, 10, 20, 30], id: \.self) { Text("\($0) chapters").tag($0) }
                }
            } header: { CalmSectionHeader("Offline") } footer: {
                Text(settings.downloadOnlyOnWiFi
                     ? "While you read a novel in your library, the next chapters are saved so they open instantly and work offline. Only on Wi-Fi (Settings → Downloads)."
                     : "While you read a novel in your library, the next chapters are saved so they open instantly and work offline.")
            }

            Section(calm: "Listening") {
                // AVSpeechUtterance rate: 0.5 is the voice's normal speed; the old "0.1×–1.0×" labels read as a
                // multiplier, so normal speed looked like half speed.
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Speed", value: speechSpeedLabel)
                    Slider(value: Binding(get: { Double(settings.ttsSpeechRate) },
                                          set: { settings.ttsSpeechRate = Float($0) }),
                           in: 0.3...0.75, step: 0.05) {
                        Text("Speed")
                    } minimumValueLabel: {
                        Image(systemName: "tortoise")
                    } maximumValueLabel: {
                        Image(systemName: "hare")
                    }
                }
            }
        }
        .navigationTitle("Novels")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var speechSpeedLabel: String {
        let r = settings.ttsSpeechRate
        if abs(r - 0.5) < 0.025 { return "Normal" }
        return r < 0.5 ? "Slower" : "Faster"
    }
}

// MARK: - UpdatesSettingsView

/// Which library titles a refresh checks. Notifications moved to Settings → Notifications (S142).
struct UpdatesSettingsView: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        CalmList {
            Section {
                Toggle(isOn: $settings.skipUpdateWithUnread) {
                    Text("Titles with unread chapters")
                    Text("You haven't caught up yet.")
                }
                Toggle(isOn: $settings.skipUpdateNotStarted) {
                    Text("Titles you haven't started")
                }
                Toggle(isOn: $settings.skipUpdateCompleted) {
                    Text("Completed titles")
                    Text("Marked Completed by the source.")
                }
                NavigationLink {
                    ExcludedCategoriesView(settings: settings)
                } label: {
                    LabeledContent("Categories", value: settings.excludedCategoryIds.isEmpty
                                   ? "None" : "\(settings.excludedCategoryIds.count)")
                }
            } header: { CalmSectionHeader("Don't Check") } footer: {
                Text("Skipped titles don't appear in the Updates Summary.")
            }
        }
        .navigationTitle("Update Rules")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - SuwayomiSettingsView

struct SuwayomiSettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var status: ConnectionTestStatus = .idle

    var body: some View {
        CalmList {
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
        CalmList {
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
        CalmList {
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
