import SwiftUI
import LocalAuthentication

// MARK: - AppLockView

struct AppLockView: View {
    let onUnlock: () -> Void

    @State private var errorMessage: String? = nil
    @State private var isAuthenticating = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)

                Text("Yomi is locked")
                    .font(.title3)
                    .fontWeight(.semibold)

                if let error = errorMessage {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Button {
                    authenticate()
                } label: {
                    Label("Unlock", systemImage: biometricIcon)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isAuthenticating)
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
