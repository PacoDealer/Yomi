import SwiftUI

// MARK: - AppearanceStudioView
//
// S142 calm redo (RESEARCH §26 principle 4: Appearance = theme + accent + app icon; reader typography stays in
// the reader panel, library grid in Settings → Library). The screen itself is the preview — every change
// applies to the whole app at once, so the old fake "Continue reading" card, the accent "blend into surfaces"
// slider (chrome stays neutral), the WCAG badge (it called 4.5:1 "AAA"; AAA is 7:1) and the duplicate
// typography/library controls are gone.

struct AppearanceStudioView: View {

    @State private var settings = AppSettings.shared
    @State private var showCustomColorPicker = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.yomiCanvas) private var canvas

    private var accent: Color { Color(hex: settings.accentColor) }

    /// Plain names for the presets (the stored values stay "Ink"/"Midnight"/… so nobody's choice changes).
    private let themes: [(key: String, label: String)] = [
        (AppSettings.automaticCanvas, "Automatic"),
        ("Ink", "Dark"),
        ("Midnight", "Black"),
        ("Paper", "Light"),
        ("Sepia", "Sepia"),
    ]

    private let icons: [(key: String?, label: String, preview: String)] = [
        (nil, "Dark", "OnboardingIcon"),
        ("AppIcon-Paper", "Light", "IconPreviewPaper"),
    ]

    var body: some View {
        CalmList {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(themes, id: \.key) { theme in themeSwatch(theme.key, label: theme.label) }
                    }
                    .padding(.vertical, 4)
                }
                .scrollClipDisabled()
            } header: { CalmSectionHeader("Theme") } footer: {
                Text(settings.canvas == AppSettings.automaticCanvas
                     ? "Light during the day and dark at night, following your iPhone."
                     : "Black turns off the pixels on OLED screens. The reader keeps its own page colours.")
            }

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(YomiTokens.Accent.presets, id: \.hex) { preset in
                            accentSwatch(preset.hex, name: preset.name)
                        }
                        customSwatch
                    }
                    .padding(.vertical, 6)
                }
                .scrollClipDisabled()
            } header: { CalmSectionHeader("Accent") } footer: {
                if accentIsHardToSee {
                    Text("This colour is hard to see on the current theme.")
                        .foregroundStyle(.orange)
                } else {
                    Text("Used for the selected tab, buttons, progress and links.")
                }
            }

            Section(calm: "App Icon") {
                HStack(spacing: 20) {
                    ForEach(icons, id: \.label) { icon in iconOption(icon) }
                }
                .padding(.vertical, 4)
            }

            Section {
                Button("Reset Appearance") {
                    settings.canvas = "Ink"
                    settings.accentColor = YomiTokens.Accent.defaultHex
                }
                .foregroundStyle(accent)
            } footer: {
                Text("Back to the Dark theme and the red accent.")
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCustomColorPicker) { customPickerSheet }
    }

    // MARK: - Theme

    private func themeSwatch(_ key: String, label: String) -> some View {
        let isSelected = settings.canvas == key
        return Button { settings.canvas = key } label: {
            VStack(spacing: 8) {
                themePreview(key)
                    .frame(width: 58, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(isSelected ? accent : canvas.textSecondary.opacity(0.25),
                                          lineWidth: isSelected ? 2.5 : 0.5)
                    )
                Text(label)
                    .font(.footnote.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? canvas.textPrimary : canvas.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) theme")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// A tiny screen: background, a cover-sized block and two text lines. Automatic shows light | dark halves.
    @ViewBuilder
    private func themePreview(_ key: String) -> some View {
        if key == AppSettings.automaticCanvas {
            HStack(spacing: 0) {
                miniScreen(YomiTokens.Canvas.paper)
                miniScreen(YomiTokens.Canvas.ink)
            }
        } else {
            miniScreen(YomiTokens.Canvas.named(key))
        }
    }

    private func miniScreen(_ c: YomiTokens.CanvasColors) -> some View {
        ZStack(alignment: .topLeading) {
            c.bg
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 3).fill(c.surface2).frame(width: 18, height: 26)
                Capsule().fill(c.textPrimary.opacity(0.8)).frame(width: 22, height: 3)
                Capsule().fill(c.textSecondary).frame(width: 14, height: 3)
            }
            .padding(8)
        }
    }

    // MARK: - Accent

    private func accentSwatch(_ hex: String, name: String) -> some View {
        let isSelected = settings.accentColor.caseInsensitiveCompare(hex) == .orderedSame
        return Button { settings.accentColor = hex } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 34, height: 34)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(YomiTokens.Accent.foreground(for: hex, on: canvas.textPrimary))
                    }
                }
                .padding(3)
                .overlay(Circle().strokeBorder(isSelected ? Color(hex: hex) : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var customSwatch: some View {
        let isCustom = !YomiTokens.Accent.presets.contains {
            $0.hex.caseInsensitiveCompare(settings.accentColor) == .orderedSame
        }
        return Button { showCustomColorPicker = true } label: {
            Circle()
                .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                .frame(width: 34, height: 34)
                .padding(3)
                .overlay(Circle().strokeBorder(isCustom ? accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Custom colour")
    }

    /// Accent as text/icons on the background: below 3:1 (WCAG non-text contrast) it's hard to see.
    private var accentIsHardToSee: Bool {
        wcagContrast(accent, settings.canvasColors(for: colorScheme).bg) < 3.0
    }

    // MARK: - App icon

    private func iconOption(_ icon: (key: String?, label: String, preview: String)) -> some View {
        let isSelected = settings.alternateIconName == icon.key
        return Button { applyAlternateIcon(icon.key) } label: {
            VStack(spacing: 8) {
                Image(icon.preview)
                    .resizable()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(isSelected ? accent : canvas.textSecondary.opacity(0.25),
                                          lineWidth: isSelected ? 2.5 : 0.5)
                    )
                Text(icon.label)
                    .font(.footnote.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? canvas.textPrimary : canvas.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(icon.label) app icon")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func applyAlternateIcon(_ name: String?) {
        guard name != settings.alternateIconName else { return }
        Task { @MainActor in
            do {
                try await UIApplication.shared.setAlternateIconName(name)
                settings.alternateIconName = name
            } catch {
                // Icon not registered in this build — keep the current one.
            }
        }
    }

    // MARK: - Custom accent sheet

    private var customPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                ColorPicker("Colour", selection: Binding(
                    get: { Color(hex: settings.accentColor) },
                    set: { settings.accentColor = $0.hexString }
                ), supportsOpacity: false)
                Circle().fill(accent).frame(width: 72, height: 72)
                if accentIsHardToSee {
                    Text("Hard to see on the current theme.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Custom Colour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showCustomColorPicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Contrast (WCAG relative luminance)

    private func wcagContrast(_ c1: Color, _ c2: Color) -> Double {
        let l1 = relativeLuminance(c1), l2 = relativeLuminance(c2)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    private func relativeLuminance(_ color: Color) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ v: CGFloat) -> Double {
            let d = Double(v)
            return d <= 0.04045 ? d / 12.92 : pow((d + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
}
