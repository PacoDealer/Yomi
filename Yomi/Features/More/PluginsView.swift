import SwiftUI
import CryptoKit

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
        url: "https://raw.githubusercontent.com/LNReader/lnreader-plugins/master/dist/plugins.min.json"
    ),
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

    private var filteredCatalog: [PluginCatalogEntry] {
        var base = searchText.isEmpty
            ? catalogService.entries
            : catalogService.entries.filter { $0.name.localizedStandardContains(searchText) }
        if !settings.showNSFW { base = base.filter { !$0.isNSFW } }
        return base
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
                    InstalledExtensionRow(ext: ext)
                }
                .onDelete { indexSet in
                    indexSet.forEach { i in
                        extensionManager.remove(extensionManager.installed[i])
                    }
                }
            }
        } header: {
            Text("Installed")
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
            } else if filteredCatalog.isEmpty {
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
                ForEach(filteredCatalog) { entry in
                    YomiCatalogEntryRow(
                        entry:        entry,
                        isInstalled:  catalogService.isInstalled(entry),
                        isInstalling: installingID == entry.id
                    ) {
                        Task { await installEntry(entry) }
                    }
                }
            }
        } header: {
            Text("Yomi catalog (\(filteredCatalog.count))")
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
}

// MARK: - FeaturedRepoRow

private struct FeaturedRepoRow: View {
    let repo: FeaturedRepo
    @State private var settings = AppSettings.shared

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
                Button("Add") {
                    settings.pluginCatalogURLs.append(repo.url)
                    PluginCatalogService.shared.invalidateCache()
                    Task { await PluginCatalogService.shared.fetchCatalog(force: true) }
                }
                .buttonStyle(.borderedProminent)
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
                    Text("Tap Add to subscribe to a community plugin catalog.")
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
                Button("Add") {
                    settings.pluginCatalogURLs.append(repo.url)
                    PluginCatalogService.shared.invalidateCache()
                    Task { await PluginCatalogService.shared.fetchCatalog(force: true) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }
}

// MARK: - InstalledExtensionRow

private struct InstalledExtensionRow: View {
    let ext: Extension

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: ext.iconURL) { image in
                image.resizable().aspectRatio(1, contentMode: .fit)
            } placeholder: {
                Image(systemName: "puzzlepiece.extension")
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .padding(8)
                    .foregroundStyle(.secondary)
                    .background(Color.secondary.opacity(0.15))
            }
            .frame(width: 40, height: 40)
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 3) {
                Text(ext.name).font(.headline)
                HStack(spacing: 6) {
                    LanguageBadge(language: ext.language)
                    Text("v\(ext.version)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - YomiCatalogEntryRow

struct YomiCatalogEntryRow: View {
    let entry:        PluginCatalogEntry
    let isInstalled:  Bool
    let isInstalling: Bool
    let onInstall:    () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: entry.iconURL.flatMap { URL(string: $0) }) { image in
                image.resizable().aspectRatio(1, contentMode: .fit)
            } placeholder: {
                Image(systemName: "puzzlepiece.extension")
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .padding(8)
                    .foregroundStyle(.secondary)
                    .background(Color.secondary.opacity(0.12))
            }
            .frame(width: 40, height: 40)
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name).font(.headline)
                HStack(spacing: 6) {
                    LanguageBadge(language: entry.language)
                    if entry.isNSFW { NSFWBadge() }
                    Text("v\(entry.version)").font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isInstalled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if isInstalling {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Button("Install", action: onInstall)
                    .buttonStyle(.borderedProminent)
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

        if extensionManager.installed.contains(where: { $0.id == id }) {
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
