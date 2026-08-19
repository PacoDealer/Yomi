import SwiftUI
import SafariServices

// MARK: - ShikimoriView

struct ShikimoriView: View {
    @State private var service = ShikimoriService.shared
    @State private var showSafari = false
    @State private var authURL: URL? = nil

    var body: some View {
        List {
            TrackerHeaderLogoSection(name: "TrackerLogoShikimori")
            if service.isLoggedIn {
                Section("Account") {
                    LabeledContent("Logged in as", value: service.username ?? "—")
                    Button("Disconnect", role: .destructive) { service.logout() }
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connect your Shikimori account to automatically track chapters you read.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Login with Shikimori") {
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
        .navigationTitle("Shikimori")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSafari) {
            if let url = authURL { SafariView(url: url) }
        }
    }
}

#Preview {
    NavigationStack { ShikimoriView() }
}
