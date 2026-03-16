import Foundation
import Observation

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
}
