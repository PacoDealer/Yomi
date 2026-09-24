import Kingfisher
import SwiftUI

// Keiyoushi (Mihon) extensions are installed from More → Extensions (PluginsView), next to Yomi's own plugins —
// this file holds the Keiyoushi-specific pieces those screens and Browse use.

// MARK: - KeiyoushiLanguagesView

/// Browse → a multi-language extension (e.g. MangaFire): pick which language to open. Lists only the languages the
/// user enabled; the toolbar button changes that set.
struct KeiyoushiLanguagesView: View {
    let packageName: String
    @Environment(\.yomiCanvas) private var canvas
    @State private var repo = KeiyoushiRepository.shared
    @State private var editing = false

    private var ext: InstalledKeiyoushiExtension? {
        repo.installed.first { $0.id == packageName }
    }

    private var sources: [KeiyoushiSource] {
        (ext?.enabledSources ?? []).sorted {
            SourceLanguage.displayName(for: $0.lang)
                .localizedCaseInsensitiveCompare(SourceLanguage.displayName(for: $1.lang)) == .orderedAscending
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(sources) { source in
                    NavigationLink {
                        KeiyoushiBrowseView(source: source)
                    } label: {
                        HStack {
                            Text(SourceLanguage.displayName(for: source.lang))
                                .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.body))
                                .foregroundStyle(canvas.textPrimary)
                            Spacer()
                            Text(source.lang.uppercased())
                                .font(YomiTokens.Font.mono(11))
                                .foregroundStyle(canvas.textSecondary)
                        }
                    }
                }
            } footer: {
                if let ext, sources.count < ext.info.sources.count {
                    Text("Showing \(sources.count) of \(ext.info.sources.count) languages.")
                }
            }
        }
        .yomiListCanvas()
        .navigationTitle(ext?.info.name ?? "Languages")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Languages") { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            if let ext {
                KeiyoushiLanguageSheet(ext: ext.info, initial: Set(ext.enabledSources.map(\.lang)),
                                       confirmTitle: "Done") { langs in
                    repo.setEnabledLangs(langs, for: ext.id)
                }
            }
        }
    }
}

// MARK: - KeiyoushiLanguageSheet

/// Choose which languages of a multi-language extension to show. Used before installing and to change it later.
struct KeiyoushiLanguageSheet: View {
    let ext: KeiyoushiExtension
    let initial: Set<String>
    let confirmTitle: String
    let onConfirm: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.yomiCanvas) private var canvas
    @State private var selected: Set<String> = []

    private var langs: [String] {
        Array(Set(ext.sources.map(\.lang))).sorted {
            SourceLanguage.displayName(for: $0).localizedCaseInsensitiveCompare(SourceLanguage.displayName(for: $1))
                == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(langs, id: \.self) { lang in
                        Button {
                            if selected.contains(lang) { selected.remove(lang) } else { selected.insert(lang) }
                        } label: {
                            HStack {
                                Text(SourceLanguage.displayName(for: lang))
                                    .foregroundStyle(canvas.textPrimary)
                                Spacer()
                                Text(lang.uppercased())
                                    .font(YomiTokens.Font.mono(11))
                                    .foregroundStyle(canvas.textSecondary)
                                Image(systemName: selected.contains(lang) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(lang) ? Color.accentColor : canvas.textSecondary)
                            }
                        }
                        .accessibilityAddTraits(selected.contains(lang) ? .isSelected : [])
                    }
                } footer: {
                    Text("\(ext.name) is available in \(langs.count) languages. Only the ones you pick show in Browse.")
                }
            }
            .yomiListCanvas()
            .navigationTitle(ext.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle) {
                        onConfirm(Array(selected))
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(selected.count == langs.count ? "Select none" : "Select all") {
                        selected = selected.count == langs.count ? [] : Set(langs)
                    }
                }
            }
            .onAppear { selected = initial }
        }
        .presentationDetents([.medium, .large])
    }

    /// The languages to preselect when installing: the phone's language if the extension has it, else English,
    /// else everything.
    static func defaultSelection(for ext: KeiyoushiExtension) -> Set<String> {
        let langs = Set(ext.sources.map(\.lang))
        let preferred = Locale.preferredLanguages.map { SourceLanguage.baseCode(for: $0) }
        for base in preferred + ["en"] {
            let match = langs.filter { SourceLanguage.baseCode(for: $0) == base }
            if !match.isEmpty { return match }
        }
        return langs
    }
}

// MARK: - KeiyoushiExtensionRow

/// A Keiyoushi extension in More → Extensions, installed or available.
struct KeiyoushiExtensionRow: View {
    let ext: KeiyoushiExtension
    let installed: InstalledKeiyoushiExtension?
    let update: KeiyoushiExtension?
    let isBusy: Bool
    let onInstall: () -> Void
    let onUpdate: () -> Void
    let onLanguages: () -> Void

    private var subtitle: String {
        let langs = Set(ext.sources.map(\.lang))
        let langText: String
        if let installed, langs.count > 1 {
            langText = "\(Set(installed.enabledSources.map(\.lang)).count) of \(langs.count) langs"
        } else if langs.count > 1 {
            langText = "\(langs.count) langs"
        } else {
            langText = ext.lang.uppercased()
        }
        return "\(langText) · v\(installed?.info.versionName ?? ext.versionName)"
    }

    var body: some View {
        HStack(spacing: 12) {
            KFImage(URL(string: ext.iconURL))
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
                Text(ext.name).font(.headline)
                HStack(spacing: 5) {
                    Text("Keiyoushi")
                        .font(.caption2).fontWeight(.medium)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .foregroundStyle(.secondary)
                        .clipShape(Capsule())
                    if ext.isNSFW { NSFWBadge() }
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isBusy {
                ProgressView().controlSize(.small)
            } else if installed != nil {
                if update != nil {
                    Button("Update", action: onUpdate)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.orange)
                } else if Set(ext.sources.map(\.lang)).count > 1 {
                    Button("Languages", action: onLanguages)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            } else {
                Button(Set(ext.sources.map(\.lang)).count > 1 ? "Get" : "Install", action: onInstall)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}
