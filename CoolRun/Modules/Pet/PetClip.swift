import Foundation

// MARK: - 片段

/// 桌宠的动作片段。
///
/// 素材来自 `dsh-pet` 插件（同一只蓝色大肥鱼），由 `scripts/pet-clips.sh`
/// 把它的 VP9-alpha 视频转成 Apple 认的 HEVC-with-alpha 再塞进 bundle。
///
/// 为什么要转格式：插件跑在 Electron 里能直接播 webm，原生 App 的
/// AVFoundation 不认 VP9，只认 hvc1 + ALPHA_MODE=1。
enum PetClip: String, CaseIterable, Sendable {
    case idle
    case idleAlt
    case lookAround
    case drag
    case clickHappy
    case clickShy
    case clickAngry
    case clickTickle
    case clickWave
    case walkCrab
    case run
    case sleepStart
    case sleepLoop
    case wake
    case workBusy
    case workThink
    case workArchive
    case workPace
    case workCelebrate
    case workTired
    case thinking
    case eatRice
    case yawn
    case stretch
    case startled
    case whale

    /// 素材文件在 bundle 里的名字（`scripts/pet-clips.sh` 里的左列）。
    nonisolated var resourceName: String { rawValue }

    /// 循环播放还是播完就回待机。
    ///
    /// 循环的只有「一直处于某个状态」的那几个（待机、睡觉、干活、被拎着），
    /// 其余都是一次性动作，播完交回 `PetModel` 决定下一步。
    nonisolated var loops: Bool {
        switch self {
        case .idle, .idleAlt, .drag, .sleepLoop,
             .workBusy, .workThink, .workArchive, .workPace, .workTired, .thinking:
            return true
        default:
            return false
        }
    }

    /// 点一下她时随机挑一个回应。
    nonisolated static let clickResponses: [PetClip] = [
        .clickHappy, .clickShy, .clickAngry, .clickTickle, .clickWave,
    ]

    /// 走两步用的片段。
    nonisolated static let walkClips: [PetClip] = [.walkCrab, .idleAlt, .run]

    /// bundle 里到底有没有这个片段。
    ///
    /// 轻量包可能不带素材（或者用户自己删了），所以每次都要问一下，
    /// 缺了就退回原来的立绘合成动画，不能白屏。
    nonisolated var isBundled: Bool {
        Bundle.main.url(forResource: resourceName, withExtension: "mov") != nil
    }

    nonisolated var url: URL? {
        Bundle.main.url(forResource: resourceName, withExtension: "mov")
    }
}
