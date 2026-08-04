import SwiftUI

// MARK: - Canvas environment
//
// Threads the resolved YomiTokens.CanvasColors (bg/surfaces/text) down to any
// view without each one re-reading AppSettings.shared. Set once in ContentView
// from `settings.canvasColors`; read anywhere via `@Environment(\.yomiCanvas)`.

private struct YomiCanvasKey: EnvironmentKey {
    static let defaultValue: YomiTokens.CanvasColors = YomiTokens.Canvas.ink
}

extension EnvironmentValues {
    var yomiCanvas: YomiTokens.CanvasColors {
        get { self[YomiCanvasKey.self] }
        set { self[YomiCanvasKey.self] = newValue }
    }
}
