import SwiftUI

// MARK: - YomiScrubber
//
// Custom-styled replacement for the native SwiftUI Slider — the system slider's
// large default thumb clashes with the app's thin-capsule progress-bar language
// used everywhere else (Continue card, chapter progress footer, cover cells).
// Thin capsule track, accent-color fill, small circular thumb.

struct YomiScrubber: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    /// What VoiceOver announces this control as. A native `Slider` would take this from its own
    /// label view; this one has no label of its own, so callers must supply it (Known Issue #120).
    var accessibilityLabelText: String = "Slider"
    /// How the current value is spoken. Defaults to the bare number, which is right for a page
    /// index but not for e.g. a font size in points.
    var accessibilityValueText: (Double) -> String = { "\(Int($0.rounded()))" }

    @State private var isDragging = false

    private var fraction: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat((value - range.lowerBound) / span)
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.15))
                    .frame(height: 4)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(0, width * fraction), height: 4)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: isDragging ? 18 : 14, height: isDragging ? 18 : 14)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .offset(x: max(0, min(width, width * fraction)) - (isDragging ? 9 : 7))
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.15), value: isDragging)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isDragging = true
                        let clampedX = min(max(0, drag.location.x), width)
                        let rawValue = range.lowerBound + Double(clampedX / width) * (range.upperBound - range.lowerBound)
                        let stepped = (rawValue / step).rounded() * step
                        value = min(max(stepped, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in isDragging = false }
            )
        }
        .frame(height: 24)
        // A DragGesture-driven custom control is invisible to VoiceOver on its own — everything a
        // native Slider provides for free has to be declared here (Known Issue #120).
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityValue(accessibilityValueText(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: setValue(value + step)
            case .decrement: setValue(value - step)
            @unknown default: break
            }
        }
    }

    private func setValue(_ new: Double) {
        value = min(max(new, range.lowerBound), range.upperBound)
    }
}
