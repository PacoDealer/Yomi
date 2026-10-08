import SwiftUI
import UniformTypeIdentifiers

// MARK: - OnboardingView
//
// S147 (RESEARCH §25.10 #3, §25.5 law 5): first run does the setup instead of describing it. One calm screen with
// three ways in — bring a library over from Mihon / Tachiyomi / Tachimanga, restore a Yomi backup, or paste a
// repository link — and "Skip for Now". Yomi still ships with no repositories and suggests none (S140): every
// repository comes from the user, either pasted here or carried in their own backup.
//
// Presented by YomiApp as a fullScreenCover outside ContentView, so it doesn't get `\.yomiCanvas` — it uses
// system colours, which follow light/dark like the "Automatic" canvas fresh installs default to.

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var backupManager = BackupManager.shared
    @State private var settings = AppSettings.shared

    /// One file importer for both backup kinds — two `.fileImporter`s on one view only reliably present the last.
    @State private var picking: Option? = nil
    /// What the open picker is for — kept apart from `picking`, which the dismissal clears before the completion runs.
    @State private var pickedKind: Option = .mihon
    @State private var showAddRepo = false
    @State private var importReport: BackupManager.TachiyomiImportReport? = nil
    @State private var busy: Option? = nil
    @State private var done: Set<Option> = []
    @State private var errorText: String? = nil
    @State private var repoCountAtOpen = 0

    private enum Option: Hashable { case mihon, yomi, repo }

    /// The user's accent. `Color.accentColor` renders system blue inside this cover (separate hierarchy).
    private var accent: Color { Color(hex: settings.accentColor) }

    private var repoCount: Int { settings.pluginCatalogURLs.count + settings.mihonRepoURLs.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                VStack(spacing: 12) {
                    optionCard(.mihon,
                               systemImage: "arrow.down.doc",
                               title: "Coming from Mihon or Tachimanga?",
                               detail: "Import a .tachibk backup — your library, categories and reading progress come along.") {
                        pickedKind = .mihon; picking = .mihon
                    }
                    optionCard(.yomi,
                               systemImage: "clock.arrow.circlepath",
                               title: "Restore a Yomi Backup",
                               detail: "Bring back a library you exported from Yomi.") {
                        pickedKind = .yomi; picking = .yomi
                    }
                    optionCard(.repo,
                               systemImage: "link",
                               title: "Add a Repository",
                               detail: "Paste the link of a Mihon, LNReader or Yomi repository, then add the sources you want.") {
                        repoCountAtOpen = repoCount
                        showAddRepo = true
                    }
                }
                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Link("How to find repositories", destination: kYomiSetupGuideURL)
                    .font(.subheadline)
            }
            .padding(.horizontal, 24)
            .padding(.top, 48)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(.systemBackground).ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { finishButton }
        .fileImporter(
            isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } }),
            allowedContentTypes: pickedKind == .yomi ? [.json] : [UTType(filenameExtension: "tachibk") ?? .data]
        ) { result in
            let kind = pickedKind
            guard case .success(let url) = result else { return }
            Task { await importBackup(kind, from: url) }
        }
        .sheet(item: $importReport) { report in
            TachiyomiImportView(report: report)
        }
        .sheet(isPresented: $showAddRepo, onDismiss: {
            if repoCount > repoCountAtOpen { done.insert(.repo) }
        }) {
            AddRepoSheet()
        }
        // fullScreenCover presents a separate view hierarchy that doesn't inherit YomiApp's .tint().
        .tint(accent)
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let icon = UIImage(named: "OnboardingIcon") {
                Image(uiImage: icon)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilityHidden(true)
            }
            Text("Welcome to Yomi")
                .font(.largeTitle.weight(.bold))
            Text("Manga, manhwa and light novels from the sources you add. Yomi comes with none — start with one of these, or skip and do it later from Browse.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private func optionCard(_ option: Option, systemImage: String, title: String, detail: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Group {
                    if busy == option {
                        ProgressView()
                    } else if done.contains(option) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(accent)
                    } else {
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                }
                .font(.body.weight(.semibold))
            }
            .padding(16)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(busy != nil)
        .accessibilityValue(done.contains(option) ? "Done" : "")
    }

    private var finishButton: some View {
        Button(action: finish) {
            Text(done.isEmpty ? "Skip for Now" : "Start Reading")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(done.isEmpty ? Color(.secondarySystemFill) : accent)
        .foregroundStyle(done.isEmpty ? Color.primary : settings.accentForeground)
        .disabled(busy != nil)
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
        .background(Color(.systemBackground))
    }

    private func importBackup(_ kind: Option, from url: URL) async {
        busy = kind
        errorText = nil
        if kind == .mihon {
            await backupManager.importTachiyomiBackup(from: url)
        } else {
            await backupManager.importBackup(from: url)
        }
        busy = nil
        if let error = backupManager.errorMessage {
            errorText = error
            return
        }
        done.insert(kind)
        if kind == .mihon { importReport = backupManager.lastTachiyomiImport }
    }

    private func finish() {
        settings.hasSeenOnboarding = true
        // A library came in → Library. Only a repository → its extensions, to add the first source.
        if done.contains(.repo) && !done.contains(.mihon) && !done.contains(.yomi) {
            appRouter.openBrowseExtensions = true
            appRouter.selectedTab = AppRouter.tabBrowse
        } else {
            appRouter.selectedTab = AppRouter.tabLibrary
        }
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    OnboardingView()
}
