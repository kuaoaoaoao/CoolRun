import SwiftUI

/// 工具浏览器：把 Agent 能做的每件事都摆出来，用户自己点、自己填参数、自己跑。
///
/// 这是"选择工具 → 使用功能"那条链路的 UI，也是排查"为什么 Agent 没调某个
/// 工具"的地方 —— 手动跑一遍就能看到真实的返回。
struct AgentToolsBrowser: View {
    let onClose: () -> Void

    @State private var query = ""
    @State private var selectedName: String?
    @State private var values: [String: JSONValue] = [:]
    @State private var result: ToolResult?
    @State private var isRunning = false
    @State private var confirmArmed = false

    @ObservedObject private var appSettings = AppSettings.shared

    private var registry: ToolRegistry { .shared }
    private var settings: AgentSettings { .shared }
    private var lang: AppLanguage { appSettings.language }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            if let name = selectedName,
               let descriptor = registry.allDescriptors.first(where: { $0.name == name }) {
                detail(descriptor)
            } else {
                toolList
            }
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                if selectedName == nil {
                    onClose()
                } else {
                    selectedName = nil
                    values = [:]
                    result = nil
                    confirmArmed = false
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help(
                selectedName == nil
                    ? LocalizedString.l(lang, en: "Back to chat", zh: "返回对话", ja: "会話に戻る", ko: "대화로 돌아가기")
                    : LocalizedString.l(lang, en: "Back to tool list", zh: "返回工具列表", ja: "ツール一覧に戻る", ko: "도구 목록으로 돌아가기")
            )

            Text(selectedName == nil ? LocalizedString.l(lang, en: "Tools", zh: "工具", ja: "ツール", ko: "도구") : (selectedName ?? ""))
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 0)

            if selectedName == nil {
                Text(LocalizedString.l(lang, en: "\(registry.allDescriptors.count) tools", zh: "\(registry.allDescriptors.count) 个", ja: "\(registry.allDescriptors.count) 個", ko: "\(registry.allDescriptors.count)개"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: 列表

    private var filtered: [ToolDescriptor] {
        let all = registry.allDescriptors
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.summary.localizedCaseInsensitiveContains(query)
        }
    }

    private var grouped: [(permission: ToolPermission, tools: [ToolDescriptor])] {
        ToolPermission.allCases.compactMap { permission in
            let tools = filtered.filter { $0.permission == permission }
            return tools.isEmpty ? nil : (permission, tools)
        }
    }

    private var toolList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                TextField(LocalizedString.l(lang, en: "Search tools", zh: "搜索工具", ja: "ツールを検索", ko: "도구 검색"), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(grouped, id: \.permission) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(group.permission.displayName) · L\(group.permission.rawValue)")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 2)
                            ForEach(group.tools) { tool in
                                toolRow(tool)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
    }

    private func toolRow(_ tool: ToolDescriptor) -> some View {
        let allowed = tool.permission <= settings.toolLevel
        return Button {
            selectedName = tool.name
            values = [:]
            result = nil
            confirmArmed = false
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol(for: tool))
                    .font(.system(size: 11))
                    .foregroundStyle(allowed ? Color.accentColor : .secondary)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(tool.name)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Text(tool.summary)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                if !allowed {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(allowed ? 1 : 0.6)
    }

    private func symbol(for tool: ToolDescriptor) -> String {
        switch tool.permission {
        case .read: return "eye"
        case .reversible: return "arrow.uturn.backward"
        case .persistent: return "square.and.pencil"
        case .dangerous: return "exclamationmark.triangle"
        }
    }

    // MARK: 详情

    private func detail(_ tool: ToolDescriptor) -> some View {
        let fields = SchemaField.fields(from: tool.parameters)
        let allowed = tool.permission <= settings.toolLevel
        let needsConfirm = tool.permission >= .persistent

        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(tool.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Text("L\(tool.permission.rawValue) · \(tool.permission.displayName)")
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.07), in: Capsule())
                    if !allowed {
                        Text(LocalizedString.l(lang, en: "Disabled at current level", zh: "当前等级未开启", ja: "現在のレベルでは無効", ko: "현재 레벨에서 사용 안 함"))
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                }

                if !fields.isEmpty {
                    Divider().opacity(0.3)
                    SchemaFormView(fields: fields, values: $values)
                }

                if !allowed {
                    Text(
                        LocalizedString.l(
                            lang,
                            en: "Raise the tool level to L\(tool.permission.rawValue) in Settings to run this.",
                            zh: "在设置里把工具等级调到 L\(tool.permission.rawValue) 才能运行。",
                            ja: "設定でツールレベルを L\(tool.permission.rawValue) に上げると実行できます。",
                            ko: "설정에서 도구 레벨을 L\(tool.permission.rawValue)로 올려야 실행할 수 있습니다."
                        )
                    )
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                runButton(tool, allowed: allowed, needsConfirm: needsConfirm)

                if let result {
                    Divider().opacity(0.3)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: result.isError ? "exclamationmark.circle" : "checkmark.circle")
                                .font(.system(size: 10))
                                .foregroundStyle(result.isError ? .red : .green)
                            Text(
                                result.isError
                                    ? LocalizedString.l(lang, en: "Failed", zh: "失败", ja: "失敗", ko: "실패")
                                    : LocalizedString.l(lang, en: "Result", zh: "结果", ja: "結果", ko: "결과")
                            )
                                .font(.system(size: 10, weight: .medium))
                            Spacer(minLength: 0)
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(result.content, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 9))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help(LocalizedString.l(lang, en: "Copy result", zh: "复制结果", ja: "結果をコピー", ko: "결과 복사"))
                        }
                        Text(result.content)
                            .font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .padding(10)
        }
    }

    private func runButton(_ tool: ToolDescriptor, allowed: Bool, needsConfirm: Bool) -> some View {
        Button {
            if needsConfirm && !confirmArmed {
                confirmArmed = true
                return
            }
            confirmArmed = false
            Task { await run(tool) }
        } label: {
            HStack(spacing: 5) {
                if isRunning {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: confirmArmed ? "checkmark.shield" : "play.fill")
                        .font(.system(size: 9))
                }
                Text(
                    confirmArmed
                        ? LocalizedString.l(lang, en: "Confirm run (writes data)", zh: "确认执行（会写入）", ja: "実行を確認（書き込みあり）", ko: "실행 확인(쓰기 발생)")
                        : LocalizedString.l(lang, en: "Run", zh: "运行", ja: "実行", ko: "실행")
                )
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
        }
        .buttonStyle(.borderedProminent)
        .tint(confirmArmed ? .orange : .accentColor)
        .controlSize(.small)
        .disabled(!allowed || isRunning)
    }

    private func run(_ tool: ToolDescriptor) async {
        isRunning = true
        defer { isRunning = false }
        let arguments = SchemaFormValues.arguments(from: values)
        result = await registry.execute(name: tool.name, arguments: arguments)
    }
}
