import AVFoundation
import MediaPlayer
import NaturalLanguage
import UIKit
import Kingfisher

// MARK: - ListenPlayer
//
// Read-aloud for novels (S143, RESEARCH §25.10 #8). One player for the whole app, so listening carries on after
// the reader closes (Martin: "keep playing", like Apple Music) and with the screen locked (`audio` background mode).
//
// Swift owns the text: a chapter's HTML becomes a list of sentences here, and each sentence is one utterance. The
// reader's web view is suspended while the phone is locked, so nothing the player needs — next chapter, progress,
// lock-screen info — can depend on it. The reader only mirrors the player: it highlights `sentenceIndex` of
// `sentences` by finding each sentence's text in the page (NovelReaderScript `tts*`).

@Observable
final class ListenPlayer {
    static let shared = ListenPlayer()

    enum Status: Equatable { case idle, loading, playing, paused, failed(String) }
    enum SleepTimer: Equatable { case off, endOfChapter, at(Date) }

    private(set) var novel: Novel?
    private(set) var chapters: [NovelChapter] = []
    private(set) var chapterIndex = 0
    private(set) var sentences: [String] = []
    private(set) var sentenceIndex = 0
    private(set) var status: Status = .idle
    private(set) var sleepTimer: SleepTimer = .off
    /// Bumped every time `sentences` is replaced, so the reader re-sends them to the page.
    private(set) var chapterToken = 0

    var isActive: Bool { novel != nil }
    /// Open novel readers — they dock their own mini-player, so the tab bar's hides meanwhile.
    var readersOpen = 0
    var isPlaying: Bool { status == .playing }
    var chapter: NovelChapter? { chapters.indices.contains(chapterIndex) ? chapters[chapterIndex] : nil }
    var hasNextChapter: Bool { chapterIndex + 1 < chapters.count }
    var hasPreviousChapter: Bool { chapterIndex > 0 }
    /// Share of the chapter's characters before the current sentence. Saved as the chapter's reading position: by
    /// characters it lines up with the reader's scroll percent far better than a sentence count (sentence lengths vary).
    var progress: Double {
        guard let total = charOffsets.last, total > 0 else { return 0 }
        let done = sentenceIndex > 0 && sentenceIndex <= charOffsets.count ? charOffsets[sentenceIndex - 1] : 0
        return Double(done) / Double(total)
    }

    @ObservationIgnored private(set) var bridge: JSBridge?
    @ObservationIgnored private var language: String?
    /// Replaced on every re-queue: `speak` right after `stopSpeaking` on the same synthesizer can be dropped.
    @ObservationIgnored private var synth = AVSpeechSynthesizer()
    @ObservationIgnored private let delegate = SpeechDelegate()
    /// Queued utterances → sentence index (-1 = the chapter-name announcement).
    @ObservationIgnored private var queued: [ObjectIdentifier: Int] = [:]
    /// The synthesizer was stopped (jump, voice change) — the next play re-queues instead of continuing.
    @ObservationIgnored private var needsRequeue = true
    @ObservationIgnored private var prepared: (id: String, sentences: [String])?
    @ObservationIgnored private var preparing = false
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var lastSavedProgress: Double = -1
    @ObservationIgnored private var listenStart: Date?
    @ObservationIgnored private var sleepTask: Task<Void, Never>?
    @ObservationIgnored private var resumeAfterInterruption = false
    @ObservationIgnored private var systemHooksInstalled = false
    @ObservationIgnored private var artwork: MPMediaItemArtwork?
    /// Cumulative character counts, for the time estimates.
    private var charOffsets: [Int] = []

    private init() {
        delegate.onStart = { id in ListenPlayer.shared.didStart(id) }
        delegate.onFinish = { id in ListenPlayer.shared.didFinish(id) }
    }

    // MARK: Starting

    /// Starts (or restarts) listening at `sentence` of chapter `index`, whose text the caller already has.
    func start(novel: Novel, bridge: JSBridge, chapters: [NovelChapter], index: Int,
               sentences list: [String], from sentence: Int, language: String?) {
        guard chapters.indices.contains(index) else { return }
        flushListeningTime()
        if self.novel?.id != novel.id { artwork = nil; loadArtwork(for: novel) }
        self.novel = novel
        self.bridge = bridge
        self.chapters = chapters
        self.language = language
        installSystemHooks()
        loadGeneration += 1
        begin(chapter: index, sentences: list, at: sentence, announce: false)
    }

    private func begin(chapter index: Int, sentences list: [String], at start: Int, announce: Bool, autoplay: Bool = true) {
        chapterIndex = index
        sentences = list
        chapterToken += 1
        prepared = nil
        preparing = false
        lastSavedProgress = -1
        var total = 0
        charOffsets = list.map { total += $0.count; return total }
        guard !list.isEmpty else {
            status = .failed("This chapter has no text to read.")
            updateNowPlaying()
            return
        }
        sentenceIndex = min(max(start, 0), list.count - 1)
        if autoplay {
            play(announce: announce)
        } else {
            status = .paused
            needsRequeue = true
            updateNowPlaying()
        }
    }

    // MARK: Controls

    func togglePlayPause() { isPlaying ? pause() : play() }

    /// After a failed chapter load: try the load again; otherwise just play.
    func retry() {
        if sentences.isEmpty { load(chapter: chapterIndex) } else { play() }
    }

    /// Estimated time left in the chapter (sentences aren't timed; ~18 characters a second at 1×).
    var secondsLeft: Double {
        guard let total = charOffsets.last else { return 0 }
        let done = sentenceIndex > 0 && sentenceIndex <= charOffsets.count ? charOffsets[sentenceIndex - 1] : 0
        return Double(total - done) / (18 * Self.speed(forRate: AppSettings.shared.ttsSpeechRate))
    }

    func play() { play(announce: false) }

    private func play(announce: Bool) {
        guard isActive, !sentences.isEmpty else { return }
        activateSession()
        if !needsRequeue && synth.isPaused {
            synth.continueSpeaking()
        } else {
            speak(from: sentenceIndex, announce: announce)
        }
        status = .playing
        listenStart = Date()
        updateNowPlaying()
    }

    func pause() {
        guard isActive else { return }
        if synth.isSpeaking { synth.pauseSpeaking(at: .immediate) }
        if status == .playing || status == .loading { status = .paused }
        flushListeningTime()
        updateNowPlaying()
    }

    func stop() {
        stopSynth()
        flushListeningTime()
        cancelSleepTimer()
        loadGeneration += 1
        novel = nil
        bridge = nil
        chapters = []
        sentences = []
        charOffsets = []
        sentenceIndex = 0
        prepared = nil
        status = .idle
        chapterToken += 1
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Previous / next sentence.
    func skip(by delta: Int) { jump(to: sentenceIndex + delta) }

    func jump(to index: Int) {
        guard !sentences.isEmpty else { return }
        sentenceIndex = min(max(index, 0), sentences.count - 1)
        if isPlaying {
            speak(from: sentenceIndex)
        } else {
            stopSynth()
        }
        saveProgress()
        updateNowPlaying()
    }

    func nextChapter() { if hasNextChapter { flushListeningTime(); load(chapter: chapterIndex + 1) } }
    func previousChapter() { if hasPreviousChapter { flushListeningTime(); load(chapter: chapterIndex - 1) } }

    /// `multiplier` (1 = the voice's normal speed) → utterance rate, then re-queue from the current sentence.
    func setSpeed(_ multiplier: Double) {
        AppSettings.shared.ttsSpeechRate = Self.rate(forSpeed: multiplier)
        requeueIfPlaying()
    }

    func setVoice(_ identifier: String) {
        AppSettings.shared.ttsVoiceId = identifier
        requeueIfPlaying()
    }

    /// The audio session's mixing option changed in Settings.
    func audioOptionsChanged() {
        guard isPlaying else { return }
        activateSession()
    }

    func setSleepTimer(_ timer: SleepTimer) {
        cancelSleepTimer()
        sleepTimer = timer
        guard case .at(let date) = timer else { return }
        sleepTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, date.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self else { return }
            self.sleepTimer = .off
            self.pause()
        }
    }

    private func cancelSleepTimer() {
        sleepTask?.cancel()
        sleepTask = nil
        sleepTimer = .off
    }

    private func requeueIfPlaying() {
        if isPlaying { speak(from: sentenceIndex) } else { stopSynth() }
    }

    // MARK: Speech

    private func speak(from index: Int, announce: Bool = false) {
        stopSynth()
        let synth = AVSpeechSynthesizer()
        synth.delegate = delegate
        self.synth = synth
        needsRequeue = false
        let voice = resolvedVoice()
        let rate = AppSettings.shared.ttsSpeechRate
        func enqueue(_ text: String, _ tag: Int, after: TimeInterval = 0) {
            let u = AVSpeechUtterance(string: text)
            u.rate = rate
            u.voice = voice
            u.postUtteranceDelay = after
            queued[ObjectIdentifier(u)] = tag
            synth.speak(u)
        }
        if announce, let name = chapter?.name {
            enqueue(Notation.plainText(name), -1, after: 0.5)
        }
        for j in index..<sentences.count { enqueue(sentences[j], j) }
    }

    private func stopSynth() {
        queued = [:]
        needsRequeue = true
        if synth.isSpeaking || synth.isPaused { synth.stopSpeaking(at: .immediate) }
    }

    private func didStart(_ id: ObjectIdentifier) {
        guard let j = queued[id], j >= 0 else { return }
        sentenceIndex = j
        saveProgress()
        updateNowPlaying()
        if j >= sentences.count / 2 { prepareNextChapter() }
    }

    private func didFinish(_ id: ObjectIdentifier) {
        guard let j = queued.removeValue(forKey: id), j == sentences.count - 1 else { return }
        chapterFinished()
    }

    private func chapterFinished() {
        markCurrentRead()
        flushListeningTime()
        if sleepTimer == .endOfChapter {
            sleepTimer = .off
            status = .paused
            needsRequeue = true
            updateNowPlaying()
            return
        }
        guard AppSettings.shared.ttsAutoAdvance, hasNextChapter else {
            status = .paused
            needsRequeue = true
            sentenceIndex = 0
            updateNowPlaying()
            return
        }
        load(chapter: chapterIndex + 1)
    }

    /// Next chapter via the player (auto-advance, lock screen, player buttons): announced, since the screen may
    /// be off. Downloaded chapters are read from disk; others come from the source.
    private func load(chapter index: Int) {
        guard chapters.indices.contains(index) else { return }
        stopSynth()
        let target = chapters[index]
        if let ready = prepared, ready.id == target.id {
            begin(chapter: index, sentences: ready.sentences, at: 0, announce: true)
            return
        }
        loadGeneration += 1
        let generation = loadGeneration
        status = .loading
        chapterIndex = index
        sentences = []
        sentenceIndex = 0
        chapterToken += 1
        updateNowPlaying()
        Task {
            let list = await fetchSentences(for: target)
            guard generation == self.loadGeneration, self.isActive else { return }
            guard let list else {
                self.status = .failed("Couldn't load \(Notation.plainText(target.name)).")
                self.updateNowPlaying()
                return
            }
            // Paused while it loaded: be ready, don't start talking.
            self.begin(chapter: index, sentences: list, at: 0, announce: true, autoplay: self.status == .loading)
        }
    }

    /// Halfway through a chapter, fetch and split the next one so the switch is instant — the app may be in the
    /// background then, and an app that stops making sound there gets suspended mid-fetch.
    private func prepareNextChapter() {
        guard AppSettings.shared.ttsAutoAdvance, hasNextChapter, !preparing, prepared == nil else { return }
        preparing = true
        let target = chapters[chapterIndex + 1]
        let generation = loadGeneration
        Task {
            let list = await fetchSentences(for: target)
            guard generation == self.loadGeneration else { return }
            self.preparing = false
            if let list, self.chapters.indices.contains(self.chapterIndex + 1),
               self.chapters[self.chapterIndex + 1].id == target.id {
                self.prepared = (target.id, list)
            }
        }
    }

    private func fetchSentences(for chapter: NovelChapter) async -> [String]? {
        guard let novel, let bridge else { return nil }
        let novelId = novel.id
        let path = chapter.path
        let task = UIApplication.shared.beginBackgroundTask(withName: "Listen: next chapter")
        defer { if task != .invalid { UIApplication.shared.endBackgroundTask(task) } }
        return await Task.detached(priority: .userInitiated) { () -> [String]? in
            let html = NovelDownloadStore.content(novelId: novelId, chapterPath: path) ?? bridge.parseChapter(path: path)
            guard !html.isEmpty else { return nil }
            return ListenText.sentences(fromHTML: html)
        }.value
    }

    // MARK: Voices

    private func resolvedVoice() -> AVSpeechSynthesisVoice? {
        let id = AppSettings.shared.ttsVoiceId
        if !id.isEmpty, let v = AVSpeechSynthesisVoice(identifier: id) { return v }
        return Self.bestVoice(for: language)
    }

    /// The novel's language (base code), else the phone's.
    var languageCode: String { language ?? Locale.current.language.languageCode?.identifier ?? "en" }

    /// Installed voices for a language, best quality first, without novelty voices ("Bells", "Bad News"…).
    static func voices(for language: String) -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language) && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .sorted { ($0.quality.rawValue, $1.name) > ($1.quality.rawValue, $0.name) }
    }

    /// The best installed voice for the language — Premium/Enhanced ones only exist once downloaded in iOS
    /// Settings. Today's default before S143 was always the compact voice.
    static func bestVoice(for language: String?) -> AVSpeechSynthesisVoice? {
        let lang = language ?? Locale.current.language.languageCode?.identifier ?? "en"
        let regional = Locale.current.language.region.map { "\(lang)-\($0.identifier)" }
        let all = voices(for: lang)
        let best = all.first?.quality
        return all.first { $0.quality == best && $0.language == regional } ?? all.first
            ?? AVSpeechSynthesisVoice(language: lang)
    }

    // MARK: Speed

    /// Utterance `rate` ↔ speed multiplier, measured S143 by synthesizing the same text at each rate and timing the
    /// audio (macOS Samantha; `write(_:toBufferCallback:)`). The scale is far from linear: 0.5 = 1×, 1.0 ≈ 4×.
    private static let rateCurve: [(rate: Float, speed: Double)] = [
        (0.30, 0.77), (0.35, 0.83), (0.40, 0.91), (0.50, 1.00), (0.52, 1.08), (0.55, 1.29), (0.57, 1.43),
        (0.60, 1.59), (0.62, 1.71), (0.65, 1.83), (0.70, 2.11), (0.75, 2.49), (0.80, 2.80), (0.90, 3.51), (1.00, 4.03),
    ]

    static func rate(forSpeed speed: Double) -> Float {
        let c = rateCurve
        if speed <= c[0].speed { return max(0.2, c[0].rate - Float((c[0].speed - speed) * 0.8)) }
        for i in 1..<c.count where speed <= c[i].speed {
            let t = (speed - c[i - 1].speed) / (c[i].speed - c[i - 1].speed)
            return c[i - 1].rate + Float(t) * (c[i].rate - c[i - 1].rate)
        }
        return 1
    }

    static func speed(forRate rate: Float) -> Double {
        let c = rateCurve
        if rate <= c[0].rate { return max(0.5, c[0].speed - Double(c[0].rate - rate) * 1.25) }
        for i in 1..<c.count where rate <= c[i].rate {
            let t = Double((rate - c[i - 1].rate) / (c[i].rate - c[i - 1].rate))
            return c[i - 1].speed + t * (c[i].speed - c[i - 1].speed)
        }
        return c[c.count - 1].speed
    }

    static let speedPresets: [Double] = [0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3]

    /// The preset nearest the saved rate.
    var speed: Double {
        let s = Self.speed(forRate: AppSettings.shared.ttsSpeechRate)
        return Self.speedPresets.min { abs($0 - s) < abs($1 - s) } ?? 1
    }

    // MARK: Reading state — listening counts as reading (History, Continue, progress)

    private func saveProgress() {
        guard !AppSettings.shared.isIncognito, let chapter, abs(progress - lastSavedProgress) >= 0.02 else { return }
        lastSavedProgress = progress
        let pct = progress
        let id = chapter.id
        Task.detached(priority: .background) { try? NovelQueries.updateScrollPercent(chapterId: id, percent: pct) }
    }

    private func markCurrentRead() {
        guard let novel, let chapter else { return }
        chapters[chapterIndex].isRead = true
        guard !AppSettings.shared.isIncognito else { return }
        let novelId = novel.id
        let id = chapter.id
        Task.detached(priority: .background) {
            try? NovelQueries.updateScrollPercent(chapterId: id, percent: 1)
            try? NovelQueries.markRead(chapterId: id, novelId: novelId)
        }
    }

    private func flushListeningTime() {
        guard let start = listenStart else { return }
        listenStart = nil
        let seconds = Int(Date().timeIntervalSince(start))
        guard !AppSettings.shared.isIncognito, seconds > 3, let novel, let chapter else { return }
        let novelId = novel.id
        let id = chapter.id
        Task.detached(priority: .background) {
            try? NovelQueries.addReadingTime(chapterId: id, novelId: novelId, seconds: seconds)
        }
    }

    // MARK: Audio session, lock screen, interruptions

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        let options: AVAudioSession.CategoryOptions = AppSettings.shared.ttsMixWithOthers ? [.mixWithOthers] : []
        try? session.setCategory(.playback, mode: .spokenAudio, options: options)
        try? session.setActive(true)
    }

    private func installSystemHooks() {
        guard !systemHooksInstalled else { return }
        systemHooksInstalled = true
        Self.installRemoteCommands()
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let options = AVAudioSession.InterruptionOptions(rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            MainActor.assumeIsolated { ListenPlayer.shared.interrupted(type: type, options: options) }
        }
        center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
            // Headphones unplugged / AirPods out: pause, like every audio app.
            guard reason == .oldDeviceUnavailable else { return }
            MainActor.assumeIsolated { ListenPlayer.shared.pause() }
        }
    }

    private func interrupted(type: AVAudioSession.InterruptionType?, options: AVAudioSession.InterruptionOptions) {
        switch type {
        case .began:
            resumeAfterInterruption = isPlaying
            pause()
        case .ended:
            if resumeAfterInterruption && options.contains(.shouldResume) { play() }
            resumeAfterInterruption = false
        default:
            break
        }
    }

    /// Handlers are built outside the main actor and hop to it: MediaPlayer doesn't promise which thread calls them.
    nonisolated private static func installRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        func on(_ command: MPRemoteCommand, _ action: @escaping @MainActor @Sendable () -> Void) {
            command.isEnabled = true
            command.addTarget { _ in
                Task { @MainActor in action() }
                return .success
            }
        }
        on(c.playCommand) { ListenPlayer.shared.play() }
        on(c.pauseCommand) { ListenPlayer.shared.pause() }
        on(c.togglePlayPauseCommand) { ListenPlayer.shared.togglePlayPause() }
        on(c.nextTrackCommand) { ListenPlayer.shared.nextChapter() }
        on(c.previousTrackCommand) { ListenPlayer.shared.previousChapter() }
    }

    private func updateNowPlaying() {
        guard let novel, let chapter else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        // Sentences aren't timed, so the lock screen's clock is an estimate from characters left (~18/s at 1×).
        let cps = 18 * Self.speed(forRate: AppSettings.shared.ttsSpeechRate)
        let total = Double(charOffsets.last ?? 0) / cps
        let done = Double(sentenceIndex > 0 && sentenceIndex <= charOffsets.count ? charOffsets[sentenceIndex - 1] : 0) / cps
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: Notation.plainText(chapter.name),
            MPMediaItemPropertyArtist: novel.title,
            MPMediaItemPropertyAlbumTitle: novel.title,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPMediaItemPropertyPlaybackDuration: total,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: done,
        ]
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork(for novel: Novel) {
        let novelId = novel.id
        let apply: @MainActor (UIImage) -> Void = { image in
            guard ListenPlayer.shared.novel?.id == novelId else { return }
            ListenPlayer.shared.artwork = Self.makeArtwork(image)
            ListenPlayer.shared.updateNowPlaying()
        }
        if let path = novel.resolvedCustomCoverPath, let image = UIImage(contentsOfFile: path) {
            apply(image)
        } else if let url = novel.coverURL {
            KingfisherManager.shared.retrieveImage(with: url) { result in
                guard case .success(let value) = result else { return }
                let image = value.image
                Task { @MainActor in apply(image) }
            }
        }
    }

    /// MediaPlayer calls the artwork handler on its own queue, so it must not be main-actor isolated.
    nonisolated private static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}

// MARK: - SpeechDelegate

/// AVSpeechSynthesizer calls its delegate off the main actor; events hop over by utterance identity.
nonisolated private final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    var onStart: @MainActor (ObjectIdentifier) -> Void = { _ in }
    var onFinish: @MainActor (ObjectIdentifier) -> Void = { _ in }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.onStart(id) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.onFinish(id) }
    }
}

// MARK: - ListenText

/// Chapter HTML → the sentences to speak. Paragraph breaks come from block tags; sentences from NLTokenizer.
nonisolated enum ListenText {
    static func sentences(fromHTML html: String) -> [String] {
        var text = html.replacing(/(?is)<(script|style)\b[^>]*>.*?<\/\1>/, with: " ")
        text = text.replacing(/(?i)<br\s*\/?>|<\/?(p|div|h[1-6]|li|blockquote|tr|section|article|hr|ul|ol|table)\b[^>]*>/, with: "\n")
        text = text.replacing(/<[^>]+>/, with: "")
        text = decodeEntities(text)
        var out: [String] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        for raw in text.split(separator: "\n") {
            let paragraph = raw.replacing(/\s+/, with: " ").trimmingCharacters(in: .whitespaces)
            guard paragraph.contains(where: { $0.isLetter || $0.isNumber }) else { continue }
            tokenizer.string = paragraph
            tokenizer.enumerateTokens(in: paragraph.startIndex..<paragraph.endIndex) { range, _ in
                let s = paragraph[range].trimmingCharacters(in: .whitespaces)
                if s.contains(where: { $0.isLetter || $0.isNumber }) {
                    out.append(s)
                } else if let last = out.indices.last, !s.isEmpty {
                    out[last] += s          // a lone "…" or "”" joins the sentence before it
                }
                return true
            }
        }
        return out
    }

    private static let named: [String: String] = [
        "nbsp": " ", "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "hellip": "…", "mdash": "—",
        "ndash": "–", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "laquo": "«", "raquo": "»",
        "middot": "·", "bull": "•", "deg": "°", "copy": "©", "trade": "™", "times": "×", "shy": "",
    ]

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        return text.replacing(/&(#[xX][0-9a-fA-F]+|#\d+|[a-zA-Z]+);/) { m in
            let body = String(m.1)
            if body.hasPrefix("#x") || body.hasPrefix("#X") {
                return UInt32(body.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? " "
            }
            if body.hasPrefix("#") {
                return UInt32(body.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? " "
            }
            return named[body.lowercased()] ?? " "
        }
    }
}
