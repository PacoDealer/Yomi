import SwiftUI
import SafariServices

// MARK: - BangumiView

struct BangumiView: View {
    @Environment(\.yomiCanvas) private var canvas
    @State private var service = BangumiService.shared
    @State private var showSafari = false
    @State private var authURL: URL? = nil

    var body: some View {
        List {
            TrackerHeaderLogoSection(name: "TrackerLogoBangumi", wordmark: true)
            if service.isLoggedIn {
                Section("Account") {
                    LabeledContent("Logged in as", value: service.username ?? "—")
                    Button("Disconnect", role: .destructive) { service.logout() }
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connect your Bangumi account to automatically track chapters you read.")
                            .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.callout))
                            .foregroundStyle(canvas.textSecondary)
                        Button("Login with Bangumi") {
                            authURL = service.authorizationURL()
                            showSafari = true
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 4)
                }
            }
            if let error = service.errorMessage {
                Section {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }
        }
        .listStyle(.insetGrouped)
        .yomiListCanvas()
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
