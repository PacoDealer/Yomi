import SwiftUI
import CryptoKit
import Kingfisher

// MARK: - Constants

let kYomiSetupGuideURL = URL(string: "https://github.com/PacoDealer/Yomi#how-to-add-a-repository")!

// S140 (RESEARCH §26): Yomi ships with no repositories. The user adds every repository by pasting its link;
// once a repository is added, every extension in it is one tap ("Add"). Removing is a swipe (red trash), both
// for extensions here and for repositories in RepositoriesView.

// MARK: - PluginsView

struct PluginsView: View {
    /// Shown as Browse's Extensions tab (Browse owns the title) rather than pushed as its own screen.
    var embedded = false
    @State private var extensionManager = ExtensionManager.shared
    @State private var catalogService   = PluginCatalogService.shared
    @State private var settings         = AppSettings.shared
    @State private var keiyoushi        = KeiyoushiRepository.shared
    @Environment(\.yomiCanvas) private var canvas

    @State private var searchText       = ""
    @State private var showInstallSheet = false
    @State private var showAddRepoSheet = false
    @State private var showRepositories = false
    /// Rows with an install or update running ("js:<id>" / "kei:<package>").
    @State private var busy: Set<String> = []
    @State private var isUpdatingAll = false
    @State private var langPickerGroup: PluginCatalogGroup? = nil
    /// A multi-language Keiyoushi extension waiting for its languages to be picked before install.
    @State private var keiyoushiInstallPick: KeiyoushiExtension? = nil
    @State private var keiyoushiLanguageEdit: InstalledKeiyoushiExtension? = nil
    @State private var errorToast: String? = nil
    /// Base language code the Available list is filtered to ("" = every language).
    @AppStorage("extensionsLanguageFilter") private var languageFilter = "en"

    private var hasRepositories: Bool {
        !settings.pluginCatalogURLs.isEmpty || !settings.keiyoushiRepoURL.isEmpty
    }

    // MARK: Data

    private func matchesSearch(_ name: String) -> Bool {
        searchText.isEmpty || name.localizedStandardContains(searchText)
    }

    /// Catalog plugins not installed yet, under the search / NSFW / language filters.
    private var availableGroups: [PluginCatalogGroup] {
        catalogService.groupedEntries.filter { group in
            !catalogService.isGroupInstalled(group)
                && (settings.showNSFW || !group.primaryEntry.isNSFW)
                && matchesSearch(group.name)
                && (languageFilter.isEmpty || group.entries.contains {
                    let code = SourceLanguage.baseCode(for: $0.language)
                    return code == languageFilter || code == "all"
                })
        }
    }

    /// Keiyoushi extensions not installed yet, under the same filters.
    private var availableKeiyoushi: [KeiyoushiExtension] {
        // The last index stays cached after its repository is removed — it isn't "available" any more.
        guard !settings.keiyoushiRepoURL.isEmpty else { return [] }
        let installedIds = Set(keiyoushi.installed.map(\.id))
        return keiyoushi.available.filter { ext in
            !installedIds.contains(ext.id)
                && (settings.showNSFW || !ext.isNSFW)
                && matchesSearch(ext.name)
                && (languageFilter.isEmpty
                    || ext.sources.contains { SourceLanguage.baseCode(for: $0.lang) == languageFilter })
        }
    }

    private var availableItems: [ExtensionItem] {
        (availableGroups.map(ExtensionItem.available) + availableKeiyoushi.map(ExtensionItem.availableKeiyoushi))
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var installedItems: [ExtensionItem] {
        (extensionManager.installed.map(ExtensionItem.installed)
            + keiyoushi.installed.map(ExtensionItem.installedKeiyoushi))
            .filter { matchesSearch($0.name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func hasUpdate(_ item: ExtensionItem) -> Bool {
        switch item {
        case .installed(let ext): return catalogService.availableUpdate(for: ext) != nil
        case .installedKeiyoushi(let ext): return keiyoushi.availableUpdate(for: ext) != nil
        default: return false
        }
    }

    private var updateItems: [ExtensionItem] { installedItems.filter(hasUpdate) }
    private var upToDateItems: [ExtensionItem] { installedItems.filter { !hasUpdate($0) } }

    /// Every language any repository offers, for the Available filter.
    private var catalogLanguages: [String] {
        let codes = catalogService.entries.map { SourceLanguage.baseCode(for: $0.language) }
            + keiyoushi.available.flatMap { $0.sources.map { SourceLanguage.baseCode(for: $0.lang) } }
        return Set(codes).subtracting(["all", ""]).sorted {
            SourceLanguage.displayName(for: $0).localizedCaseInsensitiveCompare(SourceLanguage.displayName(for: $1))
                == .orderedAscending
        }
    }

    /// Names shared by more than one row (e.g. Asura Scans from two repositories) — those rows also name their
    /// repository, or they'd be indistinguishable.
    private var sharedNames: Set<String> {
        let names = (installedItems + availableItems).map { $0.name.lowercased() }
        var seen = Set<String>(), shared = Set<String>()
        for name in names where !seen.insert(name).inserted { shared.insert(name) }
        return shared
    }

    // MARK: Body

    var body: some View {
        // Once per render — per row it rebuilt every Available group for each row and froze the list (S141).
        let shared = sharedNames
        List {
            if embedded { searchRow }
            if !updateItems.isEmpty {
                Section {
                    sectionHeader("Updates") {
                        if isUpdatingAll {
                            ProgressView().controlSize(.small)
                        } else if updateItems.count > 1 {
                            Button("Update All") { Task { await updateAll() } }
                                .font(.subheadline.weight(.semibold))
                                .buttonStyle(.borderless)
                        }
                    }
                    ForEach(updateItems) { row($0, shared: shared) }
                }
            }
            if !upToDateItems.isEmpty {
                Section {
                    sectionHeader("Installed") { countLabel(upToDateItems.count) }
                    ForEach(upToDateItems) { row($0, shared: shared) }
                }
            }
            // Extensions already added stay listed (and deletable) even with every repository removed.
            if hasRepositories { availableSection(shared: shared) } else { noRepositories }
        }
        .listStyle(.plain)
        .yomiListCanvas()
        .navigationTitle(embedded ? "Browse" : "Extensions")
        .modifier(NavBarSearch(enabled: !embedded, text: $searchText, prompt: "Search extensions"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showAddRepoSheet = true } label: {
                        Label("Add Repository", systemImage: "plus")
                    }
                    Button { showRepositories = true } label: {
                        Label("Repositories", systemImage: "tray.2")
                    }
                    Button { showInstallSheet = true } label: {
                        Label("Add Extension from Link", systemImage: "link")
                    }
                    Divider()
                    Toggle(isOn: $settings.showNSFW) {
                        Label("Show 18+ Extensions", systemImage: "eye")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Extension options")
            }
        }
        .navigationDestination(isPresented: $showRepositories) { RepositoriesView() }
        .sheet(isPresented: $showInstallSheet) {
            InstallFromURLSheet(extensionManager: extensionManager)
        }
        .sheet(isPresented: $showAddRepoSheet) {
            AddRepoSheet()
        }
        .confirmationDialog(
            langPickerGroup.map { "Add \($0.name)" } ?? "",
            isPresented: Binding(get: { langPickerGroup != nil }, set: { if !$0 { langPickerGroup = nil } }),
            titleVisibility: .visible
        ) {
            if let group = langPickerGroup {
                ForEach(group.entries) { entry in
                    let installed = catalogService.isInstalled(entry)
                    let name = SourceLanguage.displayName(for: entry.language)
                    Button(installed ? "\(name) — Added" : name) {
                        if !installed { Task { await add(entry) } }
                    }
                    .disabled(installed)
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .sheet(item: $keiyoushiInstallPick) { ext in
            KeiyoushiLanguageSheet(ext: ext, initial: KeiyoushiLanguageSheet.defaultSelection(for: ext),
                                   confirmTitle: "Add") { langs in
                Task { await installKeiyoushi(ext, langs: langs) }
            }
        }
        .sheet(item: $keiyoushiLanguageEdit) { installed in
            KeiyoushiLanguageSheet(ext: installed.info, initial: Set(installed.enabledSources.map(\.lang)),
                                   confirmTitle: "Done") { langs in
                keiyoushi.setEnabledLangs(langs, for: installed.id)
            }
        }
        .yomiToast($errorToast)
        .onAppear {
            Task { await catalogService.fetchCatalog() }
            if keiyoushi.available.isEmpty, !settings.keiyoushiRepoURL.isEmpty {
                Task { await keiyoushi.refresh() }
            }
        }
        .refreshable {
            await catalogService.fetchCatalog(force: true)
            await keiyoushi.refresh()
        }
    }

    // MARK: Pieces

    private var searchRow: some View {
        // Inside Browse a nav-bar search field would sit above the tab strip and push it down.
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(canvas.textSecondary)
            TextField("Search extensions", text: $searchText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(canvas.textSecondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(canvas.surface2, in: Capsule())
        .listRowInsets(EdgeInsets(top: 8, leading: YomiTokens.Layout.screenMargin,
                                  bottom: 4, trailing: YomiTokens.Layout.screenMargin))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// A section title as an ordinary row, so it scrolls away like the Library's instead of pinning over rows.
    private func sectionHeader<Trailing: View>(_ title: String,
                                               @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(canvas.textPrimary)
            Spacer()
            trailing()
        }
        .listRowInsets(EdgeInsets(top: 24, leading: YomiTokens.Layout.screenMargin,
                                  bottom: 4, trailing: YomiTokens.Layout.screenMargin))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func countLabel(_ count: Int) -> some View {
        Text("\(count)")
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(canvas.textSecondary)
    }

    private var noRepositories: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray.2")
                .font(.system(size: 40))
                .foregroundStyle(canvas.textSecondary)
            Text("No Repositories")
                .font(.title3.bold())
                .foregroundStyle(canvas.textPrimary)
            Text("Extensions come from repositories. Paste a repository's link to add it, then add the extensions you want.")
                .font(.subheadline)
                .foregroundStyle(canvas.textSecondary)
                .multilineTextAlignment(.center)
            PillButton(title: "Add Repository") { showAddRepoSheet = true }
                .padding(.top, 4)
            Link(destination: kYomiSetupGuideURL) {
                Text("How to find repositories")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func availableSection(shared: Set<String>) -> some View {
        Section {
            sectionHeader("Available") { languageMenu }
            if (catalogService.isLoading || keiyoushi.isLoading) && availableItems.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else if availableItems.isEmpty {
                VStack(spacing: 10) {
                    Text(emptyAvailableMessage)
                        .font(.subheadline)
                        .foregroundStyle(canvas.textSecondary)
                        .multilineTextAlignment(.center)
                    if catalogService.errorMessage != nil || keiyoushi.errorMessage != nil {
                        PillButton(title: "Try Again") {
                            Task {
                                await catalogService.fetchCatalog(force: true)
                                await keiyoushi.refresh()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(availableItems) { row($0, shared: shared) }
            }
        }
    }

    private var emptyAvailableMessage: String {
        if !searchText.isEmpty { return "No extensions match \u{201C}\(searchText)\u{201D}." }
        if let error = catalogService.errorMessage ?? keiyoushi.errorMessage {
            return "Couldn't load a repository — \(error)"
        }
        if !languageFilter.isEmpty { return "Everything in \(SourceLanguage.displayName(for: languageFilter)) is added." }
        return "You've added everything your repositories offer."
    }

    private var languageMenu: some View {
        Menu {
            Picker("Language", selection: $languageFilter) {
                Text("All Languages").tag("")
                ForEach(catalogLanguages, id: \.self) { code in
                    Text(SourceLanguage.displayName(for: code)).tag(code)
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(languageFilter.isEmpty ? "All Languages" : SourceLanguage.displayName(for: languageFilter))
                Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold))
            }
            .font(.subheadline)
            .foregroundStyle(Color.accentColor)
        }
        .accessibilityLabel("Language filter")
    }

    // MARK: Rows

    @ViewBuilder
    private func row(_ item: ExtensionItem, shared: Set<String>) -> some View {
        let origin = shared.contains(item.name.lowercased()) ? repoName(for: item) : nil
        switch item {
        case .installed(let ext):
            let update = catalogService.availableUpdate(for: ext)
            ExtensionRow(name: ext.name, iconURL: ext.iconURL ?? catalogEntry(for: ext)?.iconURL.flatMap(URL.init(string:)),
                         detail: update.map { "Version \($0.version)" }
                            ?? detail(language: ext.language, isNovel: isNovel(ext), origin: origin),
                         isNSFW: ext.isNSFW) {
                if let update {
                    PillButton(title: "Update", busy: busy.contains(item.id) || isUpdatingAll) {
                        Task { await updatePlugin(ext, to: update) }
                    }
                }
            }
            .modifier(DeleteSwipe { extensionManager.remove(ext) })
        case .installedKeiyoushi(let installed):
            let update = keiyoushi.availableUpdate(for: installed)
            let langs = Set(installed.info.sources.map(\.lang))
            ExtensionRow(name: installed.info.name, iconURL: URL(string: installed.info.iconURL),
                         detail: update.map { "Version \($0.versionName)" }
                            ?? keiyoushiDetail(installed.info, enabled: Set(installed.enabledSources.map(\.lang)),
                                               origin: origin),
                         isNSFW: installed.info.isNSFW) {
                if let update {
                    PillButton(title: "Update", busy: busy.contains(item.id) || isUpdatingAll) {
                        Task { await installKeiyoushi(update, langs: nil) }
                    }
                } else if langs.count > 1 {
                    PillButton(title: "Languages", systemImage: "globe") { keiyoushiLanguageEdit = installed }
                }
            }
            .modifier(DeleteSwipe { Task { await keiyoushi.uninstall(installed) } })
        case .available(let group):
            ExtensionRow(name: group.name, iconURL: group.primaryEntry.iconURL.flatMap(URL.init(string:)),
                         detail: group.isMultiLang
                            ? "\(group.entries.count) languages\(kindSuffix(group.primaryEntry.knownIsNovel))\(origin.map { " · \($0)" } ?? "")"
                            : detail(language: group.primaryEntry.language,
                                     isNovel: group.primaryEntry.knownIsNovel,
                                     origin: origin),
                         isNSFW: group.primaryEntry.isNSFW) {
                PillButton(title: "Add", busy: group.entries.contains { busy.contains("js:\($0.id)") }) {
                    if group.isMultiLang {
                        langPickerGroup = group
                    } else {
                        Task { await add(group.primaryEntry) }
                    }
                }
            }
        case .availableKeiyoushi(let ext):
            ExtensionRow(name: ext.name, iconURL: URL(string: ext.iconURL),
                         detail: keiyoushiDetail(ext, enabled: nil, origin: origin),
                         isNSFW: ext.isNSFW) {
                PillButton(title: "Add", busy: busy.contains(item.id)) {
                    if Set(ext.sources.map(\.lang)).count > 1 {
                        keiyoushiInstallPick = ext
                    } else {
                        Task { await installKeiyoushi(ext, langs: nil) }
                    }
                }
            }
        }
    }

    /// "English · Novels", "English", "English · Manga · LNReader".
    private func detail(language: String, isNovel: Bool?, origin: String?) -> String {
        SourceLanguage.displayName(for: language) + kindSuffix(isNovel) + (origin.map { " · \($0)" } ?? "")
    }

    private func kindSuffix(_ isNovel: Bool?) -> String {
        guard let isNovel else { return "" }
        return isNovel ? " · Novels" : " · Manga"
    }

    /// "English · Manga", "7 languages · Manga", "2 of 7 languages · Manga".
    private func keiyoushiDetail(_ ext: KeiyoushiExtension, enabled: Set<String>?, origin: String?) -> String {
        let langs = Set(ext.sources.map(\.lang))
        let langText: String
        if langs.count <= 1 {
            langText = SourceLanguage.displayName(for: ext.lang)
        } else if let enabled, enabled.count < langs.count {
            langText = "\(enabled.count) of \(langs.count) languages"
        } else {
            langText = "\(langs.count) languages"
        }
        return langText + " · Manga" + (origin.map { " · \($0)" } ?? "")
    }

    private func catalogEntry(for ext: Extension) -> PluginCatalogEntry? {
        catalogService.entries.first { $0.id == ext.id } ?? catalogService.entries.first { $0.name == ext.name }
    }

    /// Novel or manga, from Browse's script check or the catalog; nil while unknown.
    private func isNovel(_ ext: Extension) -> Bool? {
        if let known = PluginKindCache.isNovel[ext.id] { return known }
        return catalogEntry(for: ext)?.knownIsNovel
    }

    private func repoName(for item: ExtensionItem) -> String? {
        switch item {
        case .installed(let ext):
            return catalogEntry(for: ext).map { PluginCatalogService.repoLabel(from: $0.repoURL) }
        case .available(let group):
            return PluginCatalogService.repoLabel(from: group.primaryEntry.repoURL)
        case .installedKeiyoushi, .availableKeiyoushi:
            return keiyoushi.repoName ?? "Keiyoushi"
        }
    }

    // MARK: Actions

    private func add(_ entry: PluginCatalogEntry) async {
        guard let fileURL = URL(string: entry.fileURL) else { return }
        busy.insert("js:\(entry.id)")
        defer { busy.remove("js:\(entry.id)") }
        await extensionManager.install(Extension(
            id:            entry.id,
            name:          entry.name,
            version:       entry.version,
            language:      entry.language,
            iconURL:       entry.iconURL.flatMap { URL(string: $0) },
            sourceListURL: fileURL,
            isInstalled:   true,
            isNSFW:        entry.isNSFW,
            sourceIds:     []
        ))
        if let error = extensionManager.errorMessage { errorToast = error }
    }

    private func updatePlugin(_ ext: Extension, to entry: PluginCatalogEntry) async {
        busy.insert("js:\(ext.id)")
        defer { busy.remove("js:\(ext.id)") }
        await extensionManager.update(ext, to: entry)
        if let error = extensionManager.errorMessage { errorToast = error }
    }

    private func installKeiyoushi(_ ext: KeiyoushiExtension, langs: [String]?) async {
        busy.insert("kei:\(ext.id)")
        defer { busy.remove("kei:\(ext.id)") }
        do {
            try await keiyoushi.install(ext, langs: langs)
        } catch {
            errorToast = error.localizedDescription
        }
    }

    private func updateAll() async {
        guard !isUpdatingAll else { return }
        isUpdatingAll = true
        let pending = extensionManager.installed.compactMap { ext in
            catalogService.availableUpdate(for: ext).map { (ext, $0) }
        }
        for (ext, entry) in pending {
            await updatePlugin(ext, to: entry)
        }
        let keiyoushiPending = keiyoushi.installed.compactMap { keiyoushi.availableUpdate(for: $0) }
        for ext in keiyoushiPending {
            await installKeiyoushi(ext, langs: nil)
        }
        isUpdatingAll = false
    }
}

// MARK: - NavBarSearch

/// `.searchable` only when the screen owns its navigation bar.
private struct NavBarSearch: ViewModifier {
    let enabled: Bool
    @Binding var text: String
    let prompt: String

    func body(content: Content) -> some View {
        if enabled {
            content.searchable(text: $text, prompt: prompt)
        } else {
            content
        }
    }
}

// MARK: - ExtensionItem

private enum ExtensionItem: Identifiable {
    case installed(Extension)
    case installedKeiyoushi(InstalledKeiyoushiExtension)
    case available(PluginCatalogGroup)
    case availableKeiyoushi(KeiyoushiExtension)

    var id: String {
        switch self {
        case .installed(let ext): return "js:\(ext.id)"
        case .installedKeiyoushi(let ext): return "kei:\(ext.id)"
        case .available(let group): return "jsgroup:\(group.id)"
        case .availableKeiyoushi(let ext): return "kei:\(ext.id)"
        }
    }

    var name: String {
        switch self {
        case .installed(let ext): return ext.name
        case .installedKeiyoushi(let ext): return ext.info.name
        case .available(let group): return group.name
        case .availableKeiyoushi(let ext): return ext.name
        }
    }
}

// MARK: - ExtensionRow

/// App Store-style row: icon, name, one grey line, one pill on the right. No tags, no versions (S140).
private struct ExtensionRow<Trailing: View>: View {
    let name: String
    let iconURL: URL?
    let detail: String
    let isNSFW: Bool
    @ViewBuilder let trailing: Trailing
    @Environment(\.yomiCanvas) private var canvas

    var body: some View {
        HStack(spacing: 14) {
            SourceIconBadge(name: name, iconURL: iconURL, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body)
                    .foregroundStyle(canvas.textPrimary)
                    .lineLimit(1)
                Text(isNSFW ? "\(detail) · 18+" : detail)
                    .font(.subheadline)
                    .foregroundStyle(canvas.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            trailing
        }
        .listRowInsets(EdgeInsets(top: 10, leading: YomiTokens.Layout.screenMargin,
                                  bottom: 10, trailing: YomiTokens.Layout.screenMargin))
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(canvas.hairline)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 58 }
    }
}

// MARK: - PillButton

/// Grey capsule, accent text — the App Store "Get" button, used for Add / Update / Languages.
struct PillButton: View {
    let title: String
    /// Shows this symbol instead of the title (the title stays as the accessibility label).
    var systemImage: String? = nil
    var busy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Group {
                    if let systemImage { Image(systemName: systemImage) } else { Text(title) }
                }
                .opacity(busy ? 0 : 1)
                if busy { ProgressView().controlSize(.small) }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, systemImage == nil ? 16 : 0)
            .frame(minWidth: systemImage == nil ? 72 : 44, minHeight: 30)
            .background(Color.primary.opacity(0.08), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.borderless)
        .disabled(busy)
        .accessibilityLabel(title)
    }
}

// MARK: - DeleteSwipe

/// Swipe left → red trash.
struct DeleteSwipe: ViewModifier {
    /// "Remove" where the swipe only takes a row out of a list (History) and deletes nothing.
    var title = "Delete"
    let action: () -> Void

    func body(content: Content) -> some View {
        content.swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: action) {
                Label(title, systemImage: "trash")
            }
            .tint(.red) // the app-wide accent tint would otherwise paint it blue

        }
    }
}

// MARK: - RepositoriesView

/// Every repository the user added (Yomi / LNReader catalogs and the Mihon index), in Settings and in Browse's
/// ⋯ menu. Removing one keeps the extensions already added from it.
struct RepositoriesView: View {
    @State private var settings       = AppSettings.shared
    @State private var catalogService = PluginCatalogService.shared
    @State private var keiyoushi      = KeiyoushiRepository.shared
    @State private var showAddRepo    = false
    @Environment(\.yomiCanvas) private var canvas

    var body: some View {
        List {
            Section {
                ForEach(settings.pluginCatalogURLs, id: \.self) { url in
                    let count = catalogService.entries.filter { $0.repoURL == url }.count
                    repositoryRow(name: PluginCatalogService.repoLabel(from: url), url: url,
                                  count: count == 0 ? nil : count)
                        .modifier(DeleteSwipe {
                            settings.pluginCatalogURLs.removeAll { $0 == url }
                            catalogService.invalidateCache()
                            Task { await catalogService.fetchCatalog(force: true) }
                        })
                }
                if !settings.keiyoushiRepoURL.isEmpty {
                    repositoryRow(name: keiyoushi.repoName ?? PluginCatalogService.repoLabel(from: settings.keiyoushiRepoURL),
                                  url: settings.keiyoushiRepoURL,
                                  count: keiyoushi.available.isEmpty ? nil : keiyoushi.available.count)
                        .modifier(DeleteSwipe {
                            settings.keiyoushiRepoURL = ""
                            Task { await keiyoushi.refresh() }
                        })
                }
                Button { showAddRepo = true } label: {
                    Label("Add Repository", systemImage: "plus")
                        .foregroundStyle(Color.accentColor)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 12, leading: YomiTokens.Layout.screenMargin,
                                          bottom: 12, trailing: YomiTokens.Layout.screenMargin))
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Swipe to remove a repository. Extensions you already added from it stay.")
                    if !KeiyoushiJVMHost.isAvailable && !settings.keiyoushiRepoURL.isEmpty {
                        Text("This build doesn't include the on-device runtime, so Mihon extensions can't run here.")
                    }
                }
                .font(.footnote)
                .foregroundStyle(canvas.textSecondary)
                .padding(.top, 8)
            }
        }
        .listStyle(.plain)
        .yomiListCanvas()
        .navigationTitle("Repositories")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showAddRepo) { AddRepoSheet() }
        .task {
            await catalogService.fetchCatalog()
            if keiyoushi.available.isEmpty, !settings.keiyoushiRepoURL.isEmpty { await keiyoushi.refresh() }
        }
    }

    private func repositoryRow(name: String, url: String, count: Int?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                    .font(.body)
                    .foregroundStyle(canvas.textPrimary)
                Spacer()
                if let count {
                    Text("\(count) extensions")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(canvas.textSecondary)
                }
            }
            Text(url)
                .font(.footnote)
                .foregroundStyle(canvas.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(canvas.hairline)
        .listRowInsets(EdgeInsets(top: 8, leading: YomiTokens.Layout.screenMargin,
                                  bottom: 8, trailing: YomiTokens.Layout.screenMargin))
        .contextMenu {
            Button { UIPasteboard.general.string = url } label: {
                Label("Copy Link", systemImage: "doc.on.doc")
            }
        }
    }
}

// MARK: - AddRepoSheet

/// Paste a repository link. No suggestions — Yomi doesn't point at sources (S140).
struct AddRepoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings  = AppSettings.shared
    @State private var customURL = ""
    @State private var error: String? = nil

    private var trimmed: String { customURL.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://…", text: $customURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit(add)
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text("Repository Link")
                } footer: {
                    Text("A Yomi or LNReader repository (.json), or a Mihon repository (index.pb).")
                }
                Section {
                    Link(destination: kYomiSetupGuideURL) {
                        Label("How to find repositories", systemImage: "book")
                    }
                }
            }
            .navigationTitle("Add Repository")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: add)
                        .disabled(trimmed.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func add() {
        guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true, url.host != nil else {
            error = "That doesn't look like a link."
            return
        }
        // A Mihon/Keiyoushi repository is a protobuf index, not a JSON catalog — it goes to the Keiyoushi runtime.
        if url.path.lowercased().hasSuffix(".pb") {
            settings.keiyoushiRepoURL = trimmed
            Task { await KeiyoushiRepository.shared.refresh() }
            dismiss()
            return
        }
        guard !settings.pluginCatalogURLs.contains(trimmed) else {
            error = "This repository is already added."
            return
        }
        settings.pluginCatalogURLs.append(trimmed)
        PluginCatalogService.shared.invalidateCache()
        Task { await PluginCatalogService.shared.fetchCatalog(force: true) }
        dismiss()
    }
}

// MARK: - InstallFromURLSheet

private struct InstallFromURLSheet: View {
    let extensionManager: ExtensionManager
    @Environment(\.dismiss) private var dismiss

    @State private var pluginURL    = ""
    @State private var pluginName   = ""
    @State private var pluginLang   = "en"
    @State private var isNSFW       = false
    @State private var isInstalling = false
    @State private var errorMessage: String? = nil

    private var canInstall: Bool {
        !pluginURL.trimmingCharacters(in: .whitespaces).isEmpty &&
        !pluginName.trimmingCharacters(in: .whitespaces).isEmpty &&
        URL(string: pluginURL.trimmingCharacters(in: .whitespaces)) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Extension Link") {
                    TextField("https://example.com/plugin.js", text: $pluginURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section("Details") {
                    TextField("Name", text: $pluginName)
                    TextField("Language (e.g. en)", text: $pluginLang)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Toggle("18+ content", isOn: $isNSFW)
                }
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Add Extension")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isInstalling {
                        ProgressView()
                    } else {
                        Button("Add") {
                            Task { await installFromURL() }
                        }
                        .disabled(!canInstall)
                        .fontWeight(.semibold)
                    }
                }
            }
        }
    }

    private func installFromURL() async {
        let urlString = pluginURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: urlString) else { return }

        let hash = SHA256.hash(data: Data(urlString.utf8))
        let id = String(hash.compactMap { String(format: "%02x", $0) }.joined().prefix(32).lowercased())

        isInstalling = true
        errorMessage = nil

        let nameToCheck = pluginName.trimmingCharacters(in: .whitespaces)
        if extensionManager.installed.contains(where: { $0.id == id || (!nameToCheck.isEmpty && $0.name.lowercased() == nameToCheck.lowercased()) }) {
            errorMessage = "This extension is already added."
            isInstalling = false
            return
        }

        let ext = Extension(
            id:            id,
            name:          pluginName.trimmingCharacters(in: .whitespaces),
            version:       "1.0.0",
            language:      pluginLang.trimmingCharacters(in: .whitespaces).lowercased(),
            iconURL:       nil,
            sourceListURL: url,
            isInstalled:   true,
            isNSFW:        isNSFW,
            sourceIds:     []
        )
        await extensionManager.install(ext)
        if let error = extensionManager.errorMessage {
            errorMessage = error
            isInstalling = false
        } else {
            dismiss()
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PluginsView()
    }
}
