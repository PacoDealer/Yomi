import SwiftUI

// MARK: - AppearanceStudioView
//
// Canvas × Accent × Type — the three independent appearance axes.
// DESIGN_SYSTEM §12. Every control updates live.

struct AppearanceStudioView: View {

    @State private var settings = AppSettings.shared
    @State private var showCustomColorPicker = false

    // MARK: - Derived

    private var canvas: YomiTokens.CanvasColors { settings.canvasColors }
    private var accent: Color { Color(hex: settings.accentColor) }
    private var accentForeground: Color { settings.accentForeground }

    private let accentSwatches = YomiTokens.Accent.presets.map(\.hex)

    private let alternateIcons: [(label: String, key: String?)] = [
        ("Ink",   nil),
        ("Paper", "AppIcon-Paper"),
    ]

    // MARK: - Body

    var body: some View {
        List {
            previewSection
            canvasSection
            accentSection
            typeSection
            librarySection
            iconSection
            resetSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCustomColorPicker) {
            customPickerSheet
        }
    }

    // MARK: - Live preview

    private var previewSection: some View {
        Section {
            previewCard
                .padding(.vertical, 4)
        }
        .listRowInsets(.init(top: 12, leading: 16, bottom: 12, trailing: 16))
        .listRowBackground(Color.clear)
    }

    private var previewCard: some View {
        VStack(spacing: 0) {
            // Continue reading row
            HStack(spacing: 12) {
                // Cover placeholder
                RoundedRectangle(cornerRadius: YomiTokens.Radius.thumb)
                    .fill(canvas.surface1)
                    .frame(width: 52, height: 74)
                    .overlay(
                        Text("C")
                            .font(.custom(YomiTokens.Font.groteskFamily, size: 18).weight(.bold))
                            .foregroundStyle(canvas.textSecondary)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text("CONTINUE READING")
                        .font(.custom(YomiTokens.Font.monoRegular, size: 10))
                        .foregroundStyle(canvas.textSecondary)
                        .tracking(0.4)

                    Text("My Reading Title")
                        .font(.custom(YomiTokens.Font.groteskFamily, size: 15).weight(.medium))
                        .foregroundStyle(canvas.textPrimary)
                        .lineLimit(1)

                    Text("CH. 042 · 68% · ◷ 8H")
                        .font(.custom(YomiTokens.Font.monoRegular, size: 11))
                        .foregroundStyle(canvas.textSecondary)

                    HStack(spacing: 10) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(canvas.surface2).frame(height: 3)
                                Capsule().fill(accent)
                                    .frame(width: geo.size.width * 0.68, height: 3)
                            }
                        }
                        .frame(height: 3)

                        Capsule()
                            .fill(accent)
                            .frame(width: 58, height: 22)
                            .overlay(
                                Text("Resume")
                                    .font(.custom(YomiTokens.Font.groteskFamily, size: 11).weight(.medium))
                                    .foregroundStyle(accentForeground)
                            )
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)

            // Hairline
            Rectangle()
                .fill(canvas.hairline)
                .frame(height: 0.5)
                .padding(.horizontal, 14)

            // Reader text preview
            Text("In quiet hours, words became worlds, and each page turned was a breath of a different life…")
                .font(settings.useSystemFont
                      ? .system(size: 13)
                      : .custom(YomiTokens.Font.groteskFamily, size: 13))
                .foregroundStyle(canvas.textPrimary)
                .lineSpacing(3)
                .lineLimit(2)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            // Mini tab bar
            HStack {
                ForEach([
                    ("books.vertical.fill", true),
                    ("safari", false),
                    ("clock", false),
                    ("bell", false),
                    ("ellipsis", false),
                ], id: \.0) { icon, isActive in
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .foregroundStyle(isActive ? accent : canvas.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 7)
            .background(canvas.surface1)
            .overlay(alignment: .top) {
                Rectangle().fill(canvas.hairline).frame(height: 0.5)
            }
        }
        .background(canvas.bg)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }

    // MARK: - Canvas

    private var canvasSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(YomiTokens.Canvas.all, id: \.name) { preset in
                        canvasSwatch(preset)
                    }
                }
                .padding(.vertical, 6)
            }
        } header: {
            Text("Canvas")
        } footer: {
            Text("Ink is the brand default. Midnight is OLED true-black.")
        }
    }

    private func canvasSwatch(_ preset: YomiTokens.CanvasColors) -> some View {
        let isSelected = settings.canvas == preset.name
        return Button {
            settings.canvas = preset.name
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(preset.bg)
                        .frame(width: 68, height: 46)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(preset.surface1)
                        .frame(width: 46, height: 28)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(preset.surface2)
                                .frame(width: 32, height: 14)
                        )
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isSelected ? accent : Color.clear,
                            lineWidth: 2.5
                        )
                )
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(accent)
                            .background(Circle().fill(preset.bg))
                            .offset(x: 4, y: -4)
                    }
                }

                Text(preset.name.uppercased())
                    .font(.custom(YomiTokens.Font.monoRegular, size: 10))
                    .foregroundStyle(isSelected ? accent : .secondary)
                    .tracking(0.3)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Accent

    private var accentSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Color")
                        .font(.subheadline)
                    Spacer()
                    // AA contrast badge
                    let label = accentContrastLabel
                    Text(label)
                        .font(.custom(YomiTokens.Font.monoBold, size: 11))
                        .foregroundStyle(label == "Fail" ? .red : .green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(
                                (label == "Fail" ? Color.red : Color.green).opacity(0.12)
                            )
                        )
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(accentSwatches, id: \.self) { hex in
                            accentSwatch(hex: hex)
                        }
                        // Custom picker
                        Button { showCustomColorPicker = true } label: {
                            ZStack {
                                Circle()
                                    .fill(AngularGradient(
                                        colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                                        center: .center
                                    ))
                                    .frame(width: 32, height: 32)
                                if !accentSwatches.contains(settings.accentColor) {
                                    Circle()
                                        .strokeBorder(.white, lineWidth: 2.5)
                                        .frame(width: 32, height: 32)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Accent")
        } footer: {
            Text("Accent appears on active states, progress, and primary actions — never as decoration.")
        }
    }

    private func accentSwatch(hex: String) -> some View {
        let isSelected = settings.accentColor == hex
        return Button {
            settings.accentColor = hex
        } label: {
            ZStack {
                Circle().fill(Color(hex: hex)).frame(width: 32, height: 32)
                if isSelected {
                    Circle().strokeBorder(.white, lineWidth: 2.5).frame(width: 32, height: 32)
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(YomiTokens.Accent.foreground(for: hex, on: canvas.textPrimary))
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Type

    private var typeSection: some View {
        Section("Type") {
            Picker("UI font", selection: $settings.useSystemFont) {
                Text("Space Grotesk").tag(false)
                Text("System").tag(true)
            }

            Picker("Reading font", selection: $settings.novelFontFamily) {
                Text("Serif (Newsreader)").tag("Serif")
                Text("Sans").tag("System")
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Reader size")
                    Spacer()
                    Text("\(Int(settings.fontSize))pt")
                        .font(.custom(YomiTokens.Font.monoRegular, size: 13))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $settings.fontSize, in: 14...28, step: 1)
                    .tint(accent)
            }
            .padding(.vertical, 2)

            Picker("Line spacing", selection: lineSpacingBinding) {
                Text("Tight").tag("Tight")
                Text("Normal").tag("Normal")
                Text("Airy").tag("Airy")
            }
            .pickerStyle(.segmented)

            Picker("Side margins", selection: $settings.novelHorizontalPadding) {
                Text("Narrow").tag(8)
                Text("Normal").tag(16)
                Text("Wide").tag(24)
            }
        }
    }

    private var lineSpacingBinding: Binding<String> {
        Binding(
            get: {
                switch settings.lineSpacing {
                case YomiTokens.ReaderDefaults.lineSpacingTight: return "Tight"
                case YomiTokens.ReaderDefaults.lineSpacingAiry:  return "Airy"
                default:                                          return "Normal"
                }
            },
            set: { name in
                switch name {
                case "Tight": settings.lineSpacing = YomiTokens.ReaderDefaults.lineSpacingTight
                case "Airy":  settings.lineSpacing = YomiTokens.ReaderDefaults.lineSpacingAiry
                default:      settings.lineSpacing = YomiTokens.ReaderDefaults.lineSpacingNormal
                }
            }
        )
    }

    // MARK: - Library

    private var librarySection: some View {
        Section("Library") {
            Stepper("Grid columns: \(settings.libraryColumns)", value: $settings.libraryColumns, in: 2...6)
            Toggle("Show unread count badge", isOn: $settings.showUnreadBadge)
        }
    }

    // MARK: - App icon

    private var iconSection: some View {
        Section("App icon") {
            HStack(spacing: 14) {
                ForEach(alternateIcons, id: \.label) { option in
                    Button { applyAlternateIcon(option.key) } label: {
                        VStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray5))
                                .frame(width: 52, height: 52)
                                .overlay(
                                    Text(option.label.prefix(1))
                                        .font(.title2.bold())
                                        .foregroundStyle(.secondary)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(
                                            settings.alternateIconName == option.key ? accent : Color.clear,
                                            lineWidth: 2.5
                                        )
                                )
                            Text(option.label)
                                .font(.custom(YomiTokens.Font.monoRegular, size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func applyAlternateIcon(_ name: String?) {
        Task { @MainActor in
            do {
                try await UIApplication.shared.setAlternateIconName(name)
                settings.alternateIconName = name
            } catch {
                // Icon not registered yet — no-op.
            }
        }
    }

    // MARK: - Reset

    private var resetSection: some View {
        Section {
            Button("Reset to defaults", role: .destructive) {
                settings.canvas            = "Ink"
                settings.accentColor       = "#E5473A"
                settings.useSystemFont     = false
                settings.novelFontFamily   = "Serif"
                settings.fontSize          = YomiTokens.ReaderDefaults.fontSize
                settings.lineSpacing       = YomiTokens.ReaderDefaults.lineSpacingNormal
                settings.novelHorizontalPadding = 16
                settings.libraryColumns    = 3
                settings.showUnreadBadge   = true
            }
        } footer: {
            Text("Restores canvas, accent, typography, and library display to YOMI defaults.")
        }
    }

    // MARK: - Custom accent picker sheet

    private var customPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                ColorPicker(
                    "Choose accent color",
                    selection: Binding(
                        get: { Color(hex: settings.accentColor) },
                        set: { settings.accentColor = $0.hexString }
                    ),
                    supportsOpacity: false
                )
                .padding()

                Circle()
                    .fill(Color(hex: settings.accentColor))
                    .frame(width: 80, height: 80)
                    .shadow(radius: 8)

                Text(settings.accentColor.uppercased())
                    .font(.custom(YomiTokens.Font.monoBold, size: 16))
                    .foregroundStyle(.secondary)

                // Contrast badge
                let label = accentContrastLabel
                Text("Contrast: \(label)")
                    .font(.custom(YomiTokens.Font.monoRegular, size: 13))
                    .foregroundStyle(label == "Fail" ? .red : .green)

                Spacer()
            }
            .navigationTitle("Custom color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showCustomColorPicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Contrast helpers (WCAG AA)

    private var accentContrastLabel: String {
        let ratio = wcagContrast(accent, canvas.bg)
        return ratio >= 4.5 ? "AAA" : ratio >= 3.0 ? "AA" : "Fail"
    }

    private func wcagContrast(_ c1: Color, _ c2: Color) -> Double {
        let l1 = relativeLuminance(c1), l2 = relativeLuminance(c2)
        let hi = max(l1, l2), lo = min(l1, l2)
        return (hi + 0.05) / (lo + 0.05)
    }

    private func relativeLuminance(_ color: Color) -> Double {
        let uic = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uic.getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ v: CGFloat) -> Double {
            let d = Double(v)
            return d <= 0.04045 ? d / 12.92 : pow((d + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
}
