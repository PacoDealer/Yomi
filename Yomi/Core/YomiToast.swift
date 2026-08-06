import SwiftUI
import UIKit

// MARK: - YomiToast
//
// A small self-dismissing top banner for surfacing failures that would otherwise be silent
// (e.g. a GRDB write error caught and only print()'d to console). Styling matches the existing
// ad-hoc refresh-summary banner in UpdatesView.swift; this generalizes it into a reusable
// modifier so any view can report a failure without hand-rolling the overlay + dismiss timer.

private struct YomiToastModifier: ViewModifier {
    @Binding var message: String?
    var isError: Bool = true
    var duration: Duration = .seconds(2.5)

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message {
                    HStack(spacing: 8) {
                        if isError {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                        Text(message)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: message)
            .task(id: message) {
                guard message != nil else { return }
                try? await Task.sleep(for: duration)
                message = nil
            }
    }
}

extension View {
    /// Shows a self-dismissing top banner while `message` is non-nil, then clears it back to nil.
    func yomiToast(_ message: Binding<String?>, isError: Bool = true) -> some View {
        modifier(YomiToastModifier(message: message, isError: isError))
    }
}

@MainActor
enum YomiHaptics {
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
