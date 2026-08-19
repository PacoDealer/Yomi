import SwiftUI
import SafariServices

// MARK: - AniListView

struct AniListView: View {
    @State private var service = AniListTrackerService.shared
    @State private var showSafari = false
    @State private var authURL: URL? = nil

    var body: some View {
        List {
            if service.isLoggedIn {
                Section("Account") {
                    LabeledContent("Logged in as", value: service.username ?? "—")
                    Button("Disconnect", role: .destructive) { service.logout() }
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connect your AniList account to automatically track chapters you read.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Login with AniList") {
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
        .navigationTitle("AniList")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSafari) {
            if let url = authURL { SafariView(url: url) }
        }
    }
}

#Preview {
    NavigationStack { AniListView() }
}
