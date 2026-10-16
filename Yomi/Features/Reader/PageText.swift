import SwiftUI
import UIKit
import Vision
import Translation

// MARK: - Text on Page (L3d, Tachimanga "copy text / OCR")
//
// Long press a page → "Text on Page", or the reader toolbar's text button. Vision's
// `RecognizeTextRequest` reads the page, lines that sit close together are joined into one block (≈ one speech
// bubble), and blocks are put in reading order (rows top to bottom, right to left for right-to-left manga). The
// "Page" tab shows the page with each block outlined; tap one to copy it. (VisionKit Live Text was tried first: it
// found nothing on a 900 × 16,000 px webtoon page, the same scaling problem `tiles` solves.) Reading the page never
// leaves the phone. Translate opens Apple's Translation sheet, which (its own first-run notice, S173) sends the text to
// Apple unless the user chose to always translate offline in Settings.

enum PageTextRecognizer {
    /// Languages offered in the sheet's menu ("auto" = Vision detects). Vision supports more; these are the ones
    /// sources publish in.
    static let languages: [(code: String, name: String)] = [
        ("auto", "Automatic"), ("en-US", "English"), ("ja-JP", "Japanese"), ("ko-KR", "Korean"),
        ("zh-Hans", "Chinese (Simplified)"), ("zh-Hant", "Chinese (Traditional)"), ("es-ES", "Spanish"),
        ("pt-BR", "Portuguese"), ("fr-FR", "French"), ("de-DE", "German"), ("it-IT", "Italian"),
        ("ru-RU", "Russian"), ("vi-VT", "Vietnamese"), ("th-TH", "Thai"), ("id-ID", "Indonesian"),
    ]

    struct Line {
        let text: String
        let box: CGRect   // normalized, origin top-left
    }

    /// One bubble / caption: joined lines and the box around them (normalized, origin top-left).
    struct Block: Hashable {
        let text: String
        let box: CGRect
    }

    static func recognize(_ image: UIImage, language: String) async throws -> [Block] {
        guard let cgImage = image.uprightCGImage else { return [] }
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        if language == "auto" {
            request.automaticallyDetectsLanguage = true
        } else {
            request.automaticallyDetectsLanguage = false
            request.recognitionLanguages = [Locale.Language(identifier: language)]
        }
        var lines: [Line] = []
        for tile in tiles(width: cgImage.width, height: cgImage.height) {
            guard let slice = cgImage.cropping(to: tile.rect) else { continue }
            let observations = try await request.perform(on: slice)
            let h = CGFloat(cgImage.height), w = CGFloat(cgImage.width)
            for obs in observations {
                guard let text = obs.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty else { continue }
                let r = obs.boundingBox.cgRect   // normalized to the slice, origin bottom-left
                let box = CGRect(x: r.minX,
                                 y: (tile.rect.minY + (1 - r.maxY) * tile.rect.height) / h,
                                 width: r.width * tile.rect.width / w,
                                 height: r.height * tile.rect.height / h)
                // A line in the overlap is read by both slices: keep it only in the slice whose core holds its middle.
                guard tile.core.contains(box.midY * h) else { continue }
                lines.append(Line(text: text, box: box))
            }
        }
        return blocks(lines, rightToLeft: isCJK(language) || (language == "auto" && looksCJK(lines)))
    }

    /// Vision scales the whole image to its working size, so on a webtoon page (900 × 16,000 px) the text ends up a
    /// few pixels tall and nothing is found. Tall pages are read in slices 1.5× as tall as they are wide, overlapping by
    /// a fifth so a line cut by one slice is whole in the next.
    static func tiles(width: Int, height: Int) -> [(rect: CGRect, core: Range<CGFloat>)] {
        let w = CGFloat(width), h = CGFloat(height)
        let tileHeight = max(w * 1.5, 1)
        guard h > tileHeight * 1.2 else { return [(CGRect(x: 0, y: 0, width: w, height: h), 0..<h + 1)] }
        let overlap = tileHeight * 0.2
        var result: [(rect: CGRect, core: Range<CGFloat>)] = []
        var y: CGFloat = 0
        while true {
            let bottom = min(y + tileHeight, h)
            let isFirst = y == 0, isLast = bottom >= h
            let core = (isFirst ? 0 : y + overlap / 2)..<(isLast ? h + 1 : bottom - overlap / 2)
            result.append((CGRect(x: 0, y: y, width: w, height: bottom - y).integral, core))
            if isLast { break }
            y = bottom - overlap
        }
        return result
    }

    /// Joins lines whose boxes touch (grown by about one line height) into blocks, then orders the blocks.
    static func blocks(_ lines: [Line], rightToLeft: Bool) -> [Block] {
        guard !lines.isEmpty else { return [] }
        var parent = Array(lines.indices)
        func find(_ i: Int) -> Int { var i = i; while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }; return i }
        let grown = lines.map { line -> CGRect in
            let pad = min(line.box.width, line.box.height) * 0.9
            return line.box.insetBy(dx: -pad, dy: -pad)
        }
        for i in lines.indices {
            for j in lines.indices where j > i && grown[i].intersects(grown[j]) {
                parent[find(i)] = find(j)
            }
        }
        var groups: [Int: [Int]] = [:]
        for i in lines.indices { groups[find(i), default: []].append(i) }

        let made: [Block] = groups.values.map { members in
            let box = members.map { lines[$0].box }.reduce(CGRect.null) { $0.union($1) }
            // Lines inside a block: vertical CJK columns (tall, thin) read right to left, the rest top to bottom.
            let tall = members.allSatisfy { lines[$0].box.height > lines[$0].box.width * 1.5 }
            let ordered = members.sorted { a, b in
                let la = lines[a].box, lb = lines[b].box
                if tall { return rightToLeft ? la.midX > lb.midX : la.midX < lb.midX }
                return abs(la.midY - lb.midY) > min(la.height, lb.height) / 2 ? la.midY < lb.midY : la.minX < lb.minX
            }
            let joiner = ordered.map { lines[$0].text }.contains { $0.unicodeScalars.contains(where: \.isCJK) } ? "" : " "
            return Block(text: ordered.map { lines[$0].text }.joined(separator: joiner), box: box)
        }
        // Reading order: blocks whose top edges are within a block height of each other share a row.
        let sorted = made.sorted { a, b in
            let sameRow = abs(a.box.minY - b.box.minY) < min(a.box.height, b.box.height) * 0.5
            if sameRow { return rightToLeft ? a.box.midX > b.box.midX : a.box.midX < b.box.midX }
            return a.box.minY < b.box.minY
        }
        return sorted
    }

    private static func isCJK(_ code: String) -> Bool { ["ja", "zh"].contains { code.hasPrefix($0) } }

    /// "Automatic" on a Japanese/Chinese page: read bubbles right to left when most text is CJK.
    private static func looksCJK(_ lines: [Line]) -> Bool {
        let scalars = lines.flatMap { $0.text.unicodeScalars }
        guard !scalars.isEmpty else { return false }
        let japaneseOrChinese = scalars.filter { $0.isCJK && !$0.isHangul }.count
        return Double(japaneseOrChinese) / Double(scalars.count) > 0.4
    }
}

private extension Unicode.Scalar {
    var isHangul: Bool { (0xAC00...0xD7AF).contains(value) || (0x1100...0x11FF).contains(value) || (0x3130...0x318F).contains(value) }
    var isCJK: Bool {
        isHangul || (0x3040...0x30FF).contains(value) || (0x4E00...0x9FFF).contains(value) || (0x3400...0x4DBF).contains(value)
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
                            ForEach(PageTextRecognizer.languages, id: \.code) { Text($0.name).tag($0.code) }
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
                        ReaderPageActions.say("Text copied")
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
