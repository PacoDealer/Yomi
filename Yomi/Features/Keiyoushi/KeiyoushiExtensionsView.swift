import Kingfisher
import SwiftUI

// MARK: - KeiyoushiExtensionsView

/// Settings → Keiyoushi Extensions: paste a Mihon extension repository URL (e.g. Keiyoushi's `index.pb`), then
/// install / update / remove extensions from it. Installed sources appear in Browse and run on-device through the
/// embedded JVM — no server. The URL is never prefilled: the user supplies the repository (App Store 5.2.2).
struct KeiyoushiExtensionsView: View {
    @Environment(\.yomiCanvas) private var canvas
    @State private var settings = AppSettings.shared
    @State private var repo = KeiyoushiRepository.shared
    @State private var urlDraft = AppSettings.shared.keiyoushiRepoURL
    @State private var query = ""
    @State private var language = "en"
    @State private var busy: Set<String> = []
    @State private var toast: String? = nil
    @State private var errorToast: String? = nil

    private var languages: [String] {
        Array(Set(repo.available.map(\.lang))).sorted()
    }

    private var filtered: [KeiyoushiExtension] {
        let installedIds = Set(repo.installed.map(\.id))
        return repo.available.filter { ext in
            !installedIds.contains(ext.id)
                && (settings.showNSFW || !ext.isNSFW)
                && (language.isEmpty || ext.lang == language || (ext.lang == "all" && ext.sources.contains { $0.lang == language }))
                && (query.isEmpty || ext.name.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        List {
            Section {
                TextField("Repository URL (index.pb)", text: $urlDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(YomiTokens.Font.mono(12))
                    .onSubmit { Task { await applyURL() } }
                Button {
                    Task { await applyURL() }
                } label: {
                    HStack {
                        Text(repo.available.isEmpty ? "Load repository" : "Refresh")
                        Spacer()
                        if repo.isLoading { ProgressView() }
                    }
                }
                .disabled(urlDraft.trimmingCharacters(in: .whitespaces).isEmpty || repo.isLoading)
                if let error = repo.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("Repository")
            } footer: {
                if let name = repo.repoName, !repo.available.isEmpty {
                    Text("\(name) · \(repo.available.count) extensions")
                } else if !KeiyoushiJVMHost.isAvailable {
                    Text("This build doesn't include the on-device extension runtime, so installed extensions can't run here yet.")
                } else {
                    Text("Paste the URL of a Mihon/Tachiyomi extension repository index.")
                }
            }

            if !repo.installed.isEmpty {
                Section("Installed (\(repo.installed.count))") {
                    ForEach(repo.installed) { ext in
                        row(ext.info, installed: ext)
                    }
                    .onDelete { offsets in
                        let targets = offsets.map { repo.installed[$0] }
                        Task { for ext in targets { await repo.uninstall(ext) } }
                    }
                }
            }

            if !repo.available.isEmpty {
                Section {
                    Picker("Language", selection: $language) {
                        Text("All languages").tag("")
                        ForEach(languages, id: \.self) { Text($0).tag($0) }
                    }
                    ForEach(filtered) { ext in
                        row(ext, installed: nil)
                    }
                } header: {
                    Text("Available (\(filtered.count))")
                }
            }
        }
        .yomiListCanvas()
        .searchable(text: $query, prompt: "Search extensions")
        .navigationTitle("Keiyoushi Extensions")
        .navigationBarTitleDisplayMode(.inline)
        .yomiToast($toast, isError: false)
        .yomiToast($errorToast)
        .task {
            if repo.available.isEmpty, !settings.keiyoushiRepoURL.isEmpty { await repo.refresh() }
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func row(_ ext: KeiyoushiExtension, installed: InstalledKeiyoushiExtension?) -> some View {
        HStack(spacing: 12) {
            KFImage(URL(string: ext.iconURL))
                .placeholder { RoundedRectangle(cornerRadius: 8).fill(canvas.surface2) }
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(ext.name)
                    .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.body))
                    .foregroundStyle(canvas.textPrimary)
                Text("\(ext.lang.uppercased()) · v\(installed?.info.versionName ?? ext.versionName)\(ext.isNSFW ? " · 18+" : "")")
                    .font(YomiTokens.Font.mono(10))
                    .foregroundStyle(canvas.textSecondary)
            }
            Spacer(minLength: 8)

            if busy.contains(ext.id) {
                ProgressView()
            } else if let installed {
                if let update = repo.availableUpdate(for: installed) {
                    Button("Update") { Task { await install(update) } }
                        .buttonStyle(.bordered)
                } else {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                        .accessibilityLabel("Installed")
                }
            } else {
                Button("Install") { Task { await install(ext) } }
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: Actions

    private func applyURL() async {
        settings.keiyoushiRepoURL = urlDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        await repo.refresh()
    }

    private func install(_ ext: KeiyoushiExtension) async {
        busy.insert(ext.id)
        defer { busy.remove(ext.id) }
        do {
            try await repo.install(ext)
            toast = "Installed \(ext.name)"
        } catch {
            errorToast = error.localizedDescription
        }
    }
}
