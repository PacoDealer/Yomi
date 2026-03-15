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
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - General

    private var generalSection: some View {
        Section("General") {
            Picker("Default tab", selection: $settings.defaultTab) {
                Text("Library").tag("library")
                Text("Browse").tag("browse")
                Text("History").tag("history")
            }
            Toggle("Show NSFW sources", isOn: $settings.showNSFWSources)
        }
    }

    // MARK: - Reader (manga)

    private var mangaReaderSection: some View {
        Section("Reader — manga") {
            Picker("Default mode", selection: $settings.defaultReaderMode) {
                Text("RTL manga").tag("horizontalRTL")
                Text("Webtoon").tag("verticalScroll")
            }
            Toggle("Show page number", isOn: $settings.showPageNumber)
            Toggle("Keep screen on",  isOn: $settings.keepScreenOn)
        }
    }

    // MARK: - Reader (novel)

    private var novelReaderSection: some View {
        Section("Reader — novel") {
            LabeledContent("Font size") {
                HStack(spacing: 8) {
                    Slider(value: $settings.novelFontSize, in: 14...26, step: 1)
                        .frame(width: 120)
                    Text("\(Int(settings.novelFontSize))px")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Picker("Theme", selection: $settings.novelTheme) {
                Text("Dark").tag("dark")
                Text("Light").tag("light")
                Text("Sepia").tag("sepia")
            }
            LabeledContent("Line spacing") {
                HStack(spacing: 8) {
                    Slider(value: $settings.novelLineSpacing, in: 1.2...2.4, step: 0.1)
                        .frame(width: 120)
                    Text(String(format: "%.1f", settings.novelLineSpacing))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("App theme", selection: $settings.appTheme) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            Picker("Library", selection: $settings.libraryDisplayMode) {
                Label("Grid", systemImage: "square.grid.2x2").tag("grid")
                Label("List", systemImage: "list.bullet").tag("list")
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SettingsView()
    }
}
