import SwiftUI

// MARK: - 设置 · AI 助手

extension SettingsView {
    /// 「AI 助手」设置页：模型服务商选择、API Key、连通性测试。
    @MainActor
    var aiContent: some View {
        VStack(spacing: 14) {
            SettingsCard(
                icon: "brain.head.profile",
                title: LocalizedString.l(
                    AppSettings.shared.language,
                    en: "Model Provider",
                    zh: "模型服务商",
                    ja: "モデルプロバイダ",
                    ko: "모델 제공자"
                ),
                description: LocalizedString.l(
                    AppSettings.shared.language,
                    en: "The AI Assistant answers questions about your system status and gold price using the provider you configure here.",
                    zh: "AI 助手使用这里配置的服务商回答系统状态与金价相关的问题。",
                    ja: "AIアシスタントはここで設定したプロバイダを使用して、システム状態や金価格に関する質問に回答します。",
                    ko: "AI 도우미는 여기서 설정한 제공자를 사용하여 시스템 상태와 금 가격 관련 질문에 답변합니다."
                )
            ) {
                LLMProviderSettingsView()
                    .padding(12)
            }

            AIPrivacyCard()
        }
    }
}

// MARK: - 隐私说明卡片

/// 单条隐私说明条目。
private struct PrivacyItem: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
}

private struct AIPrivacyCard: View {
    @ObservedObject private var appSettings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    private var language: AppLanguage { appSettings.language }

    private var items: [PrivacyItem] {
        [
            PrivacyItem(
                icon: "key",
                text: LocalizedString.l(
                    language,
                    en: "API keys are encrypted with a key derived from this Mac's hardware ID and stored in a 0600 file — never in plain text. Copy that file to another Mac and it stays unreadable.",
                    zh: "API Key 用本机硬件 ID 派生的密钥加密后存在权限 0600 的文件里，不会明文落盘；把文件拷到别的机器上也解不开。",
                    ja: "APIキーは本機のハードウェアIDから派生した鍵で暗号化し、権限0600のファイルに保存します（平文では保存しません）。他のマシンへコピーしても復号できません。",
                    ko: "API 키는 이 Mac의 하드웨어 ID에서 파생한 키로 암호화해 권한 0600 파일에 저장합니다(평문 저장 없음). 다른 Mac으로 복사해도 복호화되지 않습니다."
                )
            ),
            PrivacyItem(
                icon: "arrow.up.right.square",
                text: LocalizedString.l(
                    language,
                    en: "Requests go directly from this Mac to the provider. No CoolRun server is involved.",
                    zh: "请求由本机直接发送到服务商，不经过任何 CoolRun 服务器。",
                    ja: "リクエストは本機からプロバイダへ直接送信されます。CoolRunのサーバーは介在しません。",
                    ko: "요청은 이 Mac에서 제공자로 직접 전송되며 CoolRun 서버를 거치지 않습니다."
                )
            ),
            PrivacyItem(
                icon: "line.3.horizontal.decrease.circle",
                text: LocalizedString.l(
                    language,
                    en: "Only the data relevant to your question is sent — not your full history or notes.",
                    zh: "只发送与问题相关的数据，不会上传完整历史记录或备忘录内容。",
                    ja: "質問に関連するデータのみを送信します。履歴全体やメモの内容は送信しません。",
                    ko: "질문과 관련된 데이터만 전송하며 전체 기록이나 메모 내용은 전송하지 않습니다."
                )
            ),
            PrivacyItem(
                icon: "exclamationmark.bubble",
                text: LocalizedString.l(
                    language,
                    en: "Gold-related answers are reference only and are not investment advice.",
                    zh: "涉及金价的回答仅供参考，不构成投资建议。",
                    ja: "金価格に関する回答は参考情報であり、投資助言ではありません。",
                    ko: "금 가격 관련 답변은 참고용이며 투자 조언이 아닙니다."
                )
            ),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.healthy)
                    .frame(width: 26, height: 26)
                    .background(
                        AppTheme.healthy.opacity(colorScheme == .dark ? 0.18 : 0.11),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )

                Text(LocalizedString.l(language, en: "Privacy", zh: "隐私说明", ja: "プライバシー", ko: "개인정보"))
                    .font(.headline)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 7) {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: item.icon)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(AppTheme.textSecondary(colorScheme))
                            .frame(width: 12)
                            .padding(.top, 2)

                        Text(item.text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .appCardSurface(cornerRadius: 12, showsShadow: false)
    }
}
