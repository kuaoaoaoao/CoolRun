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

    // 吃什么
    case eatTangyuan
    case eatZongzi
    case eatWatermelon
    case eatIceCream
    case eatHotpot
    case eatTanghulu
    case eatDumpling
    case eatNianGao

    // 时节（按日期挑，见 `seasonal(for:)`）
    case mooncake
    case snowman
    case christmasTree
    case pumpkin
    case fu
    case redPacket
    case skyLantern
    case leaves

    // 碎碎念
    case daydream
    case screenTalk
    case wipeTable

    // 自己玩
    case cat
    case code
    case ghost
    case bubbles
    case tailSlam

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

    /// 所有片段都是 10 秒（插件那边就是这么做的），一次性动作按它算时长。
    nonisolated static let typicalDuration: Double = 10

    /// 吃的。她最爱米饭，所以吃白饭不在这张表里——那个有专门的触发。
    nonisolated static let eatClips: [PetClip] = [
        .eatTangyuan, .eatZongzi, .eatWatermelon, .eatIceCream,
        .eatHotpot, .eatTanghulu, .eatDumpling, .eatNianGao,
    ]

    /// 自己玩 / 碎碎念。
    nonisolated static let playClips: [PetClip] = [
        .cat, .code, .ghost, .bubbles, .tailSlam,
        .daydream, .screenTalk, .wipeTable,
    ]

    /// 按日子挑一个应景的。没有应景的就返回 nil。
    ///
    /// 只认几个大日子，不追求全：中秋吃月饼、过年写福字收红包、圣诞装点树、
    /// 万圣节讨糖、元宵放灯、冬天堆雪人、秋天被落叶埋。
    nonisolated static func seasonal(for date: Date) -> PetClip? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.month, .day], from: date)
        guard let month = parts.month, let day = parts.day else { return nil }

        switch (month, day) {
        // 元旦
        case (1, 1...3): return .fu
        // 春节前后（按公历粗略覆盖 1 月下旬到 2 月中旬）
        case (1, 20...31), (2, 1...18): return .redPacket
        // 元宵
        case (2, 19...29), (3, 1...5): return .skyLantern
        // 春天
        case (3, 6...31), (4, 1...30), (5, 1...31): return .leaves
        // 端午
        case (6, 1...30): return .eatZongzi
        // 盛夏
        case (7, 1...31), (8, 1...20): return .eatWatermelon
        // 初秋
        case (8, 21...31), (9, 1...14): return .leaves
        // 中秋（公历 9 月中旬到 10 月上旬）
        case (9, 15...30), (10, 1...8): return .mooncake
        // 深秋
        case (10, 9...24), (11, 1...30): return .leaves
        // 万圣节
        case (10, 25...31): return .pumpkin
        // 圣诞
        case (12, 1...25): return .christmasTree
        // 冬天
        case (12, 26...31), (1, 4...19), (2, 19...28): return .snowman
        default: return nil
        }
    }

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
