import SwiftUI
import SafariServices

// MARK: - MALView

struct MALView: View {

    // MARK: - State

    @State private var malService = MALService.shared
    @State private var showSafari = false
    @State private var authURL: URL? = nil

    // MARK: - Body

    var body: some View {
        List {
            if malService.isLoggedIn {
                accountSection
                trackingSection
            } else {
                loginSection
            }
            errorSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("MyAnimeList")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSafari) {
            if let url = authURL {
                SafariView(url: url)
            }
        }
        .onOpenURL { url in
            guard url.scheme == "yomi" else { return }
            Task { await malService.handleCallback(url: url) }
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        Section("Account") {
            LabeledContent("Logged in as", value: malService.username ?? "—")
            Button("Disconnect", role: .destructive) {
                malService.logout()
            }
        }
    }

    // MARK: - Tracking Section

    private var trackingSection: some View {
        Section("Tracking") {
            Text("Chapters are automatically tracked when you finish reading them.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Login Section

    private var loginSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Connect your MyAnimeList account to automatically track chapters you read.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Login with MyAnimeList") {
                    authURL = malService.authorizationURL()
                    showSafari = true
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Error Section

    @ViewBuilder
    private var errorSection: some View {
        if let error = malService.errorMessage {
            Section {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }
}

// MARK: - SafariView

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MALView()
    }
}
