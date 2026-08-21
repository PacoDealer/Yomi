import SwiftUI
import CryptoKit
import Kingfisher

// MARK: - Constants

private let kYomiSetupGuideURL = URL(string: "https://github.com/PacoDealer/Yomi#plugin-repositories")!

// MARK: - Featured repos

private struct FeaturedRepo: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let url: String
}

private let featuredRepos: [FeaturedRepo] = [
    FeaturedRepo(
        name: "LNReader Novels",
        description: "500+ light novel sources in 18 languages",
        url: "https://raw.githubusercontent.com/LNReader/lnreader-plugins/plugins/v3.0.0/.dist/plugins.min.json"
    ),
]

// Keiyoushi (1000+ manga via Suwayomi server) is surfaced in Settings → Suwayomi Server,
// not as a catalog URL — it requires a REST bridge, not a JS plugin catalog.
// Mangayomi extensions are Dart (not JS) — cannot run in JSC. Removed from featured repos.

/// Catalog entries reachable via a documented public API (MangaDex) or that host only
/// originally-authored content on their own platform (Royal Road, Scribble Hub) — these are
/// the only sources in the Yomi-hosted catalog that aren't unlicensed third-party scrapes of
/// someone else's copyrighted translations. App Store Guideline 5.2.2 requires being
/// "specifically permitted" to access/display third-party content; everything not on this list
/// requires an explicit Copy URL + manual add instead of one-tap install, the same friction
/// already applied to the LNReader featured repo below. Deny-by-default: any new catalog entry
/// defaults to the manual-add path unless explicitly allowlisted here.
private let instantInstallSourceIDs: Set<String> = [
    "com.yomi.mangadex",
    "com.yomi.royalroad",
    "com.yomi.scribblehub",
]

// MARK: - PluginsView

struct PluginsView: View {
    @State private var extensionManager = ExtensionManager.shared
    @State private var catalogService   = PluginCatalogService.shared
    @State private var settings         = AppSettings.shared

    @State private var searchText        = ""
    @State private var showInstallSheet  = false
    @State private var showAddRepoSheet  = false
    @State private var installingID: String? = nil
    @State private var isUpdatingAll: Bool = false
    @State private var langPickerGroup: PluginCatalogGroup? = nil
    @State private var langPickerCopyGroup: PluginCatalogGroup? = nil

    private var filteredGroups: [PluginCatalogGroup] {
        var groups = settings.showNSFW
            ? catalogService.groupedEntries
            : catalogService.groupedEntries.filter { !$0.primaryEntry.isNSFW }
        if !searchText.isEmpty {
            groups = groups.filter { $0.name.localizedStandardContains(searchText) }
        }
        return groups
    }

    var body: some View {
        List {
            installedSection
            catalogSection
        }
        .navigationTitle("Plugins")
        .searchable(text: $searchText, prompt: "Search catalog")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { settings.showNSFW.toggle() } label: {
                    Label("NSFW", systemImage: settings.showNSFW ? "eye" : "eye.slash")
                        .foregroundStyle(settings.showNSFW ? .red : .secondary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showAddRepoSheet = true
                    } label: {
                        Label("Add Repository", systemImage: "externaldrive.badge.plus")
                    }
                    Button {
                        showInstallSheet = true
                    } label: {
                        Label("Install from URL", systemImage: "puzzlepiece.extension")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showInstallSheet) {
            InstallFromURLSheet(extensionManager: extensionManager)
        }
        .sheet(isPresented: $showAddRepoSheet) {
            AddRepoSheet()
        }
        .confirmationDialog(
            langPickerGroup.map { "Install \($0.name)" } ?? "",
            isPresented: Binding(get: { langPickerGroup != nil }, set: { if !$0 { langPickerGroup = nil } }),
            titleVisibility: .visible
        ) {
            if let group = langPickerGroup {
                ForEach(group.entries) { entry in
                    let installed = catalogService.isInstalled(entry)
                    Button(installed ? "\(entry.language.uppercased()) — Installed" : entry.language.uppercased()) {
                        if !installed { Task { await installEntry(entry) } }
                    }
                    .disabled(installed)
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .confirmationDialog(
            langPickerCopyGroup.map { "Copy \($0.name) URL" } ?? "",
            isPresented: Binding(get: { langPickerCopyGroup != nil }, set: { if !$0 { langPickerCopyGroup = nil } }),
            titleVisibility: .visible
        ) {
            if let group = langPickerCopyGroup {
                ForEach(group.entries) { entry in
                    Button(entry.language.uppercased()) {
                        UIPasteboard.general.string = entry.fileURL
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .onAppear { Task { await catalogService.fetchCatalog() } }
        .refreshable { await catalogService.fetchCatalog(force: true) }
    }

    // MARK: Installed section

    private var installedSection: some View {
        Section {
            if extensionManager.installed.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No plugins installed")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Plugins connect Yomi to manga and novel sources. Add a repository to get started.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    Text("Featured repositories")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    ForEach(featuredRepos) { repo in
                        FeaturedRepoRow(repo: repo)
                    }

                    Link(destination: kYomiSetupGuideURL) {
                        HStack(spacing: 4) {
                            Text("Plugin setup guide")
                                .font(.caption)
                                .foregroundStyle(.tint)
                            Image(systemName: "arrow.up.right")
                                .font(.caption2)
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .padding(.vertical, 6)
            } else {
                ForEach(extensionManager.installed) { ext in
                    InstalledExtensionRow(
                        ext: ext,
                        updateEntry: catalogService.availableUpdate(for: ext),
                        isUpdating: installingID == ext.id,
                        isUpdateAllRunning: isUpdatingAll
                    ) {
                        if let entry = catalogService.availableUpdate(for: ext) {
                            Task { await installEntry(entry) }
                        }
                    }
                }
                .onDelete { indexSet in
                    indexSet.forEach { i in
                        extensionManager.remove(extensionManager.installed[i])
                    }
                }
            }
        } header: {
            HStack {
                Text("Installed")
                let updateCount = extensionManager.installed.filter {
                    catalogService.availableUpdate(for: $0) != nil
                }.count
                if updateCount > 0 {
                    Text("\(updateCount) update\(updateCount == 1 ? "" : "s") available")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Spacer()
                    if isUpdatingAll {
                        ProgressView().controlSize(.mini)
                    } else if updateCount > 1 {
                        Button("Update all") {
                            Task { await updateAll() }
                        }
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    // MARK: Catalog section

    @ViewBuilder
    private var catalogSection: some View {
        Section {
            if catalogService.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 8)
            } else if let error = catalogService.errorMessage {
                VStack(spacing: 12) {
                    Text("Failed to load catalog: \(error)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await catalogService.fetchCatalog() }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else if filteredGroups.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    if !searchText.isEmpty {
                        Text("No results for \"\(searchText)\"")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Catalog is empty")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Retry") {
                            Task { await catalogService.fetchCatalog() }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(filteredGroups) { group in
                    CatalogGroupRow(
                        group:            group,
                        isInstalled:      catalogService.isGroupInstalled(group),
                        installingID:     installingID,
                        isInstantInstall: instantInstallSourceIDs.contains(group.primaryEntry.id),
                        onInstall: {
                            if group.isMultiLang {
                                langPickerGroup = group
                            } else {
                                Task { await installEntry(group.primaryEntry) }
                            }
                        },
                        onCopyURL: {
                            if group.isMultiLang {
                                langPickerCopyGroup = group
                            } else {
                                UIPasteboard.general.string = group.primaryEntry.fileURL
                            }
                        }
                    )
                }
            }
        } header: {
            Text("Catalog (\(filteredGroups.count))")
        } footer: {
            if filteredGroups.contains(where: { !instantInstallSourceIDs.contains($0.primaryEntry.id) }) {
                Text("Sources marked \"Copy URL\" are third-party — paste the URL via + → Install from URL to add them.")
            }
        }
    }

    // MARK: Install from catalog

    private func installEntry(_ entry: PluginCatalogEntry) async {
        guard let fileURL = URL(string: entry.fileURL) else { return }
        installingID = entry.id

        let ext = Extension(
            id:            entry.id,
            name:          entry.name,
            version:       entry.version,
            language:      entry.language,
            iconURL:       entry.iconURL.flatMap { URL(string: $0) },
            sourceListURL: fileURL,
            isInstalled:   true,
            isNSFW:        entry.isNSFW,
            sourceIds:     []
        )
        await extensionManager.install(ext)
        installingID = nil
    }

    private func updateAll() async {
        guard !isUpdatingAll else { return }
        isUpdatingAll = true
        let pending = extensionManager.installed.compactMap { catalogService.availableUpdate(for: $0) }
        for entry in pending {
            await installEntry(entry)
        }
        isUpdatingAll = false
    }
}

// MARK: - FeaturedRepoRow

private struct FeaturedRepoRow: View {
    let repo: FeaturedRepo
    @State private var settings = AppSettings.shared
    @State private var justCopied = false

    private var isAlreadyAdded: Bool {
        settings.pluginCatalogURLs.contains(repo.url)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(repo.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(repo.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isAlreadyAdded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button(justCopied ? "Copied" : "Copy URL") {
                    UIPasteboard.general.string = repo.url
                    withAnimation { justCopied = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        withAnimation { justCopied = false }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}

// MARK: - AddRepoSheet

private struct AddRepoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings   = AppSettings.shared
    @State private var customURL  = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(featuredRepos) { repo in
                        AddRepoFeaturedRow(repo: repo)
                    }
                } header: {
                    Text("Featured")
                } footer: {
                    Text("Copy a featured repo's URL, then paste it below to subscribe to it.")
                }

                Section {
                    TextField("https://example.com/index.json", text: $customURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("Add") {
                        addCustomURL()
                    }
                    .disabled(customURL.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("Custom URL")
                }

                Section {
                    Link(destination: kYomiSetupGuideURL) {
                        HStack {
                            Label("Plugin setup guide", systemImage: "book")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Find more repositories and learn how to use Yomi plugins on GitHub.")
                }
            }
            .navigationTitle("Add Repository")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func addCustomURL() {
        let trimmed = customURL.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !settings.pluginCatalogURLs.contains(trimmed) else { return }
        settings.pluginCatalogURLs.append(trimmed)
        PluginCatalogService.shared.invalidateCache()
        Task { await PluginCatalogService.shared.fetchCatalog(force: true) }
        customURL = ""
        dismiss()
    }
}

// MARK: - AddRepoFeaturedRow

private struct AddRepoFeaturedRow: View {
    let repo: FeaturedRepo
    @State private var settings = AppSettings.shared
    @State private var justCopied = false

    private var isAlreadyAdded: Bool {
        settings.pluginCatalogURLs.contains(repo.url)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(repo.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(repo.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isAlreadyAdded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button(justCopied ? "Copied" : "Copy URL") {
                    UIPasteboard.general.string = repo.url
                    withAnimation { justCopied = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        withAnimation { justCopied = false }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}

// MARK: - InstalledExtensionRow

private struct InstalledExtensionRow: View {
    let ext: Extension
    let updateEntry: PluginCatalogEntry?
    let isUpdating: Bool
    let isUpdateAllRunning: Bool
    let onUpdate: () -> Void
    @State private var isNovelPlugin: Bool? = nil

    var body: some View {
        HStack(spacing: 12) {
            KFImage(ext.iconURL)
                .placeholder {
                    Image(systemName: "puzzlepiece.extension")
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .padding(8)
                        .foregroundStyle(.secondary)
                        .background(Color.secondary.opacity(0.15))
                }
                .fade(duration: 0.2)
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .frame(width: 40, height: 40)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 3) {
                Text(ext.name).font(.headline)
                HStack(spacing: 6) {
                    LanguageBadge(language: ext.language)
                    if let isNovel = isNovelPlugin {
                        Text(isNovel ? "Novel" : "Manga")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((isNovel ? Color.purple : Color.blue).opacity(0.15))
                            .foregroundStyle(isNovel ? Color.purple : Color.blue)
                            .clipShape(Capsule())
                    }
                    Text("v\(ext.version)").font(.caption).foregroundStyle(.secondary)
                    if let update = updateEntry {
                        Text("→ v\(update.version)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            if let _ = updateEntry {
                if isUpdating || isUpdateAllRunning {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Update", action: onUpdate)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.orange)
                }
            }
        }
        .padding(.vertical, 2)
        .task(id: ext.id) {
            let id = ext.id
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let url = docs.appendingPathComponent("Extensions/\(id).js")
            isNovelPlugin = (try? String(contentsOf: url, encoding: .utf8))?.contains("popularNovels") ?? false
        }
    }
}

// MARK: - CatalogGroupRow

struct CatalogGroupRow: View {
    let group:            PluginCatalogGroup
    let isInstalled:      Bool
    let installingID:     String?
    let isInstantInstall: Bool
    let onInstall:        () -> Void
    let onCopyURL:        () -> Void

    @State private var justCopied = false

    private var isInstalling: Bool {
        group.entries.contains { $0.id == installingID }
    }
    private var repoLabel: String {
        PluginCatalogService.repoLabel(from: group.primaryEntry.repoURL)
    }

    var body: some View {
        HStack(spacing: 12) {
            KFImage(group.primaryEntry.iconURL.flatMap { URL(string: $0) })
                .placeholder {
                    Image(systemName: "puzzlepiece.extension")
                        .resizable().aspectRatio(1, contentMode: .fit)
                        .padding(8)
                        .foregroundStyle(.secondary)
                        .background(Color.secondary.opacity(0.12))
                }
                .fade(duration: 0.2)
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .frame(width: 40, height: 40)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 3) {
                Text(group.name).font(.headline)
                HStack(spacing: 5) {
                    if group.isMultiLang {
                        Text("\(group.entries.count) langs")
                            .font(.caption2).fontWeight(.semibold)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    } else {
                        LanguageBadge(language: group.primaryEntry.language)
                    }
                    if group.primaryEntry.isNovel {
                        Text("Novel")
                            .font(.caption2).fontWeight(.semibold)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.purple.opacity(0.15))
                            .foregroundStyle(Color.purple)
                            .clipShape(Capsule())
                    }
                    if group.primaryEntry.isNSFW { NSFWBadge() }
                    if !repoLabel.isEmpty {
                        Text(repoLabel)
                            .font(.caption2).fontWeight(.medium)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                    }
                    Text("v\(group.primaryEntry.version)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isInstalled {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else if isInstalling {
                ProgressView().scaleEffect(0.8)
            } else if isInstantInstall {
                Button(group.isMultiLang ? "Get" : "Install", action: onInstall)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else {
                Button(justCopied ? "Copied" : "Copy URL") {
                    if group.isMultiLang {
                        onCopyURL()
                        return
                    }
                    UIPasteboard.general.string = group.primaryEntry.fileURL
                    withAnimation { justCopied = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        withAnimation { justCopied = false }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
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
                Section("Plugin URL") {
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
                    Toggle("NSFW content", isOn: $isNSFW)
                }
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Install Plugin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isInstalling {
                        ProgressView()
                    } else {
                        Button("Install") {
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
            errorMessage = "This plugin is already installed."
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

// MARK: - Shared badge helpers

struct LanguageBadge: View {
    let language: String
    var body: some View {
        Text(language.uppercased())
            .font(.caption2).fontWeight(.semibold)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.15))
            .foregroundStyle(.tint)
            .clipShape(Capsule())
    }
}

struct NSFWBadge: View {
    var body: some View {
        Text("18+")
            .font(.caption2).fontWeight(.semibold)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.red.opacity(0.15))
            .foregroundStyle(.red)
            .clipShape(Capsule())
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PluginsView()
    }
}
