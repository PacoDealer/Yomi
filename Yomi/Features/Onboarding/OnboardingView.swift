import SwiftUI

// MARK: - OnboardingView
//
// Design spec: YOMI Screens.dc.html N.08 (Onboarding). The mock shows a single frame (icon +
// wordmark + description + CTA + page dots); the same template is reused across all 3 pages with
// per-page content, since the mock only specifies the visual language, not unique page 2/3 content.

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage: Int = 0

    private static let bg = Color(hex: "#14110F")
    private static let tx = Color(hex: "#F4EFE7")

    var body: some View {
        ZStack {
            Self.bg.ignoresSafeArea()

            TabView(selection: $currentPage) {
                OnboardingPage(
                    iconImage: "OnboardingIcon",
                    systemImage: "book.fill",
                    title: "YOMI",
                    accentSuffix: ".",
                    description: "Manga, manhwa & light novels from any source — a living archive of what you read.",
                    caption: nil,
                    buttonLabel: "Get started",
                    pageIndex: 0,
                    onAction: { currentPage = 1 }
                )
                .tag(0)

                OnboardingPage(
                    systemImage: "puzzlepiece.extension.fill",
                    title: "Install a Plugin",
                    description: "Yomi connects to content sources via user-installed plugins — browse the catalog to install your first one.",
                    caption: "yomi-plugins.web.app",
                    buttonLabel: "Next",
                    pageIndex: 1,
                    onAction: { currentPage = 2 }
                )
                .tag(1)

                OnboardingPage(
                    systemImage: "checkmark.circle.fill",
                    title: "You're all set",
                    description: "Go to More → Plugins to install your first source and start reading.",
                    caption: nil,
                    buttonLabel: "Open Plugins",
                    pageIndex: 2,
                    onAction: {
                        AppSettings.shared.hasSeenOnboarding = true
                        appRouter.selectedTab = AppRouter.tabMore
                        dismiss()
                        // Delay so MoreView's NavigationStack is rendered before the push fires.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            appRouter.openMorePlugins = true
                        }
                    }
                )
                .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        // fullScreenCover presents a separate view hierarchy that doesn't inherit YomiApp's
        // .tint() from ContentView() — without this, every Color.accentColor use here (dots,
        // CTA, icon fallback) silently renders system blue instead of the user's accent.
        .tint(Color(hex: AppSettings.shared.accentColor))
    }
}

// MARK: - OnboardingPage
//
// Shared template for all 3 pages, matching N.08: 150×150 icon/image box, wordmark or title,
// description (max ~15em), optional mono caption, page dots, full-width accent CTA.

private struct OnboardingPage: View {
    var iconImage: String? = nil
    var systemImage: String? = nil
    let title: String
    var accentSuffix: String? = nil
    let description: String
    let caption: String?
    let buttonLabel: String
    let pageIndex: Int
    let onAction: () -> Void

    private static let tx = Color(hex: "#F4EFE7")

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 34) {
                iconBox

                VStack(spacing: 16) {
                    Group {
                        if let accentSuffix {
                            Text("\(title)\(Text(accentSuffix).foregroundStyle(Color.accentColor))")
                        } else {
                            Text(title)
                        }
                    }
                    .font(YomiTokens.Font.grotesk(36, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(Self.tx)
                    .multilineTextAlignment(.center)

                    Text(description)
                        .font(YomiTokens.Font.grotesk(16))
                        .foregroundStyle(Self.tx.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .frame(maxWidth: 300)
                }
            }

            Spacer()

            VStack(spacing: 22) {
                HStack(spacing: 7) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule()
                            .fill(i == pageIndex ? Color.accentColor : Self.tx.opacity(0.24))
                            .frame(width: i == pageIndex ? 22 : 6, height: 6)
                    }
                }

                Button(action: onAction) {
                    Text(buttonLabel)
                        .font(YomiTokens.Font.grotesk(16, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.accentColor)
                        .foregroundStyle(Color(hex: "#FFF8F5"))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                if let caption {
                    Text(caption)
                        .font(YomiTokens.Font.mono(11))
                        .foregroundStyle(Self.tx.opacity(0.36))
                }
            }
            .padding(.bottom, 56)
        }
        .padding(.horizontal, 32)
    }

    @ViewBuilder
    private var iconBox: some View {
        if let iconImage, let uiImage = UIImage(named: iconImage) {
            Image(uiImage: uiImage)
                .resizable()
                .frame(width: 150, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 34))
                .shadow(color: .black.opacity(0.55), radius: 27, y: 20)
        } else if let systemImage {
            RoundedRectangle(cornerRadius: 34)
                .fill(Color(hex: "#1E1A17"))
                .frame(width: 150, height: 150)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: 56))
                        .foregroundStyle(Color.accentColor)
                }
                .shadow(color: .black.opacity(0.55), radius: 27, y: 20)
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView()
}
