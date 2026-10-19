import SwiftUI

// MARK: - SafeModeView
//
// Settings → Privacy → Safe Mode (S179, `Core/SafeMode.swift`). On hides 18+ sources and adult-tagged titles
// everywhere; a Yomi passcode locks it so turning it off (or loosening it) needs the code. Turning things stricter
// never asks.

struct SafeModeView: View {
    @State private var settings = AppSettings.shared
    @State private var isLocked = SafeMode.isLocked
    @State private var passcodeTask: PasscodeTask?
    /// Set once the passcode was entered, so the next loosening change goes through.
    @State private var approved = false

    @Environment(\.yomiCanvas) private var canvas

    var body: some View {
        CalmList {
            Section {
                Toggle(isOn: $settings.safeMode) {
                    Text("Safe Mode")
                    Text("Hides 18+ sources, and titles tagged Adult, Hentai, Smut, Ecchi or Mature, in the Library, Browse, search, History and Updates.")
                }
                .accessibilityIdentifier("safeModeToggle")
                if settings.safeMode {
                    Toggle(isOn: $settings.safeModeHidesMixed) {
                        Text("Hide mixed sources")
                        Text("Also hides sources their repository marks as mixed — most big sites, like MangaFire.")
                    }
                }
            }

            if settings.safeMode {
                Section(calm: "Lock") {
                    if isLocked {
                        Button("Change Passcode") { passcodeTask = .change }
                        Button("Remove Lock", role: .destructive) { passcodeTask = .removeLock }
                    } else {
                        Button("Lock with a Passcode") { passcodeTask = .set }
                            .accessibilityIdentifier("safeModeLock")
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    if isLocked {
                        Text("Turning Safe Mode off or showing mixed sources asks for the passcode.")
                    }
                    Text("Sources decide their own tags, so an untagged adult title can still appear. For more control, use Screen Time on the iPhone.")
                }
                .font(.footnote)
                .foregroundStyle(canvas.textSecondary)
            }
        }
        .navigationTitle("Safe Mode")
        // Loosening while locked: put the switch back and ask for the passcode (stricter never asks).
        .onChange(of: settings.safeMode) { was, now in
            if was && !now && isLocked && !approved { settings.safeMode = true; passcodeTask = .turnOff }
            approved = false
        }
        .onChange(of: settings.safeModeHidesMixed) { was, now in
            if was && !now && isLocked && !approved { settings.safeModeHidesMixed = true; passcodeTask = .showMixed }
            approved = false
        }
        .sheet(item: $passcodeTask) { task in
            PasscodeSheet(task: task) { code in finish(task, code: code) }
        }
    }

    private func finish(_ task: PasscodeTask, code: String) {
        switch task {
        case .set, .change:
            SafeMode.setPasscode(code)
        case .turnOff:
            SafeMode.removePasscode()
            approved = true
            settings.safeMode = false
        case .showMixed:
            approved = true
            settings.safeModeHidesMixed = false
        case .removeLock:
            SafeMode.removePasscode()
        }
        isLocked = SafeMode.isLocked
    }
}

// MARK: - PasscodeTask

enum PasscodeTask: String, Identifiable {
    case set, change, turnOff, showMixed, removeLock
    var id: String { rawValue }

    /// True when the current passcode must be entered first.
    var needsCurrent: Bool { self != .set }
    /// True when a new passcode is chosen (entered twice).
    var choosesNew: Bool { self == .set || self == .change }
}

// MARK: - PasscodeSheet

private struct PasscodeSheet: View {
    let task: PasscodeTask
    /// Called with the NEW code for set/change, the checked code otherwise.
    let onDone: (String) -> Void

    private enum Step { case current, new, confirm }

    @State private var step: Step
    @State private var code = ""
    @State private var firstNew = ""
    @State private var message: String?
    @FocusState private var focused: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.yomiCanvas) private var canvas

    private static let length = 4

    init(task: PasscodeTask, onDone: @escaping (String) -> Void) {
        self.task = task
        self.onDone = onDone
        _step = State(initialValue: task.needsCurrent ? .current : .new)
    }

    private var prompt: String {
        switch step {
        case .current: String(localized: "Enter the Safe Mode passcode")
        case .new: String(localized: "Choose a 4-digit passcode")
        case .confirm: String(localized: "Enter it again")
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(prompt)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(canvas.textPrimary)
                HStack(spacing: 18) {
                    ForEach(0..<Self.length, id: \.self) { i in
                        Circle()
                            .strokeBorder(canvas.textPrimary, lineWidth: 1.5)
                            .background(Circle().fill(i < code.count ? canvas.textPrimary : .clear))
                            .frame(width: 14, height: 14)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("\(code.count) of \(Self.length) digits entered")
                Text(message ?? " ")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                if step == .new && task == .set {
                    Text("Write it down — Yomi can't show it again. Forgot it? Delete and reinstall Yomi (back up your library first).")
                        .font(.footnote)
                        .foregroundStyle(canvas.textSecondary)
                        .multilineTextAlignment(.center)
                }
                // The field takes the keystrokes; the dots show them.
                TextField("", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($focused)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .accessibilityIdentifier("safeModePasscodeField")
                    .onChange(of: code) { _, new in
                        let digits = String(new.filter(\.isNumber).prefix(Self.length))
                        if digits != new { code = digits; return }
                        if digits.count == Self.length { submit(digits) }
                    }
                Spacer()
            }
            .padding(.top, 40)
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity)
            .background(canvas.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }

    private func submit(_ digits: String) {
        code = ""
        switch step {
        case .current:
            let wait = SafeMode.waitRemaining
            if wait > 0 {
                message = String(localized: "Too many tries. Try again in \(Int(wait.rounded(.up))) seconds.")
                return
            }
            guard SafeMode.check(digits) else {
                let after = SafeMode.waitRemaining
                message = after > 0 ? String(localized: "Wrong passcode. Try again in a minute.") : String(localized: "Wrong passcode.")
                return
            }
            message = nil
            if task.choosesNew { step = .new } else { onDone(digits); dismiss() }
        case .new:
            firstNew = digits
            message = nil
            step = .confirm
        case .confirm:
            guard digits == firstNew else {
                message = String(localized: "The passcodes didn't match. Choose one again.")
                step = .new
                return
            }
            onDone(digits)
            dismiss()
        }
    }
}
