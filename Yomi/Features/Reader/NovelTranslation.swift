import CryptoKit
import Foundation
import Translation

// MARK: - Novel translation (S177, ArcReader backlog — "Translation stays the headline item")
//
// Whole chapters through Apple's Translation framework: the language models are downloaded to the iPhone (the system
// asks first) and text is translated on the device. The page sends its text blocks (`yomi.translationBlocks`), each
// block's lines are translated in batches, and the page swaps them in, keeping the originals to show again. Formatting
// inside a block (italics, links) is not kept in the translation.

enum NovelTranslation {
    /// S182: OFF — Martin took Translate out until it's improved (BACKLOG in ROADMAP S182: slow, odd wording line by
    /// line). Hides the Reading-tab toggle and ignores saved per-novel choices; `novelTranslateIds` is kept as is.
    static let isAvailable = false

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

    // MARK: Saved translations (S182 — Martin: a chapter translated once should load fast the second time)

    /// One file per (target language, exact chapter text) in Caches; a changed chapter text or language misses.
    nonisolated private static let cacheDir = URL.cachesDirectory.appending(path: "novel-translations", directoryHint: .isDirectory)
    nonisolated private static let cacheLimit = 400

    nonisolated private static func cacheURL(_ blocks: [String], target: Locale.Language) -> URL {
        let key = target.minimalIdentifier + "\u{1}" + blocks.joined(separator: "\u{0}")
        let hex = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return cacheDir.appending(path: hex + ".json")
    }

    /// A translation saved earlier for exactly these blocks, or nil.
    nonisolated static func cached(_ blocks: [String], target: Locale.Language) -> [String]? {
        guard let data = try? Data(contentsOf: cacheURL(blocks, target: target)),
              let texts = try? JSONDecoder().decode([String].self, from: data),
              texts.count == blocks.count else { return nil }
        return texts
    }

    /// Saves a translation; past `cacheLimit` files the oldest go.
    nonisolated static func store(_ texts: [String], for blocks: [String], target: Locale.Language) {
        let fm = FileManager.default
        try? fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(texts) else { return }
        try? data.write(to: cacheURL(blocks, target: target), options: .atomic)
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: keys),
              files.count > cacheLimit else { return }
        let dated = files.map { ($0, (try? $0.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast) }
        for (url, _) in dated.sorted(by: { $0.1 < $1.1 }).prefix(files.count - cacheLimit) { try? fm.removeItem(at: url) }
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
            return String(localized: "Translation isn’t available for this language pair.")
        }
        if TranslationError.unableToIdentifyLanguage ~= error {
            return String(localized: "Couldn’t tell which language this chapter is in.")
        }
        return String(localized: "Couldn’t translate this chapter.")
    }
}
