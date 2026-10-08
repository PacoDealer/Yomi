import SwiftUI
import SafariServices

// MARK: - BangumiView

struct BangumiView: View {
    @Environment(\.yomiCanvas) private var canvas
    @State private var service = BangumiService.shared
    @State private var showSafari = false
    @State private var authURL: URL? = nil

    var body: some View {
        CalmList {
            TrackerHeaderLogoSection(name: "TrackerLogoBangumi", wordmark: true)
            if service.isLoggedIn {
                Section(calm: "Account") {
                    LabeledContent("Logged in as", value: service.username ?? "—")
                    Button("Disconnect", role: .destructive) { service.logout() }
                }
            } else {
                Section {
                    VStack(spacing: 16) {
                        Text("Connect your Bangumi account to automatically track chapters you read.")
                            .font(.callout)
                            .foregroundStyle(canvas.textSecondary)
                            .multilineTextAlignment(.center)
                        Button("Sign In with Bangumi") {
                            authURL = service.authorizationURL()
                            showSafari = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 4)
                }
            }
            if let error = service.errorMessage {
                Section {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
            }
        }
        .navigationTitle("Bangumi")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSafari) {
            if let url = authURL { SafariView(url: url) }
        }
    }
}

#Preview {
    NavigationStack { BangumiView() }
}
