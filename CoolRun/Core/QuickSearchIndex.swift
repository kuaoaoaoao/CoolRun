import Foundation
import SwiftUI

// MARK: - 搜索项

/// 统一搜索里的一类结果。分门别类是为了给结果上色、也让排序有个大致权重。
enum QuickSearchCategory: String, CaseIterable, Sendable {
    case module
    case recipe
    case note
    case clipboard
    case tool

    var symbol: String {
        switch self {
        case .module: return "square.grid.2x2"
        case .recipe: return "sparkles"
        case .note: return "note.text"
        case .clipboard: return "doc.on.clipboard"
        case .tool: return "wrench.and.screwdriver"
        }
    }

    /// 权重：同样命中时，场景卡排在剪贴板前面。
    nonisolated var weight: Int {
        switch self {
        case .module: return 50
        case .recipe: return 40
        case .note: return 30
        case .tool: return 20
        case .clipboard: return 10
        }
    }

    func title(_ lang: AppLanguage) -> String {
        switch self {
        case .module: return LocalizedString.l(lang, en: "Module", zh: "模块", ja: "モジュール", ko: "모듈")
        case .recipe: return LocalizedString.l(lang, en: "Action", zh: "动作", ja: "アクション", ko: "액션")
        case .note: return LocalizedString.l(lang, en: "Note", zh: "笔记", ja: "メモ", ko: "메모")
        case .clipboard: return LocalizedString.l(lang, en: "Clipboard", zh: "剪贴板", ja: "クリップボード", ko: "클립보드")
        case .tool: return LocalizedString.l(lang, en: "Tool", zh: "工具", ja: "ツール", ko: "도구")
        }
    }
}

/// 选中一条结果之后要干什么。
enum QuickSearchAction: Equatable, Sendable {
    case openModule(ViewMode)
    case openNote(UUID)
    case copyText(String)
    case runRecipe(String)
    case runTool(String)
}

struct QuickSearchItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let category: QuickSearchCategory
    /// 参与匹配的附加词（英文名、工具名、正文片段…）。标题命中优先于这里。
    let keywords: String
    let hint: String
    let action: QuickSearchAction

    nonisolated init(
        id: String,
        title: String,
        detail: String,
        symbol: String,
        category: QuickSearchCategory,
        keywords: String = "",
        hint: String = "",
        action: QuickSearchAction
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.category = category
        self.keywords = keywords
        self.hint = hint
        self.action = action
    }
}

// MARK: - 索引

@MainActor
enum QuickSearchIndex {
    /// 面板每次打开时重建。数据量在几百条这个量级，重建一次是微秒级的。
    static func build(lang: AppLanguage) -> [QuickSearchItem] {
        modules(lang: lang) + recipes() + notes() + clipboard() + tools(lang: lang)
    }

    private static func modules(lang: AppLanguage) -> [QuickSearchItem] {
        ViewMode.allCases.map { mode in
            QuickSearchItem(
                id: "module.\(mode.rawValue)",
                title: mode.displayName,
                detail: LocalizedString.l(lang, en: "Open panel", zh: "打开面板", ja: "パネルを開く", ko: "패널 열기"),
                symbol: mode.icon,
                category: .module,
                keywords: mode.rawValue,
                hint: "⌘\(mode.keyboardShortcut.character)",
                action: .openModule(mode)
            )
        }
    }

    private static func recipes() -> [QuickSearchItem] {
        AgentRecipeStore.shared.all.map { recipe in
            QuickSearchItem(
                id: "recipe.\(recipe.id)",
                title: recipe.title,
                detail: recipe.subtitle,
                symbol: recipe.symbol,
                category: .recipe,
                keywords: [recipe.slash ?? "", recipe.id, recipe.prompt].joined(separator: " "),
                hint: recipe.slash.map { "/\($0)" } ?? "",
                action: .runRecipe(recipe.id)
            )
        }
    }

    private static func notes() -> [QuickSearchItem] {
        NotesStore.shared.notes.map { note in
            let preview = note.body
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return QuickSearchItem(
                id: "note.\(note.id.uuidString)",
                title: note.title.isEmpty ? String(preview.prefix(24)) : note.title,
                detail: String(preview.prefix(70)),
                symbol: note.isPinned ? "pin.fill" : "note.text",
                category: .note,
                keywords: preview,
                hint: "",
                action: .openNote(note.id)
            )
        }
    }

    private static func clipboard() -> [QuickSearchItem] {
        // 剪贴板只放最近 80 条：再往前翻不如直接去面板里按关键词过滤。
        ClipboardHistoryStore.shared.entries.prefix(80).map { entry in
            let preview = entry.text
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return QuickSearchItem(
                id: "clip.\(entry.id.uuidString)",
                title: String(preview.prefix(48)),
                detail: String(preview.dropFirst(48).prefix(60)),
                symbol: "doc.on.clipboard",
                category: .clipboard,
                keywords: preview,
                hint: LocalizedString.l(
                    AppSettings.shared.language,
                    en: "copy", zh: "复制", ja: "コピー", ko: "복사"
                ),
                action: .copyText(entry.text)
            )
        }
    }

    private static func tools(lang: AppLanguage) -> [QuickSearchItem] {
        ToolRegistry.shared.descriptors(upTo: .dangerous).map { descriptor in
            QuickSearchItem(
                id: "tool.\(descriptor.name)",
                title: descriptor.summary,
                detail: descriptor.name,
                symbol: "wrench.and.screwdriver",
                category: .tool,
                keywords: descriptor.name,
                hint: LocalizedString.l(lang, en: "run", zh: "运行", ja: "実行", ko: "실행"),
                action: .runTool(descriptor.name)
            )
        }
    }
}

// MARK: - 排序

extension QuickSearchIndex {
    /// 打分规则：完全相等 > 前缀 > 标题包含 > 只在附加词里出现；
    /// 同分时按类别权重（模块、场景卡优先），再按标题长度（短的更准）。
    nonisolated static func rank(
        _ items: [QuickSearchItem],
        query: String,
        limit: Int = 40
    ) -> [QuickSearchItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else {
            return Array(items.prefix(limit))
        }

        var scored: [(item: QuickSearchItem, score: Int)] = []
        for item in items {
            let title = item.title.lowercased()
            let keywords = item.keywords.lowercased()

            var score = 0
            if title == needle {
                score = 1000
            } else if title.hasPrefix(needle) {
                score = 700
            } else if title.contains(needle) {
                score = 500
            } else if keywords.contains(needle) {
                score = 200
            } else if needle.count >= 2, matchesByPieces(item: item, needle: needle) {
                // 「电脑 体检」这种多词查询：每个词都命中才算数。
                score = 120
            }

            guard score > 0 else { continue }
            scored.append((item, score))
        }

        // 类别权重只用来打平手，不参与和命中质量相加：
        // 否则「标题完全相等但属于剪贴板」会被「标题前缀匹配的模块」挤下去。
        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.item.category.weight != rhs.item.category.weight {
                    return lhs.item.category.weight > rhs.item.category.weight
                }
                if lhs.item.title.count != rhs.item.title.count {
                    return lhs.item.title.count < rhs.item.title.count
                }
                return lhs.item.id < rhs.item.id
            }
            .prefix(limit)
            .map(\.item)
    }

    /// 空格分隔的多词查询：所有词都要出现在标题或附加词里。
    nonisolated private static func matchesByPieces(item: QuickSearchItem, needle: String) -> Bool {
        let pieces = needle.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard pieces.count > 1 else { return false }
        let haystack = (item.title + " " + item.keywords).lowercased()
        return pieces.allSatisfy { haystack.contains($0) }
    }
}
