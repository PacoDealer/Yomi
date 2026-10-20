import SwiftUI
import DeclaredAgeRange

// MARK: - Age gate for "Show 18+ extensions"
//
// S187 (AUDIT_S184 §2 E, guideline 4.7.5): plug-in apps must "use an age restriction mechanism based on verified or
// declared age". Turning the 18+ switch on asks the system for the person's age range (Declared Age Range, iOS 26,
// one gate at 18). Shared and 18 or over → on. Declined, or under 18 → stays off. When the service can't answer
// (no account, region, simulator) Yomi falls back to asking the person to declare it themselves — still a declared
// age, and the only option left. Turning the switch off never asks.

enum AgeGate {
    /// What the age-range request came back with, reduced to what the switch needs.
    enum Outcome: Equatable {
        case adult
        case underAge
        case declined
        /// The service couldn't answer — fall back to a self-declaration.
        case unavailable
    }

    /// Pure decision on a shared range: only a lower bound of 18 or more counts as adult. A range with no lower
    /// bound ("under 18") or one below 18 doesn't.
    static func outcome(lowerBound: Int?) -> Outcome {
        guard let lowerBound, lowerBound >= 18 else { return .underAge }
        return .adult
    }

    static func outcome(_ response: AgeRangeService.Response) -> Outcome {
        switch response {
        case .declinedSharing:        .declined
        case .sharing(let range):     outcome(lowerBound: range.lowerBound)
        @unknown default:             .declined
        }
    }

    /// DEBUG: `-yomiAgeRange adult|under|declined|unavailable` answers without the system sheet (the simulator has
    /// no age range to share).
    static var debugOverride: Outcome? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-yomiAgeRange"), i + 1 < args.count else { return nil }
        switch args[i + 1] {
        case "adult":       return .adult
        case "under":       return .underAge
        case "declined":    return .declined
        case "unavailable": return .unavailable
        default:            return nil
        }
        #else
        return nil
        #endif
    }

    /// Asks once. Errors (not available, no account, network) become `.unavailable`.
    static func request(_ action: DeclaredAgeRangeAction) async -> Outcome {
        if let debugOverride { return debugOverride }
        do {
            return outcome(try await action(ageGates: 18))
        } catch {
            print("[AgeGate] age range unavailable: \(error)")
            return .unavailable
        }
    }
}

/// The "Show 18+ extensions" switch with the age gate in front of it.
struct AdultExtensionsToggle: View {
    @State private var settings = AppSettings.shared
    @State private var checking = false
    @State private var showSelfDeclaration = false
    @State private var refusal: LocalizedStringKey?
    @Environment(\.requestAgeRange) private var requestAgeRange

    var body: some View {
        Toggle(isOn: Binding(get: { settings.showNSFW }, set: setShowNSFW)) {
            Text("Show 18+ extensions")
            Text(settings.safeMode ? "Safe Mode is on, so 18+ extensions stay hidden."
                                   : "Off hides extensions their repository marks as 18+. Turning it on asks for your age range.")
        }
        .disabled(settings.safeMode || checking)
        .confirmationDialog("Are you 18 or older?", isPresented: $showSelfDeclaration, titleVisibility: .visible) {
            Button("I'm 18 or Older") { settings.showNSFW = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your age range isn't available on this iPhone, so Yomi has to ask. 18+ extensions can show sexual content.")
        }
        .alert(refusal ?? "", isPresented: Binding(get: { refusal != nil }, set: { if !$0 { refusal = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("18+ extensions stay hidden.")
        }
    }

    private func setShowNSFW(_ on: Bool) {
        guard on else { settings.showNSFW = false; return }
        checking = true
        Task {
            let outcome = await AgeGate.request(requestAgeRange)
            checking = false
            switch outcome {
            case .adult:       settings.showNSFW = true
            case .underAge:    refusal = "18+ extensions are for adults"
            case .declined:    refusal = "Your age range wasn't shared"
            case .unavailable: showSelfDeclaration = true
            }
        }
    }
}
