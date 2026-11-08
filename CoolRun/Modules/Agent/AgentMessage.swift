import Foundation

// MARK: - JSON 值

/// 工具参数与结果的统一表示。
/// 所有 wire 层（OpenAI / Anthropic / Ollama）都用它做编解码，避免 `Any` 在模块内扩散。
enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

extension JSONValue {
    nonisolated var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    nonisolated var doubleValue: Double? {
        switch self {
        case .number(let value): return value
        case .string(let text): return Double(text)
        default: return nil
        }
    }

    nonisolated var intValue: Int? {
        doubleValue.map { Int($0) }
    }

    nonisolated var boolValue: Bool? {
        switch self {
        case .bool(let value): return value
        case .number(let value): return value != 0
        default: return nil
        }
    }

    nonisolated var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    nonisolated var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    nonisolated subscript(key: String) -> JSONValue? {
        get { objectValue?[key] }
        set {
            guard case .object(var dictionary) = self else { return }
            if let newValue {
                dictionary[key] = newValue
            } else {
                dictionary.removeValue(forKey: key)
            }
            self = .object(dictionary)
        }
    }

    /// 解析模型返回的 arguments 字符串。空串视为空对象。
    nonisolated static func parse(_ text: String) -> JSONValue? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .object([:]) }
        guard let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// 紧凑序列化，用于 tool 消息与审计日志。
    nonisolated func compactJSONString() -> String {
        guard let data = try? JSONEncoder().encode(self),
              let text = String(data: data, encoding: .utf8)
        else { return "null" }
        return text
    }

    /// 生成一份便于模型阅读的缩进文本。
    ///
    /// 不用 JSONSerialization：它会把 871.44 打成 871.44000000000005，
    /// 模型读到一串浮点尾巴既费 token 又容易抄错数。
    nonisolated func prettyJSONString() -> String {
        prettyLines(indent: 0)
    }

    private nonisolated func prettyLines(indent: Int) -> String {
        let pad = String(repeating: "  ", count: indent)
        switch self {
        case .null:
            return "null"
        case .bool(let value):
            return value ? "true" : "false"
        case .number(let value):
            guard value.isFinite else { return "null" }
            if value == value.rounded(), abs(value) < 1e15 {
                return String(Int64(value))
            }
            return "\(value)"
        case .string(let text):
            return Self.quoted(text)
        case .array(let items):
            guard !items.isEmpty else { return "[]" }
            let inner = items.map { $0.prettyLines(indent: indent + 1) }.joined(separator: ",\n")
            let itemPad = String(repeating: "  ", count: indent + 1)
            return "[\n" + itemPad + inner + "\n" + pad + "]"
        case .object(let dictionary):
            guard !dictionary.isEmpty else { return "{}" }
            let itemPad = String(repeating: "  ", count: indent + 1)
            let inner = dictionary.keys.sorted().map { key in
                itemPad + Self.quoted(key) + " : " + (dictionary[key]?.prettyLines(indent: indent + 1) ?? "null")
            }.joined(separator: ",\n")
            return "{\n" + inner + "\n" + pad + "}"
        }
    }

    nonisolated static func quoted(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
        return out
    }
}

// MARK: - 消息

enum AgentRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

/// 一次工具调用请求（模型产出）。
struct AgentToolCall: Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    /// 模型给出的原始 JSON 字符串，可能不合法，执行前统一解析。
    var argumentsText: String

    nonisolated init(id: String, name: String, argumentsText: String) {
        self.id = id
        self.name = name
        self.argumentsText = argumentsText
    }

    nonisolated var arguments: JSONValue {
        JSONValue.parse(argumentsText) ?? .object([:])
    }
}

/// 对话中的一条消息。同时用于 wire 层与 UI 回放。
struct AgentMessage: Identifiable, Equatable, Sendable {
    let id: UUID
    var role: AgentRole
    var content: String
    var toolCalls: [AgentToolCall]
    /// role == .tool 时指向对应的调用 id
    var toolCallID: String?
    /// role == .tool 时的工具名，仅用于展示
    var toolName: String?
    var isError: Bool

    nonisolated init(
        id: UUID = UUID(),
        role: AgentRole,
        content: String = "",
        toolCalls: [AgentToolCall] = [],
        toolCallID: String? = nil,
        toolName: String? = nil,
        isError: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.isError = isError
    }
}
