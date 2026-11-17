import Foundation

/// 输入框里以 `/` 开头的指令，本地解析，不走模型。
enum AgentCommand: Equatable {
    /// 展开成一段提示词发给模型。
    case send(String)
    /// 直接执行某个工具，不经过模型。
    case runTool(name: String, arguments: JSONValue)
    case clear
    case openSettings
    case help
    /// 认不出来的斜杠词，界面提示可用命令。
    case unknown(String)
}

enum AgentCommandParser {
    /// 不是斜杠指令时返回 nil，调用方按普通消息处理。
    nonisolated static func parse(_ raw: String, recipes: [AgentRecipe]) -> AgentCommand? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }

        let body = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return .help }

        let parts = body.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let head = String(parts.first ?? "")
        let rest = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""

        let word = head.lowercased()
        if Self.aliases(en: "clear", zh: "清空", ja: "クリア", ko: "지우기").contains(word) {
            return .clear
        }
        if Self.aliases(en: "settings", zh: "设置", ja: "設定", ko: "설정").contains(word) {
            return .openSettings
        }
        if Self.aliases(en: "help", zh: "帮助", ja: "ヘルプ", ko: "도움말").contains(word) {
            return .help
        }
        if word == "tool" {
            return parseTool(rest)
        }

        if let recipe = recipes.first(where: { $0.slash == head }) {
            if recipe.needsInput {
                guard !rest.isEmpty else { return .unknown(head) }
                return .send(recipe.prompt + "\n" + rest)
            }
            return .send(recipe.prompt)
        }

        // 也允许用场景 id 触发，方便插件生成的场景。
        if let recipe = recipes.first(where: { $0.id == head }) {
            return .send(recipe.prompt + (rest.isEmpty ? "" : "\n" + rest))
        }

        return .unknown(head)
    }

    private nonisolated static func parseTool(_ rest: String) -> AgentCommand {
        guard !rest.isEmpty else {
            return .runTool(name: "", arguments: .object([:]))
        }
        let pieces = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let name = String(pieces.first ?? "")
        let jsonText = pieces.count > 1 ? String(pieces[1]) : ""
        let arguments = jsonText.isEmpty ? JSONValue.object([:]) : (JSONValue.parse(jsonText) ?? .object([:]))
        return .runTool(name: name, arguments: arguments)
    }

    /// 四种语言都能用的命令别名 —— 界面语言换了，用户可能仍按母语输入。
    private nonisolated static func aliases(
        en: String,
        zh: String,
        ja: String,
        ko: String
    ) -> Set<String> {
        Set(AppLanguage.allCases.map {
            LocalizedString.l($0, en: en, zh: zh, ja: ja, ko: ko).lowercased()
        })
    }

    /// 给输入框的占位提示用的命令清单（场景的斜杠别名由调用方从场景列表补上）。
    nonisolated static var commandHints: [String] {
        ["/tool system_snapshot", "/help"]
    }
}
