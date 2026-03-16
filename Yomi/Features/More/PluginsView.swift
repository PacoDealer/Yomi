import SwiftUI
import CryptoKit

// MARK: - Keiyoushi catalog model

private struct KeiyoushiEntry: Codable, Identifiable {
    var id: String { pkg }
    let name: String
    let pkg: String
    let lang: String
    let version: String
    let nsfw: Int
}

// MARK: - PluginsView

struct PluginsView: View {
    @State private var extensionManager = ExtensionManager.shared

    // Catalog state
    @State private var catalogItems: [KeiyoushiEntry] = []
    @State private var isCatalogLoading = false
    @State private var catalogError: String? = nil
    @State private var searchText = ""

    // NSFW filter
    @State private var showNSFW: Bool = false

    // Install sheet
    @State private var showInstallSheet = false

    // Android info sheet
    @State private var androidInfoEntry: KeiyoushiEntry? = nil

    private var filteredCatalog: [KeiyoushiEntry] {
        var base = searchText.isEmpty ? catalogItems : catalogItems.filter { $0.name.localizedStandardContains(searchText) }
        if !showNSFW { base = base.filter { $0.nsfw == 0 } }
        return base
    }

    var body: some View {
        List {
            installedSection
            disclaimerBanner
            catalogSection
        }
        .navigationTitle("Plugins")
        .searchable(text: $searchText, prompt: "Search catalog")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showNSFW.toggle() } label: {
                    Label("NSFW", systemImage: showNSFW ? "eye" : "eye.slash")
                        .foregroundStyle(showNSFW ? .red : .secondary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showInstallSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showInstallSheet) {
            InstallFromURLSheet(extensionManager: extensionManager)
        }
        .sheet(item: $androidInfoEntry) { entry in
            AndroidExtensionInfoSheet(entry: entry)
        }
        .task { await loadCatalog() }
    }

    // MARK: Installed section

    private var installedSection: some View {
        Section {
            if extensionManager.installed.isEmpty {
                Text("No plugins installed yet.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
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

    // MARK: Disclaimer banner

    private var disclaimerBanner: some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Android extensions — reference only")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("The catalog below lists Keiyoushi extensions for Android. They cannot run on iOS. Tap ⓘ on any entry to learn more.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Catalog section

    @ViewBuilder
    private var catalogSection: some View {
        Section {
            if isCatalogLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 8)
            } else if let error = catalogError {
                Text("Failed to load catalog: \(error)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredCatalog) { entry in
                    CatalogEntryRow(entry: entry) {
                        androidInfoEntry = entry
                    }
                }
            }
        } header: {
            Text("Keiyoushi catalog (\(filteredCatalog.count))")
        }
    }

    // MARK: Load catalog

    private func loadCatalog() async {
        isCatalogLoading = true
        catalogError = nil
        do {
            let url = URL(string: "https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json")!
            let (data, _) = try await URLSession.shared.data(from: url)
            catalogItems = try JSONDecoder().decode([KeiyoushiEntry].self, from: data)
        } catch {
            catalogError = error.localizedDescription
        }
        isCatalogLoading = false
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

// MARK: - CatalogEntryRow

private struct CatalogEntryRow: View {
    let entry: KeiyoushiEntry
    let onInfo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Placeholder icon — Keiyoushi doesn't provide icon URLs in the index
            Image(systemName: "puzzlepiece.extension")
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .padding(8)
                .foregroundStyle(.secondary)
                .background(Color.secondary.opacity(0.12))
                .frame(width: 40, height: 40)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name).font(.headline)
                HStack(spacing: 6) {
                    LanguageBadge(language: entry.lang)
                    if entry.nsfw == 1 {
                        NSFWBadge()
                    }
                    Text("v\(entry.version)").font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                onInfo()
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - AndroidExtensionInfoSheet

private struct AndroidExtensionInfoSheet: View {
    let entry: KeiyoushiEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Android-only extension")
                                .fontWeight(.semibold)
                        }
                        Text("'\(entry.name)' is a Keiyoushi extension built as an Android .apk. It cannot be installed or run on iOS.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Yomi uses JS plugins (.js files) instead. This catalog is shown for reference so you can identify which sources exist and find or build a Yomi-compatible equivalent.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Details") {
                    LabeledContent("Name",     value: entry.name)
                    LabeledContent("Package",  value: entry.pkg)
                    LabeledContent("Language", value: entry.lang.uppercased())
                    LabeledContent("Version",  value: entry.version)
                    LabeledContent("NSFW",     value: entry.nsfw == 1 ? "Yes" : "No")
                }
            }
            .navigationTitle(entry.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - InstallFromURLSheet

private struct InstallFromURLSheet: View {
    let extensionManager: ExtensionManager
    @Environment(\.dismiss) private var dismiss

    @State private var pluginURL  = ""
    @State private var pluginName = ""
    @State private var pluginLang = "en"
    @State private var isNSFW     = false
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

        // Stable ID: first 32 chars of SHA256(url) as lowercase hex
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

private struct LanguageBadge: View {
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

private struct NSFWBadge: View {
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
