import SwiftUI
import WebKit
import UIKit

// MARK: - CFBypassView

/// Full-browser sheet that lets the user complete a Cloudflare challenge for any source.
/// Once cf_clearance is detected for a domain, cookies are copied into the source plugin's own jar (S192 — before,
/// into the store every plugin read) and into the shared store, which covers, reader pages and Keiyoushi read.
struct CFBypassView: View {
    var initialURL: String
    /// The JS plugin this page is for; nil for Keiyoushi sources (they read the shared store through the bridge).
    var cookieJar: PluginCookieJar? = nil
    /// Website mode (L3b, S171): a source's site opened from its extension's details page, like Mihon's WebView — same
    /// cookie store, so a Cloudflare check or a login done here also reaches the plugin. Done is always available.
    var isWebsite = false
    var onSuccess: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var urlText:   String
    @State private var committed = false
    @State private var bypassed: [String] = []

    init(initialURL: String = "https://", isWebsite: Bool = false, cookieJar: PluginCookieJar? = nil,
         onSuccess: @escaping () -> Void) {
        self.initialURL = initialURL
        self.isWebsite  = isWebsite
        self.cookieJar  = cookieJar
        self.onSuccess  = onSuccess
        _urlText = State(initialValue: initialURL)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                urlBar
                Divider()
                if !bypassed.isEmpty {
                    successBanner
                    Divider()
                }
                CFWebViewRepresentable(
                    urlText:   $urlText,
                    committed: $committed,
                    cookieJar: cookieJar,
                    onBypassed: { host in
                        bypassed.append(host)
                    }
                )
            }
            .navigationTitle(isWebsite ? (URL(string: initialURL)?.host() ?? "Website") : "Bypass Cloudflare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Task {
                            // Website mode: a login has no cf_clearance to wait for — hand the plugin this site's cookies.
                            if isWebsite { await CFCookieCopy.copySiteCookies(of: initialURL, to: cookieJar) }
                            onSuccess()
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(bypassed.isEmpty && !isWebsite)
                }
            }
        }
    }

    // MARK: - URL bar

    private var urlBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("https://", text: $urlText)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { committed.toggle() }
            Button {
                committed.toggle()
            } label: {
                Text("Go")
                    .font(.subheadline)
                    .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Success banner

    private var successBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Cloudflare bypassed")
                    .font(.subheadline).fontWeight(.medium)
                Text(bypassed.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.green.opacity(0.08))
    }
}

// MARK: - CFWebViewRepresentable

private struct CFWebViewRepresentable: UIViewRepresentable {
    @Binding var urlText:   String
    @Binding var committed: Bool
    var cookieJar: PluginCookieJar?
    var onBypassed: (String) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let wv = WKWebView()
        wv.customUserAgent = CFBypassConstants.userAgent
        wv.navigationDelegate = context.coordinator
        context.coordinator.webView = wv
        navigate(wv)
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        guard context.coordinator.lastCommit != committed else { return }
        context.coordinator.lastCommit = committed
        navigate(wv)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(cookieJar: cookieJar, onBypassed: onBypassed)
    }

    private func navigate(_ wv: WKWebView) {
        let trimmed = urlText.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), url.scheme != nil else { return }
        wv.load(URLRequest(url: url))
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        let cookieJar: PluginCookieJar?
        var onBypassed: (String) -> Void
        var lastCommit = false
        private var pollTimer: Timer?
        private var bypassed = Set<String>()

        init(cookieJar: PluginCookieJar?, onBypassed: @escaping (String) -> Void) {
            self.cookieJar = cookieJar
            self.onBypassed = onBypassed
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            startPolling(webView: webView)
        }

        // Start (or restart) polling for cf_clearance cookies after every page load.
        private func startPolling(webView: WKWebView) {
            pollTimer?.invalidate()
            var ticks = 0
            pollTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self, weak webView] t in
                guard let self, let webView else { t.invalidate(); return }
                ticks += 1
                if ticks > 75 { t.invalidate(); return } // 60 s safety cap

                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                    guard let self else { return }
                    for cookie in cookies where cookie.name == "cf_clearance" {
                        let raw    = cookie.domain
                        let domain = raw.hasPrefix(".") ? String(raw.dropFirst()) : raw
                        guard !self.bypassed.contains(domain) else { continue }
                        self.bypassed.insert(domain)

                        // Copy all cookies for this domain to the plugin's jar and the shared store.
                        CFCookieCopy.store(CFCookieCopy.matching(cookies, host: domain), in: self.cookieJar)
                        DispatchQueue.main.async { self.onBypassed(domain) }
                    }
                }
            }
        }

        deinit { pollTimer?.invalidate() }
    }
}

// MARK: - CFBypassManager

/// Shared constants for the CF bypass system.
enum CFBypassConstants {
    /// User-Agent used by both JSBridge (SOURCE._fetchSync) and the bypass WKWebView.
    /// Cloudflare binds cf_clearance to the UA that solved the challenge — they must match.
    nonisolated static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
}

enum CFBypassManager {
    /// Loads url in an off-screen full-size WKWebView, polls for cf_clearance for up to 30 s.
    /// Copies all domain cookies to HTTPCookieStorage.shared on success.
    /// Uses CFBypassConstants.userAgent so the clearance cookie is valid for URLSession requests too.
    @MainActor
    static func autoBypass(url: URL, cookieJar: PluginCookieJar?) async -> Bool {
        let helper = AutoBypassHelper(cookieJar: cookieJar)
        return await helper.run(url: url)
    }
}

// MARK: - AutoBypassHelper

private final class AutoBypassHelper: NSObject, WKNavigationDelegate {
    private let cookieJar: PluginCookieJar?
    private var url: URL?
    private var continuation: CheckedContinuation<Bool, Never>?
    private var webView: WKWebView?
    private var pollTimer: Timer?
    private var finished = false
    private var collectedCookies: [HTTPCookie] = []
    private var timeoutTask: Task<Void, Never>?

    init(cookieJar: PluginCookieJar?) { self.cookieJar = cookieJar }

    @MainActor
    func run(url: URL) async -> Bool {
        let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        // keyWindow available on UIWindowScene since iOS 15.
        guard let window = windowScene?.keyWindow ?? windowScene?.windows.first else { return false }

        // Full-size off-screen — Cloudflare Turnstile needs a real viewport to run its JS.
        // Use windowScene.screen to avoid deprecated UIScreen.main (iOS 26+).
        let screenBounds = windowScene?.screen.bounds ?? window.bounds
        let frame = CGRect(x: 0, y: screenBounds.height + 1,
                           width: screenBounds.width, height: screenBounds.height)
        let wv = WKWebView(frame: frame)
        // UA must match CFBypassConstants.userAgent — cf_clearance is bound to the UA that solved the challenge.
        wv.customUserAgent = CFBypassConstants.userAgent
        wv.navigationDelegate = self
        webView = wv
        self.url = url
        window.addSubview(wv)
        wv.load(URLRequest(url: url))

        return await withCheckedContinuation { [weak self] cont in
            self?.continuation = cont
            self?.timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                DispatchQueue.main.async { self?.finish(success: false) }
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        startPolling(webView: webView)
    }

    // Also restart polling on server redirects (CF sometimes redirects before didFinish).
    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        startPolling(webView: webView)
    }

    private func startPolling(webView: WKWebView) {
        pollTimer?.invalidate()
        var ticks = 0
        // Poll every 0.5 s for up to 30 s (60 ticks), matching the timeout task.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self, weak webView] t in
            guard let self, let webView, !self.finished else { t.invalidate(); return }
            ticks += 1
            if ticks > 60 { t.invalidate(); return }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                DispatchQueue.main.async {
                    guard !self.finished else { return }
                    guard cookies.contains(where: { $0.name == "cf_clearance" }) else { return }
                    self.collectedCookies = cookies
                    t.invalidate()
                    self.finish(success: true)
                }
            }
        }
    }

    private func finish(success: Bool) {
        guard !finished else { return }
        finished = true
        pollTimer?.invalidate()
        timeoutTask?.cancel()
        webView?.removeFromSuperview()
        webView = nil
        if success {
            // Only the challenged site's cookies — the off-screen view shares WebKit's store with every other page.
            CFCookieCopy.store(CFCookieCopy.matching(collectedCookies, host: url?.host() ?? ""), in: cookieJar)
        }
        continuation?.resume(returning: success)
        continuation = nil
    }

    deinit { pollTimer?.invalidate() }
}

// MARK: - CFCookieCopy

/// Moving WebKit cookies to where requests read them (S192).
enum CFCookieCopy {
    nonisolated static func matching(_ cookies: [HTTPCookie], host: String) -> [HTTPCookie] {
        PluginCookieJar.matching(cookies, host: host)
    }

    /// The plugin's jar (when there is one) and the shared store — covers, reader pages and Keiyoushi read that one.
    nonisolated static func store(_ cookies: [HTTPCookie], in jar: PluginCookieJar?) {
        for c in cookies { HTTPCookieStorage.shared.setCookie(c) }
        jar?.importCookies(cookies)
    }

    /// Website mode's Done: everything WebKit holds for that site.
    @MainActor
    static func copySiteCookies(of urlString: String, to jar: PluginCookieJar?) async {
        guard let host = URL(string: urlString)?.host() else { return }
        let all = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        store(matching(all, host: host), in: jar)
    }
}
