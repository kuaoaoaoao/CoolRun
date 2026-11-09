import Observation
import SwiftUI
import AppKit

struct GoldAnalysisView: View {
    @State private var store = GoldPriceStore.shared
    @State private var viewModel = GoldAnalysisViewModel()
    @State private var learningStore = GoldPredictionLearningStore.shared
    @ObservedObject private var appSettings = AppSettings.shared
    @State private var candlePeriod: CandlePeriod = .minute5
    @State private var chartRange: GoldChartRange = .today
    @State private var selectedTab: AnalysisTab = .analysis
    @State private var showTechnicalDetails = false
    // 手动刷新中（头部按钮显示 mini ProgressView）
    @State private var isManualRefreshing = false
    @AppStorage("goldHoldingGramsText") private var holdingGramsText = ""
    @AppStorage("goldHoldingAverageCostText") private var holdingAverageCostText = ""
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum AnalysisTab: String {
        case analysis = "analysis"
        case review = "review"

        func title(lang: AppLanguage) -> String {
            switch self {
            case .analysis: return LocalizedString.gold("analysis_tab", lang: lang)
            case .review: return LocalizedString.gold("review_tab", lang: lang)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            moduleHeader

            Group {
                switch selectedTab {
                case .analysis:
                    analysisContent
                case .review:
                    PredictionReviewView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appCardSurface(cornerRadius: 12)
    }

    private var moduleHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppTheme.gold)
                .frame(width: 28, height: 28)
                .background(
                    AppTheme.gold.opacity(colorScheme == .dark ? 0.20 : 0.13),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedString.l(
                    appSettings.language,
                    en: "Gold watch",
                    zh: "黄金观察",
                    ja: "金相場",
                    ko: "금 시세"
                ))
                .font(.system(size: 12.5, weight: .bold))
                Text(LocalizedString.l(
                    appSettings.language,
                    en: "Price, position and risk",
                    zh: "价格、持仓与风险提示",
                    ja: "価格・保有・リスク",
                    ko: "가격, 보유 및 위험"
                ))
                .font(.system(size: 9))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(LocalizedString.l(
                appSettings.language,
                en: "Gold watch, Price, position and risk",
                zh: "黄金观察，价格、持仓与风险提示",
                ja: "金相場、価格・保有・リスク",
                ko: "금 시세, 가격, 보유 및 위험"
            ))

            Spacer(minLength: 4)

            HStack(spacing: 2) {
                ForEach([AnalysisTab.analysis, .review], id: \.self) { tab in
                    Button {
                        guard selectedTab != tab else { return }
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                            selectedTab = tab
                        }
                    } label: {
                        Text(tab.title(lang: appSettings.language))
                            .font(.system(size: 9.5, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .frame(maxWidth: .infinity, minHeight: 24)
                            .foregroundStyle(
                                selectedTab == tab
                                    ? AppTheme.gold
                                    : AppTheme.textSecondary(colorScheme)
                            )
                            .background {
                                if selectedTab == tab {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(AppTheme.elevatedSurface(colorScheme))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .stroke(AppTheme.gold.opacity(0.14), lineWidth: 0.5)
                                        }
                                }
                            }
                            .rowHitTarget(cornerRadius: 6)
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.96, pressedOpacity: 0.85, reduceMotion: reduceMotion))
                    .accessibilityLabel(tab.title(lang: appSettings.language))
                    .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                }
            }
            .padding(2)
            .frame(width: 112)
            .background(
                AppTheme.progressBg(colorScheme).opacity(colorScheme == .dark ? 0.72 : 0.55),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )

            // 手动刷新：不用等定时器，随时拉最新金价
            Button {
                manualRefresh()
            } label: {
                if isManualRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.65)
                        .frame(width: 30, height: 30)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                        .frame(width: 30, height: 30)
                        .background(
                            AppTheme.progressBg(colorScheme).opacity(0.55),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
            }
            .buttonStyle(PressableButtonStyle(scale: 0.88, reduceMotion: reduceMotion))
            .disabled(isManualRefreshing)
            .accessibilityLabel(LocalizedString.l(appSettings.language, en: "Refresh now", zh: "立即刷新", ja: "今すぐ更新", ko: "지금 새로고침"))
            .help(LocalizedString.l(appSettings.language, en: "Refresh now", zh: "立即刷新", ja: "今すぐ更新", ko: "지금 새로고침"))
        }
        .padding(.horizontal, GoldLayout.contentInset)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var analysisContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: GoldLayout.sectionSpacing) {
                if let statistics = viewModel.statistics {
                    let positionAdvice = makePositionAdvice(currentPrice: statistics.currentPrice)
                    header(statistics: statistics)

                    GoldActionPlanCard(
                        plan: actionPlan(currentPrice: statistics.currentPrice),
                        isLoading: viewModel.isWeeklyForecastLoading
                    )

                    if viewModel.isLoading {
                        loadingCard
                    } else if let advancedReport = viewModel.advancedReport {
                        GoldDecisionSummaryCard(report: advancedReport)
                    }

                    GoldWeeklyForecastCard(
                        snapshot: viewModel.weeklyForecastSnapshot,
                        isLoading: viewModel.isWeeklyForecastLoading
                    )

                    marketChartCard

                    if !viewModel.multiSourcePrices.isEmpty {
                        MultiSourcePriceCard(
                            sources: viewModel.multiSourcePrices,
                            validation: store.crossValidatePrice(
                                statistics.currentPrice,
                                against: viewModel.multiSourcePrices
                            )
                        )
                    }

                    if let globalSnapshot = viewModel.globalSnapshot {
                        GlobalMarketCard(
                            snapshot: globalSnapshot,
                            domesticPrice: statistics.currentPrice
                        )
                    }

                    EventImpactCard(
                        impact: viewModel.eventImpact,
                        isLoading: viewModel.isMarketIntelligenceLoading
                    )

                    GoldPositionCard(
                        gramsText: $holdingGramsText,
                        averageCostText: $holdingAverageCostText,
                        advice: positionAdvice,
                        hasInput: hasPositionInput
                    )

                    GoldTradeLedgerCard(
                        gramsText: $holdingGramsText,
                        averageCostText: $holdingAverageCostText
                    )

                    technicalDetails

                    dataFooter(statistics: statistics)
                } else if viewModel.isLoading {
                    loadingCard
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, GoldLayout.contentInset)
            .padding(.bottom, 12)
        }
        .task {
            viewModel.refresh(records: store.records, candlePeriod: candlePeriod)
            viewModel.refreshMarketIntelligence(records: store.records, candlePeriod: candlePeriod)
            viewModel.refreshRemoteChart(range: chartRange)
            viewModel.refreshMultiSourcePrices()
        }
        .task {
            // 定时重新评估数据健康度，网络长时间失败时健康徽标也能变为"陈旧"
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                store.checkFreshness()
            }
        }
        .onChange(of: store.records) { _, records in
            viewModel.refresh(records: records, candlePeriod: candlePeriod)
            viewModel.refreshWeeklyForecast(records: records, eventImpact: viewModel.eventImpact)
        }
        .onChange(of: chartRange) { _, range in
            viewModel.refreshRemoteChart(range: range)
        }
        .onChange(of: candlePeriod) { _, period in
            viewModel.refresh(records: store.records, candlePeriod: period)
        }
        .onChange(of: appSettings.goldAutoCalibrationEnabled) { _, _ in
            // 设置页切换自动校准后立即重算，不等下一次金价刷新
            viewModel.refresh(records: store.records, candlePeriod: candlePeriod)
        }
        .onChange(of: holdingGramsText) { _, newValue in
            capturePositionIfValid()
            CloudSyncStore.shared.setString(newValue, for: .goldHoldingGrams)
        }
        .onChange(of: holdingAverageCostText) { _, newValue in
            capturePositionIfValid()
            CloudSyncStore.shared.setString(newValue, for: .goldHoldingAverageCost)
        }
        .onDisappear {
            viewModel.cancel()
        }
    }

    /// 把技术面、策略报告、一周预测三路输入压成一份能执行的计划。
    /// 只要拿不到当前价就返回 nil，卡片自己会退化成「数据不够」。
    private func actionPlan(currentPrice: Double) -> GoldActionPlan? {
        guard let snapshot = viewModel.snapshot else { return nil }
        return GoldActionPlanner.plan(
            currentPrice: currentPrice,
            snapshot: snapshot,
            signal: viewModel.signal,
            report: viewModel.advancedReport,
            weeklyForecast: viewModel.weeklyForecastSnapshot?.forecast,
            language: appSettings.language
        )
    }

    @ViewBuilder
    private var technicalDetails: some View {
        DisclosureGroup(isExpanded: $showTechnicalDetails) {
            VStack(spacing: 8) {
                if let snapshot = viewModel.snapshot {
                    indicatorGrid(snapshot: snapshot)
                }

                if let signal = viewModel.signal {
                    SignalCardView(signal: signal)
                }

                if let advancedReport = viewModel.advancedReport {
                    AdvancedStrategyCard(report: advancedReport)
                    MarketContextCard(
                        context: advancedReport.marketContext,
                        isLoading: viewModel.isMarketIntelligenceLoading
                    )
                    PredictionLearningCard(
                        summary: learningStore.summary,
                        records: learningStore.records
                    )
                    BeginnerGlossaryCard()
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(AppTheme.gold)
                VStack(alignment: .leading, spacing: 1) {
                    Text(LocalizedString.l(
                        appSettings.language,
                        en: "Deep analysis",
                        zh: "深度分析",
                        ja: "詳細分析",
                        ko: "심층 분석"
                    ))
                    .font(.system(size: 11, weight: .semibold))
                    Text(LocalizedString.l(
                        appSettings.language,
                        en: "Indicators, signals, macro and validation",
                        zh: "技术指标、交易信号、宏观与历史验证",
                        ja: "指標・シグナル・マクロ・検証",
                        ko: "지표, 신호, 거시 및 검증"
                    ))
                    .font(.system(size: 8))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                }
                Spacer()
            }
        }
        .tint(AppTheme.gold)
        .padding(10)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var tint: Color {
        switch viewModel.advancedReport?.compositeDirection {
        case .buy: return AppTheme.marketUp
        case .sell: return AppTheme.marketDown
        default: return Color(red: 0.88, green: 0.57, blue: 0.16)
        }
    }

    private func capturePositionIfValid() {
        guard let statistics = viewModel.statistics,
              let advice = makePositionAdvice(currentPrice: statistics.currentPrice) else { return }
        Analytics.capture(.goldPositionAnalyzed, properties: [
            "profit_state": profitState(for: advice.profitLoss),
            "profit_percent_bucket": profitPercentBucket(for: advice.profitPercent),
            "tone": advice.tone == .positive ? "positive" : advice.tone == .cautious ? "cautious" : "defensive",
        ], minimumInterval: 30)
    }

    private func profitState(for profitLoss: Double) -> String {
        if profitLoss > 0 { return "profit" }
        if profitLoss < 0 { return "loss" }
        return "break_even"
    }

    private func profitPercentBucket(for profitPercent: Double) -> String {
        let percent = abs(profitPercent)
        switch percent {
        case 0..<1:
            return "0_1"
        case 1..<3:
            return "1_3"
        case 3..<5:
            return "3_5"
        case 5..<10:
            return "5_10"
        default:
            return "10_plus"
        }
    }

    private func header(statistics: PriceStatistics) -> some View {
        GoldPriceSummaryCard(
            statistics: statistics,
            quote: store.latestQuote,
            health: store.dataHealth,
            lastUpdateDate: store.lastPriceUpdate ?? store.records.last?.timestamp,
            updateInterval: store.priceUpdateInterval,
            language: appSettings.language
        )
    }
    private var periodPicker: some View {
        HStack(spacing: 4) {
            ForEach(CandlePeriod.allCases, id: \.self) { period in
                Button {
                    candlePeriod = period
                } label: {
                    Text(period.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .foregroundStyle(candlePeriod == period ? amber : AppTheme.textSecondary(colorScheme))
                        .background {
                            if candlePeriod == period {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(amber.opacity(colorScheme == .dark ? 0.18 : 0.14))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.035))
        }
    }

    private var marketChartCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Label(
                    LocalizedString.l(
                        appSettings.language,
                        en: "Price trend",
                        zh: "价格走势",
                        ja: "価格推移",
                        ko: "가격 추세"
                    ),
                    systemImage: "chart.xyaxis.line"
                )
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary(colorScheme))
                Spacer()
                if viewModel.isRemoteChartLoading {
                    ProgressView()
                        .controlSize(.mini)
                } else if viewModel.remoteChartRange != chartRange {
                    // 远端失败回落本地采样数据时提示
                    Text(LocalizedString.l(
                        appSettings.language,
                        en: "Local data",
                        zh: "本地数据",
                        ja: "ローカル",
                        ko: "로컬"
                    ))
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                }
                Text(viewModel.statistics?.trendDescription ?? "")
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(tint)
            }

            chartRangePicker

            PriceLineChart(records: chartRecords)
                .frame(height: 82)

            // 时间轴起止标签（按界面语言本地化格式）
            if let axis = chartTimeAxis {
                HStack {
                    Text(axis.start)
                    Spacer()
                    Text(axis.end)
                }
                .font(.system(size: 7.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textSecondary(colorScheme).opacity(0.75))
            }

            // 选中范围的区间概览
            if let summary = chartSummary {
                HStack(spacing: 8) {
                    chartMetric(
                        label: LocalizedString.gold("high", lang: appSettings.language),
                        value: summary.high.goldPriceNumber
                    )
                    chartMetric(
                        label: LocalizedString.gold("low", lang: appSettings.language),
                        value: summary.low.goldPriceNumber
                    )
                    chartMetric(
                        label: LocalizedString.l(
                            appSettings.language,
                            en: "Change",
                            zh: "区间涨跌",
                            ja: "騰落",
                            ko: "등락"
                        ),
                        value: summary.changePercent.signedPercentText,
                        tint: AppTheme.marketColor(for: summary.changePercent)
                    )
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
                }
            }

            periodPicker

            HStack(spacing: 3) {
                let visibleCandles = viewModel.candles.suffix(28)
                let maximumChange = max(visibleCandles.map { abs($0.changePercent) }.max() ?? 0.01, 0.01)
                if visibleCandles.isEmpty {
                    Text(LocalizedString.gold("waiting_candle", lang: appSettings.language))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                        .frame(maxWidth: .infinity, minHeight: 28)
                } else {
                    ForEach(Array(visibleCandles)) { candle in
                        Capsule()
                            .fill(AppTheme.marketColor(isUp: candle.isUp))
                            .frame(width: 4, height: candleHeight(candle, maximumChange: maximumChange) * 0.68)
                            .frame(maxHeight: 30, alignment: candle.isUp ? .bottom : .top)
                            .opacity(0.82)
                            .help("\(candle.period.rawValue) \(candle.changePercent.signedPercentText)")
                    }
                }
            }
            .frame(height: 30)
        }
        .padding(GoldLayout.cardPadding)
        .goldPanelSurface()
    }

    // 走势图数据：官方数据就绪且范围匹配时优先，否则回落本地采样
    private var chartRecords: [GoldPriceRecord] {
        if viewModel.remoteChartRange == chartRange, !viewModel.remoteChartPoints.isEmpty {
            return viewModel.remoteChartPoints
        }
        return viewModel.displayRecords
    }

    // 选中范围的区间高/低/涨跌幅
    private var chartSummary: (high: Double, low: Double, changePercent: Double)? {
        let prices = chartRecords.map(\.price)
        guard let first = prices.first, first > 0,
              let last = prices.last,
              let high = prices.max(),
              let low = prices.min() else { return nil }
        return (high, low, (last - first) / first * 100)
    }

    // 图表起止时间标签：今日显示时刻，其余显示日期，随界面语言本地化
    private var chartTimeAxis: (start: String, end: String)? {
        guard let first = chartRecords.first?.timestamp,
              let last = chartRecords.last?.timestamp,
              first < last else { return nil }

        let formatter = DateFormatter()
        formatter.locale = appSettings.language.locale
        switch chartRange {
        case .today:
            formatter.setLocalizedDateFormatFromTemplate("jm")
        case .week, .month, .quarter:
            formatter.setLocalizedDateFormatFromTemplate("Md")
        case .halfYear, .year:
            formatter.setLocalizedDateFormatFromTemplate("yMd")
        }
        return (formatter.string(from: first), formatter.string(from: last))
    }

    private func chartMetric(label: String, value: String, tint: Color? = nil) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint ?? AppTheme.textPrimary(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private var chartRangePicker: some View {
        HStack(spacing: 3) {
            ForEach(GoldChartRange.allCases, id: \.self) { range in
                Button {
                    chartRange = range
                } label: {
                    Text(range.shortLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .foregroundStyle(chartRange == range ? amber : AppTheme.textSecondary(colorScheme))
                        .background {
                            if chartRange == range {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(amber.opacity(colorScheme == .dark ? 0.18 : 0.14))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.035))
        }
    }

    private var loadingCard: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedString.gold("generating_analysis", lang: appSettings.language))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary(colorScheme))
                Text(LocalizedString.gold("analysis_hint", lang: appSettings.language))
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func indicatorGrid(snapshot: TechnicalSnapshot) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                IndicatorPill(title: "RSI", value: snapshot.rsi14?.shortNumber ?? "--", detail: snapshot.rsiState.rawValue)
                IndicatorPill(title: "MACD", value: snapshot.macdHistogram?.signedShortNumber ?? "--", detail: snapshot.macdState.rawValue)
            }
            HStack(spacing: 6) {
                IndicatorPill(title: "SMA20", value: snapshot.sma20?.goldPriceNumber ?? "--", detail: LocalizedString.gold("sma", lang: appSettings.language))
                IndicatorPill(title: LocalizedString.gold("volatility", lang: appSettings.language), value: snapshot.volatility?.percentNumber ?? "--", detail: LocalizedString.gold("annualized", lang: appSettings.language))
            }
        }
    }

    private func dataFooter(statistics: PriceStatistics) -> some View {
        HStack {
            Label(String(format: LocalizedString.gold("items_count_format", lang: appSettings.language), statistics.recordCount), systemImage: "tray.full")
            Spacer()
            if let lastUpdateDate = statistics.lastUpdateDate {
                Text(lastUpdateDate, style: .time)
            }
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(AppTheme.textSecondary(colorScheme))
        .padding(.horizontal, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: store.lastFetchFailed ? "wifi.exclamationmark" : "chart.line.uptrend.xyaxis")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(store.lastFetchFailed ? AppTheme.critical : amber)
            // 区分"网络失败"与"等待首次数据"，失败时给重试按钮
            if store.lastFetchFailed {
                Text(LocalizedString.goldPrice("network_error", lang: appSettings.language))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary(colorScheme))
                Button {
                    manualRefresh()
                } label: {
                    Label(
                        LocalizedString.l(appSettings.language, en: "Retry", zh: "重试", ja: "再試行", ko: "재시도"),
                        systemImage: "arrow.clockwise"
                    )
                    .font(.system(size: 11, weight: .semibold))
                }
                .disabled(isManualRefreshing)
            } else {
                Text(LocalizedString.gold("waiting_refresh", lang: appSettings.language))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary(colorScheme))
                Text(LocalizedString.gold("refresh_hint", lang: appSettings.language))
                    .font(.system(size: 11))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 190)
        .padding(12)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // 手动刷新：先拉菜单栏同源金价，再刷新分析与行情卡片
    private func manualRefresh() {
        guard !isManualRefreshing else { return }
        isManualRefreshing = true
        Task {
            if let delegate = NSApp.delegate as? MacAppDelegate {
                await delegate.refreshGoldPriceNow()
            }
            viewModel.refresh(records: store.records, candlePeriod: candlePeriod)
            viewModel.refreshMarketIntelligence(records: store.records, candlePeriod: candlePeriod)
            viewModel.refreshRemoteChart(range: chartRange)
            viewModel.refreshMultiSourcePrices()
            isManualRefreshing = false
        }
    }

    private var panelBackground: some ShapeStyle {
        colorScheme == .dark ? Color.black.opacity(0.30) : Color.white.opacity(0.55)
    }

    private var amber: Color {
        AppTheme.gold
    }

    private func candleHeight(_ candle: GoldCandlestick, maximumChange: Double) -> CGFloat {
        8 + CGFloat(min(abs(candle.changePercent) / maximumChange, 1)) * 32
    }

    private var hasPositionInput: Bool {
        !holdingGramsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !holdingAverageCostText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func makePositionAdvice(currentPrice: Double) -> GoldHoldingAdvice? {
        guard let grams = parseInputNumber(holdingGramsText),
              let averageCost = parseInputNumber(holdingAverageCostText) else {
            return nil
        }

        return GoldPositionAdvisor.analyze(
            currentPrice: currentPrice,
            grams: grams,
            averageCost: averageCost,
            report: viewModel.advancedReport,
            signal: viewModel.signal
        )
    }

    private func parseInputNumber(_ text: String) -> Double? {
        var normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "．", with: ".")
            .replacingOccurrences(of: "。", with: ".")
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "￥", with: "")
            .replacingOccurrences(of: "元", with: "")
            .replacingOccurrences(of: "克", with: "")
            .replacingOccurrences(of: "g", with: "")
            .replacingOccurrences(of: "G", with: "")
            .replacingOccurrences(of: " ", with: "")

        if normalized.contains(","), normalized.contains(".") {
            normalized.removeAll { $0 == "," }
        } else if normalized.contains(",") {
            let parts = normalized.split(separator: ",", omittingEmptySubsequences: false)
            if parts.count == 2, (1...2).contains(parts[1].count) {
                normalized = parts.joined(separator: ".")
            } else {
                normalized.removeAll { $0 == "," }
            }
        }

        return Double(normalized)
    }
}
