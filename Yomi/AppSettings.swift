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

    /// Canvas preset: "Ink" | "Midnight" | "Paper" | "Sepia" | "Automatic" (follows the device, S142).
    /// Replaces the old theme picker as the primary appearance axis.
    var canvas: String {
        didSet { defaults.set(canvas, forKey: "canvas") }
    }

    /// Color scheme derived from canvas first, legacy theme as fallback.
    var colorScheme: ColorScheme? {
        switch canvas {
        case "Ink", "Midnight": return .dark
        case "Paper", "Sepia":  return .light
        case Self.automaticCanvas: return nil   // follow the device
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

    /// 24-hour ("14:20") or 12-hour ("2:20 PM") times. nil = follow the iPhone (default since S142, Martin);
    /// a choice made before S142 is kept.
    var use24HourClock: Bool? {
        didSet { defaults.set(use24HourClock, forKey: "use24HourClock") }
    }

    /// "28 Jul" (true) or "Jul 28" (false). nil = follow the iPhone's region (default since S142).
    var dateOrderDayFirst: Bool? {
        didSet { defaults.set(dateOrderDayFirst, forKey: "dateOrderDayFirst") }
    }

    /// Palette for the current `canvas` preset. "Automatic" (S142): follows the device's light/dark
    /// setting, Paper by day and Ink by night — pass the scheme the views are drawn in. The accent
    /// "blend into surfaces" slider was removed in S142 (RESEARCH §26: chrome stays neutral).
    func canvasColors(for scheme: ColorScheme) -> YomiTokens.CanvasColors {
        guard canvas == Self.automaticCanvas else { return YomiTokens.Canvas.named(canvas) }
        return scheme == .dark ? YomiTokens.Canvas.ink : YomiTokens.Canvas.paper
    }

    /// The preset palette, Ink for Automatic. Only for code without a view's colour scheme at hand.
    var canvasColors: YomiTokens.CanvasColors {
        canvas.isEmpty || canvas == Self.automaticCanvas ? YomiTokens.Canvas.ink : YomiTokens.Canvas.named(canvas)
    }

    static let automaticCanvas = "Automatic"

    /// Legible label/icon color for content rendered on an accent-colored fill (Resume buttons,
    /// unread badges, empty-state CTAs, …). Read this instead of hardcoding `.white` — several
    /// accent presets are too bright for white text to stay readable on them.
    var accentForeground: Color {
        YomiTokens.Accent.foreground(for: accentColor, on: canvasColors.textPrimary)
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

    /// Novel reader font: a `ReaderFont.id` ("georgia", "new-york", "literata"…). Before S136 it was
    /// "Serif" | "System"; init maps those to "georgia" | "system".
    var novelFontFamily: String {
        didSet { defaults.set(novelFontFamily, forKey: "novelFontFamily") }
    }

    /// Space after each paragraph in the novel reader, in em: 0.5 | 1.0 | 1.5.
    var novelParagraphSpacing: Double {
        didSet { defaults.set(novelParagraphSpacing, forKey: "novelParagraphSpacing") }
    }

    /// Letter spacing in the novel reader: -1 tight | 0 normal | 1 loose.
    var novelLetterSpacing: Int {
        didSet { defaults.set(novelLetterSpacing, forKey: "novelLetterSpacing") }
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

    /// When true (default), the app rotates with the device (portrait + landscape, matching
    /// Info.plist's declared orientations). When false, locked to portrait only. Read by
    /// AppDelegate.application(_:supportedInterfaceOrientationsFor:) in YomiApp.swift.
    var rotationFollowDevice: Bool {
        didSet { defaults.set(rotationFollowDevice, forKey: "rotationFollowDevice") }
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

    /// Auto-update progress on every connected tracker (MAL/AniList/Shikimori/Bangumi) whenever a
    /// chapter finishes. Previously always-on with no opt-out — see CLAUDE.md Known Issues.
    var trackerAutoUpdate: Bool {
        didSet { defaults.set(trackerAutoUpdate, forKey: "trackerAutoUpdate") }
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

    // MARK: - Keiyoushi (on-device Mihon extensions, S124)

    /// A Mihon/Keiyoushi extension repository index the user pasted, e.g. Keiyoushi's `…/repo/index.pb`.
    /// Empty = no repository. Never prefilled — the user supplies it (App Store 5.2.2, see RESEARCH.md §5).
    /// Mihon extension repositories (index.pb or index.min.json links). S142: a list — it used to be one URL
    /// (`keiyoushiRepoURL`, migrated on first launch).
    var mihonRepoURLs: [String] {
        didSet { defaults.set(mihonRepoURLs, forKey: "mihonRepoURLs") }
    }

    /// Browse's "Last used" section, most recent first — `BrowseSourceKey` raw values (plugin id or Keiyoushi
    /// source id, prefixed by kind).
    var recentSourceKeys: [String] {
        didSet { defaults.set(recentSourceKeys, forKey: "recentSourceKeys") }
    }

    func noteSourceOpened(_ key: String) {
        recentSourceKeys = [key] + recentSourceKeys.filter { $0 != key }.prefix(4)
    }

    // MARK: - App Lock

    /// Require biometric/passcode authentication when app enters foreground
    var appLockEnabled: Bool {
        didSet {
            defaults.set(appLockEnabled, forKey: "appLockEnabled")
            // Don't wait for the next Library refresh to clear an unauthenticated Home Screen
            // widget — turning protection on should hide reading history immediately.
            if appLockEnabled { WidgetDataWriter.write([]) }
        }
    }

    /// Hide app content (behind a cover) in the App Switcher / during app-switch transitions
    var secureScreenEnabled: Bool {
        didSet {
            defaults.set(secureScreenEnabled, forKey: "secureScreenEnabled")
            if secureScreenEnabled { WidgetDataWriter.write([]) }
        }
    }

    // MARK: - TTS

    /// AVSpeechSynthesizer rate for novel TTS (0.1 slow – 0.5 default – 1.0 fast)
    var ttsSpeechRate: Float {
        didSet { defaults.set(ttsSpeechRate, forKey: "ttsSpeechRate") }
    }

    /// AVSpeechSynthesisVoice identifier; empty = the best installed voice for the novel's language (S143).
    var ttsVoiceId: String {
        didSet { defaults.set(ttsVoiceId, forKey: "ttsVoiceId") }
    }

    /// Listening plays over other apps' audio instead of pausing it. Off by default: only a non-mixing
    /// session gets the lock-screen / AirPods controls (Martin S143: pause by default, but make it a setting).
    var ttsMixWithOthers: Bool {
        didSet { defaults.set(ttsMixWithOthers, forKey: "ttsMixWithOthers") }
    }

    /// Highlight the sentence being read in the reader.
    var ttsHighlight: Bool {
        didSet { defaults.set(ttsHighlight, forKey: "ttsHighlight") }
    }

    /// Carry on into the next chapter when one ends.
    var ttsAutoAdvance: Bool {
        didSet { defaults.set(ttsAutoAdvance, forKey: "ttsAutoAdvance") }
    }

    // MARK: - Downloads

    /// Manga + novel downloads, download-ahead and background downloads wait for a non-metered network
    /// (not cellular, not a personal hotspot, not Low Data Mode). On by default: users shouldn't find
    /// their data plan spent by something they didn't watch happen. Reading is never gated.
    var downloadOnlyOnWiFi: Bool {
        didSet { defaults.set(downloadOnlyOnWiFi, forKey: "downloadOnlyOnWiFi") }
    }

    // MARK: - Novel reader behaviour (S133)

    /// Scrolling past the end of a chapter continues straight into the next one.
    var novelInfiniteScroll: Bool {
        didSet { defaults.set(novelInfiniteScroll, forKey: "novelInfiniteScroll") }
    }

    /// A horizontal swipe on the page opens the next (swipe left) / previous (swipe right) chapter.
    var novelSwipeChapters: Bool {
        didSet { defaults.set(novelSwipeChapters, forKey: "novelSwipeChapters") }
    }

    /// Taps needed to show/hide the reader menu: 1 or 2.
    var novelMenuTaps: Int {
        didSet { defaults.set(novelMenuTaps, forKey: "novelMenuTaps") }
    }

    /// Novel reader layout (S136, RESEARCH §25.10 #2): "scroll" | "pages".
    var novelReadingMode: String {
        didSet { defaults.set(novelReadingMode, forKey: "novelReadingMode") }
    }

    /// Pages mode: turning past a chapter's last page continues into the next chapter. Off = the chapter ends on
    /// a "Next chapter" page. Separate from `novelInfiniteScroll` (Martin's call).
    var novelPagesContinue: Bool {
        didSet { defaults.set(novelPagesContinue, forKey: "novelPagesContinue") }
    }

    // MARK: - Novel downloads

    /// How many chapters past the open one the novel reader keeps downloaded (library novels only).
    /// 0 = off. ArcReader's "Download ahead" offers 5/10/20/30.
    var novelDownloadAhead: Int {
        didSet { defaults.set(novelDownloadAhead, forKey: "novelDownloadAhead") }
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
        // A fresh install starts from the system text size (18 pt at the default size, larger when the
        // user has set larger text system-wide — RESEARCH §25.3). A saved size always wins.
        fontSize                = d.object(forKey: "fontSize")    as? Double
            ?? min(40, UIFontMetrics(forTextStyle: .body).scaledValue(for: 18).rounded())
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
            default:      canvas = Self.automaticCanvas   // fresh install follows the iPhone (Martin, S142)
            }
        }
        accentColor             = d.string(forKey: "accentColor")            ?? "#E5473A"
        use24HourClock          = d.object(forKey: "use24HourClock") as? Bool
        dateOrderDayFirst       = d.object(forKey: "dateOrderDayFirst") as? Bool
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
        switch d.string(forKey: "novelFontFamily") {
        case nil, "Serif": novelFontFamily = "georgia"   // pre-S136 "Serif" was Georgia
        case "System":     novelFontFamily = "system"
        case let id?:      novelFontFamily = id
        }
        novelParagraphSpacing   = d.object(forKey: "novelParagraphSpacing") as? Double ?? 1.0
        novelLetterSpacing      = d.object(forKey: "novelLetterSpacing") as? Int ?? 0
        novelJustifyText        = d.object(forKey: "novelJustifyText") as? Bool ?? false
        novelHorizontalPadding  = d.object(forKey: "novelHorizontalPadding") as? Int ?? 16
        hasSeenOnboarding       = d.bool(forKey: "hasSeenOnboarding")
        // Migrate from legacy single-URL key if multi-URL key is not yet stored
        if let data = d.data(forKey: "pluginCatalogURLs"),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            pluginCatalogURLs = decoded
        } else {
            // Fresh installs start with no repositories — the user adds every one by link (S140, Guideline 5.2.2).
            pluginCatalogURLs = d.string(forKey: "pluginCatalogURL").map { [$0] } ?? []
        }
        libraryColumns          = d.object(forKey: "libraryColumns") as? Int ?? 3
        rotationFollowDevice    = d.object(forKey: "rotationFollowDevice") as? Bool ?? true
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
        alternateIconName       = d.string(forKey: "alternateIconName")
        autoWebtoonFromTags     = d.object(forKey: "autoWebtoonFromTags")          as? Bool ?? true
        deleteDownloadAfterReading = d.object(forKey: "deleteDownloadAfterReading") as? Bool ?? true
        concurrentDownloads     = d.object(forKey: "concurrentDownloads")          as? Int  ?? 3
        backgroundAutoRefreshEnabled = d.object(forKey: "backgroundAutoRefreshEnabled") as? Bool ?? false
        backgroundDownloadEnabled    = d.object(forKey: "backgroundDownloadEnabled")    as? Bool ?? false
        trackerAutoUpdate       = d.object(forKey: "trackerAutoUpdate")             as? Bool ?? true
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
        if let urls = d.stringArray(forKey: "mihonRepoURLs") {
            mihonRepoURLs = urls
        } else {
            let legacy = (d.string(forKey: "keiyoushiRepoURL") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            mihonRepoURLs = legacy.isEmpty ? [] : [legacy]
        }
        recentSourceKeys         = d.stringArray(forKey: "recentSourceKeys")     ?? []
        appLockEnabled           = d.object(forKey: "appLockEnabled")            as? Bool ?? false
        secureScreenEnabled      = d.object(forKey: "secureScreenEnabled")       as? Bool ?? false
        ttsSpeechRate            = d.object(forKey: "ttsSpeechRate")            as? Float ?? 0.5
        ttsVoiceId               = d.string(forKey: "ttsVoiceId") ?? ""
        ttsMixWithOthers         = d.object(forKey: "ttsMixWithOthers")         as? Bool ?? false
        ttsHighlight             = d.object(forKey: "ttsHighlight")             as? Bool ?? true
        ttsAutoAdvance           = d.object(forKey: "ttsAutoAdvance")           as? Bool ?? true
        novelDownloadAhead       = d.object(forKey: "novelDownloadAhead")       as? Int ?? 5
        novelInfiniteScroll      = d.object(forKey: "novelInfiniteScroll")      as? Bool ?? true
        novelSwipeChapters       = d.object(forKey: "novelSwipeChapters")       as? Bool ?? true
        novelMenuTaps            = d.object(forKey: "novelMenuTaps")            as? Int ?? 1
        novelReadingMode         = d.string(forKey: "novelReadingMode") == "pages" ? "pages" : "scroll"
        novelPagesContinue       = d.object(forKey: "novelPagesContinue")       as? Bool ?? true
        downloadOnlyOnWiFi       = d.object(forKey: "downloadOnlyOnWiFi")       as? Bool ?? true
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
