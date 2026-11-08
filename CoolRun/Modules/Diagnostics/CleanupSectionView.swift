import SwiftUI
import AppKit

/// 「磁盘满了怎么办」的答案页：勾一勾，点一下，走废纸篓。
struct CleanupSectionView: View {

    @State private var advisor = CleanupAdvisor.shared
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var selected = Set<String>()
    @State private var showsConfirmation = false
    @State private var report: CleanupAdvisor.Report?

    private var lang: AppLanguage { settings.language }

    private var safeItems: [CleanupAdvisor.Item] {
        advisor.items.filter { $0.risk == .safe }
    }
    private var cautionItems: [CleanupAdvisor.Item] {
        advisor.items.filter { $0.risk == .caution && $0.category != .largeFile }
    }
    private var largeItems: [CleanupAdvisor.Item] {
        advisor.items.filter { $0.category == .largeFile }
    }
    private var selectedItems: [CleanupAdvisor.Item] {
        advisor.items.filter { selected.contains($0.id) }
    }
    private var selectedBytes: UInt64 {
        selectedItems.reduce(0) { $0 &+ $1.bytes }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 10) {
                    summaryCard

                    if advisor.isScanning {
                        scanningCard
                    } else {
                        if !safeItems.isEmpty {
                            group(
                                title: text(en: "Safe to remove", zh: "可以放心清", ja: "削除しても安全", ko: "안전하게 삭제"),
                                tint: AppTheme.healthy,
                                items: safeItems
                            )
                        }
                        if !cautionItems.isEmpty {
                            group(
                                title: text(en: "Not recoverable", zh: "删了不可恢复", ja: "復元できません", ko: "복구 불가"),
                                tint: AppTheme.warning,
                                items: cautionItems
                            )
                        }
                        if !largeItems.isEmpty {
                            group(
                                title: text(en: "Big files", zh: "占地方的大文件", ja: "大きいファイル", ko: "큰 파일"),
                                tint: AppTheme.accent,
                                items: largeItems
                            )
                        }
                        if advisor.items.isEmpty, advisor.lastScanAt != nil {
                            emptyCard
                        }
                    }

                    if let report, !report.trashed.isEmpty || !report.failures.isEmpty {
                        resultCard(report)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .padding(.bottom, selected.isEmpty ? 0 : 60)
            }

            if !selected.isEmpty {
                actionBar
            }
        }
        .task {
            if advisor.items.isEmpty {
                await advisor.scan()
                preselectSafe()
            }
        }
        .confirmationDialog(
            text(
                en: "Move \(selected.count) item(s) to Trash?",
                zh: "把选中的 \(selected.count) 项移到废纸篓？",
                ja: "\(selected.count) 項目をゴミ箱に移動しますか？",
                ko: "\(selected.count)개 항목을 휴지통으로 옮길까요?"
            ),
            isPresented: $showsConfirmation,
            titleVisibility: .visible
        ) {
            Button(text(en: "Move to Trash", zh: "移到废纸篓", ja: "ゴミ箱へ", ko: "휴지통으로"), role: .destructive) {
                Task { await runCleanup() }
            }
            Button(text(en: "Cancel", zh: "取消", ja: "キャンセル", ko: "취소"), role: .cancel) {}
        } message: {
            Text(
                text(
                    en: "Frees \(CleanupAdvisor.formatted(selectedBytes)). You can restore them from Trash.",
                    zh: "可释放 \(CleanupAdvisor.formatted(selectedBytes))。之后还能从废纸篓里捡回来。",
                    ja: "\(CleanupAdvisor.formatted(selectedBytes)) 空きます。ゴミ箱から戻せます。",
                    ko: "\(CleanupAdvisor.formatted(selectedBytes)) 확보됩니다. 휴지통에서 되돌릴 수 있습니다."
                )
            )
        }
    }

    // MARK: - 摘要

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(CleanupAdvisor.formatted(advisor.reclaimableBytes))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(text(en: "can be reclaimed", zh: "可以释放", ja: "解放できます", ko: "확보 가능"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task {
                        selected.removeAll()
                        report = nil
                        await advisor.scan()
                        preselectSafe()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderless)
                .disabled(advisor.isScanning)
                .help(text(en: "Rescan", zh: "重新扫描", ja: "再スキャン", ko: "다시 스캔"))
            }

            if let last = advisor.lastScanAt {
                Text(
                    text(
                        en: "Scanned \(last.formatted(date: .omitted, time: .shortened)) · safe \(CleanupAdvisor.formatted(advisor.safeBytes))",
                        zh: "上次扫描 \(last.formatted(date: .omitted, time: .shortened)) · 其中安全 \(CleanupAdvisor.formatted(advisor.safeBytes))",
                        ja: "前回 \(last.formatted(date: .omitted, time: .shortened)) · 安全 \(CleanupAdvisor.formatted(advisor.safeBytes))",
                        ko: "마지막 스캔 \(last.formatted(date: .omitted, time: .shortened)) · 안전 \(CleanupAdvisor.formatted(advisor.safeBytes))"
                    )
                )
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCardSurface(cornerRadius: 12, showsShadow: false)
    }

    private var scanningCard: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(advisor.progressText ?? text(en: "Scanning…", zh: "正在扫描…", ja: "スキャン中…", ko: "스캔 중…"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(12)
        .appCardSurface(cornerRadius: 12, showsShadow: false)
    }

    private var emptyCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(AppTheme.healthy)
            Text(text(en: "Nothing worth cleaning.", zh: "没什么值得清的，挺干净。", ja: "掃除するものはありません。", ko: "정리할 것이 없습니다."))
                .font(.system(size: 12))
            Spacer()
        }
        .padding(12)
        .appCardSurface(cornerRadius: 12, showsShadow: false)
    }

    // MARK: - 分组

    private func group(title: String, tint: Color, items: [CleanupAdvisor.Item]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Circle().fill(tint).frame(width: 5, height: 5)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    row(item)
                    if index < items.count - 1 {
                        Divider().opacity(0.35).padding(.leading, 34)
                    }
                }
            }
            .appCardSurface(cornerRadius: 12, showsShadow: false)
        }
    }

    private func row(_ item: CleanupAdvisor.Item) -> some View {
        let isOn = selected.contains(item.id)
        return Button {
            if isOn {
                selected.remove(item.id)
            } else {
                selected.insert(item.id)
            }
        } label: {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isOn ? AppTheme.accent : Color.secondary.opacity(0.5))
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Image(systemName: item.icon)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text(item.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(CleanupAdvisor.formatted(item.bytes))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(item.risk == .caution ? AppTheme.warning : .secondary)
                    }
                    Text(item.note)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 底部操作

    private var actionBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(CleanupAdvisor.formatted(selectedBytes))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(
                    text(
                        en: "\(selected.count) selected",
                        zh: "已选 \(selected.count) 项",
                        ja: "\(selected.count) 件選択",
                        ko: "\(selected.count)개 선택"
                    )
                )
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showsConfirmation = true
            } label: {
                Text(text(en: "Clean up", zh: "清理", ja: "クリーンアップ", ko: "정리"))
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.bar)
    }

    // MARK: - 结果

    private func resultCard(_ report: CleanupAdvisor.Report) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: report.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(report.failures.isEmpty ? AppTheme.healthy : AppTheme.warning)
                Text(
                    text(
                        en: "Freed \(CleanupAdvisor.formatted(report.freedBytes))",
                        zh: "释放了 \(CleanupAdvisor.formatted(report.freedBytes))",
                        ja: "\(CleanupAdvisor.formatted(report.freedBytes)) 解放",
                        ko: "\(CleanupAdvisor.formatted(report.freedBytes)) 확보"
                    )
                )
                .font(.system(size: 12, weight: .medium))
                Spacer()
            }
            if !report.failures.isEmpty {
                ForEach(report.failures, id: \.self) { failure in
                    Text(failure)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            Text(text(en: "They are in Trash if you need them back.", zh: "都在废纸篓里，反悔了还能捡回来。", ja: "ゴミ箱にあります。", ko: "휴지통에 있습니다."))
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCardSurface(cornerRadius: 12, showsShadow: false)
    }

    // MARK: - 行为

    private func preselectSafe() {
        selected = Set(advisor.items.filter { $0.risk == .safe }.map(\.id))
    }

    private func runCleanup() async {
        let targets = selectedItems
        let outcome = await advisor.clean(targets)
        report = outcome
        selected.removeAll()
    }

    private func text(en: String, zh: String, ja: String, ko: String) -> String {
        LocalizedString.l(lang, en: en, zh: zh, ja: ja, ko: ko)
    }
}
