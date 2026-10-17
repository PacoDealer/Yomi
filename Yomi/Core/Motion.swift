import SwiftUI
import UIKit

// MARK: - Reduce Motion (S178, RESEARCH §25.2 — "no accessibilityReduceMotion checks")
//
// With Settings → Accessibility → Motion → Reduce Motion on, Yomi's springs, slides, animated page turns and
// animated scrolls happen at once instead (Apple HIG: replace motion; nothing here carries meaning only through
// movement). Every animation in the app goes through these helpers — use them, not withAnimation / .animation /
// .move, in new code. Read when the change happens, so switching the setting applies to the next animation.

enum Motion {
    static var reduced: Bool { UIAccessibility.isReduceMotionEnabled }

    /// `animation`, or none with Reduce Motion.
    static func animation(_ animation: Animation?) -> Animation? {
        reduced ? nil : animation
    }

    /// Slides in from `edge` — a plain fade with Reduce Motion.
    static func slide(_ edge: Edge) -> AnyTransition {
        reduced ? .opacity : .move(edge: edge).combined(with: .opacity)
    }

    /// Grows in — a plain fade with Reduce Motion.
    static var pop: AnyTransition {
        reduced ? .opacity : .scale.combined(with: .opacity)
    }
}

/// `withAnimation`, minus the animation with Reduce Motion on.
@discardableResult
func withMotion<Result>(_ animation: Animation? = .default, _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(Motion.animation(animation), body)
}

extension View {
    /// `.animation(_:value:)`, minus the animation with Reduce Motion on.
    func motion<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        self.animation(Motion.animation(animation), value: value)
    }
}
