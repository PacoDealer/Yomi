import SwiftUI
import UIKit
import WebKit
import CoreText

// MARK: - ReaderFont
//
// The novel reader's fonts (S136, RESEARCH §25.10 #1). Two kinds:
//  - Apple's own faces, referenced by CSS name. Listed only when installed: iOS downloads some families on
//    demand, and a missing one would silently render as Times.
//  - Bundled OFL faces (Literata, Newsreader, Atkinson Hyperlegible Next, OpenDyslexic) in Resources/ReaderFonts,
//    built by scripts/build-reader-fonts.sh. The web view can't see app-registered fonts (WebKit renders in its
//    own process), so they're served to it through `ReaderFontSchemeHandler` as yomi-font://<file>.

struct ReaderFont: Identifiable, Hashable {
    struct Face: Hashable {
        let file: String        // e.g. "Literata.woff2"
        let weight: String      // CSS font-weight, a range for variable files
        let italic: Bool
    }

    let id: String
    let name: String
    /// CSS `font-family` value (fallbacks included).
    let css: String
    /// Installed family name for Apple faces — availability check and the panel's preview.
    let systemFamily: String?
    let faces: [Face]

    var isBundled: Bool { !faces.isEmpty }

    static let system   = ReaderFont(id: "system", name: "System", css: "-apple-system, \"Helvetica Neue\", sans-serif",
                                     systemFamily: nil, faces: [])
    static let newYork  = ReaderFont(id: "new-york", name: "New York", css: "ui-serif, Georgia, serif",
                                     systemFamily: nil, faces: [])
    static let georgia  = ReaderFont(id: "georgia", name: "Georgia", css: "Georgia, \"Times New Roman\", serif",
                                     systemFamily: "Georgia", faces: [])

    static let all: [ReaderFont] = [
        .system,
        .newYork,
        .georgia,
        ReaderFont(id: "charter", name: "Charter", css: "Charter, Georgia, serif",
                   systemFamily: "Charter", faces: []),
        ReaderFont(id: "iowan", name: "Iowan", css: "\"Iowan Old Style\", Georgia, serif",
                   systemFamily: "Iowan Old Style", faces: []),
        ReaderFont(id: "palatino", name: "Palatino", css: "Palatino, \"Palatino Linotype\", Georgia, serif",
                   systemFamily: "Palatino", faces: []),
        bundled("literata", "Literata", fallback: "Georgia, serif",
                [("Literata.woff2", false), ("Literata-Italic.woff2", true)]),
        bundled("newsreader", "Newsreader", fallback: "Georgia, serif",
                [("Newsreader.woff2", false), ("Newsreader-Italic.woff2", true)]),
        bundled("atkinson", "Atkinson Hyperlegible", fallback: "-apple-system, sans-serif",
                [("AtkinsonHyperlegibleNext.woff2", false), ("AtkinsonHyperlegibleNext-Italic.woff2", true)]),
        ReaderFont(id: "opendyslexic", name: "OpenDyslexic", css: "\"Yomi OpenDyslexic\", -apple-system, sans-serif",
                   systemFamily: nil, faces: [
                       Face(file: "OpenDyslexic-Regular.woff2", weight: "400", italic: false),
                       Face(file: "OpenDyslexic-Bold.woff2", weight: "700", italic: false),
                       Face(file: "OpenDyslexic-Italic.woff2", weight: "400", italic: true),
                       Face(file: "OpenDyslexic-BoldItalic.woff2", weight: "700", italic: true),
                   ]),
    ]

    private static func bundled(_ id: String, _ name: String, fallback: String,
                                _ files: [(String, Bool)]) -> ReaderFont {
        ReaderFont(id: id, name: name, css: "\"Yomi \(name)\", \(fallback)", systemFamily: nil,
                   faces: files.map { Face(file: $0.0, weight: "400 700", italic: $0.1) })
    }

    /// What the reader offers on this device.
    static let available: [ReaderFont] = {
        let installed = Set(UIFont.familyNames)
        return all.filter { font in
            if let family = font.systemFamily { return installed.contains(family) }
            if font.isBundled { return font.faces.allSatisfy { ReaderFontFiles.url(for: $0.file) != nil } }
            return true
        }
    }()

    /// The saved id, or Georgia when it's unknown or not on this device.
    static func resolve(_ id: String) -> ReaderFont {
        available.first { $0.id == id } ?? .georgia
    }

    /// `@font-face` rules for this font (empty for Apple faces).
    var fontFaceCSS: String {
        faces.map { face in
            """
            @font-face { font-family: "Yomi \(name)"; src: url("\(ReaderFontSchemeHandler.scheme)://fonts/\(face.file)") format("woff2"); \
            font-weight: \(face.weight); font-style: \(face.italic ? "italic" : "normal"); font-display: block; }
            """
        }.joined(separator: "\n")
    }

    /// The font drawn in the panel's font row, so each name previews its own face.
    func previewFont(size: CGFloat) -> Font {
        switch id {
        case Self.system.id:  return .system(size: size)
        case Self.newYork.id: return .system(size: size, design: .serif)
        default:
            if let family = systemFamily { return .custom(family, size: size) }
            if let family = ReaderFontFiles.registeredFamily(for: self) { return .custom(family, size: size) }
            return .system(size: size)
        }
    }
}

// MARK: - Bundled font files

enum ReaderFontFiles {
    static func url(for file: String) -> URL? {
        let name = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension
        return Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "ReaderFonts")
            ?? Bundle.main.url(forResource: name, withExtension: ext)
    }

    private static var families: [String: String] = [:]

    /// Registers the font's upright file with CoreText (process scope) once, for SwiftUI previews only.
    @MainActor
    static func registeredFamily(for font: ReaderFont) -> String? {
        if let cached = families[font.id] { return cached }
        guard let face = font.faces.first(where: { !$0.italic }), let url = url(for: face.file),
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let family = descriptors.first.flatMap({
                  CTFontDescriptorCopyAttribute($0, kCTFontFamilyNameAttribute) as? String
              }) else { return nil }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        families[font.id] = family
        return family
    }
}

// MARK: - Scheme handler

/// Serves Resources/ReaderFonts/<file> to the reader's web view as yomi-font://fonts/<file>. Only file names
/// from `ReaderFont.all` are served. The page's origin is about:blank (null), and font loads are CORS
/// requests, hence Access-Control-Allow-Origin. Loads through a custom scheme are subresources, not
/// navigations, so the reader's navigation lockdown (Known Issue #95) is untouched.
final class ReaderFontSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "yomi-font"
    private static let allowed = Set(ReaderFont.all.flatMap { $0.faces.map(\.file) })

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, Self.allowed.contains(url.lastPathComponent),
              let fileURL = ReaderFontFiles.url(for: url.lastPathComponent),
              let data = try? Data(contentsOf: fileURL) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": "font/woff2",
            "Content-Length": "\(data.count)",
            "Access-Control-Allow-Origin": "*",
        ])!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}
