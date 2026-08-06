import SwiftUI
import WebKit
import Kingfisher

// MARK: - StorageView
//
// Tachimanga parity: a visual breakdown of app storage (downloads / image cache / plugins /
// covers / web cache / database / other), each with a real size and a Manage/Clear action where
// one makes sense — replacing AdvancedSettingsView's undifferentiated clear-cache buttons.

private struct StorageRow: Identifiable {
    let id: String
    let label: String
    let bytes: Int64
    let barOpacity: Double
    let subtitle: String?
}

struct StorageView: View {
    @Environment(\.yomiCanvas) private var canvas
    @State private var breakdown: StorageBreakdown? = nil
    @State private var isLoading = true
    @State private var showClearImageCacheConfirm = false
    @State private var showClearWebCacheConfirm = false
    @State private var showDeleteDownloadsConfirm = false
    @State private var barTrackWidth: CGFloat = 0

    private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    private func rows(for b: StorageBreakdown) -> [StorageRow] {
        [
            StorageRow(id: "downloads", label: "Downloads", bytes: b.downloads, barOpacity: 1.0, subtitle: "Saved chapters for offline reading"),
            StorageRow(id: "imageCache", label: "Image cache", bytes: b.imageCache, barOpacity: 0.7, subtitle: "Cached cover art and page images"),
            StorageRow(id: "extensions", label: "Plugins", bytes: b.extensions, barOpacity: 0.5, subtitle: "Installed source scripts"),
            StorageRow(id: "covers", label: "Custom covers", bytes: b.covers, barOpacity: 0.35, subtitle: nil),
            StorageRow(id: "webCache", label: "Web cache", bytes: b.webCache, barOpacity: 0.22, subtitle: "Cloudflare bypass sessions, cookies"),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            summaryHeader
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)

            List {
                if let breakdown {
                    ForEach(rows(for: breakdown)) { row in
                        rowSection(row)
                    }

                    Section {
                        LabeledContent("Database") {
                            Text(Self.formatter.string(fromByteCount: breakdown.database))
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("Other") {
                            Text(Self.formatter.string(fromByteCount: breakdown.other))
                                .foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text("Database holds your library, history, and settings — it can't be cleared here. \"Other\" covers miscellaneous app files.")
                            .font(.caption)
                    }
                } else if isLoading {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .confirmationDialog("Clear image cache?", isPresented: $showClearImageCacheConfirm, titleVisibility: .visible) {
            Button("Clear", role: .destructive) {
                ImageCache.default.clearCache()
                Task { await reload() }
            }
        }
        .confirmationDialog("Clear web cache & cookies?", isPresented: $showClearWebCacheConfirm, titleVisibility: .visible) {
            Button("Clear", role: .destructive) {
                URLCache.shared.removeAllCachedResponses()
                WKWebsiteDataStore.default().removeData(
                    ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                    modifiedSince: .distantPast
                ) { Task { await reload() } }
            }
        }
        .confirmationDialog("Delete all downloads?", isPresented: $showDeleteDownloadsConfirm, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) {
                Task {
                    let vm = DownloadViewModel()
                    await vm.load()
                    await vm.deleteEverything()
                    await reload()
                }
            }
        }
    }

    // MARK: - Summary header (plain view, outside the List — avoids GeometryReader-in-List-row instability)

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let breakdown {
                HStack(spacing: 1.5) {
                    ForEach(rows(for: breakdown).filter { $0.bytes > 0 }) { row in
                        Capsule()
                            .fill(Color(hex: AppSettings.shared.accentColor).opacity(row.barOpacity))
                            .frame(width: max(3, barTrackWidth * CGFloat(row.bytes) / CGFloat(max(breakdown.total, 1))))
                    }
                }
                .frame(height: 14, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { barTrackWidth = geo.size.width }
                            .onChange(of: geo.size.width) { _, newValue in barTrackWidth = newValue }
                    }
                }

                Text("\(Self.formatter.string(fromByteCount: breakdown.total)) used")
                    .font(YomiTokens.Font.mono(13))
                    .foregroundStyle(canvas.textSecondary)
            } else {
                Capsule().fill(canvas.surface2).frame(height: 14)
            }
        }
    }

    // MARK: - Row section

    @ViewBuilder
    private func rowSection(_ row: StorageRow) -> some View {
        Section {
            HStack {
                Circle()
                    .fill(Color(hex: AppSettings.shared.accentColor).opacity(row.barOpacity))
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label)
                    if let subtitle = row.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(Self.formatter.string(fromByteCount: row.bytes))
                    .foregroundStyle(.secondary)
            }

            switch row.id {
            case "downloads":
                NavigationLink("Manage downloads") { DownloadsView() }
                if row.bytes > 0 {
                    Button("Delete all downloads", role: .destructive) { showDeleteDownloadsConfirm = true }
                }
            case "imageCache":
                if row.bytes > 0 {
                    Button("Clear image cache", role: .destructive) { showClearImageCacheConfirm = true }
                }
            case "extensions":
                NavigationLink("Manage plugins") { PluginsView() }
            case "webCache":
                if row.bytes > 0 {
                    Button("Clear web cache", role: .destructive) { showClearWebCacheConfirm = true }
                }
            default:
                EmptyView()
            }
        }
    }

    // MARK: - Load

    private func reload() async {
        isLoading = true
        breakdown = await StorageManager.computeBreakdown()
        isLoading = false
    }
}

#Preview {
    NavigationStack { StorageView() }
}
