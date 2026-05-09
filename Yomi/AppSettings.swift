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

    var sendUpdateNotifications: Bool {
        didSet { defaults.set(sendUpdateNotifications, forKey: "sendUpdateNotifications") }
    }

    // MARK: - Novel reader

    /// Legacy — kept so existing data is not lost on upgrade
    var novelSepia: Bool {
        didSet { defaults.set(novelSepia, forKey: "novelSepia") }
    }

    /// Color theme for the novel reader: "Light" | "Sepia" | "Warm" | "Dark" | "AMOLED"
    var novelTheme: String {
        didSet { defaults.set(novelTheme, forKey: "novelTheme") }
    }

    /// Font family for the novel reader: "System" | "Serif"
    var novelFontFamily: String {
        didSet { defaults.set(novelFontFamily, forKey: "novelFontFamily") }
    }

    /// Justify paragraph text in the novel reader
    var novelJustifyText: Bool {
        didSet { defaults.set(novelJustifyText, forKey: "novelJustifyText") }
    }

    /// Horizontal padding (points) for the novel reader body: 8 | 16 | 24
    var novelHorizontalPadding: Int {
        didSet { defaults.set(novelHorizontalPadding, forKey: "novelHorizontalPadding") }
    }

    // MARK: - Onboarding

    var hasSeenOnboarding: Bool {
        didSet { defaults.set(hasSeenOnboarding, forKey: "hasSeenOnboarding") }
    }

    // MARK: - Plugins

    var pluginCatalogURLs: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(pluginCatalogURLs) {
                defaults.set(data, forKey: "pluginCatalogURLs")
            }
        }
    }

    // MARK: - Library display

    /// Number of columns in library grid (portrait)
    var libraryColumns: Int {
        didSet { defaults.set(libraryColumns, forKey: "libraryColumns") }
    }

    /// Show unread count badge on manga covers
    var showUnreadBadge: Bool {
        didSet { defaults.set(showUnreadBadge, forKey: "showUnreadBadge") }
    }

    // MARK: - Reader behaviour

    /// Keep screen on while reading
    var keepScreenOn: Bool {
        didSet { defaults.set(keepScreenOn, forKey: "keepScreenOn") }
    }

    /// When on: reading progress and chapter read-state are not saved
    var isIncognito: Bool {
        didSet { defaults.set(isIncognito, forKey: "isIncognito") }
    }

    /// Pure black OLED mode — forces #000000 backgrounds in dark mode
    var pureBlack: Bool {
        didSet { defaults.set(pureBlack, forKey: "pureBlack") }
    }

    /// Alternate icon name (nil = default icon). Must match CFBundleAlternateIcons key in Info.
    /// Set via UIApplication.setAlternateIconName on the main thread.
    var alternateIconName: String? {
        didSet { defaults.set(alternateIconName, forKey: "alternateIconName") }
    }

    // MARK: - Downloads

    /// Auto-switch to Webtoon mode when manga tags include manhwa/manhua/long strip
    var autoWebtoonFromTags: Bool {
        didSet { defaults.set(autoWebtoonFromTags, forKey: "autoWebtoonFromTags") }
    }

    /// Delete downloaded chapter files automatically after finishing reading
    var deleteDownloadAfterReading: Bool {
        didSet { defaults.set(deleteDownloadAfterReading, forKey: "deleteDownloadAfterReading") }
    }

    /// Max concurrent page downloads per chapter (1–5)
    var concurrentDownloads: Int {
        didSet { defaults.set(concurrentDownloads, forKey: "concurrentDownloads") }
    }

    // MARK: - Smart updates

    /// Skip update check for manga that has unread chapters
    var skipUpdateWithUnread: Bool {
        didSet { defaults.set(skipUpdateWithUnread, forKey: "skipUpdateWithUnread") }
    }

    /// Skip update check for manga not yet started (never opened)
    var skipUpdateNotStarted: Bool {
        didSet { defaults.set(skipUpdateNotStarted, forKey: "skipUpdateNotStarted") }
    }

    /// Skip update check for completed manga
    var skipUpdateCompleted: Bool {
        didSet { defaults.set(skipUpdateCompleted, forKey: "skipUpdateCompleted") }
    }

    /// Category IDs excluded from update checks
    var excludedCategoryIds: [String] {
        didSet { defaults.set(excludedCategoryIds, forKey: "excludedCategoryIds") }
    }

    // MARK: - Webtoon reader

    /// Auto-scroll interval in seconds (1–10)
    var autoScrollSpeed: Double {
        didSet { defaults.set(autoScrollSpeed, forKey: "autoScrollSpeed") }
    }

    /// Horizontal padding (points) applied to each image in Webtoon mode
    var webtoonHorizontalPadding: Int {
        didSet { defaults.set(webtoonHorizontalPadding, forKey: "webtoonHorizontalPadding") }
    }

    // MARK: - Tap zones

    /// Tap zone layout for paged reader: "default" | "sides" | "disabled"
    var tapZoneLayout: String {
        didSet { defaults.set(tapZoneLayout, forKey: "tapZoneLayout") }
    }

    // MARK: - Library display mode

    /// Library display mode: "grid" | "list"
    var libraryDisplayMode: String {
        didSet { defaults.set(libraryDisplayMode, forKey: "libraryDisplayMode") }
    }

    // MARK: - Suwayomi

    /// Suwayomi server base URL, e.g. "http://192.168.1.100:4567". Empty = disabled.
    var suwayomiURL: String {
        didSet { defaults.set(suwayomiURL, forKey: "suwayomiURL") }
    }

    // MARK: - App Lock

    /// Require biometric/passcode authentication when app enters foreground
    var appLockEnabled: Bool {
        didSet { defaults.set(appLockEnabled, forKey: "appLockEnabled") }
    }

    // MARK: - TTS

    /// AVSpeechSynthesizer rate for novel TTS (0.1 slow – 0.5 default – 1.0 fast)
    var ttsSpeechRate: Float {
        didSet { defaults.set(ttsSpeechRate, forKey: "ttsSpeechRate") }
    }

    // MARK: - OPDS

    /// OPDS catalog root URL, e.g. "http://192.168.1.x:5000/opds/v1.2/catalog". Empty = disabled.
    var opdsURL: String {
        didSet { defaults.set(opdsURL, forKey: "opdsURL") }
    }

    /// Optional Basic-Auth username for the OPDS server
    var opdsUsername: String {
        didSet { defaults.set(opdsUsername, forKey: "opdsUsername") }
    }

    /// Optional Basic-Auth password for the OPDS server
    var opdsPassword: String {
        didSet { defaults.set(opdsPassword, forKey: "opdsPassword") }
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
        sendUpdateNotifications = d.object(forKey: "sendUpdateNotifications") as? Bool ?? true
        novelSepia              = d.bool(forKey: "novelSepia")
        // novelTheme: migrate from legacy novelSepia + global theme
        if let saved = d.string(forKey: "novelTheme") {
            novelTheme = saved
        } else if d.bool(forKey: "novelSepia") {
            novelTheme = "Sepia"
        } else if (d.string(forKey: "theme") ?? "System") == "Dark" {
            novelTheme = "Dark"
        } else {
            novelTheme = "Light"
        }
        novelFontFamily         = d.string(forKey: "novelFontFamily")              ?? "Serif"
        novelJustifyText        = d.object(forKey: "novelJustifyText") as? Bool ?? false
        novelHorizontalPadding  = d.object(forKey: "novelHorizontalPadding") as? Int ?? 16
        hasSeenOnboarding       = d.bool(forKey: "hasSeenOnboarding")
        // Migrate from legacy single-URL key if multi-URL key is not yet stored
        if let data = d.data(forKey: "pluginCatalogURLs"),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            pluginCatalogURLs = decoded
        } else {
            let legacy = d.string(forKey: "pluginCatalogURL") ?? "https://yomi-plugins.web.app/index.json"
            pluginCatalogURLs = [legacy]
        }
        libraryColumns          = d.object(forKey: "libraryColumns") as? Int ?? 3
        keepScreenOn            = d.object(forKey: "keepScreenOn")   as? Bool ?? true
        isIncognito             = d.bool(forKey: "isIncognito")
        showUnreadBadge         = d.object(forKey: "showUnreadBadge") as? Bool ?? true
        pureBlack               = d.object(forKey: "pureBlack")      as? Bool ?? false
        alternateIconName       = d.string(forKey: "alternateIconName")
        autoWebtoonFromTags     = d.object(forKey: "autoWebtoonFromTags")          as? Bool ?? true
        deleteDownloadAfterReading = d.object(forKey: "deleteDownloadAfterReading") as? Bool ?? true
        concurrentDownloads     = d.object(forKey: "concurrentDownloads")          as? Int  ?? 3
        skipUpdateWithUnread    = d.object(forKey: "skipUpdateWithUnread")         as? Bool ?? false
        skipUpdateNotStarted    = d.object(forKey: "skipUpdateNotStarted")         as? Bool ?? false
        skipUpdateCompleted     = d.object(forKey: "skipUpdateCompleted")          as? Bool ?? false
        excludedCategoryIds     = d.stringArray(forKey: "excludedCategoryIds")     ?? []
        autoScrollSpeed          = d.object(forKey: "autoScrollSpeed")          as? Double ?? 3.0
        webtoonHorizontalPadding = d.object(forKey: "webtoonHorizontalPadding") as? Int    ?? 0
        tapZoneLayout            = d.string(forKey: "tapZoneLayout")             ?? "default"
        libraryDisplayMode       = d.string(forKey: "libraryDisplayMode")        ?? "grid"
        suwayomiURL              = d.string(forKey: "suwayomiURL")               ?? ""
        appLockEnabled           = d.object(forKey: "appLockEnabled")            as? Bool ?? false
        ttsSpeechRate            = d.object(forKey: "ttsSpeechRate")            as? Float ?? 0.5
        opdsURL                  = d.string(forKey: "opdsURL")                  ?? ""
        opdsUsername             = d.string(forKey: "opdsUsername")             ?? ""
        opdsPassword             = d.string(forKey: "opdsPassword")             ?? ""
    }
}
