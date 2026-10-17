import SwiftUI
import CryptoKit

// MARK: - Safe Mode
//
// S179 (RESEARCH §25.13 #5, ROADMAP group I): parents asked for a safe mode a child can't switch off. With Safe Mode
// on, sources their repository marks 18+ disappear everywhere (Browse, Extensions, search, Library, History,
// Updates, Continue, widget, Migrate), and so do titles tagged with an adult genre — most sites mix both, so
// "mixed" sources stay listed unless the parent hides those too. A Yomi passcode (not the iPhone's: a child knows
// that one) locks it. Sources can still serve untagged adult titles — the screen says so.

/// What Safe Mode hides, captured on the main actor so detached loads can filter with it.
nonisolated struct SafeFilter: Sendable {
    let isOn: Bool
    /// Yomi source ids (`plugin id` / `keiyoushi_<id>`) to hide.
    let hiddenSources: Set<String>

    static let off = SafeFilter(isOn: false, hiddenSources: [])

    func hidesSource(_ sourceId: String) -> Bool { isOn && hiddenSources.contains(sourceId) }

    func allows(sourceId: String, genres: [String]) -> Bool {
        guard isOn else { return true }
        return !hiddenSources.contains(sourceId) && !genres.contains(where: Self.isAdultGenre)
    }

    func allows(_ manga: Manga) -> Bool { allows(sourceId: manga.sourceId, genres: manga.genres) }
    func allows(_ novel: Novel) -> Bool { allows(sourceId: novel.sourceId, genres: novel.genres) }

    /// Genre tags sites use for sexual content. Ecchi and Mature are included: this mode is for children.
    static let adultGenres: Set<String> = [
        "hentai", "smut", "adult", "adults only", "pornographic", "porn", "erotica", "erotic", "ecchi", "mature",
        "18+", "r-18", "r18", "nsfw", "sexual violence", "lolicon", "shotacon",
    ]

    static func isAdultGenre(_ genre: String) -> Bool {
        adultGenres.contains(genre.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

enum SafeMode {
    /// The current filter. Main actor: it reads the installed extensions and the Keiyoushi index.
    static var filter: SafeFilter {
        let settings = AppSettings.shared
        guard settings.safeMode else { return .off }
        var hidden = Set<String>()
        for ext in ExtensionManager.shared.installed where ext.isNSFW { hidden.insert(ext.id) }
        let keiyoushi = KeiyoushiRepository.shared
        for ext in keiyoushi.installed.map(\.info) + keiyoushi.available where hides(ext, settings: settings) {
            for source in ext.sources { hidden.insert(KeiyoushiMapping.sourcePrefix + source.id) }
        }
        return SafeFilter(isOn: true, hiddenSources: hidden)
    }

    /// True when Safe Mode hides this one source — a lookup, cheaper than building `filter` (for views).
    static func hidesSource(_ sourceId: String) -> Bool {
        guard AppSettings.shared.safeMode else { return false }
        if KeiyoushiMapping.isKeiyoushiSourceId(sourceId) {
            let id = KeiyoushiMapping.mihonSourceId(sourceId)
            let repo = KeiyoushiRepository.shared
            guard let ext = repo.installedExtension(forSourceId: id)?.info
                    ?? repo.available.first(where: { $0.sources.contains { $0.id == id } }) else { return false }
            return hides(ext)
        }
        return ExtensionManager.shared.installed.first { $0.id == sourceId }?.isNSFW ?? false
    }

    /// True when Safe Mode hides a title with these genres (cheap — no source lookup; for browse results).
    static func hidesGenres(_ genres: [String]) -> Bool {
        AppSettings.shared.safeMode && genres.contains(where: SafeFilter.isAdultGenre)
    }

    /// True when Safe Mode hides this Mihon extension (18+, or mixed when the parent chose to hide those too).
    static func hides(_ ext: KeiyoushiExtension, settings: AppSettings = .shared) -> Bool {
        guard settings.safeMode else { return false }
        return ext.isNSFW || (settings.safeModeHidesMixed && ext.contentWarning == 2)
    }

    // MARK: Passcode

    private static let passcodeKey = "safeModePasscode"
    private static let failuresKey = "safeModePasscodeFailures"
    private static let lockedUntilKey = "safeModeLockedUntil"
    static let maxFailures = 5
    static let waitAfterFailures: TimeInterval = 60

    static var isLocked: Bool { KeychainHelper.load(for: passcodeKey) != nil }

    static func setPasscode(_ code: String) {
        KeychainHelper.save(hash(code), for: passcodeKey)
        UserDefaults.standard.removeObject(forKey: failuresKey)
    }

    static func removePasscode() { KeychainHelper.delete(for: passcodeKey) }

    /// Seconds left before another try is allowed (after `maxFailures` wrong codes in a row).
    static var waitRemaining: TimeInterval {
        let until = UserDefaults.standard.double(forKey: lockedUntilKey)
        return max(0, until - Date().timeIntervalSince1970)
    }

    /// Checks a code. Wrong codes count; `maxFailures` in a row make the next try wait a minute.
    static func check(_ code: String) -> Bool {
        guard waitRemaining == 0, let stored = KeychainHelper.load(for: passcodeKey) else { return false }
        let defaults = UserDefaults.standard
        if hash(code) == stored {
            defaults.removeObject(forKey: failuresKey)
            return true
        }
        let failures = defaults.integer(forKey: failuresKey) + 1
        if failures >= maxFailures {
            defaults.set(Date().timeIntervalSince1970 + waitAfterFailures, forKey: lockedUntilKey)
            defaults.removeObject(forKey: failuresKey)
        } else {
            defaults.set(failures, forKey: failuresKey)
        }
        return false
    }

    /// The keychain outlives a deleted app; a fresh install starts unlocked (UserDefaults is empty again, so Safe
    /// Mode itself is off — a passcode left behind would lock a setting nobody can see).
    static func clearStalePasscode() {
        if UserDefaults.standard.object(forKey: "safeMode") == nil { removePasscode() }
    }

    private static func hash(_ code: String) -> String {
        SHA256.hash(data: Data("yomi-safe-mode:\(code)".utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Detail screen cover

/// Covers a title's page when Safe Mode hides it — titles from mixed sources often only show their genres once the
/// details load, so the page itself is the last place to catch them.
struct SafeModeCover: ViewModifier {
    let sourceId: String
    let genres: [String]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.yomiCanvas) private var canvas

    private var isHidden: Bool {
        SafeMode.hidesGenres(genres) || SafeMode.hidesSource(sourceId)
    }

    func body(content: Content) -> some View {
        content.overlay {
            if isHidden {
                VStack(spacing: 14) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 34))
                        .foregroundStyle(canvas.textSecondary)
                    Text("Hidden by Safe Mode")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(canvas.textPrimary)
                    Text("This title is marked for adults.")
                        .font(.subheadline)
                        .foregroundStyle(canvas.textSecondary)
                    Button("Go Back") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 6)
                }
                .multilineTextAlignment(.center)
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(canvas.bg.ignoresSafeArea())
                .accessibilityIdentifier("safeModeCover")
            }
        }
    }
}

extension View {
    func safeModeCover(sourceId: String, genres: [String]) -> some View {
        modifier(SafeModeCover(sourceId: sourceId, genres: genres))
    }
}
