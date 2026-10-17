import SwiftUI

// MARK: - LicensesView
//
// More → About → Open Source Licenses (S151). Everything Yomi bundles, with the licence text each one requires
// us to pass on. Texts live in Resources/Licenses and Resources/ReaderFonts; scripts/build-licenses.sh collects
// them from the copies we build from. The Mihon runtime entries apply to builds that embed it (device builds).

struct LicensesView: View {
    var body: some View {
        CalmList {
            Section(calm: "App") {
                LicenseRow(name: "GRDB.swift", license: "MIT", file: "licence-grdb")
                LicenseRow(name: "Kingfisher", license: "MIT", file: "licence-kingfisher")
                LicenseRow(name: "Unrar.swift and UnRAR", license: "MIT; UnRAR source under RARLAB's licence",
                           file: "licence-unrar")
                LicenseRow(name: "PLzmaSDK and LZMA SDK", license: "MIT; LZMA SDK public domain",
                           file: "licence-plzmasdk")
                #if DEBUG
                LicenseRow(name: "Pulse", license: "MIT", file: "licence-pulse")
                #endif
            }
            Section(calm: "Ported code") {
                LicenseRow(name: "Mihon", license: "Apache-2.0, parts ported to Swift", file: "licence-mihon")
                LicenseRow(name: "image-decoder (crop borders)", license: "Mozilla Public License 2.0, ported to Swift",
                           file: "licence-image-decoder")
            }
            Section(calm: "Plugin runtime") {
                LicenseRow(name: "cheerio", license: "MIT, with BSD-2-Clause and ISC parts", file: "licence-cheerio")
                LicenseRow(name: "Day.js", license: "MIT", file: "licence-dayjs")
                LicenseRow(name: "core-js", license: "MIT", file: "licence-core-js")
            }
            Section(calm: "Reader fonts") {
                LicenseRow(name: "Literata", license: "SIL Open Font License 1.1", file: "Literata-OFL")
                LicenseRow(name: "Newsreader", license: "SIL Open Font License 1.1", file: "Newsreader-OFL")
                LicenseRow(name: "Atkinson Hyperlegible Next", license: "SIL Open Font License 1.1",
                           file: "AtkinsonHyperlegibleNext-OFL")
                LicenseRow(name: "OpenDyslexic", license: "SIL Open Font License 1.1", file: "OpenDyslexic-OFL")
            }
            Section(calm: "Mihon extension runtime") {
                LicenseRow(name: "OpenJDK", license: "GPL v2 with the Classpath Exception", file: "licence-openjdk")
                LicenseRow(name: "M-Extension-Server", license: "Mozilla Public License 2.0, modified by Yomi",
                           file: "licence-m-extension-server")
                LicenseRow(name: "Extension server libraries", license: "Apache-2.0, BSD, MIT and others",
                           file: "licence-server-libraries")
            }
        }
        .navigationTitle("Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - LicenseRow

private struct LicenseRow: View {
    let name: String
    let license: String
    let file: String

    @Environment(\.yomiCanvas) private var canvas

    var body: some View {
        NavigationLink {
            LicenseTextView(title: name, file: file)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .foregroundStyle(canvas.textPrimary)
                Text(license)
                    .font(.footnote)
                    .foregroundStyle(canvas.textSecondary)
            }
        }
    }
}

// MARK: - LicenseTextView

private struct LicenseTextView: View {
    let title: String
    let file: String

    @Environment(\.yomiCanvas) private var canvas
    @State private var text: String?

    var body: some View {
        Group {
            if let text {
                LongText(text: text, color: UIColor(canvas.textPrimary))
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(canvas.bg.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let file = file
            text = await Task.detached { Self.load(file) }.value
        }
    }

    nonisolated private static func load(_ file: String) -> String {
        for folder in ["Licenses", "ReaderFonts", nil] as [String?] {
            if let url = Bundle.main.url(forResource: file, withExtension: "txt", subdirectory: folder),
               let text = try? String(contentsOf: url, encoding: .utf8) {
                return text
            }
        }
        return "The licence text is missing from this build."
    }
}

/// Read-only text that stays fast at hundreds of kilobytes (the server libraries file) — SwiftUI's `Text`
/// lays the whole string out at once.
private struct LongText: UIViewRepresentable {
    let text: String
    let color: UIColor

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.backgroundColor = .clear
        view.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        view.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 24, right: 12)
        view.dataDetectorTypes = .link
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text { view.text = text }
        view.textColor = color
    }
}
