import SwiftUI
import LocalAuthentication

// MARK: - AppLockView
//
// Presented via a fullScreenCover attached to the WindowGroup's ContentView() call site (see
// YomiApp.swift), so it sits outside ContentView's own `.environment(\.yomiCanvas, ...)` — reads
// AppSettings.shared / YomiTokens.Canvas.ink directly instead, same as OnboardingView and
// SecureScreenCover for the identical reason (their doc comments explain it in full).

struct AppLockView: View {
    let onUnlock: () -> Void

    @State private var errorMessage: String? = nil
    @State private var isAuthenticating = false

    private static let canvas = YomiTokens.Canvas.ink

    var body: some View {
        ZStack {
            Self.canvas.bg.ignoresSafeArea()

            VStack(spacing: 24) {
                RoundedRectangle(cornerRadius: 34)
                    .fill(Self.canvas.surface1)
                    .frame(width: 96, height: 96)
                    .overlay {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(Color(hex: AppSettings.shared.accentColor))
                    }
                    .shadow(color: .black.opacity(0.55), radius: 27, y: 20)

                Text("Yomi is locked")
                    .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.title2, weight: .semibold))
                    .foregroundStyle(Self.canvas.textPrimary)

                if let error = errorMessage {
                    Text(error)
                        .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.footnote))
                        .foregroundStyle(Self.canvas.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Button {
                    authenticate()
                } label: {
                    Label("Unlock", systemImage: biometricIcon)
                        .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.body, weight: .medium))
                        .frame(width: 200, height: 52)
                        .background(Color(hex: AppSettings.shared.accentColor))
                        .foregroundStyle(AppSettings.shared.accentForeground)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isAuthenticating)
                .padding(.top, 8)
            }
        }
        .onAppear { authenticate() }
    }

    private var biometricIcon: String {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return "lock.open"
        }
        return context.biometryType == .faceID ? "faceid" : "touchid"
    }

    private func authenticate() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        errorMessage = nil
        let context = LAContext()
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            errorMessage = "Authentication not available on this device."
            isAuthenticating = false
            return
        }
        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Unlock Yomi"
        ) { success, error in
            DispatchQueue.main.async {
                isAuthenticating = false
                if success {
                    onUnlock()
                } else if let err = error as? LAError, err.code != .userCancel {
                    errorMessage = err.localizedDescription
                }
            }
        }
    }
}
