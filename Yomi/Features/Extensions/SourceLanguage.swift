import Foundation

/// Normalizes the language labels different source catalogs use, so one language filter works across all of them:
/// Yomi's catalog and Keiyoushi use codes (`en`, `pt-BR`, `es-419`), LNReader uses native names (`English`,
/// `Español`, `中文, 汉语, 漢語`, `‎العربية` with a stray direction mark).
nonisolated enum SourceLanguage {
    /// Native and English language names → ISO code, e.g. "español" / "spanish" → "es".
    private static let namesToCodes: [String: String] = {
        var map: [String: String] = [:]
        let english = Locale(identifier: "en")
        for code in Locale.LanguageCode.isoLanguageCodes.map(\.identifier) {
            if let native = Locale(identifier: code).localizedString(forLanguageCode: code) {
                map[native.lowercased()] = code
            }
            if let name = english.localizedString(forLanguageCode: code) {
                map[name.lowercased()] = code
            }
        }
        map["bahasa indonesia"] = "id"
        return map
    }()

    private static let strip = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: "\u{200E}\u{200F}"))

    /// The base language code for filtering — `pt-BR` and `Português` both give `pt`. `"all"` for a
    /// multi-language catalog entry.
    static func baseCode(for raw: String) -> String {
        let cleaned = raw.trimmingCharacters(in: strip).lowercased()
        if cleaned == "multi" || cleaned == "all" { return "all" }
        for part in cleaned.split(separator: ",") {
            let name = part.trimmingCharacters(in: strip)
            if let code = namesToCodes[name] { return code }
        }
        return String(cleaned.split(separator: "-").first ?? Substring(cleaned))
    }

    /// A readable name in the user's language: "en" → "English", "pt-BR" → "Portuguese (Brazil)".
    static func displayName(for raw: String) -> String {
        let cleaned = raw.trimmingCharacters(in: strip)
        if baseCode(for: cleaned) == "all" { return "Multiple languages" }
        if let name = Locale.current.localizedString(forIdentifier: cleaned), name.lowercased() != cleaned.lowercased() {
            return name.prefix(1).uppercased() + name.dropFirst()
        }
        let code = baseCode(for: cleaned)
        return Locale.current.localizedString(forLanguageCode: code).map { $0.prefix(1).uppercased() + $0.dropFirst() }
            ?? cleaned
    }
}
