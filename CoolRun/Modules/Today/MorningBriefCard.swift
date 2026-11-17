import SwiftUI

// MARK: - 晨间简报卡片

/// 一张卡片说清今天。行数固定、字号克制、不用渐变，
/// 只在真的需要注意的地方给一点颜色。
struct MorningBriefCard: View {

    @State private var store = MorningBriefStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    private var lang: AppLanguage { settings.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if let brief = store.brief {
                if brief.lines.isEmpty, brief.summary == nil {
                    calmRow
                } else {
                    lines(brief)
                    if let summary = brief.summary {
                        summaryView(summary)
                    }
                }
                footer(brief)
            } else {
                loadingRows
            }
        }
        .padding(14)
        .appCardSurface(cornerRadius: 14, showsShadow: false)
        .task { await store.refreshIfNeeded() }
    }

    // MARK: 头部

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(store.brief?.greeting ?? LocalizedString.l(lang, en: "Hello", zh: "你好", ja: "こんにちは", ko: "안녕하세요"))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary(colorScheme))
            Spacer(minLength: 8)
            Text(Self.dateText(Date(), lang: lang))
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
        }
    }

    // MARK: 要点

    private func lines(_ brief: MorningBrief) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(brief.lines) { line in
                Button {
                    if let destination = line.destination {
                        AppNavigationRouter.shared.open(destination)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: line.icon)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary(colorScheme))
                            .frame(width: 15, alignment: .leading)

                        Text(line.title)
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.textPrimary(colorScheme))
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Text(line.detail)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(detailColor(line.tone))
                            .lineLimit(1)
                    }
                    .frame(minHeight: 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowHighlightButtonStyle())
                .disabled(line.destination == nil)
            }
        }
        .padding(.top, 12)
    }

    private func detailColor(_ tone: MorningBriefLine.Tone) -> Color {
        switch tone {
        case .normal: AppTheme.textSecondary(colorScheme)
        case .attention: AppTheme.textPrimary(colorScheme)
        case .warning: AppTheme.warning
        case .critical: AppTheme.critical
        }
    }

    private var calmRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.healthy)
            Text(
                LocalizedString.l(
                    lang,
                    en: "Nothing special today. Carry on.",
                    zh: "今天没什么特别的，该干嘛干嘛。",
                    ja: "今日は特に変わったことはありません。いつも通りに。",
                    ko: "오늘은 특별한 일이 없습니다. 하던 일을 하세요."
                )
            )
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
        }
        .padding(.top, 12)
    }

    private var loadingRows: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(AppTheme.progressBg(colorScheme))
                    .frame(width: index == 2 ? 120 : 180, height: 10)
            }
        }
        .padding(.top, 12)
    }

    // MARK: 润色结果

    private func summaryView(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(AppTheme.separator(colorScheme))
                .frame(height: 0.5)
                .padding(.vertical, 10)

            Text(summary)
                .font(.system(size: 12))
                .lineSpacing(3.5)
                .foregroundStyle(AppTheme.textPrimary(colorScheme).opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 底部

    private func footer(_ brief: MorningBrief) -> some View {
        HStack(spacing: 8) {
            Button {
                Task { await store.refine() }
            } label: {
                HStack(spacing: 4) {
                    if store.isRefining {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .medium))
                    }
                    Text(
                        store.isRefining
                            ? LocalizedString.l(lang, en: "Thinking…", zh: "在想…", ja: "考え中…", ko: "생각 중…")
                            : (brief.summary == nil
                                ? LocalizedString.l(lang, en: "Let me summarize", zh: "让本鱼说说", ja: "まとめてみる", ko: "정리해 볼게")
                                : LocalizedString.l(lang, en: "Say it again", zh: "再说一遍", ja: "もう一度", ko: "다시 말하기"))
                    )
                        .font(.system(size: 11))
                }
                .foregroundStyle(AppTheme.accent)
            }
            .buttonStyle(.plain)
            .disabled(store.isRefining)

            if let error = store.refineError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.warning)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button {
                Task { await store.refresh(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }
            .buttonStyle(.plain)
            .disabled(store.isRefreshing)
            .help(LocalizedString.l(lang, en: "Regenerate", zh: "重新生成", ja: "再生成", ko: "다시 생성"))
        }
        .padding(.top, 12)
    }

    // MARK: 日期

    private static func dateText(_ date: Date, lang: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = lang.locale
        formatter.setLocalizedDateFormatFromTemplate("MMMdEEEE")
        return formatter.string(from: date)
    }
}
