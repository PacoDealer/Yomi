import SwiftUI
import AVFoundation

// MARK: - ListenMiniPlayer
//
// The docked player (S143, Readest / Apple Music style): cover, chapter, play/pause, next sentence. Tapping it
// opens the full player. Lives at the bottom of the reader and above the tab bar.

struct ListenMiniPlayer: View {
    var onOpen: () -> Void
    /// Above the tab bar the system draws the glass capsule itself.
    var inTabBar = false
    @State private var player = ListenPlayer.shared

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    if let novel = player.novel {
                        CoverImage(url: novel.coverURL)
                            .frame(width: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(player.chapter.map { Notation.plainText($0.name) } ?? "")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Now listening: \(player.chapter?.name ?? ""). Open player")

            ListenPlayButton(size: 20)
                .frame(width: 40, height: 40)

            Button { player.skip(by: 1) } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 17))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(player.sentences.isEmpty)
            .accessibilityLabel("Next sentence")
        }
        .foregroundStyle(.primary)
        .padding(.leading, inTabBar ? 8 : 10)
        .padding(.trailing, 6)
        .padding(.vertical, inTabBar ? 0 : 8)
        .glassEffect(inTabBar ? .identity : .regular, in: Capsule())
    }

    private var subtitle: String {
        switch player.status {
        case .loading: return "Loading…"
        case .failed(let message): return message
        default: return player.novel?.title ?? ""
        }
    }
}

/// Play / pause, or a spinner while the next chapter loads, or retry after a failure.
struct ListenPlayButton: View {
    var size: CGFloat
    @State private var player = ListenPlayer.shared

    var body: some View {
        switch player.status {
        case .loading:
            ProgressView()
        case .failed:
            Button { player.retry() } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: size * 0.85, weight: .semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Try again")
        default:
            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: size))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
        }
    }
}

// MARK: - ListenPlayerView

/// The full player sheet: what's being read, sentence/chapter controls, speed, voice, sleep timer.
struct ListenPlayerView: View {
    /// Shown outside the reader (tab bar): opens the novel in the reader at the chapter being read.
    var onOpenReader: (() -> Void)? = nil
    @State private var player = ListenPlayer.shared
    @State private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    /// The user's accent, explicitly: `Color.accentColor` in a sheet resolved to the asset colour (system blue).
    private var accent: Color { Color(hex: settings.accentColor) }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header
                currentSentence
                progress
                controls
                speedRow
                VStack(spacing: 0) {
                    voiceRow
                    sleepRow
                    if let onOpenReader {
                        Button {
                            dismiss()
                            onOpenReader()
                        } label: {
                            optionLabel("Open in reader", systemImage: "book", value: nil)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button(role: .destructive) {
                    player.stop()
                    dismiss()
                } label: {
                    Text("Stop listening")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 16)
        }
        // Sheets don't inherit YomiApp's tint (menus, pickers).
        .tint(accent)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onChange(of: player.isActive) { _, active in if !active { dismiss() } }
    }

    private var header: some View {
        VStack(spacing: 14) {
            if let novel = player.novel {
                CoverImage(url: novel.coverURL)
                    .frame(width: 150)
                    .clipShape(RoundedRectangle(cornerRadius: YomiTokens.Radius.cover))
                    .coverHairline()
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
            }
            VStack(spacing: 4) {
                Text(player.chapter.map { Notation.plainText($0.name) } ?? "")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(player.novel?.title ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder private var currentSentence: some View {
        switch player.status {
        case .failed(let message):
            Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        case .loading:
            Text("Loading the next chapter…").font(.callout).foregroundStyle(.secondary)
        default:
            if player.sentences.indices.contains(player.sentenceIndex) {
                Text(player.sentences[player.sentenceIndex])
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .frame(minHeight: 60)
                    .animation(.easeInOut(duration: 0.2), value: player.sentenceIndex)
            }
        }
    }

    private var progress: some View {
        VStack(spacing: 6) {
            ProgressView(value: player.progress)
                .tint(accent)
            HStack {
                Text(player.sentences.isEmpty ? " " : "\(player.sentenceIndex + 1) of \(player.sentences.count)")
                Spacer()
                Text(timeLeft)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var timeLeft: String {
        let minutes = Int((player.secondsLeft / 60).rounded(.up))
        guard !player.sentences.isEmpty else { return "" }
        return minutes <= 1 ? "Under a minute left" : "About \(minutes) min left"
    }

    private var controls: some View {
        HStack {
            controlButton("backward.end.fill", "Previous chapter", enabled: player.hasPreviousChapter) { player.previousChapter() }
            Spacer()
            controlButton("backward.fill", "Previous sentence", enabled: !player.sentences.isEmpty) { player.skip(by: -1) }
            Spacer()
            ListenPlayButton(size: 34)
                .frame(width: 64, height: 64)
            Spacer()
            controlButton("forward.fill", "Next sentence", enabled: !player.sentences.isEmpty) { player.skip(by: 1) }
            Spacer()
            controlButton("forward.end.fill", "Next chapter", enabled: player.hasNextChapter) { player.nextChapter() }
        }
        .foregroundStyle(.primary)
    }

    private func controlButton(_ symbol: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(label)
    }

    private var speedRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Speed").font(.subheadline).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ListenPlayer.speedPresets, id: \.self) { speed in
                        let selected = player.speed == speed
                        Button { player.setSpeed(speed) } label: {
                            Text(Self.speedLabel(speed))
                                .font(.subheadline.weight(selected ? .semibold : .regular).monospacedDigit())
                                .padding(.horizontal, 13)
                                .padding(.vertical, 7)
                                .foregroundStyle(selected ? Color(uiColor: .systemBackground) : .primary)
                                .background(selected ? Color.primary : Color.primary.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Speed \(Self.speedLabel(speed))")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func speedLabel(_ speed: Double) -> String {
        (speed.rounded() == speed ? String(Int(speed)) : String(format: "%g", speed)) + "×"
    }

    private var voiceRow: some View {
        let voices = ListenPlayer.voices(for: player.languageCode)
        return Menu {
            Picker("Voice", selection: Binding(get: { settings.ttsVoiceId }, set: { player.setVoice($0) })) {
                Text("Automatic").tag("")
                ForEach(voices, id: \.identifier) { voice in
                    Text(Self.voiceLabel(voice)).tag(voice.identifier)
                }
            }
            Section("Better voices: iPhone Settings → Accessibility → Read & Speak → Voices") {}
        } label: {
            optionLabel("Voice", systemImage: "person.wave.2",
                        value: voices.first { $0.identifier == settings.ttsVoiceId }.map(Self.voiceLabel) ?? "Automatic")
        }
        .buttonStyle(.plain)
    }

    nonisolated static func voiceLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium:  return "\(voice.name) · Premium"
        case .enhanced: return "\(voice.name) · Enhanced"
        default:        return voice.name
        }
    }

    private var sleepRow: some View {
        Menu {
            Button("Off") { player.setSleepTimer(.off) }
            Button("End of chapter") { player.setSleepTimer(.endOfChapter) }
            ForEach([15, 30, 45, 60], id: \.self) { minutes in
                Button("\(minutes) minutes") { player.setSleepTimer(.at(Date().addingTimeInterval(Double(minutes) * 60))) }
            }
        } label: {
            HStack {
                optionLabel("Sleep timer", systemImage: "moon.zzz", value: nil)
                Group {
                    switch player.sleepTimer {
                    case .off: Text("Off")
                    case .endOfChapter: Text("End of chapter")
                    case .at(let date): Text(timerInterval: Date()...max(date, Date()), countsDown: true)
                    }
                }
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func optionLabel(_ title: String, systemImage: String, value: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 24)
                .foregroundStyle(accent)
            Text(title)
            Spacer()
            if let value {
                Text(value).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
