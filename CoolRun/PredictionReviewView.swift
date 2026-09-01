import SwiftUI
import Observation

/// 完整预测复盘页
/// 展示所有预测历史、支持多维筛选、每条预测的证据快照。
/// 顶部 segmented 切换 30 分钟预测与一周预测复盘；两个 Store 的 summary 独立展示，不相加。
@MainActor
struct PredictionReviewView: View {
    @State private var store = GoldPredictionLearningStore.shared
    @State private var priceStore = GoldPriceStore.shared
    @State private var expandedRecordID: UUID?
    @State private var reviewScope: ReviewScope = .thirtyMinutes
    @ObservedObject private var appSettings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    enum ReviewScope: String, CaseIterable, Identifiable {
        case thirtyMinutes
        case weekly

        var id: String { rawValue }

        func title(lang: AppLanguage) -> String {
            switch self {
            case .thirtyMinutes:
                return LocalizedString.l(lang, en: "30 min", zh: "30 分钟", ja: "30分", ko: "30분")
            case .weekly:
                return LocalizedString.l(lang, en: "1 week", zh: "一周", ja: "1週間", ko: "1주")
            }
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            scopePicker

            switch reviewScope {
            case .thirtyMinutes:
                thirtyMinutesContent
            case .weekly:
                GoldWeeklyForecastReviewView()
            }
        }
        .padding(.vertical, 6)
        .background(colorScheme == .dark ? Color.black.opacity(0.28) : Color.white.opacity(0.72))
    }

    private var scopePicker: some View {
        Picker(
            LocalizedString.l(appSettings.language, en: "Scope", zh: "范围", ja: "範囲", ko: "범위"),
            selection: $reviewScope
        ) {
            ForEach(ReviewScope.allCases) { scope in
                Text(scope.title(lang: appSettings.language)).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 160)
        .frame(maxWidth: .infinity)
    }

    private var thirtyMinutesContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                summaryCard
                if !store.allRecords.isEmpty {
                    groupedStatsCard
                }
                filterSection
                recordList
            }
            .padding(.vertical, 6)
        }
    }
    
    // MARK: - Summary Card
    
    private var dataHealthStatus: String {
        priceStore.dataHealth.description
    }
    
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(LocalizedString.gold("review_overview", lang: appSettings.language), systemImage: "target")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                Spacer()
                Text(store.summary.hitRate?.percentNumber ?? "--")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
            
            // 数据健康状态
            HStack(spacing: 8) {
                Label(dataHealthStatus, systemImage: dataHealthIcon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(dataHealthColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(dataHealthColor.opacity(0.10))
                    .clipShape(Capsule())
                
                if let age = priceStore.lastPriceAge {
                    Text(LocalizedString.goldAge(age, lang: appSettings.language))
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                }
                
                Spacer()
            }
            
            HStack(spacing: 8) {
                StatPill(title: LocalizedString.gold("total_predictions", lang: appSettings.language), value: "\(store.summary.totalCount)", detail: "\(LocalizedString.gold("validated", lang: appSettings.language)) \(store.summary.validatedCount)")
                StatPill(title: LocalizedString.gold("pending", lang: appSettings.language), value: "\(store.summary.pendingCount)", detail: "")
                StatPill(title: LocalizedString.gold("average_error", lang: appSettings.language), value: store.summary.averageAbsoluteError?.percentNumber ?? "--", detail: LocalizedString.gold("minutes_30", lang: appSettings.language))
                StatPill(title: LocalizedString.gold("prediction_bias", lang: appSettings.language), value: store.summary.averagePredictionBias?.signedPercentNumber ?? "--", detail: LocalizedString.gold("prediction_minus_actual", lang: appSettings.language))
            }
            
            if !store.summary.calibrationText.isEmpty {
                Text(store.summary.calibrationText)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            if !appSettings.goldAutoCalibrationEnabled {
                Label(LocalizedString.gold("calibration_off_note", lang: appSettings.language), systemImage: "pause.circle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            } else if !store.summary.strategyCalibration.isNeutral {
                calibrationBadge
            }
        }
        .padding(12)
        .background(panelBg)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tint.opacity(0.15), lineWidth: 1)
        }
    }
    
    private var calibrationBadge: some View {
        let cal = store.summary.strategyCalibration
        return HStack(spacing: 6) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 10))
            Text(String(
                format: LocalizedString.gold("calibration_applied_format", lang: appSettings.language),
                cal.confidenceMultiplier.twoDigitNumber,
                cal.exposureMultiplier.twoDigitNumber
            ))
                .font(.system(size: 10, weight: .medium))
            Text(cal.note)
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.10))
        .clipShape(Capsule())
    }
    
    // MARK: - Grouped Stats
    
    /// 分组统计：按策略版本、市场状态、预测方向展示命中率和平均误差
    private var groupedStatsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(LocalizedString.gold("group_stats", lang: appSettings.language), systemImage: "chart.bar.doc.horizontal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary(colorScheme))
            
            groupedStatsSection(
                title: LocalizedString.gold("by_strategy_version", lang: appSettings.language),
                summaries: store.summaryByStrategyVersion,
                displayName: { $0 }
            )
            groupedStatsSection(
                title: LocalizedString.gold("by_market_state", lang: appSettings.language),
                summaries: store.summaryByRegime,
                displayName: { $0 }
            )
            groupedStatsSection(
                title: LocalizedString.gold("by_direction", lang: appSettings.language),
                summaries: store.summaryByDirection,
                displayName: { directionText(for: $0) }
            )
        }
        .padding(12)
        .background(panelBg)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    
    @ViewBuilder
    private func groupedStatsSection(
        title: String,
        summaries: [String: GoldPredictionLearningSummary],
        displayName: @escaping (String) -> String
    ) -> some View {
        if !summaries.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                
                ForEach(summaries.keys.sorted(), id: \.self) { key in
                    if let groupSummary = summaries[key] {
                        groupedStatsRow(name: displayName(key), summary: groupSummary)
                    }
                }
            }
        }
    }
    
    private func groupedStatsRow(name: String, summary: GoldPredictionLearningSummary) -> some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppTheme.textPrimary(colorScheme))
                .lineLimit(1)
                .frame(minWidth: 60, alignment: .leading)
            
            Spacer()
            
            Text(String(format: LocalizedString.gold("validated_count_format", lang: appSettings.language), summary.validatedCount))
                .font(.system(size: 9))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
            
            Text("\(LocalizedString.gold("hit_rate", lang: appSettings.language)) \(summary.hitRate?.percentNumber ?? "--")")
                .font(.system(size: 9, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(hitRateColor(summary))
            
            Text("\(LocalizedString.gold("average_error", lang: appSettings.language)) \(summary.averageAbsoluteError?.percentNumber ?? "--")")
                .font(.system(size: 9))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
    
    private func hitRateColor(_ summary: GoldPredictionLearningSummary) -> Color {
        guard let hitRate = summary.hitRate, summary.validatedCount >= 8 else {
            return AppTheme.textSecondary(colorScheme)
        }
        if hitRate >= 0.62 { return AppTheme.healthy }
        if hitRate <= 0.42 { return AppTheme.critical }
        return Color(red: 0.88, green: 0.57, blue: 0.16)
    }
    
    // MARK: - Filter Section
    
    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(LocalizedString.gold("filter", lang: appSettings.language), systemImage: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary(colorScheme))
                Spacer()
                Button(LocalizedString.gold("clear", lang: appSettings.language)) {
                    store.clearFilter()
                }
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                .disabled(isFilterEmpty)
            }
            
            filterRow(
                label: LocalizedString.gold("strategy_version", lang: appSettings.language),
                options: GoldPredictionLearningStore.availableStrategyVersions,
                selection: $store.filterStrategyVersion,
                placeholder: LocalizedString.gold("all_versions", lang: appSettings.language)
            )
            
            HStack(spacing: 8) {
                filterRowCompact(
                    label: LocalizedString.gold("market_state", lang: appSettings.language),
                    options: GoldPredictionLearningStore.availableRegimes,
                    selection: $store.filterRegime,
                    placeholder: LocalizedString.gold("all", lang: appSettings.language)
                )
                let buyText = LocalizedString.gold("buy", lang: appSettings.language)
                let sellText = LocalizedString.gold("sell", lang: appSettings.language)
                filterRowCompact(
                    label: LocalizedString.gold("direction", lang: appSettings.language),
                    options: GoldPredictionLearningStore.availableDirections.map { $0 == "buy" ? buyText : sellText },
                    selection: Binding(
                        get: { store.filterDirection.map { $0 == "buy" ? buyText : sellText } },
                        set: { newValue in
                            // 选"全部"（nil）时清空筛选，否则映射回内部值
                            switch newValue {
                            case buyText: store.filterDirection = "buy"
                            case sellText: store.filterDirection = "sell"
                            default: store.filterDirection = nil
                            }
                        }
                    ),
                    placeholder: LocalizedString.gold("all", lang: appSettings.language)
                )
                let pendingText = LocalizedString.gold("pending", lang: appSettings.language)
                let validatedText = LocalizedString.gold("validated", lang: appSettings.language)
                filterRowCompact(
                    label: LocalizedString.gold("status", lang: appSettings.language),
                    options: [pendingText, validatedText],
                    selection: Binding(
                        get: { store.filterStatus.map { $0 == .pending ? pendingText : validatedText } },
                        set: { newValue in
                            // 选"全部"（nil）时清空筛选，否则映射回内部值
                            switch newValue {
                            case pendingText: store.filterStatus = .pending
                            case validatedText: store.filterStatus = .validated
                            default: store.filterStatus = nil
                            }
                        }
                    ),
                    placeholder: LocalizedString.gold("all", lang: appSettings.language)
                )
            }
        }
        .padding(12)
        .background(panelBg)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    
    private func filterRow(label: String, options: [String], selection: Binding<String?>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
            Picker("", selection: selection) {
                Text(placeholder).tag(String?.none)
                ForEach(options, id: \.self) { option in
                    Text(option).tag(String?.some(option))
                }
            }
            .pickerStyle(.menu)
            .font(.system(size: 11))
            .foregroundStyle(AppTheme.textPrimary(colorScheme))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
    
    private func filterRowCompact(label: String, options: [String], selection: Binding<String?>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
            Picker("", selection: selection) {
                Text(placeholder).tag(String?.none)
                ForEach(options, id: \.self) { option in
                    Text(option).tag(String?.some(option))
                }
            }
            .pickerStyle(.menu)
            .font(.system(size: 10))
            .foregroundStyle(AppTheme.textPrimary(colorScheme))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
    }
    
    private var isFilterEmpty: Bool {
        store.filterStrategyVersion == nil &&
        store.filterRegime == nil &&
        store.filterDirection == nil &&
        store.filterStatus == nil
    }
    
    // MARK: - Record List
    
    private var recordList: some View {
        LazyVStack(spacing: 8, pinnedViews: []) {
            if store.records.isEmpty {
                emptyState
            } else {
                ForEach(store.records) { record in
                    recordRow(record: record)
                }
            }
        }
    }
    
    private var emptyState: some View {
        ContentUnavailableView {
            Label(LocalizedString.gold("no_prediction_records", lang: appSettings.language), systemImage: "target")
        } description: {
            Text(LocalizedString.gold("no_prediction_hint", lang: appSettings.language))
        }
    }
    
    private func recordRow(record: GoldPredictionLearningRecord) -> some View {
        let isExpanded = expandedRecordID == record.id
        return VStack(spacing: 0) {
            // 主行：方向 + 状态 + 时间 + 简要结果
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // 方向标签
                Text(directionText(for: record.predictedDirection))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(directionColor(for: record.predictedDirection))
                    .frame(width: 36, alignment: .leading)
                
                // 状态和时间
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        statusBadge(record: record)
                        Text(record.createdAt, style: .date)
                            .font(.system(size: 9))
                            .foregroundStyle(AppTheme.textSecondary(colorScheme))
                        Text(record.createdAt, style: .time)
                            .font(.system(size: 9))
                            .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    }
                    Text("\(LocalizedString.gold("strategy_version", lang: appSettings.language)): \(record.strategyVersion) · \(record.regime)")
                        .font(.system(size: 9))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme).opacity(0.7))
                }
                
                Spacer()
                
                // 结果
                if record.status == .validated, let actualReturn = record.actualReturn {
                    resultView(actualReturn: actualReturn, wasHit: record.wasDirectionalHit == true)
                } else if record.status == .pending {
                    Text(LocalizedString.gold("pending", lang: appSettings.language))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(red: 0.88, green: 0.57, blue: 0.16))
                }
                
                // 展开按钮
                Button {
                    expandedRecordID = isExpanded ? nil : record.id
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(panelBg)
            // 整行可点展开，不用去点 10pt 的小箭头
            .contentShape(Rectangle())
            .onTapGesture {
                expandedRecordID = isExpanded ? nil : record.id
            }
            
            // 展开的详情区域
            if isExpanded {
                VStack(spacing: 8) {
                    Divider()
                        .background(AppTheme.textSecondary(colorScheme).opacity(0.2))
                    
                    // 证据快照
                    evidenceSnapshot(record: record)
                    
                    // 详细信息表格
                    detailTable(record: record)
                    
                    // 原始依据
                    if !record.sourceSummary.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(LocalizedString.gold("source_summary", lang: appSettings.language))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                            Text(record.sourceSummary)
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.textPrimary(colorScheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(panelBg.opacity(0.6))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    
    // MARK: - Row Components
    
    private func statusBadge(record: GoldPredictionLearningRecord) -> some View {
        let (text, color): (String, Color) = {
            switch record.status {
            case .pending:
                return (LocalizedString.gold("pending", lang: appSettings.language), Color(red: 0.88, green: 0.57, blue: 0.16))
            case .validated:
                if record.wasDirectionalHit == true {
                    return (LocalizedString.gold("hit", lang: appSettings.language), AppTheme.healthy)
                } else if record.wasDirectionalHit == false {
                    return (LocalizedString.gold("miss", lang: appSettings.language), AppTheme.critical)
                }
                return (LocalizedString.gold("validated", lang: appSettings.language), AppTheme.textSecondary(colorScheme))
            }
        }()
        
        return Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
    
    private func resultView(actualReturn: Double, wasHit: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(String(format: LocalizedString.gold("actual_return_format", lang: appSettings.language), actualReturn.signedPercentNumber))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(wasHit ? AppTheme.healthy : AppTheme.critical)
        }
    }
    
    // MARK: - Evidence Snapshot
    
    private func evidenceSnapshot(record: GoldPredictionLearningRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedString.gold("evidence_snapshot", lang: appSettings.language))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
            
            HStack(spacing: 12) {
                // 左侧：技术面
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedString.gold("technicals", lang: appSettings.language))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    evidenceLine(LocalizedString.gold("opportunity_score", lang: appSettings.language), "\(Int(record.technicalOpportunity))")
                    evidenceLine(LocalizedString.gold("suggested_position", lang: appSettings.language), "\(record.suggestedExposure.percentNumber)")
                    evidenceLine(LocalizedString.gold("predicted_return", lang: appSettings.language), record.predictedReturn.signedPercentNumber)
                }
                
                Divider()
                
                // 右侧：宏观新闻
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedString.gold("macro_news_analysis", lang: appSettings.language))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    if let macroScore = record.macroScore {
                        evidenceLine(LocalizedString.gold("macro_score", lang: appSettings.language), "\(macroScore.signedShortNumber)")
                    } else {
                        Text("\(LocalizedString.gold("macro_score", lang: appSettings.language)): \(LocalizedString.gold("none", lang: appSettings.language))")
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.textSecondary(colorScheme).opacity(0.6))
                    }
                    if let newsScore = record.newsScore {
                        evidenceLine(LocalizedString.gold("news_score", lang: appSettings.language), "\(newsScore.signedShortNumber)")
                    } else {
                        Text("\(LocalizedString.gold("news_score", lang: appSettings.language)): \(LocalizedString.gold("none", lang: appSettings.language))")
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.textSecondary(colorScheme).opacity(0.6))
                    }
                }
            }
        }
    }
    
    private func evidenceLine(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textPrimary(colorScheme))
        }
    }
    
    // MARK: - Detail Table
    
    private func detailTable(record: GoldPredictionLearningRecord) -> some View {
        let rows: [(String, String)] = [
            (LocalizedString.gold("record_id", lang: appSettings.language), record.id.uuidString.prefix(8) + "..."),
            (LocalizedString.gold("direction", lang: appSettings.language), directionText(for: record.predictedDirection)),
            (LocalizedString.gold("confidence_value", lang: appSettings.language), record.confidence.percentNumber),
            (LocalizedString.gold("strategy_version", lang: appSettings.language), record.strategyVersion),
            (LocalizedString.gold("market_state", lang: appSettings.language), record.regime),
            (LocalizedString.gold("start_price", lang: appSettings.language), "¥\(record.startPrice.goldPriceNumber)/g"),
            (LocalizedString.gold("predicted_return", lang: appSettings.language), record.predictedReturn.signedPercentNumber),
            (LocalizedString.gold("created_at", lang: appSettings.language), record.createdAt.formatted(.dateTime.year().month().day().hour().minute())),
            (LocalizedString.gold("resolved_at", lang: appSettings.language), record.resolvedAt?.formatted(.dateTime.year().month().day().hour().minute()) ?? "--"),
        ]
        
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { row in
                let index = row.offset
                let label = row.element.0
                let value = row.element.1

                HStack {
                    Text(label)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                        .frame(width: 80, alignment: .leading)
                    Text(value)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary(colorScheme))
                    Spacer()
                }
                .padding(.vertical, 3)
                if index < rows.count - 1 {
                    Divider()
                        .background(AppTheme.textSecondary(colorScheme).opacity(0.1))
                }
            }
        }
        .padding(10)
        .background(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
    
    // MARK: - Helpers
    
    private var tint: Color {
        guard let hitRate = store.summary.hitRate, store.summary.validatedCount >= 8 else {
            return Color(red: 0.88, green: 0.57, blue: 0.16)
        }
        if hitRate >= 0.62 { return AppTheme.healthy }
        if hitRate <= 0.42 { return AppTheme.critical }
        return Color(red: 0.88, green: 0.57, blue: 0.16)
    }
    
    private var dataHealthColor: Color {
        switch priceStore.dataHealth {
        case .healthy: return AppTheme.healthy
        case .stale: return Color(red: 0.88, green: 0.57, blue: 0.16)
        case .priceJump: return Color.orange
        case .invalidPrice: return AppTheme.critical
        }
    }
    
    private var dataHealthIcon: String {
        switch priceStore.dataHealth {
        case .healthy: return "checkmark.circle"
        case .stale: return "clock.badge.exclamationmark"
        case .priceJump: return "arrow.up.arrow.down.circle"
        case .invalidPrice: return "xmark.octagon"
        }
    }
    
    private var panelBg: some ShapeStyle {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06)
    }
    
    private func directionText(for direction: String) -> String {
        switch direction {
        case "buy": return LocalizedString.gold("buy", lang: appSettings.language)
        case "sell": return LocalizedString.gold("sell", lang: appSettings.language)
        default: return LocalizedString.gold("hold", lang: appSettings.language)
        }
    }
    
    private func directionColor(for direction: String) -> Color {
        switch direction {
        case "buy": return AppTheme.healthy
        case "sell": return AppTheme.critical
        default: return AppTheme.textSecondary(colorScheme)
        }
    }
}

// MARK: - StatPill

private struct StatPill: View {
    let title: String
    let value: String
    let detail: String
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textPrimary(colorScheme))
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 8))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme).opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private extension Double {
    var goldPriceNumber: String {
        formatted(.number.precision(.fractionLength(2)))
    }

    var twoDigitNumber: String {
        formatted(.number.precision(.fractionLength(2)))
    }

    var percentNumber: String {
        formatted(.percent.precision(.fractionLength(1)))
    }

    var signedPercentNumber: String {
        formatted(.percent.sign(strategy: .always()).precision(.fractionLength(1)))
    }

    var signedShortNumber: String {
        formatted(.number.sign(strategy: .always()).precision(.fractionLength(2)))
    }
}
