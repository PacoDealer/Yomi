import Foundation
import Observation

// MARK: - AppSettings

/// Singleton that persists all user-facing settings to UserDefaults.
/// Backed by @Observable so SwiftUI views re-render automatically on changes.
@Observable final class AppSettings {

    static let shared = AppSettings()
    private init() {}

    // MARK: - Storage

    @ObservationIgnored private let defaults = UserDefaults.standard

    // MARK: - General

    var showNSFWSources: Bool {
        get { defaults.bool(forKey: "showNSFWSources") }
        set { defaults.set(newValue, forKey: "showNSFWSources") }
    }

    var defaultTab: String {
        get { defaults.string(forKey: "defaultTab") ?? "library" }
        set { defaults.set(newValue, forKey: "defaultTab") }
    }

    // MARK: - Reader (manga)

    var defaultReaderMode: String {
        get { defaults.string(forKey: "defaultReaderMode") ?? "horizontalRTL" }
        set { defaults.set(newValue, forKey: "defaultReaderMode") }
    }

    var showPageNumber: Bool {
        get { defaults.object(forKey: "showPageNumber") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showPageNumber") }
    }

    var keepScreenOn: Bool {
        get { defaults.object(forKey: "keepScreenOn") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "keepScreenOn") }
    }

    // MARK: - Reader (novel)

    var novelFontSize: Double {
        get { defaults.object(forKey: "novelFontSize") as? Double ?? 18.0 }
        set { defaults.set(newValue, forKey: "novelFontSize") }
    }

    var novelTheme: String {
        get { defaults.string(forKey: "novelTheme") ?? "dark" }
        set { defaults.set(newValue, forKey: "novelTheme") }
    }

    var novelLineSpacing: Double {
        get { defaults.object(forKey: "novelLineSpacing") as? Double ?? 1.8 }
        set { defaults.set(newValue, forKey: "novelLineSpacing") }
    }

    // MARK: - Appearance

    var appTheme: String {
        get { defaults.string(forKey: "appTheme") ?? "system" }
        set { defaults.set(newValue, forKey: "appTheme") }
    }

    var libraryDisplayMode: String {
        get { defaults.string(forKey: "libraryDisplayMode") ?? "grid" }
        set { defaults.set(newValue, forKey: "libraryDisplayMode") }
    }
}
