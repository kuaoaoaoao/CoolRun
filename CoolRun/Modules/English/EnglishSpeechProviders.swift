import AVFoundation
import CryptoKit
import Foundation

struct EnglishSpeechRequest {
    let text: String
    let rate: Double
    let volume: Double
    let language: String
    let voice: AVSpeechSynthesisVoice?
    let kokoroVoice: String
}

@MainActor
protocol EnglishSpeechProviding: AnyObject {
    func speak(_ request: EnglishSpeechRequest) async -> Bool
    func pause()
    func resume()
    func stop()
}

@MainActor
final class SystemEnglishSpeechProvider: NSObject, EnglishSpeechProviding {
    /// `AVSpeechSynthesizer` 偶尔会在多次立即停止/重新播放后保留一个失效的内部音频队列。
    /// 每次显式停止都换一个实例，并在新语句迟迟没有启动时自动重试一次。
    private var synthesizer = AVSpeechSynthesizer()
    private var utteranceContinuation: CheckedContinuation<Bool, Never>?
    private var activeUtteranceID: ObjectIdentifier?
    private var activeRequest: EnglishSpeechRequest?
    private var startupWatchdog: Task<Void, Never>?
    private var retryCount = 0

    private static let startupTimeout: Duration = .seconds(3)

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ request: EnglishSpeechRequest) async -> Bool {
        guard !request.text.isEmpty else { return true }

        // 防御并发调用，避免新的 continuation 覆盖仍在等待的旧语句。
        if utteranceContinuation != nil {
            cancelCurrentUtterance(replacingSynthesizer: true)
        }

        return await withCheckedContinuation { continuation in
            utteranceContinuation = continuation
            activeRequest = request
            retryCount = 0
            startUtterance(request, useSelectedVoice: true)
        }
    }

    func pause() {
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .word)
        }
    }

    func resume() {
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
        }
    }

    func stop() {
        cancelCurrentUtterance(replacingSynthesizer: true)
    }

    private func finishUtterance(id: ObjectIdentifier?, success: Bool) {
        guard id == activeUtteranceID else { return }
        startupWatchdog?.cancel()
        startupWatchdog = nil
        let continuation = utteranceContinuation
        utteranceContinuation = nil
        activeUtteranceID = nil
        activeRequest = nil
        retryCount = 0
        continuation?.resume(returning: success)
    }

    private func startUtterance(_ request: EnglishSpeechRequest, useSelectedVoice: Bool) {
        startupWatchdog?.cancel()

        let utterance = AVSpeechUtterance(string: request.text)
        utterance.voice = useSelectedVoice
            ? request.voice
            : AVSpeechSynthesisVoice(language: request.language)
        utterance.rate = Float(min(max(request.rate, 0.1), 0.65))
        utterance.volume = EnglishLearningManager.playbackVolume(request.volume)
        utterance.pitchMultiplier = 1
        utterance.preUtteranceDelay = 0.08
        utterance.postUtteranceDelay = 0.15

        let id = ObjectIdentifier(utterance)
        activeUtteranceID = id
        synthesizer.speak(utterance)

        startupWatchdog = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.startupTimeout)
            } catch {
                return
            }
            self?.handleStartupTimeout(for: id)
        }
    }

    private func handleStartupTimeout(for id: ObjectIdentifier) {
        guard id == activeUtteranceID, let request = activeRequest else { return }

        if retryCount == 0 {
            retryCount = 1
            replaceSynthesizer(stoppingCurrent: true)
            // 所选系统语音资源若刚好失效，重试时让系统自动选择可用语音。
            startUtterance(request, useSelectedVoice: false)
        } else {
            finishUtterance(id: id, success: false)
            replaceSynthesizer(stoppingCurrent: true)
        }
    }

    private func cancelCurrentUtterance(replacingSynthesizer: Bool) {
        let id = activeUtteranceID
        finishUtterance(id: id, success: false)
        if replacingSynthesizer {
            replaceSynthesizer(stoppingCurrent: true)
        } else if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func replaceSynthesizer(stoppingCurrent: Bool) {
        startupWatchdog?.cancel()
        startupWatchdog = nil

        let previous = synthesizer
        previous.delegate = nil
        if stoppingCurrent, previous.isSpeaking || previous.isPaused {
            previous.stopSpeaking(at: .immediate)
        }

        let replacement = AVSpeechSynthesizer()
        replacement.delegate = self
        synthesizer = replacement
    }
}

extension SystemEnglishSpeechProvider: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard self?.activeUtteranceID == id else { return }
            self?.startupWatchdog?.cancel()
            self?.startupWatchdog = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.finishUtterance(id: id, success: true)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.finishUtterance(id: id, success: false)
        }
    }
}

@MainActor
final class KokoroEnglishSpeechProvider: NSObject, EnglishSpeechProviding {
    static let defaultVoice = "af_heart"
    static let providerVersion = "kokoro-command-v1"
    static let timeout: TimeInterval = 12

    private let settings: AppSettings
    private let cacheDirectory: URL?
    private var audioPlayer: AVAudioPlayer?
    private var playbackContinuation: CheckedContinuation<Bool, Never>?

    init(
        settings: AppSettings,
        cacheDirectory: URL?
    ) {
        self.settings = settings
        self.cacheDirectory = cacheDirectory
        super.init()
    }

    static func canAttempt(commandPath: String) -> Bool {
        let path = commandPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return !path.isEmpty && FileManager.default.isExecutableFile(atPath: path)
    }

    static func speed(for rate: Double) -> Double {
        rate <= 0.35 ? 0.82 : 1.0
    }

    static func commandArguments(
        text: String,
        voice: String,
        speed: Double,
        outputURL: URL
    ) -> [String] {
        [
            "--text", text,
            "--voice", voice,
            "--speed", String(format: "%.2f", speed),
            "--output", outputURL.path
        ]
    }

    static func cacheFileName(text: String, voice: String, speed: Double) -> String {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = "\(providerVersion)|\(voice)|\(String(format: "%.2f", speed))|\(normalized)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".wav"
    }

    func speak(_ request: EnglishSpeechRequest) async -> Bool {
        guard request.language.hasPrefix("en"),
              Self.canAttempt(commandPath: settings.englishKokoroCommandPath),
              let outputURL = cacheURL(for: request) else {
            return false
        }

        if !FileManager.default.fileExists(atPath: outputURL.path) {
            let speed = Self.speed(for: request.rate)
            let arguments = Self.commandArguments(
                text: request.text,
                voice: request.kokoroVoice,
                speed: speed,
                outputURL: outputURL
            )
            let didSynthesize = await Self.runCommand(
                commandPath: settings.englishKokoroCommandPath,
                arguments: arguments,
                timeout: Self.timeout
            )
            guard didSynthesize,
                  !Task.isCancelled,
                  FileManager.default.fileExists(atPath: outputURL.path) else {
                return false
            }
        }

        return await playAudio(at: outputURL, volume: request.volume)
    }

    func pause() {
        audioPlayer?.pause()
    }

    func resume() {
        audioPlayer?.play()
    }

    func stop() {
        let player = audioPlayer
        player?.delegate = nil
        player?.stop()
        finishPlayback(player: player, success: false)
    }

    private func cacheURL(for request: EnglishSpeechRequest) -> URL? {
        guard let cacheDirectory else { return nil }
        do {
            try FileManager.default.createDirectory(
                at: cacheDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            return nil
        }
        let speed = Self.speed(for: request.rate)
        return cacheDirectory.appendingPathComponent(
            Self.cacheFileName(text: request.text, voice: request.kokoroVoice, speed: speed)
        )
    }

    private func playAudio(at url: URL, volume: Double) async -> Bool {
        await withCheckedContinuation { continuation in
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                playbackContinuation = continuation
                audioPlayer = player
                player.delegate = self
                player.volume = EnglishLearningManager.playbackVolume(volume)
                player.prepareToPlay()
                if !player.play() {
                    finishPlayback(player: player, success: false)
                }
            } catch {
                continuation.resume(returning: false)
            }
        }
    }

    private func finishPlayback(player: AVAudioPlayer?, success: Bool) {
        if let player, player !== audioPlayer {
            return
        }
        let continuation = playbackContinuation
        playbackContinuation = nil
        audioPlayer = nil
        continuation?.resume(returning: success)
    }

    private static func runCommand(
        commandPath: String,
        arguments: [String],
        timeout: TimeInterval
    ) async -> Bool {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: commandPath)
            process.arguments = arguments

            do {
                try process.run()
            } catch {
                return false
            }

            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                try? await Task.sleep(for: .milliseconds(50))
            }

            if process.isRunning {
                process.terminate()
                return false
            }

            return process.terminationStatus == 0
        }.value
    }

    static func defaultCacheDirectory() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(GoldDataStorage.directoryName, isDirectory: true)
            .appendingPathComponent("kokoro-cache", isDirectory: true)
    }
}

extension KokoroEnglishSpeechProvider: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.finishPlayback(player: player, success: flag)
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            self?.finishPlayback(player: player, success: false)
        }
    }
}
