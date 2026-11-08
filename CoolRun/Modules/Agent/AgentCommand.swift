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

        switch head.lowercased() {
        case "clear", "清空":
            return .clear
        case "settings", "设置":
            return .openSettings
        case "help", "帮助":
            return .help
        case "tool":
            return parseTool(rest)
        default:
            break
        }

        if let recipe = recipes.first(where: { $0.slash == head }) {
            if recipe.needsInput {
                guard !rest.isEmpty else { return .unknown(recipe.inputHint ?? "还需要补一句内容") }
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

    /// 给输入框的占位提示用的命令清单。
    nonisolated static var commandHints: [String] {
        ["/体检", "/金价", "/今天", "/记 <内容>", "/提醒 30m 喝水", "/tool system_snapshot", "/help"]
    }
}
