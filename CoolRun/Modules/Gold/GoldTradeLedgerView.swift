import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

// MARK: - 黄金交易流水卡片

/// 交易流水与持仓收益：记录多笔买卖、自动算持仓均价、收益曲线、CSV 导出。
/// 挂载在 GoldAnalysisView 的持仓卡之后，无流水时显示折叠入口。
struct GoldTradeLedgerCard: View {
    @Binding var gramsText: String
    @Binding var averageCostText: String
    @State private var tradeStore = GoldTradeStore.shared
    @State private var priceStore = GoldPriceStore.shared
    @ObservedObject private var appSettings = AppSettings.shared
    @ObservedObject private var router = AppNavigationRouter.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var isExpanded = false
    // 删除前待确认的记录（confirmationDialog 防误删）
    @State private var recordPendingDelete: GoldTradeRecord?
    // CSV 导出成功后短暂显示“已导出”
    @State private var csvExported = false
    @State private var csvExportFeedbackTask: Task<Void, Never>?
    // 添加表单
    @State private var formIsBuy = true
    @State private var formGrams = ""
    @State private var formPrice = ""
    @State private var formDate = Date()

    private var lang: AppLanguage { appSettings.language }

    private var summary: (grams: Double, averageCost: Double) {
        GoldTradeStore.holdingSummary(records: tradeStore.records)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header

            if isExpanded {
                if !tradeStore.records.isEmpty {
                    summaryRow
                    profitCurveSection
                    recordList
                } else {
                    Text(LocalizedString.l(
                        lang,
                        en: "Log each buy/sell to track average cost and profit over time.",
                        zh: "记录每笔买卖，自动计算持仓均价与收益变化。",
                        ja: "売買を記録すると平均コストと損益を自動計算します。",
                        ko: "매수/매도를 기록하면 평균 단가와 손익을 자동 계산합니다."
                    ))
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                }

                addForm
            }
        }
        .padding(10)
        .background(AppTheme.gold.opacity(colorScheme == .dark ? 0.10 : 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.gold.opacity(0.18), lineWidth: 1)
        }
        .onAppear {
            if !tradeStore.records.isEmpty { isExpanded = true }
        }
        .onReceive(router.$request.compactMap { $0 }) { request in
            guard request.quickAction == .recordGoldTrade else { return }
            withAnimation(.easeInOut(duration: 0.15)) { isExpanded = true }
            router.consumeQuickAction(request.id)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Label(
                LocalizedString.l(lang, en: "Trade Ledger", zh: "交易流水", ja: "取引履歴", ko: "거래 내역"),
                systemImage: "list.bullet.rectangle.portrait"
            )
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(AppTheme.textPrimary(colorScheme))

            if !tradeStore.records.isEmpty {
                Text("\(tradeStore.records.count)")
                    .font(.system(size: 9, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.gold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppTheme.gold.opacity(0.14), in: Capsule())
            }

            Spacer(minLength: 6)

            if !tradeStore.records.isEmpty {
                Button {
                    exportCSV()
                } label: {
                    Label(
                        csvExported
                            ? LocalizedString.l(lang, en: "Exported", zh: "已导出", ja: "エクスポート済み", ko: "내보냄 완료")
                            : LocalizedString.l(lang, en: "CSV", zh: "CSV", ja: "CSV", ko: "CSV"),
                        systemImage: csvExported ? "checkmark.circle.fill" : "square.and.arrow.up"
                    )
                    .font(.system(size: 9, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(csvExported ? AppTheme.healthy : AppTheme.textSecondary(colorScheme))
                .help(LocalizedString.l(lang, en: "Export CSV", zh: "导出 CSV", ja: "CSV をエクスポート", ko: "CSV 내보내기"))
            }

            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
        }
    }

    // MARK: - 持仓汇总

    private var summaryRow: some View {
        let result = summary
        return HStack(spacing: 6) {
            ledgerMetric(
                title: LocalizedString.l(lang, en: "Held", zh: "持仓", ja: "保有", ko: "보유"),
                value: String(format: "%.2f g", result.grams)
            )
            ledgerMetric(
                title: LocalizedString.l(lang, en: "Avg cost", zh: "均价", ja: "平均コスト", ko: "평균 단가"),
                value: result.grams > 0 ? String(format: "¥%.2f", result.averageCost) : "--"
            )

            Button {
                applyToHoldings(result)
            } label: {
                Label(
                    LocalizedString.l(lang, en: "Apply", zh: "应用到持仓", ja: "保有に反映", ko: "보유에 적용"),
                    systemImage: "arrow.right.circle"
                )
                .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(AppTheme.gold)
            .disabled(result.grams <= 0)
            .help(LocalizedString.l(
                lang,
                en: "Write computed grams and average cost into the position card",
                zh: "把计算出的克数与均价写入上方持仓卡",
                ja: "計算した保有量と平均コストを保有カードへ反映",
                ko: "계산된 보유량과 평균 단가를 보유 카드에 반영"
            ))
        }
    }

    private func ledgerMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textPrimary(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(7)
        .background(AppTheme.progressBg(colorScheme), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    // MARK: - 收益曲线

    @ViewBuilder
    private var profitCurveSection: some View {
        let result = summary
        let curveRecords = priceStore.recordsSince(Date().addingTimeInterval(-30 * 24 * 3600))
        if result.grams > 0, curveRecords.count >= 2 {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(LocalizedString.l(lang, en: "P/L · 30 days", zh: "收益曲线 · 近30天", ja: "損益 · 30日", ko: "손익 · 30일"))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    Spacer()
                    if let lastPrice = curveRecords.last?.price {
                        let profit = result.grams * (lastPrice - result.averageCost)
                        Text(String(format: "%@¥%.0f", profit >= 0 ? "+" : "-", abs(profit)))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.marketColor(for: profit))
                    }
                }

                ProfitCurveChart(
                    records: curveRecords,
                    grams: result.grams,
                    averageCost: result.averageCost
                )
                .frame(height: 56)
            }
            .padding(7)
            .background(AppTheme.progressBg(colorScheme), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }

    // MARK: - 流水列表

    private var recordList: some View {
        VStack(spacing: 3) {
            ForEach(tradeStore.records.reversed().prefix(8)) { record in
                recordRow(record)
            }
            if tradeStore.records.count > 8 {
                Text(LocalizedString.l(
                    lang,
                    en: "Showing latest 8 of \(tradeStore.records.count)",
                    zh: "仅显示最近 8 条，共 \(tradeStore.records.count) 条",
                    ja: "最新 8 件を表示（全 \(tradeStore.records.count) 件）",
                    ko: "최근 8건 표시 (총 \(tradeStore.records.count)건)"
                ))
                .font(.system(size: 8))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }
        }
    }

    private func recordRow(_ record: GoldTradeRecord) -> some View {
        HStack(spacing: 6) {
            Text(record.isBuy
                 ? LocalizedString.l(lang, en: "BUY", zh: "买入", ja: "買い", ko: "매수")
                 : LocalizedString.l(lang, en: "SELL", zh: "卖出", ja: "売り", ko: "매도"))
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(record.isBuy ? Color(nsColor: .systemRed) : Color(nsColor: .systemGreen))
                .frame(width: 30, alignment: .leading)

            Text(record.date, format: .dateTime.month(.twoDigits).day(.twoDigits))
                .font(.system(size: 9))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))

            Spacer(minLength: 4)

            Text(String(format: "%.2f g", abs(record.grams)))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textPrimary(colorScheme))

            Text(String(format: "¥%.2f", record.pricePerGram))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textPrimary(colorScheme))
                .frame(width: 62, alignment: .trailing)

            Button {
                recordPendingDelete = record
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme).opacity(0.6))
                    // 扩大热区，9pt 图标本身太难点
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(LocalizedString.l(lang, en: "Delete", zh: "删除", ja: "削除", ko: "삭제"))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(AppTheme.progressBg(colorScheme), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .confirmationDialog(
            LocalizedString.l(lang, en: "Delete this record?", zh: "删除这条记录？", ja: "この記録を削除しますか？", ko: "이 기록을 삭제하시겠습니까?"),
            isPresented: Binding(
                get: { recordPendingDelete?.id == record.id },
                set: { if !$0 { recordPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(LocalizedString.l(lang, en: "Delete", zh: "删除", ja: "削除", ko: "삭제"), role: .destructive) {
                tradeStore.remove(id: record.id)
                recordPendingDelete = nil
            }
            Button(LocalizedString.l(lang, en: "Cancel", zh: "取消", ja: "キャンセル", ko: "취소"), role: .cancel) {
                recordPendingDelete = nil
            }
        }
    }

    // MARK: - 添加表单

    private var addForm: some View {
        // 面板宽度有限（320pt），表单拆成两行避免撑破卡片
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Picker("", selection: $formIsBuy) {
                    Text(LocalizedString.l(lang, en: "Buy", zh: "买入", ja: "買い", ko: "매수")).tag(true)
                    Text(LocalizedString.l(lang, en: "Sell", zh: "卖出", ja: "売り", ko: "매도")).tag(false)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 96)

                TextField(
                    LocalizedString.l(lang, en: "Grams", zh: "克数", ja: "グラム", ko: "그램"),
                    text: $formGrams
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10))
                .frame(minWidth: 50, maxWidth: .infinity)

                TextField(
                    LocalizedString.l(lang, en: "¥/g", zh: "单价 ¥/g", ja: "単価 ¥/g", ko: "단가 ¥/g"),
                    text: $formPrice
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10))
                .frame(minWidth: 60, maxWidth: .infinity)
            }

            HStack(spacing: 6) {
                DatePicker("", selection: $formDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .font(.system(size: 10))

                Spacer(minLength: 6)

                Button {
                    addRecord()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(canAdd ? AppTheme.gold : AppTheme.textSecondary(colorScheme).opacity(0.4))
                }
                .buttonStyle(.plain)
                .disabled(!canAdd)
                .help(LocalizedString.l(lang, en: "Add record", zh: "添加记录", ja: "記録を追加", ko: "기록 추가"))
            }

            // 非法输入时给出原因，不让按钮静默置灰
            if hasInvalidInput {
                Text(LocalizedString.l(
                    lang,
                    en: "Grams and price must be numbers greater than 0",
                    zh: "克数与单价需为大于 0 的数字",
                    ja: "グラムと単価は 0 より大きい数値を入力してください",
                    ko: "그램수와 단가는 0보다 큰 숫자여야 합니다"
                ))
                .font(.system(size: 9))
                .foregroundStyle(Color(nsColor: .systemRed))
            }
        }
    }

    private var canAdd: Bool {
        parsedGrams != nil && parsedPrice != nil
    }

    // 输入非空但解析失败（非数字或 ≤0）
    private var hasInvalidInput: Bool {
        let gramsText = formGrams.trimmingCharacters(in: .whitespaces)
        let priceText = formPrice.trimmingCharacters(in: .whitespaces)
        return (!gramsText.isEmpty && parsedGrams == nil) || (!priceText.isEmpty && parsedPrice == nil)
    }

    private var parsedGrams: Double? {
        let value = Double(formGrams.trimmingCharacters(in: .whitespaces))
        guard let value, value > 0 else { return nil }
        return value
    }

    private var parsedPrice: Double? {
        let value = Double(formPrice.trimmingCharacters(in: .whitespaces))
        guard let value, value > 0 else { return nil }
        return value
    }

    // MARK: - Actions

    private func addRecord() {
        guard let grams = parsedGrams, let price = parsedPrice else { return }
        tradeStore.add(GoldTradeRecord(
            date: formDate,
            grams: formIsBuy ? grams : -grams,
            pricePerGram: price
        ))
        formGrams = ""
        formPrice = ""
        isExpanded = true
    }

    private func applyToHoldings(_ result: (grams: Double, averageCost: Double)) {
        guard result.grams > 0 else { return }
        gramsText = String(format: "%.2f", result.grams)
        averageCostText = String(format: "%.2f", result.averageCost)
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.title = LocalizedString.l(lang, en: "Export Trades CSV", zh: "导出交易流水 CSV", ja: "取引履歴 CSV をエクスポート", ko: "거래 내역 CSV 내보내기")
        panel.nameFieldStringValue = "gold-trades-\(Self.dateStamp()).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let csv = GoldTradeStore.csvText(records: tradeStore.records)
        try? csv.data(using: .utf8)?.write(to: url, options: .atomic)

        // 导出成功后在卡片内短暂显示“已导出”
        withAnimation(.easeInOut(duration: 0.15)) { csvExported = true }
        csvExportFeedbackTask?.cancel()
        csvExportFeedbackTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.15)) { csvExported = false }
        }
    }

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: Date())
    }
}

// MARK: - 收益曲线图

/// 以持仓克数 × 价格 − 成本绘制盈亏曲线，0 轴画虚线。
private struct ProfitCurveChart: View {
    let records: [GoldPriceRecord]
    let grams: Double
    let averageCost: Double
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            guard records.count >= 2, grams > 0 else { return }

            let profits = records.map { grams * ($0.price - averageCost) }
            guard var minProfit = profits.min(), var maxProfit = profits.max() else { return }
            // 值域始终包含 0 轴
            minProfit = min(minProfit, 0)
            maxProfit = max(maxProfit, 0)
            let range = max(maxProfit - minProfit, 0.01)

            func yPos(_ value: Double) -> CGFloat {
                size.height - CGFloat((value - minProfit) / range) * size.height
            }

            // 0 轴虚线
            let zeroY = yPos(0)
            var zeroPath = Path()
            zeroPath.move(to: CGPoint(x: 0, y: zeroY))
            zeroPath.addLine(to: CGPoint(x: size.width, y: zeroY))
            context.stroke(
                zeroPath,
                with: .color(Color.primary.opacity(colorScheme == .dark ? 0.25 : 0.18)),
                style: StrokeStyle(lineWidth: 0.8, dash: [3, 3])
            )

            var path = Path()
            var lastPoint = CGPoint.zero
            for (index, profit) in profits.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(max(profits.count - 1, 1))
                lastPoint = CGPoint(x: x, y: yPos(profit))
                if index == 0 {
                    path.move(to: lastPoint)
                } else {
                    path.addLine(to: lastPoint)
                }
            }

            // 中国市场惯例：盈利红、亏损绿。
            let tint = AppTheme.marketColor(for: profits.last ?? 0)

            var fillPath = path
            fillPath.addLine(to: CGPoint(x: size.width, y: zeroY))
            fillPath.addLine(to: CGPoint(x: 0, y: zeroY))
            fillPath.closeSubpath()
            context.fill(fillPath, with: .color(tint.opacity(colorScheme == .dark ? 0.16 : 0.10)))

            context.stroke(path, with: .color(tint), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))

            // 最新点
            let dotRadius: CGFloat = 2.2
            context.fill(
                Path(ellipseIn: CGRect(
                    x: lastPoint.x - dotRadius,
                    y: lastPoint.y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                )),
                with: .color(tint)
            )
        }
    }
}
