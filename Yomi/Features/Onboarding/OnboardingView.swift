import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage: Int = 0

    var body: some View {
        ZStack {
            Color(red: 0.11, green: 0.11, blue: 0.12) // #1C1C1E
                .ignoresSafeArea()

            TabView(selection: $currentPage) {
                WelcomePage(onNext: { currentPage = 1 })
                    .tag(0)

                InstallPluginPage(onNext: { currentPage = 2 })
                    .tag(1)

                ReadyPage(onDone: {
                    AppSettings.shared.hasSeenOnboarding = true
                    appRouter.selectedTab = AppRouter.tabMore
                    dismiss()
                    // Delay so MoreView's NavigationStack is rendered before the push fires.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        appRouter.openMorePlugins = true
                    }
                })
                .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
    }
}

// MARK: - Page 1: Welcome

private struct WelcomePage: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "book.fill")
                .font(.system(size: 72))
                .foregroundStyle(.tint)

            VStack(spacing: 12) {
                Text("Welcome to Yomi")
                    .font(.largeTitle).fontWeight(.bold)
                    .foregroundStyle(.white)

                Text("Manga, manhwa & light novels from any source.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Spacer()

            Button(action: onNext) {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 64)
        }
    }
}

// MARK: - Page 2: Install a Plugin

private struct InstallPluginPage: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "puzzlepiece.extension.fill")
                .font(.system(size: 60))
                .foregroundStyle(.white)

            VStack(spacing: 12) {
                Text("Install a Plugin")
                    .font(.largeTitle).fontWeight(.bold)
                    .foregroundStyle(.white)

                Text("Plugins connect Yomi to content sources. Browse the Yomi catalog to install your first one.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)

                Text("yomi-plugins.web.app")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 4)
            }
            .padding(.horizontal, 32)

            Spacer()

            Button(action: onNext) {
                Text("Next")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 64)
        }
    }
}

// MARK: - Page 3: Ready

private struct ReadyPage: View {
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)

            VStack(spacing: 12) {
                Text("You're all set")
                    .font(.largeTitle).fontWeight(.bold)
                    .foregroundStyle(.white)

                Text("Go to More → Plugins to install your first source.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Spacer()

            Button(action: onDone) {
                Text("Open Plugins")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 64)
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView()
}
