import SwiftUI

/// 从工具声明的 JSON Schema 里解析出来的一个字段。
struct SchemaField: Identifiable, Equatable {
    enum Kind: Equatable {
        case text
        case number(isInteger: Bool)
        case boolean
        case choice([String])
    }

    let name: String
    let kind: Kind
    let title: String
    let detail: String?
    let minimum: Double?
    let maximum: Double?
    let defaultValue: JSONValue?
    let isRequired: Bool

    var id: String { name }

    /// 解析 `{"type":"object","properties":{...},"required":[...]}`。
    nonisolated static func fields(from schema: JSONValue) -> [SchemaField] {
        guard case .object(let root) = schema,
              case .object(let properties) = root["properties"] ?? .object([:])
        else { return [] }

        let required: Set<String> = {
            guard case .array(let items) = root["required"] ?? .array([]) else { return [] }
            return Set(items.compactMap(\.stringValue))
        }()

        return properties.keys.sorted().compactMap { key -> SchemaField? in
            guard case .object(let spec) = properties[key] else { return nil }
            let type = spec["type"]?.stringValue ?? "string"
            let kind: Kind
            if case .array(let choices) = spec["enum"] ?? .array([]) {
                kind = .choice(choices.compactMap(\.stringValue))
            } else {
                switch type {
                case "boolean": kind = .boolean
                case "integer": kind = .number(isInteger: true)
                case "number": kind = .number(isInteger: false)
                default: kind = .text
                }
            }
            return SchemaField(
                name: key,
                kind: kind,
                title: spec["title"]?.stringValue ?? key,
                detail: spec["description"]?.stringValue,
                minimum: spec["minimum"]?.doubleValue,
                maximum: spec["maximum"]?.doubleValue,
                defaultValue: spec["default"],
                isRequired: required.contains(key)
            )
        }
    }

    /// 这个字段在表单里是否需要显示"必填"标记。
    var showsRequiredBadge: Bool {
        isRequired && defaultValue == nil
    }
}

/// 通用参数表单：工具浏览器和确认条都能用。
struct SchemaFormView: View {
    let fields: [SchemaField]
    @Binding var values: [String: JSONValue]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(fields) { field in
                fieldRow(field)
            }
        }
    }

    @ViewBuilder
    private func fieldRow(_ field: SchemaField) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(field.title)
                    .font(.system(size: 11, weight: .medium))
                if field.showsRequiredBadge {
                    Text("*")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.red.opacity(0.8))
                }
                Spacer(minLength: 0)
            }
            if let detail = field.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            control(field)
        }
    }

    @ViewBuilder
    private func control(_ field: SchemaField) -> some View {
        switch field.kind {
        case .boolean:
            Toggle("", isOn: Binding(
                get: { values[field.name]?.boolValue ?? (field.defaultValue?.boolValue ?? false) },
                set: { values[field.name] = .bool($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()

        case .choice(let options):
            Picker("", selection: Binding(
                get: { values[field.name]?.stringValue ?? options.first ?? "" },
                set: { values[field.name] = .string($0) }
            )) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .controlSize(.small)

        case .number(let isInteger):
            TextField("", text: Binding(
                get: {
                    if case .number(let n) = values[field.name] ?? .null {
                        return isInteger ? String(Int(n)) : String(n)
                    }
                    if case .number(let n) = field.defaultValue ?? .null {
                        return isInteger ? String(Int(n)) : String(n)
                    }
                    return ""
                },
                set: { text in
                    let trimmed = text.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, let number = Double(trimmed) else {
                        values[field.name] = .null
                        return
                    }
                    values[field.name] = .number(isInteger ? number.rounded() : number)
                }
            ))
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)

        case .text:
            TextField("", text: Binding(
                get: { values[field.name]?.stringValue ?? field.defaultValue?.stringValue ?? "" },
                set: { values[field.name] = .string($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
        }
    }
}

/// 把表单里填的值收成工具调用需要的 JSON。
enum SchemaFormValues {
    /// 丢掉空值 —— 让服务端用默认值，而不是收到 `""` 或 `null`。
    nonisolated static func arguments(from values: [String: JSONValue]) -> JSONValue {
        var result: [String: JSONValue] = [:]
        for (key, value) in values {
            switch value {
            case .null:
                continue
            case .string(let text) where text.isEmpty:
                continue
            default:
                result[key] = value
            }
        }
        return .object(result)
    }

    /// 必填但没填的字段名。
    nonisolated static func missingRequired(fields: [SchemaField], values: [String: JSONValue]) -> [String] {
        fields.filter { field in
            guard field.isRequired else { return false }
            switch values[field.name] {
            case .none, .null:
                return true
            case .string(let text):
                return text.isEmpty
            default:
                return false
            }
        }.map(\.name)
    }
}
