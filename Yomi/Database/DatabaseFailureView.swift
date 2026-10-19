import SwiftUI

/// Shown instead of the app when the library can't be opened or updated at launch (S185) — before, Yomi stopped with a
/// `fatalError` at every launch. The data stays on the phone (plus the copy taken before migrating, S184); this screen
/// lets the user share it for a fix, or try again.
struct DatabaseFailureView: View {
    let error: Error?
    let onRetry: () -> Void

    @State private var files = DatabaseManager.shared.filesForSupport()

    var body: some View {
        ContentUnavailableView {
            Label("Yomi couldn't open your library", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            VStack(spacing: 12) {
                Text("Your library is still on this iPhone — nothing was deleted. Share the database so the problem can be fixed, or try again.")
                if let error {
                    Text(verbatim: String(describing: error))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(6)
                }
            }
        } actions: {
            if !files.isEmpty {
                ShareLink(items: files) {
                    Label("Share Database", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }
            Button("Try Again", action: onRetry)
                .buttonStyle(.bordered)
        }
        .onAppear { files = DatabaseManager.shared.filesForSupport() }
    }
}
