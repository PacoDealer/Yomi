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
