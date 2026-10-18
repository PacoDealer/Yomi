import SwiftUI

// MARK: - NovelTheme
//
// The novel reader's colours: eight built-ins (YomiTokens.Reader) plus themes the reader makes (S177 — ArcReader's
// "New" theme). Identified by a string kept in `AppSettings.novelTheme`: the built-in's name, or "custom:<uuid>".

struct NovelTheme: Equatable, Identifiable {
    let id: String
    let name: String
    let bg: String
    let fg: String
    let isDark: Bool

    var isCustom: Bool { id.hasPrefix(CustomNovelTheme.prefix) }
    var colorScheme: ColorScheme { isDark ? .dark : .light }
    /// Color for the theme swatch circle in the overlay
    var swatchColor: Color { Color(hex: bg) }
    var uiColor: UIColor { UIColor(Color(hex: bg)) }

    static let light = NovelTheme(YomiTokens.Reader.light)

    static var builtIns: [NovelTheme] { YomiTokens.Reader.all.map { NovelTheme($0) } }

    /// Built-ins, then the reader's own themes in the order they were made.
    static var all: [NovelTheme] { builtIns + CustomNovelTheme.load().map(\.theme) }

    /// The saved theme; a deleted custom theme falls back to Light.
    static func resolve(_ id: String) -> NovelTheme {
        all.first { $0.id == id } ?? .light
    }

    private init(_ token: YomiTokens.ReaderTheme) {
        // id keeps the English token name (it is what settings store); the name is only shown.
        self.init(id: token.name, name: String(localized: String.LocalizationValue(token.name)), bg: token.bg, fg: token.fg, isDark: token.isDark)
    }

    init(id: String, name: String, bg: String, fg: String, isDark: Bool) {
        self.id = id; self.name = name; self.bg = bg; self.fg = fg; self.isDark = isDark
    }
}

// MARK: - Night theme (S178, RESEARCH §25.3 #9 — "offer auto-switch to a dark theme at night"; no health claims)

enum NightTheme {
    /// Whether the reader should show the night theme now.
    static func isNight(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let s = AppSettings.shared
        guard !s.novelNightTheme.isEmpty else { return false }
        guard s.novelNightMode == "schedule" else { return ReaderBackdrop.systemIsDark }
        let c = calendar.dateComponents([.hour, .minute], from: now)
        return inWindow((c.hour ?? 0) * 60 + (c.minute ?? 0), start: s.novelNightStart, end: s.novelNightEnd)
    }

    /// `minute` (after midnight) inside [start, end), which may run past midnight. start == end = never.
    nonisolated static func inWindow(_ minute: Int, start: Int, end: Int) -> Bool {
        if start == end { return false }
        return start < end ? (minute >= start && minute < end) : (minute >= start || minute < end)
    }

    /// Dark themes first — what a night theme is usually chosen from — then the light ones.
    static var choices: [NovelTheme] {
        NovelTheme.all.filter(\.isDark) + NovelTheme.all.filter { !$0.isDark }
    }

    static func timeLabel(_ minutes: Int) -> String {
        var c = DateComponents(); c.hour = minutes / 60; c.minute = minutes % 60
        let date = Calendar.current.date(from: c) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - CustomNovelTheme

struct CustomNovelTheme: Codable, Equatable, Identifiable {
    static let prefix = "custom:"

    var id: String
    var name: String
    var bg: String
    var fg: String

    var theme: NovelTheme {
        NovelTheme(id: id, name: name, bg: bg, fg: fg, isDark: ThemeContrast.luminance(bg) < 0.18)
    }

    static func new(from base: NovelTheme) -> CustomNovelTheme {
        CustomNovelTheme(id: prefix + UUID().uuidString, name: String(localized: "My theme"), bg: base.bg, fg: base.fg)
    }

    static func load() -> [CustomNovelTheme] {
        (try? JSONDecoder().decode([CustomNovelTheme].self, from: AppSettings.shared.novelCustomThemes)) ?? []
    }

    static func save(_ themes: [CustomNovelTheme]) {
        AppSettings.shared.novelCustomThemes = (try? JSONEncoder().encode(themes)) ?? Data()
    }

    /// Adds or replaces `theme`.
    static func upsert(_ theme: CustomNovelTheme) {
        var list = load()
        if let i = list.firstIndex(where: { $0.id == theme.id }) { list[i] = theme } else { list.append(theme) }
        save(list)
    }

    static func delete(id: String) {
        save(load().filter { $0.id != id })
    }
}

// MARK: - Contrast (WCAG 2.x relative luminance)

enum ThemeContrast {
    nonisolated static func luminance(_ hex: String) -> Double {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6, let v = UInt64(h, radix: 16) else { return 1 }
        func channel(_ c: UInt64) -> Double {
            let x = Double(c & 0xFF) / 255
            return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(v >> 16) + 0.7152 * channel(v >> 8) + 0.0722 * channel(v)
    }

    nonisolated static func ratio(_ a: String, _ b: String) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// "#RRGGBB" for a picked colour, opacity dropped (the page is opaque).
    static func hex(_ color: Color) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).resolvedColor(with: .current).getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ x: CGFloat) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}

// MARK: - Editor

/// New / edit a custom theme: name, two colours, a live sample and its contrast. WCAG AA for body text is 4.5:1.
struct CustomThemeEditor: View {
    @State var theme: CustomNovelTheme
    let isNew: Bool
    /// Called with the saved theme, or nil when it was deleted.
    let onDone: (CustomNovelTheme?) -> Void
    @Environment(\.dismiss) private var dismiss

    private var contrast: Double { ThemeContrast.ratio(theme.bg, theme.fg) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("The scholar stopped at the gate. \u{201C}You came back,\u{201D} the old man said, without looking up from his tea.")
                        .font(.custom("Georgia", size: 18))
                        .foregroundStyle(Color(hex: theme.fg))
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .listRowBackground(Color(hex: theme.bg))
                        .accessibilityLabel("Sample text")
                } footer: {
                    Text(contrastNote)
                        .foregroundStyle(contrast < 4.5 ? Color.orange : Color.secondary)
                }
                Section {
                    TextField("Name", text: $theme.name)
                    ColorPicker("Background", selection: colorBinding(\.bg), supportsOpacity: false)
                    ColorPicker("Text", selection: colorBinding(\.fg), supportsOpacity: false)
                }
                if !isNew {
                    Section {
                        Button("Delete Theme", role: .destructive) {
                            CustomNovelTheme.delete(id: theme.id)
                            onDone(nil)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New Theme" : "Edit Theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        theme.name = theme.name.trimmingCharacters(in: .whitespaces)
                        if theme.name.isEmpty { theme.name = String(localized: "My theme") }
                        CustomNovelTheme.upsert(theme)
                        onDone(theme)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var contrastNote: String {
        let r = String(format: "%.1f", contrast)
        return contrast < 4.5
            ? String(localized: "Contrast \(r):1 — hard to read for long. 4.5:1 or more is recommended.")
            : String(localized: "Contrast \(r):1")
    }

    private func colorBinding(_ key: WritableKeyPath<CustomNovelTheme, String>) -> Binding<Color> {
        Binding(get: { Color(hex: theme[keyPath: key]) },
                set: { theme[keyPath: key] = ThemeContrast.hex($0) })
    }
}
