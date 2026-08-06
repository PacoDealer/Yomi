import SwiftUI

// MARK: - Glass chip
//
// Shared 44×44 floating Liquid Glass circle used by chrome buttons that sit
// directly over content (reader top bars, Detail's glass nav — DESIGN_SYSTEM §9.8/§14).

extension View {
    func glassChip() -> some View {
        self
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .glassEffect(.regular, in: Circle())
    }
}
