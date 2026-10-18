import SwiftUI
import UniformTypeIdentifiers

// MARK: - LocalSourceView
//
// Browse → Local Files (S148 part C): the user's own CBZ/ZIP/image folders (manga) and EPUBs (novels). Two ways in:
// Import (copies into Yomi) and a linked Files folder (Mihon's "storage location", read in place). Calm style.

struct LocalSourceView: View {
    @Environment(\.yomiCanvas) private var canvas
    @State private var manga: [Manga] = []
    @State private var novels: [Novel] = []
    @State private var linkedName: String?
    @State private var isScanning = false
    @State private var picker: PickerMode?
    /// Kept apart from `picker`: the importer's isPresented setter clears `picker` before the result arrives.
    @State private var pickedMode: PickerMode = .importFiles
    @State private var report: String?

    enum PickerMode: Identifiable {
        case importFiles, linkFolder
        var id: Self { self }
    }

    static let cbzType = UTType(filenameExtension: "cbz", conformingTo: .zip) ?? .zip
    static let cbrType = UTType("com.yomi.cbr") ?? UTType(filenameExtension: "cbr") ?? .data
    static let rarType = UTType("com.rarlab.rar-archive") ?? UTType(filenameExtension: "rar") ?? .data
    static let cb7Type = UTType("com.yomi.cb7") ?? UTType(filenameExtension: "cb7") ?? .data
    static let sevenZType = UTType("org.7-zip.7-zip-archive") ?? UTType(filenameExtension: "7z") ?? .data
    static let epubType = UTType("org.idpf.epub-container") ?? UTType(filenameExtension: "epub") ?? .data

    var body: some View {
        CalmList {
            if !manga.isEmpty {
                Section {
                    ForEach(manga) { item in
                        NavigationLink { MangaDetailView(manga: item) } label: {
                            row(title: item.title, coverPath: item.resolvedCustomCoverPath, subtitle: "Manga")
                        }
                    }
                } header: { CalmSectionHeader("Manga") }
            }
            if !novels.isEmpty {
                Section {
                    ForEach(novels) { item in
                        NavigationLink { NovelDetailView(novel: item) } label: {
                            row(title: item.title, coverPath: item.resolvedCustomCoverPath,
                                subtitle: item.author ?? "EPUB")
                        }
                    }
                } header: { CalmSectionHeader("Novels") }
            }
            Section {
                Button { pickedMode = .importFiles; picker = .importFiles } label: {
                    Label("Import Files", systemImage: "square.and.arrow.down")
                }
                if let linkedName {
                    LabeledContent {
                        Button("Unlink", role: .destructive) {
                            LocalLibrary.unlinkFolder()
                            self.linkedName = nil
                        }
                    } label: {
                        Label(linkedName, systemImage: "folder")
                            .foregroundStyle(canvas.textPrimary)
                    }
                } else {
                    Button { pickedMode = .linkFolder; picker = .linkFolder } label: {
                        Label("Link a Folder", systemImage: "folder.badge.plus")
                    }
                }
                Button { Task { await rescan(announce: true) } } label: {
                    Label("Scan Again", systemImage: "arrow.clockwise")
                }
                .disabled(isScanning)
            } header: {
                CalmSectionHeader(manga.isEmpty && novels.isEmpty ? "Add your files" : "Files")
            } footer: {
                Text("CBZ, CBR, CB7, ZIP, RAR, 7Z and folders of images open as manga; EPUBs open as novels. A linked folder works like Mihon's local folder: one folder per series, one archive or image folder per chapter, cover.jpg optional.")
                    .font(.footnote)
                    .foregroundStyle(canvas.textSecondary)
            }
        }
        .background(canvas.bg.ignoresSafeArea())
        .navigationTitle("Local Files")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isScanning && manga.isEmpty && novels.isEmpty { ProgressView() }
        }
        .fileImporter(
            isPresented: Binding(get: { picker != nil }, set: { if !$0 { picker = nil } }),
            allowedContentTypes: pickedMode == .linkFolder ? [.folder] : [Self.cbzType, .zip, Self.cbrType, Self.rarType, Self.cb7Type, Self.sevenZType, Self.epubType, .folder],
            allowsMultipleSelection: pickedMode != .linkFolder
        ) { result in
            let mode = pickedMode
            guard case .success(let urls) = result, !urls.isEmpty else { return }
            Task { await handlePicked(urls, mode: mode) }
        }
        .alert("Local Files", isPresented: Binding(get: { report != nil }, set: { if !$0 { report = nil } })) {
            Button("OK") { report = nil }
        } message: {
            Text(report ?? "")
        }
        .task { await rescan(announce: false) }
    }

    private func row(title: String, coverPath: String?, subtitle: String) -> some View {
        HStack(spacing: 12) {
            CoverImage(url: coverPath.map { URL(fileURLWithPath: $0) })
                .frame(width: 44, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(canvas.textPrimary)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(canvas.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Actions

    private func handlePicked(_ urls: [URL], mode: PickerMode) async {
        if mode == .linkFolder, let folder = urls.first {
            do {
                try LocalLibrary.linkFolder(folder)
                linkedName = folder.lastPathComponent
            } catch {
                report = String(localized: "Couldn't link that folder: \(error.localizedDescription)")
                return
            }
            await rescan(announce: true)
            return
        }
        isScanning = true
        let imported = await Task.detached(priority: .userInitiated) { LocalLibrary.importItems(urls) }.value
        await rescan(announce: false)
        var lines: [String] = []
        if !imported.imported.isEmpty { lines.append(String(localized: "Imported \(imported.imported.count) items.")) }
        lines += imported.skipped
        report = lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private func rescan(announce: Bool) async {
        isScanning = true
        linkedName = LocalLibrary.linkedFolder()?.lastPathComponent
        let result = await Task.detached(priority: .userInitiated) { LocalLibrary.scan() }.value
        await load()
        isScanning = false
        if announce {
            var lines = [result.newTitles + result.newChapters == 0
                         ? String(localized: "Nothing new.")
                         : String(localized: "\(result.newTitles) new titles, \(result.newChapters) new chapters.")]
            lines += result.skipped
            report = lines.joined(separator: "\n")
        }
    }

    private func load() async {
        let (m, n) = await Task.detached(priority: .userInitiated) {
            ((try? MangaQueries.fetchAll()) ?? [], (try? NovelQueries.fetchAll()) ?? [])
        }.value
        manga = m.filter { LocalLibrary.isLocalSourceId($0.sourceId) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        novels = n.filter { LocalLibrary.isLocalSourceId($0.sourceId) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}
