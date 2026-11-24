import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case chinese = "zh"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chinese: return "简体中文"  // i18n-allow: 语言自称：每种语言用本语言名显示
        case .english: return "English"
        case .japanese: return "日本語"  // i18n-allow: 语言自称：每种语言用本语言名显示
        case .korean: return "한국어"
        }
    }

    var locale: Locale {
        Locale(identifier: rawValue)
    }
}

// MARK: - 菜单栏显示模式

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case goldPrice = "gold_price"
    case date = "date"
    case cpu = "cpu"
    case memory = "memory"
    case network = "network"
    case english = "english"
    case countdown = "countdown"

    var id: String { rawValue }

    func displayName(lang: AppLanguage? = nil) -> String {
        let currentLang = lang ?? AppSettings.shared.language
        switch self {
        case .goldPrice:
            return LocalizedString.l(currentLang, en: "Gold Price", zh: "金价", ja: "金価格", ko: "금 가격")
        case .date:
            return LocalizedString.l(currentLang, en: "Date", zh: "日期", ja: "日付", ko: "날짜")
        case .cpu:
            return LocalizedString.l(currentLang, en: "CPU Usage", zh: "CPU 占用", ja: "CPU 使用率", ko: "CPU 사용률")
        case .memory:
            return LocalizedString.l(currentLang, en: "Memory Usage", zh: "内存占用", ja: "メモリ使用率", ko: "메모리 사용량")
        case .network:
            return LocalizedString.l(currentLang, en: "Network Speed", zh: "实时网速", ja: "ネットワーク速度", ko: "네트워크 속도")
        case .english:
            return LocalizedString.l(currentLang, en: "English Learning", zh: "英语学习", ja: "英語学習", ko: "영어 학습")
        case .countdown:
            return LocalizedString.l(currentLang, en: "Countdown", zh: "倒数日", ja: "カウントダウン", ko: "카운트다운")
        }
    }

    var icon: String {
        switch self {
        case .goldPrice: return "chart.line.uptrend.xyaxis"
        case .date: return "calendar"
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .network: return "arrow.up.arrow.down.circle"
        case .english: return "character.book.closed"
        case .countdown: return "timer"
        }
    }
}

enum MenuBarCompositionStyle: String, CaseIterable, Identifiable {
    case single
    case pair
    case rotation

    var id: String { rawValue }

    func displayName(lang: AppLanguage) -> String {
        switch self {
        case .single:
            return LocalizedString.l(lang, en: "Single", zh: "单项", ja: "単一", ko: "단일")
        case .pair:
            return LocalizedString.l(lang, en: "Compact Pair", zh: "双项紧凑", ja: "コンパクト2項目", ko: "압축 2개")
        case .rotation:
            return LocalizedString.l(lang, en: "Rotate", zh: "定时轮播", ja: "切り替え", ko: "순환")
        }
    }
}

// MARK: - 刷新与动画策略

enum SystemRefreshRate: String, CaseIterable, Identifiable {
    case realtime
    case balanced
    case energySaving = "energy_saving"

    var id: String { rawValue }

    var duration: Duration {
        switch self {
        case .realtime: return .seconds(1)
        case .balanced: return .seconds(2)
        case .energySaving: return .seconds(5)
        }
    }

    func displayName(lang: AppLanguage) -> String {
        switch self {
        case .realtime: return LocalizedString.l(lang, en: "Real-time (1s)", zh: "实时（1 秒）", ja: "リアルタイム（1秒）", ko: "실시간(1초)")
        case .balanced: return LocalizedString.l(lang, en: "Balanced (2s)", zh: "均衡（2 秒）", ja: "バランス（2秒）", ko: "균형(2초)")
        case .energySaving: return LocalizedString.l(lang, en: "Energy Saving (5s)", zh: "节能（5 秒）", ja: "省電力（5秒）", ko: "절전(5초)")
        }
    }
}

enum MenuBarAnimationRate: String, CaseIterable, Identifiable {
    case off
    case energySaving = "energy_saving"
    case smooth

    var id: String { rawValue }

    var framesPerSecond: Double? {
        switch self {
        case .off: return nil
        case .energySaving: return 8
        case .smooth: return 20
        }
    }

    func displayName(lang: AppLanguage) -> String {
        switch self {
        case .off: return LocalizedString.l(lang, en: "Off", zh: "关闭", ja: "オフ", ko: "끄기")
        case .energySaving: return LocalizedString.l(lang, en: "Energy Saving (8 FPS)", zh: "节能（8 FPS）", ja: "省電力（8 FPS）", ko: "절전(8 FPS)")
        case .smooth: return LocalizedString.l(lang, en: "Smooth (20 FPS)", zh: "流畅（20 FPS）", ja: "なめらか（20 FPS）", ko: "부드럽게(20 FPS)")
        }
    }
}

enum MenuBarCoinMotion: String, CaseIterable, Identifiable {
    case classicFlip = "classic_flip"
    case luckyBounce = "lucky_bounce"
    case coinToss = "coin_toss"
    case rolling = "rolling"
    case shimmer = "shimmer"

    var id: String { rawValue }

    var speedMultiplier: Double {
        switch self {
        case .classicFlip: return 1
        case .luckyBounce: return 0.82
        case .coinToss: return 0.68
        case .rolling: return 0.74
        case .shimmer: return 0.46
        }
    }

    func displayName(lang: AppLanguage) -> String {
        switch self {
        case .classicFlip:
            return LocalizedString.l(lang, en: "Classic Flip", zh: "经典翻面", ja: "クラシック反転", ko: "클래식 뒤집기")
        case .luckyBounce:
            return LocalizedString.l(lang, en: "Lucky Bounce", zh: "招财弹跳", ja: "幸運バウンド", ko: "행운 바운스")
        case .coinToss:
            return LocalizedString.l(lang, en: "Coin Toss", zh: "抛金币", ja: "コイントス", ko: "동전 던지기")
        case .rolling:
            return LocalizedString.l(lang, en: "Rolling Coin", zh: "金币滚动", ja: "コインロール", ko: "동전 굴리기")
        case .shimmer:
            return LocalizedString.l(lang, en: "Golden Shimmer", zh: "金光闪闪", ja: "金色のきらめき", ko: "황금 반짝임")
        }
    }
}

enum MenuBarCoinAppearance: String, CaseIterable, Identifiable {
    case yuan
    case lucky
    case rising
    case ancient
    case starlight

    var id: String { rawValue }

    func displayName(lang: AppLanguage) -> String {
        switch self {
        case .yuan:
            return LocalizedString.l(lang, en: "Yuan Coin", zh: "人民币金币", ja: "元コイン", ko: "위안 금화")
        case .lucky:
            return LocalizedString.l(lang, en: "Lucky Coin", zh: "招财福币", ja: "招福コイン", ko: "행운 복주화")
        case .rising:
            return LocalizedString.l(lang, en: "Rising Coin", zh: "上涨金币", ja: "上昇コイン", ko: "상승 금화")
        case .ancient:
            return LocalizedString.l(lang, en: "Ancient Coin", zh: "方孔古钱", ja: "古銭", ko: "옛날 엽전")
        case .starlight:
            return LocalizedString.l(lang, en: "Starlight Coin", zh: "星光金币", ja: "星光コイン", ko: "별빛 금화")
        }
    }
}

enum GoldRefreshRate: String, CaseIterable, Identifiable {
    case seconds30 = "30_seconds"
    case minute = "1_minute"
    case minutes5 = "5_minutes"

    var id: String { rawValue }

    var duration: Duration {
        switch self {
        case .seconds30: return .seconds(30)
        case .minute: return .seconds(60)
        case .minutes5: return .seconds(300)
        }
    }

    func displayName(lang: AppLanguage) -> String {
        switch self {
        case .seconds30: return LocalizedString.l(lang, en: "30 seconds", zh: "30 秒", ja: "30秒", ko: "30초")
        case .minute: return LocalizedString.l(lang, en: "1 minute", zh: "1 分钟", ja: "1分", ko: "1분")
        case .minutes5: return LocalizedString.l(lang, en: "5 minutes", zh: "5 分钟", ja: "5分", ko: "5분")
        }
    }
}
