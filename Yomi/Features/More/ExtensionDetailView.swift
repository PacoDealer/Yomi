import SwiftUI

// MARK: - ExtensionDetailView
//
// L3b (S171): an extension's own page, opened by tapping its row in Extensions — installed or not (Mihon's extension
// details; Tachimanga v2.1/v4.14 "open a source's website without installing"). Shows what the repository says about
// it, opens the source's website in Yomi's web view (same cookie store as the plugins, so a Cloudflare check or a
// login there also helps the source), and for Keiyoushi lists every source with its own settings (before, only
// reachable from that source's Browse screen). Yomi/LNReader plugins have no settings of their own.
//
// The page resolves its extension from the live managers each render, so Add/Update/Remove show at once.

enum ExtensionDetailTarget: Hashable {
    /// A JS plugin: installed (its id) and/or a catalog group (name + repository).
    case plugin(installedId: String?, groupName: String?, repoURL: String?)
    case keiyoushi(packageName: String)
}

struct ExtensionDetailView: View {
    let target: ExtensionDetailTarget
    /// Installs and updates run in `PluginsView` (its busy rows and error toast).
    let busy: Set<String>
    let onAdd: (PluginCatalogEntry) async -> Void
    let onUpdate: (Extension, PluginCatalogEntry) async -> Void
    let onInstallKeiyoushi: (KeiyoushiExtension, [String]?) async -> Void

    @State private var extensionManager = ExtensionManager.shared
    @State private var catalogService   = PluginCatalogService.shared
    @State private var keiyoushi        = KeiyoushiRepository.shared
    @Environment(\.yomiCanvas) private var canvas
    @Environment(\.dismiss) private var dismiss

    @State private var website: String?
    @State private var confirmRemove = false
    @State private var showLangPicker = false
    @State private var keiyoushiInstallPick: KeiyoushiExtension?
    @State private var keiyoushiLanguageEdit: InstalledKeiyoushiExtension?

    var body: some View {
        CalmList {
            switch target {
            case let .plugin(installedId, groupName, repoURL):
                pluginContent(installed: installedPlugin(installedId, groupName, repoURL),
                              group: catalogGroup(installedId, groupName, repoURL))
            case .keiyoushi(let packageName):
                keiyoushiContent(packageName)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: Binding(get: { website.map(WebsiteLink.init) }, set: { website = $0?.url })) { link in
            CFBypassView(initialURL: link.url, isWebsite: true) {}
        }
        .sheet(item: $keiyoushiInstallPick) { ext in
            KeiyoushiLanguageSheet(ext: ext, initial: KeiyoushiLanguageSheet.defaultSelection(for: ext),
                                   confirmTitle: "Add") { langs in
                Task { await onInstallKeiyoushi(ext, langs) }
            }
        }
        .sheet(item: $keiyoushiLanguageEdit) { installed in
            KeiyoushiLanguageSheet(ext: installed.info, initial: Set(installed.enabledSources.map(\.lang)),
                                   confirmTitle: "Done") { langs in
                keiyoushi.setEnabledLangs(langs, for: installed.id)
            }
        }
    }

    // MARK: Plugin (Yomi / LNReader / Mangayomi)

    private func installedPlugin(_ id: String?, _ name: String?, _ repoURL: String?) -> Extension? {
        if let id, let ext = extensionManager.installed.first(where: { $0.id == id }) { return ext }
        guard let group = catalogGroup(id, name, repoURL) else { return nil }
        return extensionManager.installed.first { ext in group.entries.contains { $0.matches(ext) } }
    }

    private func catalogGroup(_ id: String?, _ name: String?, _ repoURL: String?) -> PluginCatalogGroup? {
        if let name, let group = catalogService.groupedEntries.first(where: {
            $0.name == name && (repoURL == nil || $0.primaryEntry.repoURL == repoURL)
        }) { return group }
        guard let id, let ext = extensionManager.installed.first(where: { $0.id == id }),
              let entry = catalogService.entries.first(where: { $0.matches(ext) }) else { return nil }
        return catalogService.groupedEntries.first { $0.entries.contains { $0.id == entry.id && $0.repoURL == entry.repoURL } }
    }

    @ViewBuilder
    private func pluginContent(installed: Extension?, group: PluginCatalogGroup?) -> some View {
        let entry = installed.flatMap { ext in catalogService.entries.first { $0.matches(ext) } } ?? group?.primaryEntry
        let name = installed?.name ?? group?.name ?? entry?.name ?? String(localized: "Extension")
        let update = installed.flatMap { catalogService.availableUpdate(for: $0) }
        let isNovel = installed.flatMap { PluginKindCache.isNovel[$0.id] } ?? entry?.knownIsNovel
        let languages = group.map { $0.entries.map(\.language) } ?? [installed?.language ?? entry?.language ?? ""]

        header(name: name, iconURL: installed?.iconURL ?? entry?.iconURL.flatMap(URL.init(string:)),
               line: [installed.map { String(localized: "Version \($0.version)") } ?? entry.map { String(localized: "Version \($0.version)") },
                      isNovel.map { $0 ? String(localized: "Novels") : String(localized: "Manga") }].compactMap { $0 }.joined(separator: " · "),
               isNSFW: installed?.isNSFW ?? entry?.isNSFW ?? false, isMihonIcon: false)

        Section {
            HStack(spacing: 10) {
                if let installed {
                    if let update {
                        PillButton(title: "Update to \(update.version)", busy: busy.contains("js:\(installed.id)")) {
                            Task { await onUpdate(installed, update) }
                        }
                    } else {
                        Label("Added", systemImage: "checkmark").font(.subheadline.weight(.semibold))
                            .foregroundStyle(canvas.textSecondary)
                    }
                } else if let group {
                    PillButton(title: "Add", busy: group.entries.contains { busy.contains("js:\($0.id)") }) {
                        if group.isMultiLang { showLangPicker = true } else { Task { await onAdd(group.primaryEntry) } }
                    }
                }
                Spacer()
                if let site = entry?.site, URL(string: site)?.scheme != nil {
                    PillButton(title: "Website") { website = site }
                }
            }
        }
        .confirmationDialog("Add \(name)", isPresented: $showLangPicker, titleVisibility: .visible) {
            ForEach(group?.entries ?? []) { e in
                let added = catalogService.isInstalled(e)
                Button(added ? "\(SourceLanguage.displayName(for: e.language)) — Added"
                             : SourceLanguage.displayName(for: e.language)) {
                    if !added { Task { await onAdd(e) } }
                }
                .disabled(added)
            }
            Button("Cancel", role: .cancel) {}
        }

        if let text = entry?.description, !text.isEmpty, URL(string: text)?.scheme == nil {
            Section(calm: "About") {
                Text(text).foregroundStyle(canvas.textPrimary)
            }
        }

        Section(calm: "Information") {
            infoRow("Language", languages.map(SourceLanguage.displayName(for:)).joined(separator: ", "))
            if let entry { infoRow("Repository", PluginCatalogService.repoLabel(from: entry.repoURL)) }
            if let site = entry?.site { infoRow("Website", URL(string: site)?.host() ?? site) }
            if installed != nil, entry == nil { infoRow("Source", String(localized: "Added from a link")) }
        }

        if let installed {
            Section {
                if let previous = extensionManager.previousVersion(of: installed) {
                    Button("Go Back to Version \(previous)", systemImage: "arrow.uturn.backward") {
                        extensionManager.restorePrevious(of: installed)
                    }
                }
                Button("Remove", systemImage: "trash", role: .destructive) { confirmRemove = true }
                    .confirmationDialog("Remove \(name)?", isPresented: $confirmRemove, titleVisibility: .visible) {
                        Button("Remove", role: .destructive) {
                            extensionManager.remove(installed)
                            dismiss()
                        }
                    } message: {
                        Text("Titles from it stay in your library; their chapters load again once it's added back.")
                    }
            }
        }
    }

    // MARK: Keiyoushi

    @ViewBuilder
    private func keiyoushiContent(_ packageName: String) -> some View {
        let installed = keiyoushi.installed.first { $0.id == packageName }
        if let info = installed?.info ?? keiyoushi.available.first(where: { $0.id == packageName }) {
            let update = installed.flatMap { keiyoushi.availableUpdate(for: $0) }
            let enabled = Set((installed?.enabledSources ?? []).map(\.id))
            let homes = Set(info.sources.map(\.homeURL).filter { !$0.isEmpty })

            header(name: info.name, iconURL: URL(string: info.iconURL),
                   line: String(localized: "Version \(info.versionName) · Manga"), isNSFW: info.isNSFW, isMihonIcon: true)

            Section {
                HStack(spacing: 10) {
                    if let installed {
                        if let update {
                            PillButton(title: "Update to \(update.versionName)", busy: busy.contains("kei:\(packageName)")) {
                                Task { await onInstallKeiyoushi(update, nil) }
                            }
                        } else if Set(info.sources.map(\.lang)).count > 1 {
                            PillButton(title: "Languages", systemImage: "globe") { keiyoushiLanguageEdit = installed }
                        } else {
                            Label("Added", systemImage: "checkmark").font(.subheadline.weight(.semibold))
                                .foregroundStyle(canvas.textSecondary)
                        }
                    } else {
                        PillButton(title: "Add", busy: busy.contains("kei:\(packageName)")) {
                            if Set(info.sources.map(\.lang)).count > 1 {
                                keiyoushiInstallPick = info
                            } else {
                                Task { await onInstallKeiyoushi(info, nil) }
                            }
                        }
                    }
                    Spacer()
                    // One website for the whole extension when its sources share it; else each source has its own.
                    if homes.count == 1, let site = homes.first {
                        PillButton(title: "Website") { website = site }
                    }
                }
            }

            Section {
                ForEach(info.sources.sorted { lhs, rhs in
                    let l = enabled.contains(lhs.id), r = enabled.contains(rhs.id)
                    if l != r { return l }
                    return SourceLanguage.displayName(for: lhs.lang)
                        .localizedCaseInsensitiveCompare(SourceLanguage.displayName(for: rhs.lang)) == .orderedAscending
                }) { source in
                    sourceRow(source, isOn: enabled.contains(source.id), showWebsite: homes.count > 1)
                }
            } header: { CalmSectionHeader("Sources") } footer: {
                Text(installed == nil
                     ? "Add the extension to change a source's settings."
                     : "A source's settings are its extension's own (e.g. image quality, hiding premium chapters). Off = a language you didn't turn on.")
            }

            Section(calm: "Information") {
                infoRow("Language", SourceLanguage.displayName(for: info.lang))
                infoRow("Repository", keiyoushi.repoName(for: info))
                infoRow("Package", info.packageName)
            }

            if let installed {
                Section {
                    Button("Remove", systemImage: "trash", role: .destructive) { confirmRemove = true }
                        .confirmationDialog("Remove \(info.name)?", isPresented: $confirmRemove, titleVisibility: .visible) {
                            Button("Remove", role: .destructive) {
                                Task { await keiyoushi.uninstall(installed) }
                                dismiss()
                            }
                        } message: {
                            Text("Titles from it stay in your library; their chapters load again once it's added back.")
                        }
                }
            }
        } else {
            YomiEmptyState(systemImage: "puzzlepiece.extension", title: "Not available",
                           message: "This extension isn't in your repositories any more.")
        }
    }

    @ViewBuilder
    private func sourceRow(_ source: KeiyoushiSource, isOn: Bool, showWebsite: Bool) -> some View {
        let label = HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name).foregroundStyle(canvas.textPrimary)
                Text(isOn || keiyoushi.installed.isEmpty ? SourceLanguage.displayName(for: source.lang)
                                                         : "\(SourceLanguage.displayName(for: source.lang)) · Off")
                    .font(.subheadline).foregroundStyle(canvas.textSecondary)
            }
            Spacer()
            if showWebsite, !source.homeURL.isEmpty {
                Button { website = source.homeURL } label: { Image(systemName: "safari") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("\(source.name) website")
            }
        }
        if isOn {
            NavigationLink { KeiyoushiSourceSettingsView(source: source) } label: { label }
                .accessibilityHint("Opens this source's settings")
        } else {
            label
        }
    }

    // MARK: Pieces

    private func header(name: String, iconURL: URL?, line: String, isNSFW: Bool, isMihonIcon: Bool) -> some View {
        VStack(spacing: 10) {
            SourceIconBadge(name: name, iconURL: iconURL, size: 72, isMihonIcon: isMihonIcon)
            Text(name).font(.title2.bold()).foregroundStyle(canvas.textPrimary).multilineTextAlignment(.center)
            Text(isNSFW ? "\(line) · 18+" : line).font(.subheadline).foregroundStyle(canvas.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func infoRow(_ title: LocalizedStringKey, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value).foregroundStyle(canvas.textSecondary).multilineTextAlignment(.trailing)
        }
        .foregroundStyle(canvas.textPrimary)
    }
}

/// `fullScreenCover(item:)` wants an Identifiable.
private struct WebsiteLink: Identifiable {
    let url: String
    var id: String { url }
}
