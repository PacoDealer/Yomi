import SwiftUI

// MARK: - YomiEmptyState
//
// Design spec: YOMI Screens.dc.html N.09 (Empty state). The mock's decorative glyph is bespoke to
// the Library empty state specifically; this reusable version generalizes it to a boxed SF Symbol
// (s1 card + hairline ring) so every ContentUnavailableView call site in the app can share one
// design-system-correct empty state instead of the native system-styled default.

struct YomiEmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    var actionLabel: String? = nil
    var actionIcon: String? = nil
    var action: (() -> Void)? = nil

    @Environment(\.yomiCanvas) private var canvas

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(canvas.surface1)
                    .frame(width: 92, height: 84)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(canvas.hairline, lineWidth: 2)
                    }
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 14, height: 14)
                    .offset(y: -42)
                Image(systemName: systemImage)
                    .font(.system(size: 26))
                    .foregroundStyle(canvas.textSecondary)
            }
            .frame(height: 132)

            VStack(spacing: 8) {
                Text(title)
                    .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.headline, weight: .medium))
                    .foregroundStyle(canvas.textPrimary)
                Text(message)
                    .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.footnote))
                    .foregroundStyle(canvas.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 280)
            }

            if let actionLabel, let action {
                Button(action: action) {
                    HStack(spacing: 8) {
                        if let actionIcon {
                            Image(systemName: actionIcon)
                                .font(.system(size: 14))
                        }
                        Text(actionLabel)
                            .font(YomiTokens.Font.grotesk(15, weight: .medium))
                    }
                    .foregroundStyle(AppSettings.shared.accentForeground)
                    .padding(.horizontal, 24)
                    .frame(height: 46)
                    .background(Color.accentColor, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
