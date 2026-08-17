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

    /// Canvas preset: "Ink" | "Midnight" | "Paper" | "Sepia" | "" (follow device).
    /// Replaces the old theme picker as the primary appearance axis.
    var canvas: String {
        didSet { defaults.set(canvas, forKey: "canvas") }
    }

    /// Color scheme derived from canvas first, legacy theme as fallback.
    var colorScheme: ColorScheme? {
        switch canvas {
        case "Ink", "Midnight": return .dark
        case "Paper", "Sepia":  return .light
        default:
            switch theme {
            case "Light": return .light
            case "Dark":  return .dark
            default:      return nil
            }
        }
    }

    var accentColor: String {
        didSet { defaults.set(accentColor, forKey: "accentColor") }
    }

    /// 24-hour clock ("14:20") vs 12-hour ("2:20 PM") for History's today-timestamp.
    var use24HourClock: Bool {
        didSet { defaults.set(use24HourClock, forKey: "use24HourClock") }
    }

    /// Day-before-month date order ("28 JUL") vs month-before-day ("JUL 28") for History's
    /// older-than-a-week timestamp.
    var dateOrderDayFirst: Bool {
        didSet { defaults.set(dateOrderDayFirst, forKey: "dateOrderDayFirst") }
    }

    /// How strongly the accent color is blended into canvas surfaces (0 = off, 1 = fully accent).
    /// Only `bg`/`surface1`/`surface2` shift — text/hairline stay put so legibility isn't a moving
    /// target. Default 0 preserves the exact existing look for every current user.
    var colorBlendLevel: Double {
        didSet { defaults.set(colorBlendLevel, forKey: "colorBlendLevel") }
    }

    /// Resolved canvas palette (bg/surfaces/text) for the current `canvas` preset.
    /// Single source of truth — read this instead of re-deriving `YomiTokens.Canvas.named(...)`.
    var canvasColors: YomiTokens.CanvasColors {
        canvas.isEmpty ? YomiTokens.Canvas.ink : YomiTokens.Canvas.named(canvas)
    }

    /// `canvasColors` with `bg`/`surface1`/`surface2` blended toward `accentColor` by
    /// `colorBlendLevel`. This is what should actually be threaded through the app (`\.yomiCanvas`,
    /// Appearance Studio's preview) — `canvasColors` itself stays the pure, unblended preset.
    var blendedCanvasColors: YomiTokens.CanvasColors {
        guard colorBlendLevel > 0 else { return canvasColors }
        let base = canvasColors
        let accent = Color(hex: accentColor)
        return YomiTokens.CanvasColors(
            name:          base.name,
            bg:            base.bg.mix(with: accent, amount: colorBlendLevel),
            surface1:      base.surface1.mix(with: accent, amount: colorBlendLevel),
            surface2:      base.surface2.mix(with: accent, amount: colorBlendLevel),
            textPrimary:   base.textPrimary,
            textSecondary: base.textSecondary,
            hairline:      base.hairline
        )
    }

    /// Legible label/icon color for content rendered on an accent-colored fill (Resume buttons,
    /// unread badges, empty-state CTAs, …). Read this instead of hardcoding `.white` — several
    /// accent presets are too bright for white text to stay readable on them.
    var accentForeground: Color {
        YomiTokens.Accent.foreground(for: accentColor, on: canvasColors.textPrimary)
    }

    var useSystemFont: Bool {
        didSet { defaults.set(useSystemFont, forKey: "useSystemFont") }
    }

    // MARK: - Content

    var showNSFW: Bool {
        didSet { defaults.set(showNSFW, forKey: "showNSFW") }
    }

    // MARK: - Backup

    var iCloudAutoBackup: Bool {
        didSet { defaults.set(iCloudAutoBackup, forKey: "iCloudAutoBackup") }
    }

    // MARK: - CloudKit sync (S102 — live cross-device sync, distinct from the iCloud backup above)

    var cloudSyncEnabled: Bool {
        didSet {
            defaults.set(cloudSyncEnabled, forKey: "cloudSyncEnabled")
            if cloudSyncEnabled {
                Task { await CloudSyncManager.shared.enable() }
            } else {
                CloudSyncManager.shared.disable()
            }
        }
    }

    // MARK: - Reading reminders

    var readingReminderEnabled: Bool {
        didSet { defaults.set(readingReminderEnabled, forKey: "readingReminderEnabled") }
    }

    var readingReminderDays: Int {
        didSet { defaults.set(readingReminderDays, forKey: "readingReminderDays") }
    }

    // MARK: - App Store review

    var chaptersReadCount: Int {
        didSet { defaults.set(chaptersReadCount, forKey: "chaptersReadCount") }
    }

    /// Call after each chapter is marked read. Returns true when a review prompt threshold is hit.
    func recordChapterRead() -> Bool {
        chaptersReadCount += 1
        return [10, 50, 200].contains(chaptersReadCount)
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

    /// Show item count on Library category tabs
    var showCategoryItemCounts: Bool {
        didSet { defaults.set(showCategoryItemCounts, forKey: "showCategoryItemCounts") }
    }

    /// Category a newly-added title is auto-assigned to (nil = none, leave unassigned)
    var defaultCategoryId: String? {
        didSet { defaults.set(defaultCategoryId, forKey: "defaultCategoryId") }
    }

    /// Which tab the app opens to on launch. Matches ContentView's Tab(value:) tags
    /// (0 Library, 1 Browse, 2 History, 3 Updates, 4 More).
    var defaultTab: Int {
        didSet { defaults.set(defaultTab, forKey: "defaultTab") }
    }

    /// Bottom tab bar order, as `YomiTabID` raw values. Always contains all 5 ids — hiding a tab
    /// only removes it from `hiddenTabIDs`, never from this list, so a re-shown tab keeps its
    /// last position. iPhone has no built-in tab-customization UI (only the sidebar-only system
    /// affordance, which never renders in compact width) — see CustomizeTabsView.
    var tabOrder: [String] {
        didSet { defaults.set(tabOrder, forKey: "tabOrder") }
    }

    /// Ids hidden from the tab bar. Never contains "more" — it's the only way back into this
    /// settings screen, so it can't be hidden.
    var hiddenTabIDs: [String] {
        didSet { defaults.set(hiddenTabIDs, forKey: "hiddenTabIDs") }
    }

    /// SOURCE.fetch request timeout, seconds. Mirrored into jsBridgeRequestTimeout (a
    /// nonisolated(unsafe) module var) since JSBridge reads it from Task.detached, where
    /// touching AppSettings.shared directly is unsafe.
    var requestTimeout: Double {
        didSet {
            defaults.set(requestTimeout, forKey: "requestTimeout")
            jsBridgeRequestTimeout = requestTimeout
        }
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

    // MARK: - Background tasks

    /// Periodically check the library for new chapters in the background (BGAppRefreshTask).
    /// iOS decides actual timing/frequency — this only controls whether one gets scheduled at all.
    var backgroundAutoRefreshEnabled: Bool {
        didSet { defaults.set(backgroundAutoRefreshEnabled, forKey: "backgroundAutoRefreshEnabled") }
    }

    /// Auto-download newly-discovered manga chapters found during a background refresh.
    /// No effect while `backgroundAutoRefreshEnabled` is off — nothing runs to find new chapters.
    /// Novels have no download feature at all (not just in the background), so this is manga-only.
    var backgroundDownloadEnabled: Bool {
        didSet { defaults.set(backgroundDownloadEnabled, forKey: "backgroundDownloadEnabled") }
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

    /// Manga reader page layout: "single" / "double" (spreads) / "automatic" (spreads in landscape)
    var pageLayout: String {
        didSet { defaults.set(pageLayout, forKey: "pageLayout") }
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

    /// Hide app content (behind a cover) in the App Switcher / during app-switch transitions
    var secureScreenEnabled: Bool {
        didSet { defaults.set(secureScreenEnabled, forKey: "secureScreenEnabled") }
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

    /// Optional Basic-Auth password for the OPDS server. Stored in Keychain, not UserDefaults
    /// (matches the MAL-token precedent) — the stored property itself only exists so @Observable
    /// can track it; the didSet writes through to Keychain instead of `defaults`.
    var opdsPassword: String {
        didSet { KeychainHelper.save(opdsPassword, for: "opdsPassword") }
    }

    // MARK: - Init

    private init() {
        let d = UserDefaults.standard
        readerMode              = d.string(forKey: "readerMode")             ?? "Manga (RTL)"
        fontSize                = d.object(forKey: "fontSize")    as? Double ?? 18.0
        lineSpacing             = d.object(forKey: "lineSpacing") as? Double ?? 1.6
        theme                   = d.string(forKey: "theme")                  ?? "System"
        // canvas: migrate from legacy theme + pureBlack on first launch.
        if let saved = d.string(forKey: "canvas"), !saved.isEmpty {
            canvas = saved
        } else {
            let savedTheme     = d.string(forKey: "theme")         ?? "System"
            let savedPureBlack = d.object(forKey: "pureBlack") as? Bool ?? false
            switch savedTheme {
            case "Dark":  canvas = savedPureBlack ? "Midnight" : "Ink"
            case "Light": canvas = "Paper"
            default:      canvas = "Ink"   // true fresh install — documented design default
            }
        }
        accentColor             = d.string(forKey: "accentColor")            ?? "#E5473A"
        colorBlendLevel         = d.object(forKey: "colorBlendLevel") as? Double ?? 0.0
        use24HourClock          = d.object(forKey: "use24HourClock") as? Bool ?? true
        dateOrderDayFirst       = d.object(forKey: "dateOrderDayFirst") as? Bool ?? false
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
        showCategoryItemCounts  = d.object(forKey: "showCategoryItemCounts") as? Bool ?? true
        defaultCategoryId       = d.string(forKey: "defaultCategoryId")
        defaultTab              = d.object(forKey: "defaultTab") as? Int ?? 0
        // tabOrder: always includes every known tab id, unknown/stale, and missing ids healed
        // (a saved order can only go stale if a future app version adds/removes a tab).
        let knownTabIDs = YomiTabID.allCases.map(\.rawValue)
        let savedOrder = (d.stringArray(forKey: "tabOrder") ?? []).filter { knownTabIDs.contains($0) }
        let missingFromSaved = knownTabIDs.filter { !savedOrder.contains($0) }
        tabOrder = savedOrder + missingFromSaved
        hiddenTabIDs = (d.stringArray(forKey: "hiddenTabIDs") ?? []).filter { $0 != YomiTabID.more.rawValue }
        requestTimeout          = d.object(forKey: "requestTimeout") as? Double ?? 30
        jsBridgeRequestTimeout  = d.object(forKey: "requestTimeout") as? Double ?? 30
        pureBlack               = d.object(forKey: "pureBlack")      as? Bool ?? false
        alternateIconName       = d.string(forKey: "alternateIconName")
        autoWebtoonFromTags     = d.object(forKey: "autoWebtoonFromTags")          as? Bool ?? true
        deleteDownloadAfterReading = d.object(forKey: "deleteDownloadAfterReading") as? Bool ?? true
        concurrentDownloads     = d.object(forKey: "concurrentDownloads")          as? Int  ?? 3
        backgroundAutoRefreshEnabled = d.object(forKey: "backgroundAutoRefreshEnabled") as? Bool ?? false
        backgroundDownloadEnabled    = d.object(forKey: "backgroundDownloadEnabled")    as? Bool ?? false
        skipUpdateWithUnread    = d.object(forKey: "skipUpdateWithUnread")         as? Bool ?? false
        skipUpdateNotStarted    = d.object(forKey: "skipUpdateNotStarted")         as? Bool ?? false
        skipUpdateCompleted     = d.object(forKey: "skipUpdateCompleted")          as? Bool ?? false
        excludedCategoryIds     = d.stringArray(forKey: "excludedCategoryIds")     ?? []
        autoScrollSpeed          = d.object(forKey: "autoScrollSpeed")          as? Double ?? 3.0
        webtoonHorizontalPadding = d.object(forKey: "webtoonHorizontalPadding") as? Int    ?? 0
        tapZoneLayout            = d.string(forKey: "tapZoneLayout")             ?? "default"
        pageLayout               = d.string(forKey: "pageLayout")                ?? "single"
        libraryDisplayMode       = d.string(forKey: "libraryDisplayMode")        ?? "grid"
        suwayomiURL              = d.string(forKey: "suwayomiURL")               ?? ""
        appLockEnabled           = d.object(forKey: "appLockEnabled")            as? Bool ?? false
        secureScreenEnabled      = d.object(forKey: "secureScreenEnabled")       as? Bool ?? false
        ttsSpeechRate            = d.object(forKey: "ttsSpeechRate")            as? Float ?? 0.5
        opdsURL                  = d.string(forKey: "opdsURL")                  ?? ""
        opdsUsername             = d.string(forKey: "opdsUsername")             ?? ""
        // opdsPassword: migrate any legacy UserDefaults value to Keychain, then load from Keychain.
        if let legacy = d.string(forKey: "opdsPassword"), !legacy.isEmpty {
            KeychainHelper.save(legacy, for: "opdsPassword")
            d.removeObject(forKey: "opdsPassword")
        }
        opdsPassword             = KeychainHelper.load(for: "opdsPassword") ?? ""
        iCloudAutoBackup         = d.object(forKey: "iCloudAutoBackup")        as? Bool ?? true
        cloudSyncEnabled         = d.object(forKey: "cloudSyncEnabled")        as? Bool ?? false
        readingReminderEnabled   = d.object(forKey: "readingReminderEnabled") as? Bool ?? false
        readingReminderDays      = d.object(forKey: "readingReminderDays")    as? Int  ?? 2
        chaptersReadCount        = d.object(forKey: "chaptersReadCount")      as? Int  ?? 0
    }
}
