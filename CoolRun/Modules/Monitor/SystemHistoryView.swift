import SwiftUI
import Combine

struct SystemHistoryCard: View {
    @State private var store = SystemHistoryStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var router = AppNavigationRouter.shared
    @Environment(\.colorScheme) private var colorScheme
    private let disclosure = MonitorSectionDisclosure.shared

    private var isExpanded: Bool { disclosure.isExpanded(.history) }

    private var recent: [SystemHistorySample] { store.recentSamples(hours: 24) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { disclosure.toggle(.history) }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                    Text(LocalizedString.l(settings.language, en: "Recent system history", zh: "最近系统记录", ja: "最近のシステム履歴", ko: "최근 시스템 기록"))
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    if !store.anomalies.isEmpty {
                        Text("\(store.anomalies.count)")
                            .font(.caption2.bold().monospacedDigit())
                            .foregroundStyle(AppTheme.warning)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.warning.opacity(0.12), in: Capsule())
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .frame(minHeight: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                if recent.isEmpty {
                    Text(LocalizedString.l(settings.language, en: "History appears after the first five-minute sample.", zh: "首次运行约 5 分钟后开始显示历史记录。", ja: "最初の5分サンプル後に表示されます。", ko: "첫 5분 샘플 후 기록이 표시됩니다."))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                } else {
                    historyTrends
                }

                Divider()

                if store.anomalies.isEmpty {
                    Label(
                        LocalizedString.l(settings.language, en: "No recent anomalies", zh: "最近没有记录到异常", ja: "最近の異常はありません", ko: "최근 이상 없음"),
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.caption2)
                    .foregroundStyle(AppTheme.healthy)
                } else {
                    ForEach(store.anomalies.prefix(3)) { anomaly in
                        anomalyRow(anomaly)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.elevatedSurface(colorScheme))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.stroke(colorScheme), lineWidth: 0.5)
        }
        .onReceive(router.$request.compactMap { $0 }) { request in
            guard request.quickAction == .showSystemHistory else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                disclosure.setExpanded(true, for: .history)
            }
            router.consumeQuickAction(request.id)
        }
    }

    private var historyTrends: some View {
        VStack(spacing: 7) {
            historyLine(
                title: "CPU",
                value: recent.map(\.cpuUsage).max() ?? 0,
                values: recent.map(\.cpuUsage),
                tint: AppTheme.accent
            )
            historyLine(
                title: LocalizedString.l(settings.language, en: "Memory", zh: "内存", ja: "メモリ", ko: "메모리"),
                value: recent.map(\.memoryUsage).max() ?? 0,
                values: recent.map(\.memoryUsage),
                tint: AppTheme.warning
            )
        }
    }

    private func historyLine(title: String, value: Double, values: [Double], tint: Color) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption2.weight(.medium))
                .frame(width: 42, alignment: .leading)
            SparklineChart(values: values, color: tint, showGradient: false, valueRange: 0...1)
                .frame(height: 18)
            Text(String(format: "max %.0f%%", value * 100))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                .frame(width: 58, alignment: .trailing)
        }
    }

    private func anomalyRow(_ anomaly: SystemAnomalyEvent) -> some View {
        HStack(spacing: 7) {
            Image(systemName: anomaly.kind.icon)
                .foregroundStyle(anomaly.severity.color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(anomalyTitle(anomaly))
                    .font(.caption2.weight(.semibold))
                Text(anomaly.timestamp.formatted(.relative(presentation: .named)))
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }
            Spacer()
            if let topProcessName = anomaly.topProcessName {
                Text(topProcessName)
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    .lineLimit(1)
                    .frame(maxWidth: 80, alignment: .trailing)
            }
        }
    }

    private func anomalyTitle(_ anomaly: SystemAnomalyEvent) -> String {
        switch anomaly.kind {
        case .cpu: "CPU \(Int(anomaly.value * 100))%"
        case .memory: LocalizedString.l(settings.language, en: "Memory \(Int(anomaly.value * 100))%", zh: "内存 \(Int(anomaly.value * 100))%", ja: "メモリ \(Int(anomaly.value * 100))%", ko: "메모리 \(Int(anomaly.value * 100))%")
        case .storage: LocalizedString.l(settings.language, en: "Storage \(Int(anomaly.value * 100))%", zh: "储存 \(Int(anomaly.value * 100))%", ja: "ストレージ \(Int(anomaly.value * 100))%", ko: "저장 공간 \(Int(anomaly.value * 100))%")
        case .temperature: String(format: "%.0f°C", anomaly.value)
        }
    }
}
