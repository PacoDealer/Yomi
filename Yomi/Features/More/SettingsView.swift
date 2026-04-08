import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var showCustomColorPicker = false

    // 10 curated swatches (hex strings)
    private let accentSwatches: [String] = [
        "#FF6B6B", // coral (default)
        "#FF9F43", // orange
        "#FECA57", // yellow
        "#48DBFB", // sky
        "#0ABDE3", // cyan
        "#006BA6", // blue
        "#5F27CD", // purple
        "#C56BFF", // lavender
        "#FF6EB4", // pink
        "#00D2A4", // teal
    ]

    var body: some View {
        List {
            generalSection
            librarySection
            mangaReaderSection
            novelReaderSection
            appearanceSection
            advancedSection
            aboutSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - General

    private var generalSection: some View {
        Section("General") {
            Toggle("Show NSFW content", isOn: $settings.showNSFW)
        }
    }

    // MARK: - Library

    private var librarySection: some View {
        Section("Library") {
            Stepper(
                "Items per row: \(settings.libraryColumns)",
                value: $settings.libraryColumns,
                in: 2...6
            )
        }
    }

    // MARK: - Reader — Manga

    private var mangaReaderSection: some View {
        Section("Reader — Manga") {
            Picker("Default mode", selection: $settings.readerMode) {
                Text("Manga (RTL)").tag("Manga (RTL)")
                Text("Manhwa (LTR)").tag("Manhwa (LTR)")
                Text("Webtoon").tag("Webtoon")
            }
            .pickerStyle(.menu)

            Toggle("Keep screen on while reading", isOn: $settings.keepScreenOn)
        }
    }

    // MARK: - Reader — Novels

    private var novelReaderSection: some View {
        Section("Reader — Novels") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Font size: \(Int(settings.fontSize))pt")
                    .font(.subheadline)
                Slider(value: $settings.fontSize, in: 14...28, step: 1)
                    .tint(Color(hex: settings.accentColor))
            }
            .padding(.vertical, 4)

            Stepper(
                "Line spacing: \(String(format: "%.1f", settings.lineSpacing))×",
                value: $settings.lineSpacing,
                in: 1.0...2.5,
                step: 0.1
            )
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $settings.theme) {
                Text("System").tag("System")
                Text("Light").tag("Light")
                Text("Dark").tag("Dark")
            }
            .pickerStyle(.segmented)

            // Accent color
            VStack(alignment: .leading, spacing: 10) {
                Text("Accent color")
                    .font(.subheadline)

                // Swatch row — scrollable so all swatches fit on any screen width
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(accentSwatches, id: \.self) { hex in
                            swatchButton(hex: hex)
                        }

                        // Custom color picker button (rainbow circle)
                        Button {
                            showCustomColorPicker = true
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(
                                        AngularGradient(
                                            gradient: Gradient(colors: [
                                                .red, .yellow, .green, .cyan, .blue, .purple, .red
                                            ]),
                                            center: .center
                                        )
                                    )
                                    .frame(width: 32, height: 32)
                                if !accentSwatches.contains(settings.accentColor) {
                                    Circle()
                                        .strokeBorder(.white, lineWidth: 2.5)
                                        .frame(width: 32, height: 32)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .sheet(isPresented: $showCustomColorPicker) {
                            customColorPickerSheet
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(.vertical, 4)

            Toggle("Use system font", isOn: $settings.useSystemFont)
        }
    }

    // MARK: - Swatch button

    private func swatchButton(hex: String) -> some View {
        let isSelected = settings.accentColor == hex
        return Button {
            settings.accentColor = hex
        } label: {
            ZStack {
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 32, height: 32)
                if isSelected {
                    Circle()
                        .strokeBorder(.white, lineWidth: 2.5)
                        .frame(width: 32, height: 32)
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Custom color picker sheet

    private var customColorPickerSheet: some View {
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
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(.secondary)

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

    // MARK: - Advanced

    private var advancedSection: some View {
        Section("Advanced") {
            Button("Clear image cache") {
                URLCache.shared.removeAllCachedResponses()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            .foregroundStyle(.primary)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            LabeledContent(
                "Version",
                value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
            )
            LabeledContent(
                "Build",
                value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
            )
            Link("GitHub", destination: URL(string: "https://github.com/PacoDealer/Yomi")!)
            Link("Report a bug", destination: URL(string: "https://github.com/PacoDealer/Yomi/issues")!)
            Link("Privacy Policy", destination: URL(string: "https://yomi-plugins.web.app/privacy")!)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SettingsView()
    }
}
