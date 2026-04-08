import SwiftUI
import Observation

// MARK: - AppSettings
//
// @Observable requires STORED properties for the observation graph to work.
// Computed vars backed by UserDefaults are invisible to @Observable —
// mutations write to UserDefaults but no notification fires, so views
// depending on those properties never re-render.
//
// Pattern: stored property with didSet → persists to UserDefaults.
// @Observable macro instruments the stored property → mutation fires → views update.

@Observable final class AppSettings {

    // MARK: - Singleton

    static let shared = AppSettings()

    // MARK: - Private storage

    @ObservationIgnored private let defaults = UserDefaults.standard

    // MARK: - Reader

    var readerMode: String {
        didSet { defaults.set(readerMode, forKey: "readerMode") }
    }

    var fontSize: Double {
        didSet { defaults.set(fontSize, forKey: "fontSize") }
    }

    var lineSpacing: Double {
        didSet { defaults.set(lineSpacing, forKey: "lineSpacing") }
    }

    // MARK: - Appearance

    var theme: String {
        didSet { defaults.set(theme, forKey: "theme") }
    }

    /// Derived from theme — reactive because theme is now a stored property.
    var colorScheme: ColorScheme? {
        switch theme {
        case "Light": return .light
        case "Dark":  return .dark
        default:      return nil
        }
    }

    var accentColor: String {
        didSet { defaults.set(accentColor, forKey: "accentColor") }
    }

    var useSystemFont: Bool {
        didSet { defaults.set(useSystemFont, forKey: "useSystemFont") }
    }

    // MARK: - Content

    var showNSFW: Bool {
        didSet { defaults.set(showNSFW, forKey: "showNSFW") }
    }

    // MARK: - Notifications

    var hasRequestedNotifications: Bool {
        didSet { defaults.set(hasRequestedNotifications, forKey: "hasRequestedNotifications") }
    }

    // MARK: - Novel reader

    var novelSepia: Bool {
        didSet { defaults.set(novelSepia, forKey: "novelSepia") }
    }

    // MARK: - Onboarding

    var hasSeenOnboarding: Bool {
        didSet { defaults.set(hasSeenOnboarding, forKey: "hasSeenOnboarding") }
    }

    // MARK: - Plugins

    var pluginCatalogURL: String {
        didSet { defaults.set(pluginCatalogURL, forKey: "pluginCatalogURL") }
    }

    // MARK: - Library display

    /// Number of columns in library grid (portrait)
    var libraryColumns: Int {
        didSet { defaults.set(libraryColumns, forKey: "libraryColumns") }
    }

    // MARK: - Reader behaviour

    /// Keep screen on while reading
    var keepScreenOn: Bool {
        didSet { defaults.set(keepScreenOn, forKey: "keepScreenOn") }
    }

    // MARK: - Init

    private init() {
        let d = UserDefaults.standard
        readerMode              = d.string(forKey: "readerMode")             ?? "Manga (RTL)"
        fontSize                = d.object(forKey: "fontSize")    as? Double ?? 18.0
        lineSpacing             = d.object(forKey: "lineSpacing") as? Double ?? 1.6
        theme                   = d.string(forKey: "theme")                  ?? "System"
        accentColor             = d.string(forKey: "accentColor")            ?? "#FF6B6B"
        useSystemFont           = d.object(forKey: "useSystemFont") as? Bool ?? true
        showNSFW                = d.object(forKey: "showNSFW")     as? Bool  ?? false
        hasRequestedNotifications = d.bool(forKey: "hasRequestedNotifications")
        novelSepia              = d.bool(forKey: "novelSepia")
        hasSeenOnboarding       = d.bool(forKey: "hasSeenOnboarding")
        pluginCatalogURL        = d.string(forKey: "pluginCatalogURL")       ?? "https://yomi-plugins.web.app/index.json"
        libraryColumns          = d.object(forKey: "libraryColumns") as? Int ?? 3
        keepScreenOn            = d.object(forKey: "keepScreenOn")   as? Bool ?? true
    }
}
