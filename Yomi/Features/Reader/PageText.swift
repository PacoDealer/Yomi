import SwiftUI
import UIKit
import Translation

// MARK: - Text on Page (L3d, Tachimanga "copy text / OCR")
//
// Long press a page → "Text on Page", or the reader toolbar's text button. Recognition and reading order live in
// `PageTextLayout.swift` (no UIKit, tested on the Mac). The "Page" tab shows the page with each block outlined; tap
// one to copy it. (VisionKit Live Text was tried first: it found nothing on a 900 × 16,000 px webtoon page, the same
// scaling problem `tiles` solves.) Reading the page never leaves the phone. Translate opens Apple's Translation sheet, which (its own first-run notice, S173) sends the text to
// Apple unless the user chose to always translate offline in Settings.

extension PageTextRecognizer {
    static func recognize(_ image: UIImage, language: String) async throws -> [Block] {
        guard let cgImage = image.uprightCGImage else { return [] }
        return try await recognize(cgImage, language: language)
    }
}

extension UIImage {
    /// The pixels as shown (orientation applied), so slices line up with the page. Reader pages are almost always `.up`.
    var uprightCGImage: CGImage? {
        if imageOrientation == .up, let cgImage { return cgImage }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: size.width * scale, height: size.height * scale), format: format)
            .image { _ in draw(in: CGRect(origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale))) }
            .cgImage
    }
}

// MARK: - Sheet

struct PageTextSheet: View {
    let image: UIImage

    @Environment(\.dismiss) private var dismiss
    @State private var settings = AppSettings.shared
    @State private var tab = "text"
    @State private var blocks: [PageTextRecognizer.Block]? = nil
    @State private var failed = false
    @State private var translating = false
    @State private var copiedIndex: Int? = nil

    private var allText: String { (blocks ?? []).map(\.text).joined(separator: "\n\n") }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Show", selection: $tab) {
                    Text("Text").tag("text")
                    Text("Page").tag("page")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                if tab == "text" { textList } else { OutlinedPage(image: image, blocks: blocks ?? []) }
            }
            .navigationTitle("Text on Page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Language", selection: $settings.pageTextLanguage) {
                            ForEach(PageTextRecognizer.languages, id: \.code) { Text(PageTextRecognizer.displayName($0)).tag($0.code) }
                        }
                    } label: {
                        Label("Language", systemImage: "globe")
                    }
                    .accessibilityLabel("Text language")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        UIPasteboard.general.string = allText
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        ReaderPageActions.say(String(localized: "Text copied"))
                        dismiss()
                    } label: { Label("Copy All", systemImage: "doc.on.doc") }
                    .disabled(allText.isEmpty)
                    Spacer()
                    Button { translating = true } label: { Label("Translate", systemImage: "translate") }
                        .disabled(allText.isEmpty)
                }
            }
            .translationPresentation(isPresented: $translating, text: allText)
            .task(id: settings.pageTextLanguage) { await run() }
        }
    }

    @ViewBuilder private var textList: some View {
        if let blocks {
            if blocks.isEmpty {
                ContentUnavailableView("No Text Found", systemImage: "text.viewfinder",
                                       description: Text(failed ? "Couldn't read this page." : "Try another language from the globe menu."))
            } else {
                List {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                        HStack(alignment: .top, spacing: 12) {
                            Text(block.text)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                UIPasteboard.general.string = block.text
                                copiedIndex = index
                            } label: {
                                Image(systemName: copiedIndex == index ? "checkmark" : "doc.on.doc")
                                    .foregroundStyle(Color.accentColor)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Copy")
                        }
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        } else {
            ProgressView("Reading the page…").frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func run() async {
        blocks = nil
        copiedIndex = nil
        do {
            failed = false
            blocks = try await PageTextRecognizer.recognize(image, language: settings.pageTextLanguage)
        } catch {
            failed = true
            blocks = []
        }
    }
}

/// The page with the found blocks outlined; tap one to copy it. Drawn in slices ≤ 4,000 px tall — a single image
/// taller than 4,096 px renders black on the phone (#190).
private struct OutlinedPage: View {
    let image: UIImage
    let blocks: [PageTextRecognizer.Block]

    @State private var slices: [UIImage] = []
    @State private var copied: PageTextRecognizer.Block? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(slices.indices, id: \.self) { i in
                    Image(uiImage: slices[i]).resizable().scaledToFit()
                }
            }
            .overlay {
                GeometryReader { geo in
                    ForEach(blocks, id: \.self) { block in
                        let rect = CGRect(x: block.box.minX * geo.size.width, y: block.box.minY * geo.size.height,
                                          width: block.box.width * geo.size.width, height: block.box.height * geo.size.height)
                            .insetBy(dx: -4, dy: -4)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accentColor.opacity(copied == block ? 0.35 : 0.12))
                            .strokeBorder(Color.accentColor, lineWidth: 1.5)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .onTapGesture {
                                UIPasteboard.general.string = block.text
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                copied = block
                            }
                            .accessibilityElement()
                            .accessibilityLabel(block.text)
                            .accessibilityHint("Copies this text")
                            .accessibilityAddTraits(.isButton)
                    }
                }
            }
        }
        .task { slices = Self.slice(image) }
    }

    private static func slice(_ image: UIImage) -> [UIImage] {
        guard let cg = image.uprightCGImage, cg.height > 4000 else { return [image] }
        return stride(from: 0, to: cg.height, by: 4000).compactMap { y in
            cg.cropping(to: CGRect(x: 0, y: y, width: cg.width, height: min(4000, cg.height - y)))
                .map { UIImage(cgImage: $0) }
        }
    }
}
