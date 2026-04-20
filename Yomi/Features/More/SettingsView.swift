import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var showCustomColorPicker = false
    @State private var newRepoURL: String = ""
    @State private var showAddRepo = false

    // Alternate icons: key = display name, value = CFBundleAlternateIcons key (nil = default)
    private let alternateIcons: [(label: String, key: String?)] = [
        ("Default",  nil),
        ("Dark",     "AppIconDark"),
        ("Minimal",  "AppIconMinimal"),
    ]

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
            downloadsSection
            updatesSection
            novelReaderSection
            appearanceSection
            pluginRepositoriesSection
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
            Toggle("Show unread count badge", isOn: $settings.showUnreadBadge)
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

            Toggle(isOn: $settings.autoWebtoonFromTags) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-detect webtoon")
                    Text("Switches to Webtoon mode for manhwa/manhua/long-strip titles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Tap zones", selection: $settings.tapZoneLayout) {
                Text("Default (equal thirds)").tag("default")
                Text("Sides (20 · 60 · 20%)").tag("sides")
                Text("Disabled (swipe only)").tag("disabled")
            }

            Toggle("Keep screen on while reading", isOn: $settings.keepScreenOn)

            Toggle(isOn: $settings.isIncognito) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Incognito mode", systemImage: "theatermasks")
                    Text("Reading progress and history won't be saved")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Downloads

    private var downloadsSection: some View {
        Section("Downloads") {
            Stepper(
                "Auto-scroll speed: \(String(format: "%.0f", settings.autoScrollSpeed))s",
                value: $settings.autoScrollSpeed,
                in: 1...10,
                step: 0.5
            )

            Picker("Webtoon margins", selection: $settings.webtoonHorizontalPadding) {
                Text("None").tag(0)
                Text("Small (8 pt)").tag(8)
                Text("Normal (16 pt)").tag(16)
                Text("Wide (24 pt)").tag(24)
            }

            Toggle(isOn: $settings.deleteDownloadAfterReading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Delete after reading")
                    Text("Removes downloaded files when you finish a chapter")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Stepper(
                "Concurrent downloads: \(settings.concurrentDownloads)",
                value: $settings.concurrentDownloads,
                in: 1...5
            )
        }
    }

    // MARK: - Updates

    private var updatesSection: some View {
        Section("Updates") {
            Toggle(isOn: $settings.skipUpdateWithUnread) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Skip if unread chapters exist")
                    Text("Don't check for updates when you already have unread content")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: $settings.skipUpdateNotStarted) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Skip titles not started")
                    Text("Don't check titles you've never opened")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: $settings.skipUpdateCompleted) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Skip completed titles")
                    Text("Don't check titles marked as Completed by the source")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            NavigationLink("Excluded categories") {
                ExcludedCategoriesView(settings: settings)
            }
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

            Picker("Font family", selection: $settings.novelFontFamily) {
                Text("Serif (Georgia)").tag("Serif")
                Text("System").tag("System")
            }

            Picker("Default theme", selection: $settings.novelTheme) {
                ForEach(NovelTheme.allCases, id: \.rawValue) { theme in
                    Text(theme.rawValue).tag(theme.rawValue)
                }
            }

            Picker("Margins", selection: $settings.novelHorizontalPadding) {
                Text("Narrow").tag(8)
                Text("Normal").tag(16)
                Text("Wide").tag(28)
            }
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

            // App icon picker
            VStack(alignment: .leading, spacing: 8) {
                Text("App icon")
                    .font(.subheadline)
                HStack(spacing: 12) {
                    ForEach(alternateIcons, id: \.label) { option in
                        Button {
                            applyAlternateIcon(option.key)
                        } label: {
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemGray5))
                                    .frame(width: 56, height: 56)
                                    .overlay(
                                        Text(option.label.prefix(1))
                                            .font(.title2.bold())
                                            .foregroundStyle(.secondary)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(
                                                settings.alternateIconName == option.key
                                                    ? Color(hex: settings.accentColor)
                                                    : Color.clear,
                                                lineWidth: 2.5
                                            )
                                    )
                                Text(option.label)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 4)

            Toggle("Use system font", isOn: $settings.useSystemFont)

            Toggle(isOn: $settings.pureBlack) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Pure black (OLED)", systemImage: "circle.fill")
                    Text("Forces #000000 backgrounds — saves battery on OLED screens")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
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

    // MARK: - Apply alternate icon

    private func applyAlternateIcon(_ name: String?) {
        Task { @MainActor in
            do {
                try await UIApplication.shared.setAlternateIconName(name)
                settings.alternateIconName = name
            } catch {
                // Icon not registered in Info.plist CFBundleAlternateIcons — silently ignore.
                // Add the icon entries in Xcode: Target → Info → CFBundleIcons → CFBundleAlternateIcons.
            }
        }
    }

    // MARK: - Plugin Repositories

    private var pluginRepositoriesSection: some View {
        Section {
            ForEach(settings.pluginCatalogURLs, id: \.self) { url in
                Text(url)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .onDelete { offsets in
                settings.pluginCatalogURLs.remove(atOffsets: offsets)
                PluginCatalogService.shared.invalidateCache()
            }

            Button {
                newRepoURL = ""
                showAddRepo = true
            } label: {
                Label("Add repository", systemImage: "plus")
            }
            .sheet(isPresented: $showAddRepo) {
                addRepoSheet
            }
        } header: {
            Text("Plugin Repositories")
        } footer: {
            Text("Catalogs are merged. Duplicate plugin IDs: first catalog wins.")
                .font(.caption)
        }
    }

    private var addRepoSheet: some View {
        NavigationStack {
            Form {
                Section("Catalog URL") {
                    TextField("https://example.com/index.json", text: $newRepoURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("Add Repository")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddRepo = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let trimmed = newRepoURL.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty, !settings.pluginCatalogURLs.contains(trimmed) {
                            settings.pluginCatalogURLs.append(trimmed)
                            PluginCatalogService.shared.invalidateCache()
                        }
                        showAddRepo = false
                    }
                    .disabled(newRepoURL.trimmingCharacters(in: .whitespaces).isEmpty)
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

// MARK: - ExcludedCategoriesView

private struct ExcludedCategoriesView: View {
    let settings: AppSettings
    @State private var categories: [Category] = []

    var body: some View {
        List {
            if categories.isEmpty {
                Text("No categories yet. Create categories in your library to exclude them from update checks.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(categories) { cat in
                    Button {
                        var excluded = settings.excludedCategoryIds
                        if excluded.contains(cat.id) {
                            excluded.removeAll { $0 == cat.id }
                        } else {
                            excluded.append(cat.id)
                        }
                        settings.excludedCategoryIds = excluded
                    } label: {
                        HStack {
                            Text(cat.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if settings.excludedCategoryIds.contains(cat.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Excluded Categories")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            categories = (try? CategoryQueries.fetchAll()) ?? []
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SettingsView()
    }
}
