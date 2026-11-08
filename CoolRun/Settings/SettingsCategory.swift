import Foundation

// MARK: - 设置分类

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general = "general"
    case monitors = "monitors"
    case reminders = "reminders"
    case menubar = "menubar"
    case english = "english"
    case ai = "ai"
    case plugins = "plugins"
    case data = "data"
    case about = "about"

    var id: String { rawValue }

    func displayName(lang: AppLanguage) -> String {
        switch self {
        case .general: return LocalizedString.l(lang, en: "General", zh: "通用", ja: "一般", ko: "일반")
        case .monitors: return LocalizedString.l(lang, en: "Monitors", zh: "监控", ja: "監視", ko: "모니터")
        case .reminders: return LocalizedString.l(lang, en: "Reminders", zh: "提醒", ja: "通知", ko: "알림")
        case .menubar: return LocalizedString.l(lang, en: "Menu Bar", zh: "菜单栏", ja: "メニュー", ko: "메뉴 막대")
        case .english: return LocalizedString.l(lang, en: "English", zh: "英语", ja: "英語", ko: "영어")
        case .ai: return LocalizedString.l(lang, en: "AI Assistant", zh: "AI 助手", ja: "AI アシスタント", ko: "AI 도우미")
        case .plugins: return LocalizedString.l(lang, en: "Plugins", zh: "插件", ja: "プラグイン", ko: "플러그인")
        case .data: return LocalizedString.l(lang, en: "Data", zh: "数据", ja: "データ", ko: "데이터")
        case .about: return LocalizedString.l(lang, en: "About", zh: "关于", ja: "情報", ko: "정보")
        }
    }

    func subtitle(lang: AppLanguage) -> String {
        switch self {
        case .general:
            return LocalizedString.l(lang, en: "Language, startup and privacy", zh: "语言、启动与隐私", ja: "言語、起動、プライバシー", ko: "언어, 시작 및 개인정보")
        case .monitors:
            return LocalizedString.l(lang, en: "Choose metrics and sampling speed", zh: "选择指标与采样速度", ja: "指標とサンプリング速度", ko: "지표 및 샘플링 속도")
        case .reminders:
            return LocalizedString.l(lang, en: "Dates, study and system attention", zh: "日期、学习与系统异常提醒", ja: "日付、学習、システム通知", ko: "날짜, 학습 및 시스템 알림")
        case .menubar:
            return LocalizedString.l(lang, en: "Control the menu bar at a glance", zh: "控制菜单栏的显示方式", ja: "メニューバーの表示を管理", ko: "메뉴 막대 표시 관리")
        case .english:
            return LocalizedString.l(lang, en: "Voice, content and study goals", zh: "语音、内容与学习目标", ja: "音声、教材、学習目標", ko: "음성, 콘텐츠 및 학습 목표")
        case .ai:
            return LocalizedString.l(lang, en: "Model provider and API key", zh: "模型服务商与 API Key", ja: "モデルプロバイダとAPIキー", ko: "모델 제공자 및 API 키")
        case .plugins:
            return LocalizedString.l(lang, en: "Install local plugins and manage what they can touch", zh: "本地安装插件，管理它们能用什么", ja: "ローカルプラグインの管理", ko: "로컬 플러그인 관리")
        case .data:
            return LocalizedString.l(lang, en: "Backup, restore and updates", zh: "备份、恢复与更新", ja: "バックアップ、復元、更新", ko: "백업, 복원 및 업데이트")
        case .about:
            return LocalizedString.l(lang, en: "Version and project information", zh: "版本与项目信息", ja: "バージョンとプロジェクト情報", ko: "버전 및 프로젝트 정보")
        }
    }

    var icon: String {
        switch self {
        case .general: return "gear"
        case .monitors: return "chart.bar.fill"
        case .reminders: return "bell.badge.fill"
        case .menubar: return "menubar.rectangle"
        case .english: return "character.book.closed"
        case .ai: return "brain.head.profile"
        case .plugins: return "puzzlepiece.extension"
        case .data: return "icloud.and.arrow.down"
        case .about: return "info.circle"
        }
    }
}
