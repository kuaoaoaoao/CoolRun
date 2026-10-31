import AppKit
import AVFoundation
import Combine
import Foundation

@MainActor
final class EnglishLearningManager: NSObject, ObservableObject {
    static let shared = EnglishLearningManager()

    @Published private(set) var state: SpeechState = .idle
    @Published private(set) var category: EnglishLearningCategory = .words
    @Published private(set) var currentItem: EnglishLearningItem?
    @Published private(set) var currentSpokenText = ""
    @Published private(set) var currentIndex = 0
    @Published private(set) var queueCount = 0
    @Published private(set) var isContinuous = false

    private let repository: EnglishContentRepository
    private let textbookStore: EnglishTextbookStore
    private let progressStore: EnglishProgressStore
    private let settings: AppSettings
    private let systemSpeechProvider: EnglishSpeechProviding
    private let kokoroSpeechProvider: EnglishSpeechProviding
    private var queue: [EnglishLearningItem] = []
    private var sessionTask: Task<Void, Never>?
    private var sessionID = UUID()
    private weak var activeSpeechProvider: EnglishSpeechProviding?
    private var isSlowPlayback = false
    private var cancellables: Set<AnyCancellable> = []

    var menuBarText: String {
        let isIdle = state == .idle
        let fallback = textbookStore.dailyWord()
        let item = isIdle ? fallback : (currentItem ?? fallback)
        return item.menuBarText(
            style: settings.englishMenuTextStyle,
            activeSegment: isIdle || currentSpokenText.isEmpty ? nil : currentSpokenText
        )
    }

    var currentProgress: EnglishItemProgress {
        guard let currentItem else { return EnglishItemProgress() }
        return progressStore.progress(for: currentItem.id)
    }

    var positionText: String {
        guard queueCount > 0 else { return "0 / 0" }
        return "\(currentIndex + 1) / \(queueCount)"
    }

    convenience override init() {
        self.init(
            repository: .shared,
            progressStore: .shared,
            settings: .shared
        )
    }

    init(
        repository: EnglishContentRepository,
        textbookStore: EnglishTextbookStore? = nil,
        progressStore: EnglishProgressStore,
        settings: AppSettings,
        systemSpeechProvider: EnglishSpeechProviding? = nil,
        kokoroSpeechProvider: EnglishSpeechProviding? = nil
    ) {
        self.repository = repository
        self.textbookStore = textbookStore ?? .shared
        self.progressStore = progressStore
        self.settings = settings
        self.systemSpeechProvider = systemSpeechProvider ?? SystemEnglishSpeechProvider()
        self.kokoroSpeechProvider = kokoroSpeechProvider ?? KokoroEnglishSpeechProvider(
            settings: settings,
            cacheDirectory: KokoroEnglishSpeechProvider.defaultCacheDirectory()
        )
        super.init()
        rebuildQueue(keepingItemID: self.textbookStore.dailyWord().id)
        self.textbookStore.$selectedTextbookID
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.stop()
                self?.refreshQueue()
            }
            .store(in: &cancellables)
    }

    static func availableVoices(for accent: EnglishAccent) -> [AVSpeechSynthesisVoice] {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let matchingVoices = voices.filter { $0.language == accent.rawValue }
        let fallbackVoices = voices.filter { $0.language.hasPrefix("en-") }
        return (matchingVoices.isEmpty ? fallbackVoices : matchingVoices)
            .sorted {
                if $0.quality != $1.quality { return $0.quality.rawValue > $1.quality.rawValue }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    static func playbackVolume(_ value: Double) -> Float {
        Float(min(max(value, 0.1), 1))
    }

    /// 当前口音+用户偏好下真正会用到的英语语音（跟 speak 走同一套逻辑）。
    var currentEnglishVoice: AVSpeechSynthesisVoice? {
        selectedVoice(language: settings.englishAccent.rawValue)
    }

    /// 当前英语语音是不是压缩版（听起来最机械的一档）。
    var needsHigherQualityEnglishVoice: Bool {
        guard let voice = currentEnglishVoice else { return false }
        return voice.quality == .default
    }

    /// 用于 UI 展示的语音质量标签。
    static func qualityLabel(for voice: AVSpeechSynthesisVoice?) -> String {
        guard let voice else { return "未选择" }
        switch voice.quality {
        case .premium: return "Premium"
        case .enhanced: return "Enhanced"
        default: return "压缩版"
        }
    }

    /// 跳转到 macOS 系统设置里管理/下载语音的页面。
    /// 不同 macOS 版本 URL scheme 不一样，按可用性依次尝试，最后兜底打开系统设置。
    static func openSystemVoiceDownloadSettings() {
        let candidates = [
            // macOS 13+：辅助功能 → 朗读内容
            "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?SpokenContent",
            // 旧版 Ventura
            "x-apple.systempreferences:com.apple.preference.universalaccess?SpokenContent",
            // 语音设置面板
            "x-apple.systempreferences:com.apple.Speech-Settings.extension"
        ]
        for str in candidates {
            if let url = URL(string: str), NSWorkspace.shared.open(url) {
                return
            }
        }
        _ = NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    func selectCategory(_ newCategory: EnglishLearningCategory) {
        guard category != newCategory else { return }
        stop()
        category = newCategory
        let preferredID = newCategory == .daily ? repository.dailyQuote().id : nil
        rebuildQueue(keepingItemID: preferredID)
        markCurrentViewed()
    }

    func markCurrentViewed() {
        guard let currentItem else { return }
        progressStore.recordShown(currentItem.id)
        objectWillChange.send()
    }

    func toggleContinuousPlayback() {
        switch state {
        case .idle:
            startContinuousPlayback()
        case .playing:
            pause()
        case .paused:
            resume()
        }
    }

    func startContinuousPlayback() {
        guard currentItem != nil else { return }
        startSession(continuous: true, slow: false)
    }

    func replay(slow: Bool = false) {
        guard currentItem != nil else { return }
        startSession(continuous: false, slow: slow)
    }

    func pause() {
        guard state == .playing else { return }
        state = .paused
        activeSpeechProvider?.pause()
    }

    func resume() {
        guard state == .paused else { return }
        state = .playing
        activeSpeechProvider?.resume()
    }

    func stop() {
        sessionID = UUID()
        sessionTask?.cancel()
        sessionTask = nil
        isContinuous = false
        isSlowPlayback = false
        state = .idle
        currentSpokenText = ""
        stopUtterance()
    }

    func next() {
        move(by: 1)
    }

    func previous() {
        move(by: -1)
    }

    func markUnfamiliar() {
        guard let currentItem else { return }
        progressStore.setMastery(.unfamiliar, for: currentItem.id)
        objectWillChange.send()
        next()
    }

    func markKnown() {
        guard let currentItem else { return }
        let existing = progressStore.progress(for: currentItem.id).mastery
        progressStore.setMastery(existing >= .familiar ? .mastered : .familiar, for: currentItem.id)
        objectWillChange.send()
        next()
    }

    func toggleFavorite() {
        guard let currentItem else { return }
        progressStore.toggleFavorite(currentItem.id)
        objectWillChange.send()
    }

    func refreshQueue(on date: Date = Date(), calendar: Calendar = .current) {
        let preferredID = category == .daily
            ? repository.dailyQuote(on: date, calendar: calendar).id
            : currentItem?.id
        rebuildQueue(keepingItemID: preferredID, on: date, calendar: calendar)
    }

    private func move(by offset: Int) {
        guard !queue.isEmpty else { return }
        let wasActive = state != .idle
        let wasContinuous = isContinuous
        let wasSlowPlayback = isSlowPlayback
        sessionID = UUID()
        sessionTask?.cancel()
        stopUtterance()
        currentIndex = (currentIndex + offset + queue.count) % queue.count
        currentItem = queue[currentIndex]
        currentSpokenText = ""
        markCurrentViewed()
        if wasActive {
            startSession(continuous: wasContinuous, slow: wasSlowPlayback)
        } else {
            state = .idle
        }
    }

    private func rebuildQueue(
        keepingItemID itemID: String?,
        on date: Date = Date(),
        calendar: Calendar = .current
    ) {
        if category == .words {
            queue = textbookStore.orderedWords(
                progress: progressStore.records,
                on: date,
                calendar: calendar
            )
        } else {
            queue = repository.orderedItems(
                for: category,
                stage: settings.englishStage,
                progress: progressStore.records,
                on: date,
                calendar: calendar
            )
        }
        queueCount = queue.count
        guard !queue.isEmpty else {
            currentIndex = 0
            currentItem = nil
            return
        }
        currentIndex = itemID.flatMap { id in queue.firstIndex { $0.id == id } } ?? 0
        currentItem = queue[currentIndex]
    }

    private func startSession(continuous: Bool, slow: Bool) {
        sessionID = UUID()
        let id = sessionID
        sessionTask?.cancel()
        stopUtterance()
        isContinuous = continuous
        isSlowPlayback = slow
        state = .playing
        sessionTask = Task { [weak self] in
            await self?.runSession(id: id, continuous: continuous, slow: slow)
        }
    }

    private func runSession(id: UUID, continuous: Bool, slow: Bool) async {
        defer {
            if id == sessionID {
                currentSpokenText = ""
                state = .idle
                isContinuous = false
                isSlowPlayback = false
                sessionTask = nil
            }
        }

        while isValidSession(id) {
            guard let item = currentItem else { break }
            progressStore.recordShown(item.id)

            let repeatCount = continuous ? max(1, settings.englishRepeatCount) : 1
            let rate = slow ? settings.englishSlowRate : settings.englishNormalRate

            for _ in 0..<repeatCount {
                for segment in item.speechSegments {
                    guard await waitUntilPlaying(id: id) else { return }
                    currentSpokenText = segment
                    guard await speak(
                        segment,
                        rate: rate,
                        language: settings.englishAccent.rawValue,
                        sessionID: id
                    ),
                          isValidSession(id) else { return }
                }
            }

            if settings.englishSpeakTranslation, !item.translation.isEmpty {
                guard await waitUntilPlaying(id: id) else { return }
                currentSpokenText = item.translation
                guard await speak(
                    item.translation,
                    rate: min(rate, 0.42),
                    language: "zh-CN",
                    sessionID: id
                ),
                      isValidSession(id) else { return }
            }

            progressStore.recordListened(item.id)
            objectWillChange.send()

            guard continuous else { return }

            do {
                try await Task.sleep(for: .seconds(max(1, settings.englishItemInterval)))
            } catch {
                return
            }
            guard await waitUntilPlaying(id: id), isValidSession(id), !queue.isEmpty else { return }
            currentIndex = (currentIndex + 1) % queue.count
            currentItem = queue[currentIndex]
            currentSpokenText = ""
        }
    }

    private func waitUntilPlaying(id: UUID) async -> Bool {
        while isValidSession(id), state == .paused {
            do {
                try await Task.sleep(for: .milliseconds(150))
            } catch {
                return false
            }
        }
        return isValidSession(id) && state == .playing
    }

    private func speak(_ text: String, rate: Double, language: String, sessionID id: UUID) async -> Bool {
        guard !text.isEmpty else { return true }
        guard isValidSession(id) else { return false }
        let request = EnglishSpeechRequest(
            text: text,
            rate: rate,
            volume: settings.englishVolume,
            language: language,
            voice: selectedVoice(language: language),
            kokoroVoice: settings.englishKokoroVoice
        )

        if language.hasPrefix("en"), settings.englishTTSBackend == .kokoro {
            activeSpeechProvider = kokoroSpeechProvider
            let didSpeak = await kokoroSpeechProvider.speak(request)
            guard isValidSession(id) else { return false }
            clearActiveProvider(kokoroSpeechProvider, for: id)
            if didSpeak {
                return true
            }
        }

        guard isValidSession(id) else { return false }
        activeSpeechProvider = systemSpeechProvider
        let didSpeak = await systemSpeechProvider.speak(request)
        guard isValidSession(id) else { return false }
        clearActiveProvider(systemSpeechProvider, for: id)
        return didSpeak
    }

    private func clearActiveProvider(_ provider: EnglishSpeechProviding, for id: UUID) {
        guard id == sessionID, activeSpeechProvider === provider else { return }
        activeSpeechProvider = nil
    }

    private func selectedVoice(language: String) -> AVSpeechSynthesisVoice? {
        if language.hasPrefix("zh") {
            return AVSpeechSynthesisVoice.speechVoices()
                .filter { $0.language.hasPrefix("zh") }
                .max { $0.quality.rawValue < $1.quality.rawValue }
                ?? AVSpeechSynthesisVoice(language: language)
        }
        if !settings.englishVoiceIdentifier.isEmpty,
           let selected = AVSpeechSynthesisVoice(identifier: settings.englishVoiceIdentifier),
           selected.language == settings.englishAccent.rawValue {
            return selected
        }
        return Self.availableVoices(for: settings.englishAccent).first
            ?? AVSpeechSynthesisVoice(language: settings.englishAccent.rawValue)
            ?? AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix("en-") }
    }

    private func stopUtterance() {
        systemSpeechProvider.stop()
        kokoroSpeechProvider.stop()
        activeSpeechProvider = nil
    }

    private func isValidSession(_ id: UUID) -> Bool {
        id == sessionID && !Task.isCancelled
    }
}
