import Foundation

// MARK: - 文本形式的工具调用兜底

/// 有些模型不按 `tool_calls` 字段返回，而是把调用写进正文：
///
///     <tool_call>{"name":"gold_technical","arguments":{}}</tool_call>
///
/// 或者干脆吐一段 JSON。不处理的话引擎会把它当成最终回答，用户看到一堆标签。
/// 这里把正文里的 JSON 对象扫出来，名字对得上注册表就还原成一次真正的调用。
enum AgentToolCallParser {

    static func parse(_ text: String, known: Set<String>) -> [AgentToolCall] {
        var results: [AgentToolCall] = []
        for candidate in jsonObjects(in: text) {
            guard let data = candidate.data(using: .utf8),
                  let value = try? JSONDecoder().decode(JSONValue.self, from: data),
                  case .object(let dictionary) = value
            else { continue }

            let name = dictionary["name"]?.stringValue
                ?? dictionary["tool"]?.stringValue
                ?? dictionary["tool_name"]?.stringValue
            guard let name, known.contains(name) else { continue }

            let arguments = dictionary["arguments"]
                ?? dictionary["parameters"]
                ?? dictionary["args"]
                ?? .object([:])
            results.append(AgentToolCall(
                id: "text-\(results.count)",
                name: name,
                argumentsText: arguments.compactJSONString()
            ))
        }
        return results
    }

    /// 扫出正文里所有顶层 JSON 对象。引号内的花括号不参与配对。
    static func jsonObjects(in text: String) -> [String] {
        var results: [String] = []
        var depth = 0
        var start: String.Index?
        var inString = false
        var escaped = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]

            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                index = text.index(after: index)
                continue
            }

            switch character {
            case "\"":
                inString = true
            case "{":
                if depth == 0 { start = index }
                depth += 1
            case "}":
                depth -= 1
                if depth == 0, let begin = start {
                    results.append(String(text[begin...index]))
                    start = nil
                }
                if depth < 0 { depth = 0 }
            default:
                break
            }
            index = text.index(after: index)
        }
        return results
    }
}
