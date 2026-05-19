import SwiftUI
import WebKit
import UIKit

// MARK: - CFBypassView

/// Full-browser sheet that lets the user complete a Cloudflare challenge for any source.
/// Once cf_clearance is detected for a domain, cookies are copied into URLSession shared
/// storage so that JSBridge SOURCE.fetch picks them up automatically on the next load.
struct CFBypassView: View {
    var initialURL: String
    var onSuccess: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var urlText:   String
    @State private var committed = false
    @State private var bypassed: [String] = []

    init(initialURL: String = "https://", onSuccess: @escaping () -> Void) {
        self.initialURL = initialURL
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
                    onBypassed: { host in
                        bypassed.append(host)
                    }
                )
            }
            .navigationTitle("Bypass Cloudflare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSuccess()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(bypassed.isEmpty)
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
        Coordinator(onBypassed: onBypassed)
    }

    private func navigate(_ wv: WKWebView) {
        let trimmed = urlText.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), url.scheme != nil else { return }
        wv.load(URLRequest(url: url))
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var onBypassed: (String) -> Void
        var lastCommit = false
        private var pollTimer: Timer?
        private var bypassed = Set<String>()

        init(onBypassed: @escaping (String) -> Void) {
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

                        // Copy all cookies for this domain into URLSession shared storage.
                        // JSBridge SOURCE.fetch uses URLSession.shared, which reads from
                        // HTTPCookieStorage.shared automatically (httpShouldHandleCookies = true).
                        for c in cookies {
                            let cd = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain
                            if cd == domain || domain.hasSuffix("." + cd) {
                                HTTPCookieStorage.shared.setCookie(c)
                            }
                        }
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
    static func autoBypass(url: URL) async -> Bool {
        let helper = AutoBypassHelper()
        return await helper.run(url: url)
    }
}

// MARK: - AutoBypassHelper

private final class AutoBypassHelper: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Bool, Never>?
    private var webView: WKWebView?
    private var pollTimer: Timer?
    private var finished = false
    private var collectedCookies: [HTTPCookie] = []
    private var timeoutTask: Task<Void, Never>?

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
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.finished else { return }
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
            for c in collectedCookies { HTTPCookieStorage.shared.setCookie(c) }
        }
        continuation?.resume(returning: success)
        continuation = nil
    }

    deinit { pollTimer?.invalidate() }
}
