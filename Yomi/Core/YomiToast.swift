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
                    .transition(Motion.slide(.top))
                }
            }
            .motion(.easeInOut(duration: 0.2), value: message)
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

// MARK: - Pull to refresh status (detail pages)
//
// The manga/novel detail pages draw their header up under the status bar with the navigation bar hidden, so the
// system refresh spinner has nowhere visible to sit — a pull ran the refresh with no sign that anything happened.
// This pill says "Checking…" while it runs, then the result for a moment.

enum PullRefreshStatus: Equatable {
    case checking
    case done(String)
}

private struct PullRefreshStatusModifier: ViewModifier {
    @Binding var status: PullRefreshStatus?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let status {
                    HStack(spacing: 8) {
                        switch status {
                        case .checking:
                            ProgressView().controlSize(.small)
                            Text("Checking for new chapters…")
                        case .done(let message):
                            Text(message)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(Motion.slide(.top))
                    .accessibilityElement(children: .combine)
                }
            }
            .motion(.easeInOut(duration: 0.2), value: status)
            .task(id: status) {
                guard case .done = status else { return }
                try? await Task.sleep(for: .seconds(2.5))
                status = nil
            }
    }
}

extension View {
    /// The pull-to-refresh pill of a detail page: shown while `status` is `.checking`, a result for 2.5 s after `.done`.
    func pullRefreshStatus(_ status: Binding<PullRefreshStatus?>) -> some View {
        modifier(PullRefreshStatusModifier(status: status))
    }
}

@MainActor
enum YomiHaptics {
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
