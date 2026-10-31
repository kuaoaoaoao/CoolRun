import SwiftUI

// MARK: - LLM Provider 配置面板

/// 可复用的 LLM 配置面板。
/// 同时用于「设置 → AI 助手」页面和 AI 助手模块内的配置弹窗。
@MainActor
struct LLMProviderSettingsView: View {
    /// 保存成功后的回调（弹窗场景用于关闭 sheet）
    var onSaved: (() -> Void)?

    @State private var service = LLMService.shared
    @ObservedObject private var appSettings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedKind: LLMProviderKind = .openai
    @State private var apiKey = ""
    @State private var baseURL = ""
    @State private var model = ""

    @State private var isTesting = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var hasLoaded = false

    private var language: AppLanguage { appSettings.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            providerPicker

            if selectedKind.requiresAPIKey {
                apiKeyField
            }

            advancedFields

            actionRow

            if let statusMessage {
                Label(statusMessage, systemImage: statusIsError ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(statusIsError ? AppTheme.critical : AppTheme.healthy)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(LocalizedString.l(
                language,
                en: "API keys are stored in the macOS Keychain and never leave your Mac except when sent directly to the provider you choose.",
                zh: "API Key 保存在 macOS 钥匙串中，除直接发送给你选择的模型服务商外不会离开本机。",
                ja: "APIキーはmacOSキーチェーンに保存され、選択したプロバイダへ直接送信する場合を除きMac外に出ません。",
                ko: "API 키는 macOS 키체인에 저장되며, 선택한 제공자에게 직접 전송되는 경우를 제외하면 Mac을 벗어나지 않습니다."
            ))
            .font(.system(size: 9))
            .foregroundStyle(AppTheme.textSecondary(colorScheme))
            .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear(perform: loadCurrent)
        .onChange(of: selectedKind) { _, newKind in
            loadSaved(for: newKind)
            statusMessage = nil
        }
    }

    // MARK: - Provider 选择

    private var providerPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedString.l(language, en: "Provider", zh: "服务商", ja: "プロバイダ", ko: "제공자"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))

            HStack(spacing: 6) {
                ForEach(LLMProviderKind.allCases) { kind in
                    Button {
                        selectedKind = kind
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: kind.icon)
                                .font(.system(size: 13, weight: .semibold))
                            Text(kind.displayName)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(
                            selectedKind == kind
                                ? AppTheme.accent
                                : AppTheme.textSecondary(colorScheme)
                        )
                        .background(
                            selectedKind == kind
                                ? AppTheme.accent.opacity(colorScheme == .dark ? 0.18 : 0.11)
                                : AppTheme.progressBg(colorScheme).opacity(0.6),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(
                                    selectedKind == kind
                                        ? AppTheme.accent.opacity(0.35)
                                        : AppTheme.stroke(colorScheme),
                                    lineWidth: selectedKind == kind ? 1 : 0.5
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedKind == kind ? .isSelected : [])
                }
            }
        }
    }

    // MARK: - API Key

    private var apiKeyField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedString.l(language, en: "API Key", zh: "API Key", ja: "APIキー", ko: "API 키"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))

            SecureField(
                LocalizedString.l(language, en: "Paste your API key", zh: "粘贴 API Key", ja: "APIキーを貼り付け", ko: "API 키 붙여넣기"),
                text: $apiKey
            )
            .textFieldStyle(.plain)
            .font(.system(size: 11, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(AppTheme.progressBg(colorScheme), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }

    // MARK: - Base URL / Model

    private var advancedFields: some View {
        HStack(spacing: 8) {
            labeledField(
                title: LocalizedString.l(language, en: "Base URL", zh: "接口地址", ja: "ベースURL", ko: "기본 URL"),
                placeholder: selectedKind.defaultBaseURL,
                text: $baseURL
            )
            labeledField(
                title: LocalizedString.l(language, en: "Model", zh: "模型", ja: "モデル", ko: "모델"),
                placeholder: selectedKind.defaultModel,
                text: $model
            )
        }
    }

    private func labeledField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(AppTheme.progressBg(colorScheme), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }

    // MARK: - 操作按钮

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button(action: save) {
                Text(LocalizedString.l(language, en: "Save", zh: "保存", ja: "保存", ko: "저장"))
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)

            Button(action: testConnection) {
                HStack(spacing: 4) {
                    if isTesting {
                        ProgressView().controlSize(.mini)
                    }
                    Text(LocalizedString.l(language, en: "Test", zh: "测试连接", ja: "接続テスト", ko: "연결 테스트"))
                        .font(.system(size: 11, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .disabled(isTesting || (selectedKind.requiresAPIKey && apiKey.isEmpty))

            if service.isConfigured {
                Button(action: clearAll) {
                    Text(LocalizedString.l(language, en: "Clear", zh: "清除", ja: "クリア", ko: "지우기"))
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - 行为

    private func loadCurrent() {
        guard !hasLoaded else { return }
        hasLoaded = true

        if let current = service.currentConfiguration() {
            selectedKind = current.kind
            apiKey = current.apiKey
            baseURL = current.baseURL
            model = current.model
        } else {
            let saved = service.savedConfiguration(for: selectedKind)
            apiKey = saved.apiKey
            baseURL = saved.baseURL
            model = saved.model
        }
    }

    private func loadSaved(for kind: LLMProviderKind) {
        let saved = service.savedConfiguration(for: kind)
        apiKey = saved.apiKey
        baseURL = saved.baseURL
        model = saved.model
    }

    private func save() {
        let success = service.configure(
            kind: selectedKind,
            apiKey: apiKey,
            baseURL: baseURL,
            model: model
        )
        if success {
            statusIsError = false
            statusMessage = LocalizedString.l(
                language,
                en: "Saved. The assistant is ready to use.",
                zh: "已保存，助手可以开始使用。",
                ja: "保存しました。アシスタントを使用できます。",
                ko: "저장되었습니다. 도우미를 사용할 수 있습니다."
            )
            onSaved?()
        } else {
            statusIsError = true
            statusMessage = service.lastError
        }
    }

    private func testConnection() {
        // 先按当前表单值写入，避免测试未保存的配置
        guard service.configure(kind: selectedKind, apiKey: apiKey, baseURL: baseURL, model: model) else {
            statusIsError = true
            statusMessage = service.lastError
            return
        }

        isTesting = true
        statusMessage = nil

        Task {
            let result = await service.testConnection()
            isTesting = false
            switch result {
            case .success:
                statusIsError = false
                statusMessage = LocalizedString.l(
                    language,
                    en: "Connection successful.",
                    zh: "连接成功。",
                    ja: "接続に成功しました。",
                    ko: "연결에 성공했습니다."
                )
            case .failure(let error):
                statusIsError = true
                statusMessage = error.localizedDescription
            }
        }
    }

    private func clearAll() {
        service.clearConfiguration()
        apiKey = ""
        baseURL = selectedKind.defaultBaseURL
        model = selectedKind.defaultModel
        statusIsError = false
        statusMessage = LocalizedString.l(
            language,
            en: "Configuration cleared.",
            zh: "已清除配置。",
            ja: "設定をクリアしました。",
            ko: "설정을 지웠습니다."
        )
    }
}

// MARK: - 配置弹窗

@MainActor
struct LLMConfigSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appSettings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(
                    LocalizedString.l(appSettings.language, en: "AI Assistant Setup", zh: "AI 助手设置", ja: "AI アシスタント設定", ko: "AI 도우미 설정"),
                    systemImage: "brain.head.profile"
                )
                .font(.system(size: 13, weight: .semibold))

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            ScrollView {
                LLMProviderSettingsView(onSaved: { dismiss() })
                    .padding(16)
            }
        }
        .frame(width: 420, height: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
