import SwiftUI
import UIKit

// Hiding the navigation bar (readers, Settings, Downloads, Insights, More) also switches off UIKit's
// left-edge "swipe to go back". `.swipeBackEnabled()` turns it back on for the hosting navigation
// controller: the edge gesture may begin whenever there is a screen to pop to and no transition is running.
extension View {
    func swipeBackEnabled() -> some View {
        background(SwipeBackInstaller().frame(width: 0, height: 0))
    }
}

private struct SwipeBackInstaller: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let pop = navigationController?.interactivePopGestureRecognizer else { return }
            pop.delegate = SwipeBackDelegate.shared
            pop.isEnabled = true
        }
    }
}

/// Shared because `UIGestureRecognizer.delegate` is weak. Navigation controllers are found from the
/// gesture's view (the navigation controller's own view), so one instance serves every stack.
private final class SwipeBackDelegate: NSObject, UIGestureRecognizerDelegate {
    static let shared = SwipeBackDelegate()

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let nav = gestureRecognizer.view?.next as? UINavigationController else { return false }
        return nav.viewControllers.count > 1 && nav.transitionCoordinator == nil
    }
}

// A screen that hides its navigation bar (title detail screens) still got it when it was pushed from a screen
// with an ACTIVE search (Library, History, a source's search): UIKit keeps the bar for the search, so the
// title showed the system back button above its own (#206). `.navigationBarStaysHidden(_:)` hides it again
// when the screen appears. Ending the search before the push instead was tried and broke SwiftUI's state.
extension View {
    func navigationBarStaysHidden(_ hidden: Bool) -> some View {
        background(NavigationBarHider(hidden: hidden).frame(width: 0, height: 0))
    }
}

private struct NavigationBarHider: UIViewControllerRepresentable {
    let hidden: Bool

    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.hidden = hidden
    }

    final class Controller: UIViewController {
        var hidden = true

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            hideIfNeeded()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            hideIfNeeded()
        }

        private func hideIfNeeded() {
            guard hidden, let nav = navigationController, !nav.isNavigationBarHidden else { return }
            nav.setNavigationBarHidden(true, animated: false)
        }
    }
}
