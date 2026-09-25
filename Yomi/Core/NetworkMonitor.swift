import Foundation
import Network

// MARK: - NetworkMonitor

/// Decides whether downloads may use the current network. Reading is never gated here — only work
/// the app starts on its own or queues in bulk (manga/novel downloads, download-ahead, background
/// downloads).
///
/// "Expensive" rather than "is it Wi-Fi": `NWPath.isExpensive` is also true on a Wi-Fi hotspot shared
/// from another phone, which spends that phone's cellular plan. `isConstrained` is Low Data Mode,
/// which Apple asks apps to honour by holding back prefetching and bulk transfers.
@Observable final class NetworkMonitor {

    static let shared = NetworkMonitor()

    /// False until the first path update (milliseconds after launch), so nothing downloads on an
    /// unknown — possibly cellular — network in that window.
    private(set) var isConnected = false
    /// Cellular, or Wi-Fi from a personal hotspot.
    private(set) var isExpensive = false
    /// Low Data Mode (on either Wi-Fi or cellular).
    private(set) var isConstrained = false

    /// "Download on cellular now" from the Downloads screen. Covers what's queued right now and is
    /// withdrawn once both queues drain, so a one-off yes never becomes a permanent setting.
    private(set) var cellularAllowedForCurrentQueue = false

    /// Set when something is queued while downloads are held back, so the screen the user tapped
    /// Download on can say why nothing is moving. Detail views show it as a toast and clear it.
    var queuedNotice: String? = nil

    private let monitor = NWPathMonitor()
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private init() {
        #if DEBUG
        // The simulator always sees the Mac's network; `-yomiSimulateCellular` makes it look metered.
        let simulateCellular = ProcessInfo.processInfo.arguments.contains("-yomiSimulateCellular")
        #else
        let simulateCellular = false
        #endif
        monitor.pathUpdateHandler = { @Sendable path in
            let connected = path.status == .satisfied
            let expensive = path.isExpensive || simulateCellular
            let constrained = path.isConstrained
            Task { @MainActor in
                let monitor = NetworkMonitor.shared
                monitor.isConnected = connected
                monitor.isExpensive = expensive
                monitor.isConstrained = constrained
                monitor.resumeWaiters()
            }
        }
        monitor.start(queue: DispatchQueue(label: "yomi.network-monitor", qos: .utility))
    }

    private var isMetered: Bool { isExpensive || isConstrained }

    var downloadsAllowed: Bool {
        guard isConnected else { return false }
        return !AppSettings.shared.downloadOnlyOnWiFi || !isMetered || cellularAllowedForCurrentQueue
    }

    /// Downloads are queued but held back only by the Wi-Fi setting (not by being offline).
    var isWaitingForWiFi: Bool {
        isConnected && isMetered && !downloadsAllowed
    }

    /// Short reason for a queued download that isn't moving, or nil if it may run.
    var waitReason: String? {
        if !isConnected { return "Waiting for connection" }
        if isWaitingForWiFi { return isConstrained && !isExpensive ? "Paused — Low Data Mode" : "Waiting for Wi-Fi" }
        return nil
    }

    /// Suspends until downloads may run. Download workers call this before each item, so a switch to
    /// cellular pauses the queue between items and Wi-Fi coming back resumes it without anyone asking.
    func waitUntilDownloadsAllowed() async {
        while !downloadsAllowed {
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    /// Download managers call this on enqueue.
    func noteQueued() {
        guard let reason = waitReason else { return }
        queuedNotice = "Queued · \(reason.prefix(1).lowercased() + reason.dropFirst())"
    }

    func allowCellularForCurrentQueue() {
        cellularAllowedForCurrentQueue = true
        resumeWaiters()
    }

    /// The Wi-Fi setting changed — re-evaluate anything waiting on it.
    func settingsChanged() {
        resumeWaiters()
    }

    /// Called by the download managers when their queue empties.
    func queueDrained() {
        let mangaIdle = !DownloadManager.shared.isRunning && DownloadManager.shared.queue.isEmpty
        if mangaIdle && !NovelDownloadManager.shared.isRunning {
            cellularAllowedForCurrentQueue = false
        }
    }

    private func resumeWaiters() {
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume() }
    }
}
