import SwiftUI
import UIKit

/// F17 (S169): what the reader learns from a page's pixels — its margins (crop borders) and the colour around it
/// (automatic background). Worked out once per page from a small copy, off the main thread, and kept like `PageShapes`.
struct PageLook: Codable, Equatable, Sendable {
    /// The page without its margins, as fractions of the page (0…1). nil = nothing worth cropping.
    var crop: CGRect?
    var portrait: PageBackground.Choice
    var landscape: PageBackground.Choice

    nonisolated static let plain = PageLook(crop: nil, portrait: .solid(.white), landscape: .solid(.white))

    /// Long side of the copy the page is measured on. Margins come out to within a pixel of it (~0.3 % of a page).
    nonisolated static let sampleSize = 384

    /// Measures a page. Runs off the main thread; a page it can't read gets `plain`.
    nonisolated static func measure(_ image: CGImage) -> PageLook {
        let w0 = image.width, h0 = image.height
        guard w0 > 0, h0 > 0 else { return .plain }
        // A 900x16000 long-strip page measured at 384 px tall would be 9 px wide: keep at least 128 px across.
        let scale = min(1, max(Double(sampleSize) / Double(max(w0, h0)), 128 / Double(min(w0, h0))))
        let w = max(1, Int(Double(w0) * scale)), h = max(1, Int(Double(h0) * scale))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let data = ctx.data else { return .plain }
        ctx.setFillColor(gray: 1, alpha: 1)   // a transparent page reads as white paper
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)   // row 0 = top of the page

        var gray = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            let r = Int(px[i * 4]), g = Int(px[i * 4 + 1]), b = Int(px[i * 4 + 2])
            gray[i] = UInt8((r * 299 + g * 587 + b * 114) / 1000)
        }
        func rgb(_ x: Int, _ y: Int) -> PageBackground.RGB {
            let i = (y * w + x) * 4
            return PageBackground.RGB(r: px[i], g: px[i + 1], b: px[i + 2])
        }

        let found = PageBorders.find(gray: gray, width: w, height: h)
        var crop: CGRect? = nil
        // One sample pixel of slack on every side so the crop never bites into the art.
        let x0 = max(found.x - 1, 0), y0 = max(found.y - 1, 0)
        let x1 = min(found.x + found.width + 1, w), y1 = min(found.y + found.height + 1, h)
        let rect = CGRect(x: Double(x0) / Double(w), y: Double(y0) / Double(h),
                          width: Double(x1 - x0) / Double(w), height: Double(y1 - y0) / Double(h))
        // Yomi's own guard (Mihon has none): a nearly blank page with one small mark would be blown up to fill the screen.
        let worthIt = rect.width < 0.995 || rect.height < 0.995
        if worthIt, rect.width >= 0.25, rect.height >= 0.25 { crop = rect }

        return PageLook(crop: crop,
                        portrait: PageBackground.choose(width: w, height: h, isLandscape: false, pixel: rgb),
                        landscape: PageBackground.choose(width: w, height: h, isLandscape: true, pixel: rgb))
    }
}

/// Every page measured so far, by URL (`PageNames` for Keiyoushi pages). Saved to Caches next to `PageShapes`, so a reopened chapter is cropped from its
/// first frame instead of showing the margins for a moment.
@MainActor enum PageLooks {
    private static let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("page-looks.json")
    private static var store: [String: PageLook]?
    private static var dirty = false

    static func cached(_ url: String) -> PageLook? { loaded()[PageNames.key(url)] }

    /// The page's look, measured now if it isn't known yet.
    static func look(for url: String, image: UIImage) async -> PageLook {
        if let known = cached(url) { return known }
        guard let cg = image.cgImage else { return .plain }
        let look = await Task.detached(priority: .userInitiated) { PageLook.measure(cg) }.value
        if (store?.count ?? 0) > 5000 { store?.removeAll() }
        store?[PageNames.key(url)] = look
        dirty = true
        return look
    }

    /// Called when the reader closes.
    static func save() {
        guard dirty, let looks = store else { return }
        dirty = false
        let file = file
        Task.detached(priority: .utility) { try? JSONEncoder().encode(looks).write(to: file, options: .atomic) }
    }

    private static func loaded() -> [String: PageLook] {
        if let store { return store }
        let looks = (try? JSONDecoder().decode([String: PageLook].self, from: Data(contentsOf: file))) ?? [:]
        store = looks
        return looks
    }
}

/// The colour behind the pages (F17). "black" is the pre-F17 look and the default; "automatic" follows the iPhone's
/// light/dark (dark grey or white, as Mihon does) and, in the paged modes, each page's own margins.
enum ReaderBackdrop {
    static let gray = Color(white: 0.13)

    static func base(_ setting: String) -> Color {
        switch setting {
        case "white":     return .white
        case "gray":      return gray
        case "automatic": return systemIsDark ? gray : .white
        default:          return .black
        }
    }

    /// Whether text and spinners drawn straight on the backdrop need to be dark.
    static func isLight(_ setting: String) -> Bool {
        setting == "white" || (setting == "automatic" && !systemIsDark)
    }

    /// The iPhone's own light/dark. Not the view's colour scheme: the reader forces dark on itself. A screen's traits
    /// don't follow a window's override.
    static var systemIsDark: Bool {
        let scene = UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene
        return scene?.screen.traitCollection.userInterfaceStyle == .dark
    }

    @ViewBuilder static func view(_ choice: PageBackground.Choice) -> some View {
        switch choice {
        case .solid(let c):
            color(c)
        case .split(let top, let bottom):
            // Mihon's four-stop gradient: the top colour, a soft change through the middle, the bottom colour.
            LinearGradient(stops: [.init(color: color(top), location: 0), .init(color: color(top), location: 1 / 3),
                                   .init(color: color(bottom), location: 2 / 3), .init(color: color(bottom), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    private static func color(_ c: PageBackground.RGB) -> Color {
        Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
    }
}

/// Shows only `crop` (fractions of the page) of a resizable image, fitted like `scaledToFit`. nil = the whole page.
struct PageCrop: ViewModifier {
    let crop: CGRect?
    /// The whole page's width / height.
    let aspect: CGFloat?

    func body(content: Content) -> some View {
        if let crop, let aspect, crop.width > 0, crop.height > 0 {
            Color.clear
                .aspectRatio(aspect * crop.width / crop.height, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    GeometryReader { g in
                        let w = g.size.width / crop.width, h = g.size.height / crop.height
                        content
                            .frame(width: w, height: h)
                            .offset(x: -crop.minX * w, y: -crop.minY * h)
                    }
                }
                .clipped()
        } else {
            content.scaledToFit()
        }
    }
}

extension CGImage {
    /// The part of the page inside `crop` (fractions), or the page itself.
    nonisolated func cropped(to crop: CGRect?) -> CGImage {
        guard let crop else { return self }
        let r = CGRect(x: crop.minX * Double(width), y: crop.minY * Double(height),
                       width: crop.width * Double(width), height: crop.height * Double(height)).integral
        return cropping(to: r) ?? self
    }
}

/// The background choices, shared by Settings and the reader's own sheet.
struct ReaderBackgroundPicker: View {
    @Binding var selection: String

    var body: some View {
        Picker("Background", selection: $selection) {
            Text("Black").tag("black")
            Text("Dark grey").tag("gray")
            Text("White").tag("white")
            Text("Automatic").tag("automatic")
        }
    }
}
