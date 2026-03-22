import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        List {
            generalSection
            mangaReaderSection
            novelReaderSection
            appearanceSection
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

    // MARK: - Reader — Manga

    private var mangaReaderSection: some View {
        Section("Reader — Manga") {
            Picker("Default mode", selection: $settings.readerMode) {
                Text("Manga (RTL)").tag("Manga (RTL)")
                Text("Webtoon").tag("Webtoon")
            }
            .pickerStyle(.menu)
        }
    }

    // MARK: - Reader — Novels

    private var novelReaderSection: some View {
        Section("Reader — Novels") {
            Stepper(
                "Font size: \(Int(settings.fontSize))pt",
                value: $settings.fontSize,
                in: 12...24,
                step: 2
            )
            Stepper(
                "Line spacing: \(String(format: "%0.1f", locale: Locale(identifier: "en_US"), settings.lineSpacing))",
                value: $settings.lineSpacing,
                in: 1.0...2.5,
                step: 0.25
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
            .pickerStyle(.menu)
            Toggle("Use system font", isOn: $settings.useSystemFont)
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
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SettingsView()
    }
}
