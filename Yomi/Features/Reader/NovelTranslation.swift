import Foundation
import Translation

// MARK: - Novel translation (S177, ArcReader backlog — "Translation stays the headline item")
//
// Whole chapters through Apple's Translation framework: the language models are downloaded to the iPhone (the system
// asks first) and text is translated on the device. The page sends its text blocks (`yomi.translationBlocks`), each
// block's lines are translated in batches, and the page swaps them in, keeping the originals to show again. Formatting
// inside a block (italics, links) is not kept in the translation.

enum NovelTranslation {
    /// Lines per `translations(from:)` call.
    private static let batchSize = 120

    /// Translates every line of every block; blank lines stay as they are. Same shape out as in.
    static func translate(_ blocks: [String], session: TranslationSession) async throws -> [String] {
        var lines = blocks.map { $0.components(separatedBy: "\n") }
        var requests: [(block: Int, line: Int, text: String)] = []
        for (b, blockLines) in lines.enumerated() {
            for (l, line) in blockLines.enumerated() where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                requests.append((b, l, line))
            }
        }
        var start = 0
        while start < requests.count {
            try Task.checkCancellation()
            let slice = requests[start..<min(start + batchSize, requests.count)]
            let responses = try await session.translations(from: slice.map {
                TranslationSession.Request(sourceText: $0.text)
            })
            for (req, res) in zip(slice, responses) { lines[req.block][req.line] = res.targetText }
            start += batchSize
        }
        return lines.map { $0.joined(separator: "\n") }
    }

    /// The language chapters are translated into: the saved choice, or the iPhone's language.
    static func target(_ saved: String) -> Locale.Language {
        saved.isEmpty ? Locale.current.language : Locale.Language(identifier: saved)
    }

    /// "French", "English (US)", "Chinese, Simplified" — the script only where it tells two apart.
    static func name(_ language: Locale.Language) -> String {
        let code = language.languageCode?.identifier ?? language.minimalIdentifier
        var base = Locale.current.localizedString(forLanguageCode: code) ?? code
        if code == "zh", let script = language.script {
            base = Locale.current.localizedString(forIdentifier: "zh-\(script.identifier)") ?? base
        } else if code == "en" || code == "pt", let region = language.region {
            base += " (\(Locale.current.localizedString(forRegionCode: region.identifier) ?? region.identifier))"
        }
        return base
    }

    /// What to tell the reader when a chapter can't be translated.
    static func message(for error: Error) -> String {
        if TranslationError.unsupportedLanguagePairing ~= error || TranslationError.unsupportedSourceLanguage ~= error
            || TranslationError.unsupportedTargetLanguage ~= error {
            return "Translation isn’t available for this language pair."
        }
        if TranslationError.unableToIdentifyLanguage ~= error {
            return "Couldn’t tell which language this chapter is in."
        }
        return "Couldn’t translate this chapter."
    }
}
