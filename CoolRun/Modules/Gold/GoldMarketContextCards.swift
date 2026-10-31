import SwiftUI
import AppKit

struct MarketContextCard: View {
    let context: GoldMarketContext?
    let isLoading: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var tint: Color {
        switch context?.tone ?? .neutral {
        case .bullish: AppTheme.marketUp
        case .neutral: Color(red: 0.88, green: 0.57, blue: 0.16)
        case .bearish: AppTheme.marketDown
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(context?.tone.title ?? LocalizedString.gold("macro_news_analysis"), systemImage: "newspaper")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)

                Spacer(minLength: 6)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(context?.overallScore.signedShortNumber ?? "--")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                }
            }

            if let context {
                if context.isFromCache || context.isPartial {
                    Label(contextStatusText(context), systemImage: context.isFromCache ? "clock.badge.checkmark" : "exclamationmark.triangle")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(context.isFromCache ? tint : AppTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    StrategyMetric(
                        title: LocalizedString.gold("macro"),
                        value: context.macroScore.signedShortNumber,
                        detail: macroDetail(context.macro),
                        help: LocalizedString.l(AppSettings.shared.language, en: "Uses U.S. 10-year Treasury yield changes. Falling yields usually support gold; rising yields usually pressure it.", zh: "当前先使用美国 10 年期国债收益率变化。收益率下行通常利好黄金，上行通常压制黄金。", ja: "米10年債利回りの変化を使用します。利回り低下は通常金に追い風、上昇は逆風です。", ko: "미국 10년물 국채 금리 변화를 사용합니다. 금리 하락은 보통 금에 우호적이고 상승은 압박 요인입니다.")
                    )
                    StrategyMetric(
                        title: LocalizedString.gold("news"),
                        value: context.newsScore.signedShortNumber,
                        detail: String(format: LocalizedString.gold("items_count_format"), context.newsItems.count),
                        help: LocalizedString.l(AppSettings.shared.language, en: "Reads RSS headlines about gold, USD, the Fed and yields, then scores sentiment with keywords.", zh: "读取黄金、美元、美联储、收益率相关 RSS 标题，用关键词做轻量情绪评分。", ja: "金、ドル、FRB、利回りに関するRSS見出しを読み、キーワードで軽量なセンチメント評価を行います。", ko: "금, 달러, 연준, 금리 관련 RSS 제목을 읽고 키워드로 간단한 심리를 점수화합니다.")
                    )
                }

                ForEach(Array(context.reasons.prefix(3)), id: \.self) { reason in
                    Label(reason, systemImage: "circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !context.newsItems.isEmpty {
                    Divider()
                        .opacity(0.45)

                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(context.newsItems.prefix(6))) { item in
                            newsRow(item)
                        }
                    }
                }
            } else {
                Text(isLoading ? LocalizedString.gold("macro_loading") : LocalizedString.gold("macro_unavailable"))
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(colorScheme == .dark ? Color.black.opacity(0.25) : Color.white.opacity(0.48))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        }
    }

    private func macroDetail(_ macro: GoldMacroSnapshot?) -> String {
        guard let macro, let yield = macro.tenYearYield else { return LocalizedString.gold("treasury_10y") }
        if let change = macro.tenYearYieldChangeBps {
            return "\(yield.shortNumber)% \(change.signedShortNumber)bp"
        }
        return "\(yield.shortNumber)%"
    }

    @ViewBuilder
    private func newsRow(_ item: GoldNewsItem) -> some View {
        let content = HStack(alignment: .top, spacing: 7) {
            Circle()
                .fill(newsTint(item))
                .frame(width: 6, height: 6)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary(colorScheme))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 5) {
                    if let source = item.source, !source.isEmpty {
                        Text(source)
                    }
                    if let publishedAt = item.publishedAt {
                        Text(publishedAt, style: .relative)
                    }
                    Text(newsImpactText(item))
                        .foregroundStyle(newsTint(item))
                }
                .font(.system(size: 8.5))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }

            Spacer(minLength: 0)

            if item.link != nil {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }
        }

        if let link = item.link {
            Link(destination: link) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    private func newsTint(_ item: GoldNewsItem) -> Color {
        if item.sentimentScore > 0 { return AppTheme.marketUp }
        if item.sentimentScore < 0 { return AppTheme.marketDown }
        return AppTheme.textSecondary(colorScheme)
    }

    private func newsImpactText(_ item: GoldNewsItem) -> String {
        if item.sentimentScore > 0 {
            return LocalizedString.l(AppSettings.shared.language, en: "Bullish", zh: "利多", ja: "強気", ko: "호재")
        }
        if item.sentimentScore < 0 {
            return LocalizedString.l(AppSettings.shared.language, en: "Bearish", zh: "利空", ja: "弱気", ko: "악재")
        }
        return LocalizedString.l(AppSettings.shared.language, en: "Neutral", zh: "中性", ja: "中立", ko: "중립")
    }

    private func contextStatusText(_ context: GoldMarketContext) -> String {
        if let missing = context.missingDataDescription {
            return String(format: context.isFromCache ? LocalizedString.gold("cached_data_format") : LocalizedString.gold("partial_data_format"), missing)
        }
        return context.isFromCache ? LocalizedString.gold("cached_15min") : LocalizedString.gold("macro_partial")
    }
}

// MARK: - 事件影响

/// 事件影响卡片的纯文案映射：只做展示文本转换，不做任何推断或加权。
struct GoldEventImpactPresentation: Equatable {
    let directionText: String
    let confidenceText: String
    let dataStateText: String
    let riskText: String

    nonisolated init(impact: GoldEventImpact, language: AppLanguage) {
        directionText = Self.directionText(for: impact.direction, dataState: impact.dataState, language: language)
        confidenceText = LocalizedString.l(
            language,
            en: "Evidence strength: \(Self.confidenceWord(impact.confidence, language: .english))",
            zh: "证据强度：\(Self.confidenceWord(impact.confidence, language: .chinese))",
            ja: "証拠強度：\(Self.confidenceWord(impact.confidence, language: .japanese))",
            ko: "증거 강도: \(Self.confidenceWord(impact.confidence, language: .korean))"
        )
        dataStateText = Self.dataStateText(for: impact.dataState, language: language)
        riskText = LocalizedString.l(
            language,
            en: "Volatility risk: \(Self.riskWord(impact.volatilityRisk, language: .english))",
            zh: "波动风险：\(Self.riskWord(impact.volatilityRisk, language: .chinese))",
            ja: "ボラティリティリスク：\(Self.riskWord(impact.volatilityRisk, language: .japanese))",
            ko: "변동성 리스크: \(Self.riskWord(impact.volatilityRisk, language: .korean))"
        )
    }

    nonisolated static func evidenceLabel(for state: GoldEvidenceState, language: AppLanguage) -> String {
        switch state {
        case .observed:
            return LocalizedString.l(
                language,
                en: "Confirmed",
                zh: "已确认",
                ja: "確認済み",
                ko: "확인됨"
            )
        case .inferred:
            return LocalizedString.l(
                language,
                en: "Inferred",
                zh: "推断",
                ja: "推論",
                ko: "추론"
            )
        }
    }

    nonisolated private static func directionText(
        for direction: GoldImpactDirection,
        dataState: GoldIntelligenceDataState,
        language: AppLanguage
    ) -> String {
        guard dataState != .unavailable else {
            return LocalizedString.l(
                language,
                en: "No direction yet",
                zh: "暂无方向",
                ja: "方向なし",
                ko: "방향 없음"
            )
        }
        switch direction {
        case .bullish:
            return LocalizedString.l(language, en: "Short-term bullish", zh: "短线偏多", ja: "短期強気", ko: "단기 강세")
        case .bearish:
            return LocalizedString.l(language, en: "Short-term bearish", zh: "短线偏空", ja: "短期弱気", ko: "단기 약세")
        case .neutral:
            return LocalizedString.l(language, en: "Short-term neutral", zh: "短线中性", ja: "短期中立", ko: "단기 중립")
        }
    }

    nonisolated private static func confidenceWord(
        _ confidence: GoldImpactConfidence,
        language: AppLanguage
    ) -> String {
        switch confidence {
        case .unavailable:
            return LocalizedString.l(language, en: "unavailable", zh: "不可用", ja: "利用不可", ko: "사용 불가")
        case .low:
            return LocalizedString.l(language, en: "low", zh: "低", ja: "低", ko: "낮음")
        case .medium:
            return LocalizedString.l(language, en: "medium", zh: "中", ja: "中", ko: "보통")
        case .high:
            return LocalizedString.l(language, en: "high", zh: "高", ja: "高", ko: "높음")
        }
    }

    nonisolated private static func dataStateText(
        for dataState: GoldIntelligenceDataState,
        language: AppLanguage
    ) -> String {
        switch dataState {
        case .live:
            return LocalizedString.l(language, en: "Live data", zh: "实时数据", ja: "リアルタイムデータ", ko: "실시간 데이터")
        case .partial:
            return LocalizedString.l(language, en: "Incomplete data", zh: "数据不完整", ja: "不完全なデータ", ko: "불완전한 데이터")
        case .stale:
            return LocalizedString.l(language, en: "Cached data", zh: "缓存数据", ja: "キャッシュデータ", ko: "캐시 데이터")
        case .unavailable:
            return LocalizedString.l(language, en: "Data unavailable", zh: "数据不可用", ja: "データ利用不可", ko: "데이터 사용 불가")
        }
    }

    nonisolated private static func riskWord(
        _ risk: GoldVolatilityRisk,
        language: AppLanguage
    ) -> String {
        switch risk {
        case .normal:
            return LocalizedString.l(language, en: "normal", zh: "正常", ja: "通常", ko: "보통")
        case .elevated:
            return LocalizedString.l(language, en: "elevated", zh: "升高", ja: "上昇", ko: "높아짐")
        case .high:
            return LocalizedString.l(language, en: "high", zh: "高", ja: "高い", ko: "높음")
        }
    }
}

// MARK: - 事件影响卡片

/// 展示事件影响引擎的方向、置信度、波动风险、证据链与反方风险。
/// 只负责解释，不生成任何交易动作（买入/卖出/减仓等），也不参与策略加权。
struct EventImpactCard: View {
    let impact: GoldEventImpact?
    let isLoading: Bool

    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    private var language: AppLanguage { settings.language }

    private var presentation: GoldEventImpactPresentation? {
        guard let impact else { return nil }
        return GoldEventImpactPresentation(impact: impact, language: language)
    }

    private var directionTint: Color {
        switch impact?.direction ?? .neutral {
        case .bullish: AppTheme.marketUp
        case .neutral: Color(red: 0.88, green: 0.57, blue: 0.16)
        case .bearish: AppTheme.marketDown
        }
    }

    /// 默认展开的 observed / inferred 条数上限，其余折叠进 DisclosureGroup。
    private static let maxExpandedObserved = 3
    private static let maxExpandedInferred = 2

    private var observedEvidence: [GoldEventEvidence] {
        (impact?.evidence ?? []).filter { $0.state == .observed }
    }

    private var inferredEvidence: [GoldEventEvidence] {
        (impact?.evidence ?? []).filter { $0.state == .inferred }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if let impact, let presentation {
                metricRow(presentation)

                stateBadge(impact)

                Text(impact.headline)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)

                if !observedEvidence.isEmpty {
                    Divider().opacity(0.45)
                    evidenceSection(
                        state: .observed,
                        items: observedEvidence,
                        expandedLimit: Self.maxExpandedObserved
                    )
                }

                if !inferredEvidence.isEmpty {
                    if observedEvidence.isEmpty { Divider().opacity(0.45) }
                    evidenceSection(
                        state: .inferred,
                        items: inferredEvidence,
                        expandedLimit: Self.maxExpandedInferred
                    )
                }

                if !impact.counterRisks.isEmpty {
                    Divider().opacity(0.45)
                    counterRiskSection(impact.counterRisks)
                }
            } else {
                Text(
                    isLoading
                        ? LocalizedString.l(language, en: "Loading event impact…", zh: "正在获取事件影响…", ja: "イベント影響を取得中…", ko: "이벤트 영향을 가져오는 중…")
                        : LocalizedString.l(language, en: "Event impact is unavailable", zh: "事件影响数据暂不可用", ja: "イベント影響データを利用できません", ko: "이벤트 영향 데이터를 사용할 수 없습니다")
                )
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            }

            Text(LocalizedString.l(
                language,
                en: "Event impact is a logical analysis of public data, not investment advice.",
                zh: "事件影响为基于公开数据的逻辑分析，不构成投资建议。",
                ja: "イベント影響は公開データに基づく論理分析であり、投資助言ではありません。",
                ko: "이벤트 영향은 공개 데이터 기반의 논리적 분석이며, 투자 조언이 아닙니다."
            ))
            .font(.system(size: 8))
            .foregroundStyle(AppTheme.textSecondary(colorScheme))
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(colorScheme == .dark ? Color.black.opacity(0.25) : Color.white.opacity(0.48))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(directionTint.opacity(0.18), lineWidth: 1)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(
                LocalizedString.l(language, en: "Event impact", zh: "事件影响", ja: "イベント影響", ko: "이벤트 영향"),
                systemImage: "bolt.horizontal"
            )
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(directionTint)

            Spacer(minLength: 6)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else if let updatedAt = impact?.updatedAt {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(LocalizedString.l(language, en: "As of ", zh: "数据截至 ", ja: "データ時点 ", ko: "데이터 기준 "))
                        .font(.system(size: 8.5))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    Text(updatedAt, style: .time)
                        .font(.system(size: 8.5))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                }
            }
        }
    }

    private func metricRow(_ presentation: GoldEventImpactPresentation) -> some View {
        HStack(spacing: 6) {
            metricChip(text: presentation.directionText, tint: directionTint)
            Spacer(minLength: 0)
            metricChip(text: presentation.confidenceText, tint: AppTheme.textPrimary(colorScheme))
            Spacer(minLength: 0)
            metricChip(text: presentation.riskText, tint: riskTint)
        }
    }

    private func metricChip(text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
            }
    }

    private var riskTint: Color {
        switch impact?.volatilityRisk ?? .normal {
        case .normal: AppTheme.textSecondary(colorScheme)
        case .elevated: Color(red: 0.88, green: 0.57, blue: 0.16)
        case .high: AppTheme.critical
        }
    }

    /// 数据状态用文字 + 图标表达，不只靠颜色。
    @ViewBuilder
    private func stateBadge(_ impact: GoldEventImpact) -> some View {
        let (text, icon, tint): (String, String, Color) = {
            switch impact.dataState {
            case .live:
                return (LocalizedString.l(language, en: "Live data", zh: "实时数据", ja: "リアルタイムデータ", ko: "실시간 데이터"), "checkmark.circle", AppTheme.healthy)
            case .partial:
                return (LocalizedString.l(language, en: "Incomplete data", zh: "数据不完整", ja: "不完全なデータ", ko: "불완전한 데이터"), "exclamationmark.triangle", AppTheme.warning)
            case .stale:
                return (LocalizedString.l(language, en: "Cached data", zh: "缓存数据", ja: "キャッシュデータ", ko: "캐시 데이터"), "clock.badge.checkmark", Color(red: 0.88, green: 0.57, blue: 0.16))
            case .unavailable:
                return (LocalizedString.l(language, en: "Data unavailable", zh: "数据不可用", ja: "データ利用不可", ko: "데이터 사용 불가"), "wifi.slash", AppTheme.critical)
            }
        }()
        Label(text, systemImage: icon)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func evidenceSection(
        state: GoldEvidenceState,
        items: [GoldEventEvidence],
        expandedLimit: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(GoldEventImpactPresentation.evidenceLabel(for: state, language: language))
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))

            ForEach(items.prefix(expandedLimit)) { evidence in
                evidenceRow(evidence)
            }

            if items.count > expandedLimit {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(items.dropFirst(expandedLimit)) { evidence in
                            evidenceRow(evidence)
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Text(LocalizedString.l(
                        language,
                        en: "Show \(items.count - expandedLimit) more",
                        zh: "展开其余 \(items.count - expandedLimit) 条",
                        ja: "残り \(items.count - expandedLimit) 件を表示",
                        ko: "나머지 \(items.count - expandedLimit)개 보기"
                    ))
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                }
            }
        }
    }

    @ViewBuilder
    private func evidenceRow(_ evidence: GoldEventEvidence) -> some View {
        let content = HStack(alignment: .top, spacing: 7) {
            Circle()
                .fill(evidenceTint(evidence.direction))
                .frame(width: 6, height: 6)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(evidence.summary)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary(colorScheme))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 5) {
                    if let source = evidence.source, !source.isEmpty {
                        Text(source)
                    }
                    if let observedAt = evidence.observedAt {
                        Text(observedAt, style: .relative)
                    }
                }
                .font(.system(size: 8.5))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }

            Spacer(minLength: 0)

            if evidence.link != nil {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }
        }

        // 新闻链接只挂在对应 observed 证据上，推断不提供跳转
        if let link = evidence.link, evidence.state == .observed {
            Link(destination: link) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    private func evidenceTint(_ direction: GoldImpactDirection) -> Color {
        switch direction {
        case .bullish: AppTheme.marketUp
        case .neutral: AppTheme.textSecondary(colorScheme)
        case .bearish: AppTheme.marketDown
        }
    }

    private func counterRiskSection(_ risks: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                LocalizedString.l(language, en: "Counter risks", zh: "反方风险", ja: "反対リスク", ko: "반대 리스크"),
                systemImage: "exclamationmark.circle"
            )
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(Color(red: 0.88, green: 0.57, blue: 0.16))

            ForEach(Array(risks.prefix(3).enumerated()), id: \.offset) { _, risk in
                Label(risk, systemImage: "circle.fill")
                    .font(.system(size: 9.5))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 预测学习卡片

