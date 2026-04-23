import SwiftUI
import WebKit

// MARK: - CFBypassView

/// Full-browser sheet that lets the user complete a Cloudflare challenge for any source.
/// Once cf_clearance is detected for a domain, cookies are copied into URLSession shared
/// storage so that JSBridge SOURCE.fetch picks them up automatically on the next load.
struct CFBypassView: View {
    var onSuccess: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var urlText   = "https://"
    @State private var committed = false
    @State private var bypassed: [String] = []

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
