import Foundation
import Observation
import SwiftUI

// MARK: - AppSettings

/// Singleton settings store backed by UserDefaults.
/// All properties are computed vars so reads always reflect the current
/// persisted value; writes go straight to UserDefaults.
/// Wrapped in @State in a SwiftUI view to get $bindings.
@Observable final class AppSettings {

    // MARK: - Singleton

    static let shared = AppSettings()
    private init() {}

    // MARK: - Private storage

    private let defaults = UserDefaults.standard

    // MARK: - Reader

    /// Reading mode for manga. Values: "Manga (RTL)", "Webtoon"
    var readerMode: String {
        get { defaults.string(forKey: "readerMode") ?? "Manga (RTL)" }
        set { defaults.set(newValue, forKey: "readerMode") }
    }

    /// Font size for the novel reader (points)
    var fontSize: Double {
        get { defaults.object(forKey: "fontSize") as? Double ?? 16.0 }
        set { defaults.set(newValue, forKey: "fontSize") }
    }

    /// Line spacing multiplier for the novel reader
    var lineSpacing: Double {
        get { defaults.object(forKey: "lineSpacing") as? Double ?? 1.5 }
        set { defaults.set(newValue, forKey: "lineSpacing") }
    }

    // MARK: - Appearance

    /// App color scheme override. Values: "System", "Light", "Dark"
    var theme: String {
        get { defaults.string(forKey: "theme") ?? "System" }
        set { defaults.set(newValue, forKey: "theme") }
    }

    /// Resolved ColorScheme for .preferredColorScheme(). Nil = follow system.
    var colorScheme: ColorScheme? {
        switch theme {
        case "Light": return .light
        case "Dark":  return .dark
        default:      return nil
        }
    }

    /// Whether to use the system font or the built-in reader font
    var useSystemFont: Bool {
        get { defaults.object(forKey: "useSystemFont") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "useSystemFont") }
    }

    // MARK: - Content

    /// Whether to show NSFW sources and catalog entries
    var showNSFW: Bool {
        get { defaults.object(forKey: "showNSFW") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "showNSFW") }
    }

    /// Whether the app has already prompted the user for notification permission
    var hasRequestedNotifications: Bool {
        get { defaults.bool(forKey: "hasRequestedNotifications") }
        set { defaults.set(newValue, forKey: "hasRequestedNotifications") }
    }

    /// Whether the novel reader uses sepia background (#F4ECD8) and text (#5C4033)
    var novelSepia: Bool {
        get { defaults.bool(forKey: "novelSepia") }
        set { defaults.set(newValue, forKey: "novelSepia") }
    }

    /// Whether the user has completed the first-launch onboarding flow
    var hasSeenOnboarding: Bool {
        get { defaults.bool(forKey: "hasSeenOnboarding") }
        set { defaults.set(newValue, forKey: "hasSeenOnboarding") }
    }

    // MARK: - Plugins

    /// URL of the plugin catalog index.json used by PluginsView "Browse catalog"
    var pluginCatalogURL: String {
        get { defaults.string(forKey: "pluginCatalogURL") ?? "https://yomi-plugins.web.app/index.json" }
        set { defaults.set(newValue, forKey: "pluginCatalogURL") }
    }

    // MARK: - Accent color

    /// Hex string for the app accent/tint color. Default: red.
    var accentColor: String {
        get { defaults.string(forKey: "accentColor") ?? "#FF6B6B" }
        set { defaults.set(newValue, forKey: "accentColor") }
    }
}

// MARK: - Color(hex:)

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
