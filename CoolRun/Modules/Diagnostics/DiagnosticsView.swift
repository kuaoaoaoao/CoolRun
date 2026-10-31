import SwiftUI
import AppKit

enum DiagnosticsSection: String, CaseIterable, Identifiable {
    case sleep
    case network
    case storage
    case residue

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .sleep: "moon.zzz.fill"
        case .network: "network"
        case .storage: "internaldrive.fill"
        case .residue: "app.badge.checkmark"
        }
    }

    func title(lang: AppLanguage) -> String {
        switch self {
        case .sleep:
            LocalizedString.l(lang, en: "Sleep", zh: "睡眠", ja: "スリープ", ko: "절전")
        case .network:
            LocalizedString.l(lang, en: "Network", zh: "网络", ja: "ネット", ko: "네트워크")
        case .storage:
            LocalizedString.l(lang, en: "Storage", zh: "存储", ja: "ストレージ", ko: "저장 공간")
        case .residue:
            LocalizedString.l(lang, en: "Residue", zh: "残留", ja: "残留", ko: "잔여 파일")
        }
    }
}

struct DiagnosticsView: View {
    @State private var selection: DiagnosticsSection = .sleep
    @State private var model = DiagnosticsViewModel.shared
    @State private var hoveredSection: DiagnosticsSection?
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            header
            sectionPicker

            Group {
                switch selection {
                case .sleep:
                    SleepDiagnosticsSectionView(model: model)
                case .network:
                    NetworkDiagnosticsSectionView(model: model)
                case .storage:
                    StorageDiagnosticsSectionView(model: model)
                case .residue:
                    AppResidueSectionView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "stethoscope")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 32, height: 32)
                .background(AppTheme.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedString.l(settings.language, en: "Mac Diagnostics", zh: "Mac 诊断", ja: "Mac診断", ko: "Mac 진단"))
                    .font(.subheadline.weight(.bold))
                Text(LocalizedString.l(settings.language, en: "On demand · processed locally", zh: "按需运行 · 仅在本机处理", ja: "オンデマンド · ローカル処理", ko: "요청 시 실행 · 로컬 처리"))
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }
            Spacer()
        }
        .padding(10)
        .appCardSurface(cornerRadius: 11, showsShadow: false)
    }

    private var sectionPicker: some View {
        HStack(spacing: 3) {
            ForEach(DiagnosticsSection.allCases) { section in
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) { selection = section }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: section.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(section.title(lang: settings.language))
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selection == section ? AppTheme.accent : AppTheme.textSecondary(colorScheme))
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(sectionBackground(section))
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(section.title(lang: settings.language))
                .accessibilityAddTraits(selection == section ? .isSelected : [])
                .onHover { isHovering in
                    if isHovering {
                        hoveredSection = section
                    } else if hoveredSection == section {
                        hoveredSection = nil
                    }
                }
            }
        }
        .padding(3)
        .background(AppTheme.chromeSurface(colorScheme), in: RoundedRectangle(cornerRadius: 10))
        .animation(.easeOut(duration: 0.12), value: hoveredSection)
    }

    private func sectionBackground(_ section: DiagnosticsSection) -> Color {
        if selection == section {
            return AppTheme.accent.opacity(colorScheme == .dark ? 0.20 : 0.13)
        }
        return hoveredSection == section ? AppTheme.accent.opacity(0.07) : .clear
    }

    private func placeholder(icon: String, title: String, detail: String) -> some View {
        ContentUnavailableView(title, systemImage: icon, description: Text(detail))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .appCardSurface(cornerRadius: 11, showsShadow: false)
    }
}

private struct StorageDiagnosticsSectionView: View {
    let model: DiagnosticsViewModel
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                DiagnosticsRunCard(
                    icon: "internaldrive.fill",
                    title: text(en: "System Data insights", zh: "System Data 透视", ja: "System Data分析", ko: "System Data 분석"),
                    detail: text(en: "Scans selected user Library folders. It never deletes or downloads files.", zh: "扫描指定的用户资源库目录；不会删除文件或触发云端下载。", ja: "ユーザライブラリの指定場所だけを読み取り、削除やクラウド取得はしません。", ko: "사용자 라이브러리의 지정된 위치만 읽고 삭제하거나 클라우드 파일을 받지 않습니다."),
                    buttonTitle: text(en: "Scan storage", zh: "扫描存储", ja: "ストレージを確認", ko: "저장 공간 확인"),
                    isRunning: model.isScanningStorage,
                    action: model.scanStorage
                )

                if model.isScanningStorage {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            ProgressView(value: model.storageProgress)
                            Button {
                                model.cancelStorageScan()
                            } label: {
                                Label(
                                    text(en: "Cancel", zh: "取消", ja: "キャンセル", ko: "취소"),
                                    systemImage: "xmark.circle.fill"
                                )
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                            .contentShape(Rectangle())
                        }
                        Text(storageProgressText)
                            .font(.system(size: 9))
                            .foregroundStyle(AppTheme.textSecondary(colorScheme))
                        Text(text(
                            en: "You can keep using other features. The first scan after granting access may take longer.",
                            zh: "扫描期间仍可切换和使用其他功能；首次授权后的扫描可能稍慢。",
                            ja: "スキャン中も他の機能を使用できます。初回許可後は時間がかかることがあります。",
                            ko: "검사 중에도 다른 기능을 사용할 수 있습니다. 처음 접근을 허용한 뒤에는 시간이 더 걸릴 수 있습니다."
                        ))
                        .font(.system(size: 9))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    }
                    .padding(10)
                    .appCardSurface(cornerRadius: 11, showsShadow: false)
                }

                if let result = model.storageResult {
                    storageSummary(result)
                    ForEach(result.items.filter { $0.allocatedBytes > 0 || $0.inaccessibleCount > 0 }) { item in
                        storageCategoryCard(item)
                    }
                } else if !model.isScanningStorage {
                    ContentUnavailableView(
                        text(en: "No storage scan yet", zh: "还没有存储扫描结果", ja: "スキャン結果はまだありません", ko: "아직 저장 공간 검사 결과가 없습니다"),
                        systemImage: "internaldrive",
                        description: Text(text(en: "Totals are estimates from readable, locally allocated files.", zh: "结果仅估算当前可读且已分配在本机的文件。", ja: "読み取り可能でローカルにあるファイルの推定値です。", ko: "읽을 수 있고 로컬에 할당된 파일의 추정치입니다."))
                    )
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .appCardSurface(cornerRadius: 11, showsShadow: false)
                }
            }
            .padding(1)
        }
        .scrollIndicators(.hidden)
    }

    private var storageProgressText: String {
        let count = model.storageScannedEntryCount.formatted()
        guard let category = model.storageCurrentCategory else {
            return text(
                en: "Preparing the storage scan…",
                zh: "正在准备存储扫描…",
                ja: "ストレージスキャンを準備中…",
                ko: "저장 공간 검사를 준비 중…"
            )
        }
        let title = categoryTitle(category)
        return text(
            en: "Scanning \(title) · \(count) entries checked",
            zh: "正在扫描\(title) · 已检查 \(count) 项",
            ja: "\(title)を確認中 · \(count)項目を確認済み",
            ko: "\(title) 검사 중 · \(count)개 항목 확인됨"
        )
    }

    private func storageSummary(_ result: StorageScanResult) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(text(en: "Visible diagnostic total", zh: "本次可见诊断总量", ja: "確認できた合計", ko: "확인된 총용량"))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    Text(formatBytes(result.allocatedBytes))
                        .font(.title3.weight(.bold).monospacedDigit())
                }
                Spacer()
                Text(String(format: "%.1fs", result.duration))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }
            if result.isPartial {
                Label(
                    text(en: "Partial result: some folders were inaccessible or reached the scan limit.", zh: "结果不完整：部分目录不可访问或达到扫描上限。", ja: "一部のフォルダを確認できないか上限に達しました。", ko: "일부 폴더에 접근할 수 없거나 검사 한도에 도달했습니다."),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: 9))
                .foregroundStyle(AppTheme.warning)
            }
            Text(text(en: "This is a curated explanation, not the same accounting model used by System Settings.", zh: "这是针对常见目录的解释性扫描，与系统设置的统计口径并不完全相同。", ja: "よくある場所の説明用スキャンで、システム設定の集計とは異なります。", ko: "주요 위치를 설명하기 위한 검사이며 시스템 설정의 집계 방식과 다릅니다."))
                .font(.system(size: 9))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
        }
        .padding(10)
        .appCardSurface(cornerRadius: 11, showsShadow: false)
    }

    private func storageCategoryCard(_ item: StorageInsightItem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: categoryIcon(item.category)).foregroundStyle(AppTheme.accent).frame(width: 18)
                Text(categoryTitle(item.category)).font(.caption.weight(.semibold))
                Spacer()
                Text(formatBytes(item.allocatedBytes)).font(.caption2.weight(.semibold).monospacedDigit())
                Button {
                    reveal(item.url)
                } label: {
                    Image(systemName: "arrow.right.circle")
                }
                .buttonStyle(.plain)
                .help(text(en: "Show in Finder", zh: "在 Finder 中显示", ja: "Finderで表示", ko: "Finder에서 보기"))
            }
            ForEach(item.hotspots.prefix(4)) { hotspot in
                HStack(spacing: 6) {
                    Text(hotspot.url.lastPathComponent)
                        .font(.system(size: 9))
                        .lineLimit(1)
                    Spacer()
                    Text(formatBytes(hotspot.allocatedBytes))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    Button { reveal(hotspot.url) } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                }
            }
            if item.inaccessibleCount > 0 || item.reachedEntryLimit {
                Text(text(en: "Coverage is partial for this category.", zh: "此分类的扫描覆盖不完整。", ja: "この分類の確認は部分的です。", ko: "이 분류의 검사 범위가 완전하지 않습니다."))
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.warning)
            }
        }
        .padding(10)
        .appCardSurface(cornerRadius: 11, showsShadow: false)
    }

    private func categoryTitle(_ category: StorageInsightCategory) -> String {
        switch category {
        case .caches: text(en: "Caches", zh: "缓存", ja: "キャッシュ", ko: "캐시")
        case .logs: text(en: "Logs", zh: "日志", ja: "ログ", ko: "로그")
        case .applicationSupport: text(en: "Application Support", zh: "应用支持文件", ja: "Application Support", ko: "응용 프로그램 지원")
        case .containers: text(en: "App Containers", zh: "App 容器", ja: "Appコンテナ", ko: "앱 컨테이너")
        case .developer: text(en: "Developer Data", zh: "开发者数据", ja: "開発者データ", ko: "개발자 데이터")
        case .deviceBackups: text(en: "Device Backups", zh: "设备备份", ja: "デバイスのバックアップ", ko: "기기 백업")
        }
    }

    private func categoryIcon(_ category: StorageInsightCategory) -> String {
        switch category {
        case .caches: "bolt.horizontal.circle"
        case .logs: "doc.text.magnifyingglass"
        case .applicationSupport: "shippingbox"
        case .containers: "square.stack.3d.up"
        case .developer: "hammer"
        case .deviceBackups: "iphone.gen3"
        }
    }

    private func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }

    private func text(en: String, zh: String, ja: String, ko: String) -> String {
        LocalizedString.l(settings.language, en: en, zh: zh, ja: ja, ko: ko)
    }
}

private struct AppResidueSectionView: View {
    let model: DiagnosticsViewModel
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedURLs = Set<URL>()
    @State private var showsCleanupConfirmation = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                DiagnosticsRunCard(
                    icon: "app.badge.checkmark",
                    title: text(en: "Application residue", zh: "应用残留", ja: "Appの残留データ", ko: "앱 잔여 파일"),
                    detail: text(en: "Shows only old, identifier-shaped entries not tied to an installed app.", zh: "仅显示较旧、名称符合应用标识且未关联已安装 App 的项目。", ja: "古く、識別子形式で、インストール済みAppに属さない項目だけを表示します。", ko: "오래되었고 앱 식별자 형식이며 설치된 앱과 연결되지 않은 항목만 표시합니다."),
                    buttonTitle: text(en: "Scan residue", zh: "扫描残留", ja: "残留データを確認", ko: "잔여 파일 확인"),
                    isRunning: model.isScanningResidue,
                    action: {
                        selectedURLs.removeAll()
                        model.scanResidue()
                    }
                )

                safetyCard

                if let result = model.residueResult {
                    residueSummary(result)
                    if result.candidates.isEmpty {
                        ContentUnavailableView(
                            text(en: "No high-confidence residue found", zh: "没有发现高置信残留", ja: "確度の高い残留データはありません", ko: "신뢰도 높은 잔여 파일이 없습니다"),
                            systemImage: "checkmark.seal.fill"
                        )
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .appCardSurface(cornerRadius: 11, showsShadow: false)
                    } else {
                        candidateList(result.candidates)
                        cleanupButton
                    }
                } else if !model.isScanningResidue {
                    ContentUnavailableView(
                        text(en: "No residue scan yet", zh: "还没有残留扫描结果", ja: "スキャン結果はまだありません", ko: "아직 잔여 파일 검사 결과가 없습니다"),
                        systemImage: "app.dashed"
                    )
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .appCardSurface(cornerRadius: 11, showsShadow: false)
                }

                if let report = model.residueCleanupReport {
                    cleanupReport(report)
                }
            }
            .padding(1)
        }
        .scrollIndicators(.hidden)
        .alert(
            text(en: "Move selected items to Trash?", zh: "将所选项目移入废纸篓？", ja: "選択項目をゴミ箱に移動しますか？", ko: "선택한 항목을 휴지통으로 이동할까요?"),
            isPresented: $showsCleanupConfirmation
        ) {
            Button(text(en: "Cancel", zh: "取消", ja: "キャンセル", ko: "취소"), role: .cancel) {}
            Button(text(en: "Move to Trash", zh: "移入废纸篓", ja: "ゴミ箱に移動", ko: "휴지통으로 이동"), role: .destructive) {
                model.trashResidue(urls: selectedURLs)
                selectedURLs.removeAll()
            }
        } message: {
            Text(cleanupConfirmationMessage)
        }
    }

    private var safetyCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(
                text(en: "Conservative safety rules", zh: "保守型安全规则", ja: "保守的な安全ルール", ko: "보수적인 안전 규칙"),
                systemImage: "lock.shield.fill"
            )
            .font(.caption2.weight(.semibold))
            Text(text(en: "Apple files, installed apps, shared folders, recent items and symbolic links are excluded. There is no permanent-delete fallback.", zh: "Apple 文件、已安装 App、共享目录、近期项目和符号链接均会被排除；废纸篓失败时不会改为永久删除。", ja: "Apple項目、インストール済みApp、共有フォルダ、新しい項目、シンボリックリンクは除外し、完全削除には切り替えません。", ko: "Apple 파일, 설치된 앱, 공유 폴더, 최근 항목과 심볼릭 링크는 제외하며 영구 삭제로 전환하지 않습니다."))
                .font(.system(size: 9))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
        }
        .padding(10)
        .appCardSurface(cornerRadius: 11, showsShadow: false)
    }

    private func residueSummary(_ result: AppResidueScanResult) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(text(en: "Candidates", zh: "候选项目", ja: "候補", ko: "후보 항목"))
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                Text("\(result.candidates.count)").font(.title3.weight(.bold).monospacedDigit())
            }
            Spacer()
            Text(text(en: "Inspected \(result.inspectedEntryCount) · excluded \(result.excludedEntryCount)", zh: "检查 \(result.inspectedEntryCount) · 排除 \(result.excludedEntryCount)", ja: "確認 \(result.inspectedEntryCount) · 除外 \(result.excludedEntryCount)", ko: "검사 \(result.inspectedEntryCount) · 제외 \(result.excludedEntryCount)"))
                .font(.system(size: 9))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
        }
        .padding(10)
        .appCardSurface(cornerRadius: 11, showsShadow: false)
    }

    private func candidateList(_ candidates: [AppResidueCandidate]) -> some View {
        VStack(spacing: 0) {
            ForEach(candidates.prefix(40)) { candidate in
                HStack(spacing: 7) {
                    Button {
                        if selectedURLs.contains(candidate.url) {
                            selectedURLs.remove(candidate.url)
                        } else {
                            selectedURLs.insert(candidate.url)
                        }
                    } label: {
                        Image(systemName: selectedURLs.contains(candidate.url) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(selectedURLs.contains(candidate.url) ? AppTheme.accent : AppTheme.textSecondary(colorScheme))
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(candidate.identifier).font(.system(size: 9, weight: .semibold)).lineLimit(1)
                        Text(candidate.url.deletingLastPathComponent().lastPathComponent)
                            .font(.system(size: 8))
                            .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    }
                    Spacer()
                    Text(formatBytes(candidate.allocatedBytes))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    Button { NSWorkspace.shared.activateFileViewerSelecting([candidate.url]) } label: {
                        Image(systemName: "magnifyingglass").font(.system(size: 9, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 6)
                if candidate.id != candidates.prefix(40).last?.id { Divider().padding(.leading, 24) }
            }
        }
        .padding(.horizontal, 10)
        .appCardSurface(cornerRadius: 11, showsShadow: false)
    }

    private var cleanupButton: some View {
        Button(role: .destructive) {
            showsCleanupConfirmation = true
        } label: {
            HStack(spacing: 6) {
                if model.isCleaningResidue { ProgressView().controlSize(.small) }
                Image(systemName: "trash")
                Text(text(en: "Move \(selectedURLs.count) selected items to Trash", zh: "将所选 \(selectedURLs.count) 项移入废纸篓", ja: "選択した\(selectedURLs.count)項目をゴミ箱へ", ko: "선택한 \(selectedURLs.count)개 항목을 휴지통으로"))
            }
            .font(.caption2.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 26)
        }
        .buttonStyle(.bordered)
        .disabled(selectedURLs.isEmpty || model.isCleaningResidue)
    }

    private func cleanupReport(_ report: AppResidueCleanupReport) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(
                text(en: "Moved \(report.trashedURLs.count) item(s) to Trash", zh: "已将 \(report.trashedURLs.count) 项移入废纸篓", ja: "\(report.trashedURLs.count)項目をゴミ箱へ移動しました", ko: "\(report.trashedURLs.count)개 항목을 휴지통으로 이동했습니다"),
                systemImage: report.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .font(.caption2.weight(.semibold))
            .foregroundStyle(report.failures.isEmpty ? AppTheme.healthy : AppTheme.warning)
            ForEach(report.failures.prefix(3)) { failure in
                Text("\(failure.url.lastPathComponent): \(failure.message)")
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    .lineLimit(2)
            }
        }
        .padding(10)
        .appCardSurface(cornerRadius: 11, showsShadow: false)
    }

    private var cleanupConfirmationMessage: String {
        let selectedCandidates = model.residueResult?.candidates.filter { selectedURLs.contains($0.url) } ?? []
        let bytes = selectedCandidates.reduce(UInt64(0)) { $0 &+ $1.allocatedBytes }
        let examples = selectedCandidates.prefix(3).map(\.identifier).joined(separator: "\n")
        return text(
            en: "\(selectedCandidates.count) item(s), \(formatBytes(bytes)). They remain recoverable from Trash.\n\(examples)",
            zh: "共 \(selectedCandidates.count) 项，\(formatBytes(bytes))。移入后仍可从废纸篓恢复。\n\(examples)",
            ja: "\(selectedCandidates.count)項目、\(formatBytes(bytes))。ゴミ箱から復元できます。\n\(examples)",
            ko: "\(selectedCandidates.count)개, \(formatBytes(bytes)). 휴지통에서 복구할 수 있습니다.\n\(examples)"
        )
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }

    private func text(en: String, zh: String, ja: String, ko: String) -> String {
        LocalizedString.l(settings.language, en: en, zh: zh, ja: ja, ko: ko)
    }
}

private struct SleepDiagnosticsSectionView: View {
    let model: DiagnosticsViewModel
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                DiagnosticsRunCard(
                    icon: "moon.zzz.fill",
                    title: text(en: "Sleep diagnostics", zh: "睡眠诊断", ja: "スリープ診断", ko: "절전 진단"),
                    detail: text(en: "Reads power assertions and the last 24 hours of sleep events.", zh: "读取电源断言与最近 24 小时的睡眠事件。", ja: "電源アサーションと直近24時間の履歴を確認します。", ko: "전원 요청과 최근 24시간 절전 이벤트를 확인합니다."),
                    buttonTitle: text(en: "Run diagnosis", zh: "开始诊断", ja: "診断を開始", ko: "진단 시작"),
                    isRunning: model.isRunningSleep,
                    action: model.runSleepDiagnostics
                )

                if let summary = model.latestSleep {
                    statusCard(summary)
                    blockersCard(summary)
                    historyCard
                } else if !model.isRunningSleep {
                    emptyCard(
                        icon: "moon.stars",
                        title: text(en: "No sleep report yet", zh: "还没有睡眠报告", ja: "レポートはまだありません", ko: "아직 절전 보고서가 없습니다"),
                        detail: text(en: "The scan is read-only and does not change power settings.", zh: "诊断全程只读，不会修改电源设置。", ja: "診断は読み取り専用で、電源設定を変更しません。", ko: "진단은 읽기 전용이며 전원 설정을 변경하지 않습니다.")
                    )
                }
            }
            .padding(1)
        }
        .scrollIndicators(.hidden)
    }

    private func statusCard(_ summary: SleepDiagnosticSummary) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            DiagnosticStatusHeader(
                severity: summary.severity,
                title: sleepHeadline(summary),
                timestamp: summary.timestamp
            )

            HStack(spacing: 6) {
                diagnosticMetric(
                    value: "\(summary.wakeCount)",
                    label: text(en: "Full wakes", zh: "完全唤醒", ja: "フルウェイク", ko: "전체 깨우기")
                )
                diagnosticMetric(
                    value: "\(summary.darkWakeCount)",
                    label: "Dark Wake"
                )
                diagnosticMetric(
                    value: summary.batteryDropPercentagePoints.map { "−\($0)%" } ?? "—",
                    label: text(en: "Battery", zh: "电量变化", ja: "バッテリー", ko: "배터리")
                )
            }

            if !summary.unavailableChecks.isEmpty {
                Label(
                    text(en: "Some checks were unavailable; this is a partial report.", zh: "部分检查不可用，当前为不完整报告。", ja: "一部の確認ができないため部分的な結果です。", ko: "일부 확인을 사용할 수 없어 부분 보고서입니다."),
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption2)
                .foregroundStyle(AppTheme.warning)
            }
        }
        .padding(10)
        .appCardSurface(cornerRadius: 11, showsShadow: false)
    }

    private func blockersCard(_ summary: SleepDiagnosticSummary) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(
                text(en: "Active sleep assertions", zh: "当前阻止休眠项", ja: "有効なスリープ抑止", ko: "활성 절전 방지 항목"),
                systemImage: "hand.raised.fill"
            )
            .font(.caption.weight(.semibold))

            if summary.blockers.isEmpty {
                Label(
                    text(en: "No active blockers found", zh: "没有发现活动中的阻止项", ja: "有効な抑止はありません", ko: "활성 방지 항목이 없습니다"),
                    systemImage: "checkmark.circle.fill"
                )
                .font(.caption2)
                .foregroundStyle(AppTheme.healthy)
            } else {
                ForEach(summary.blockers.prefix(6)) { blocker in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(blocker.owner)
                                .font(.caption2.weight(.semibold))
                            Spacer()
                            if let processID = blocker.processID {
                                Text("PID \(processID)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                            }
                        }
                        Text(blocker.reason ?? blocker.assertionType)
                            .font(.system(size: 9))
                            .foregroundStyle(AppTheme.textSecondary(colorScheme))
                            .lineLimit(2)
                    }
                    if blocker.id != summary.blockers.prefix(6).last?.id { Divider() }
                }
                Text(text(en: "Review an unexpected app before quitting it. CoolRun never terminates it automatically.", zh: "如果出现意外 App，可先检查再退出；CoolRun 不会自动结束进程。", ja: "不要なAppか確認してから終了してください。自動終了はしません。", ko: "예상하지 못한 앱인지 확인한 뒤 종료하세요. 자동으로 종료하지 않습니다."))
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }
        }
        .padding(10)
        .appCardSurface(cornerRadius: 11, showsShadow: false)
    }

    @ViewBuilder
    private var historyCard: some View {
        if model.sleepHistory.count > 1 {
            VStack(alignment: .leading, spacing: 6) {
                Text(text(en: "Recent reports", zh: "最近报告", ja: "最近のレポート", ko: "최근 보고서"))
                    .font(.caption.weight(.semibold))
                ForEach(model.sleepHistory.dropFirst().prefix(3)) { item in
                    HStack {
                        Circle().fill(item.severity.tint).frame(width: 6, height: 6)
                        Text(item.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                        Spacer()
                        Text("Dark Wake \(item.darkWakeCount)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    }
                }
            }
            .padding(10)
            .appCardSurface(cornerRadius: 11, showsShadow: false)
        }
    }

    private func sleepHeadline(_ summary: SleepDiagnosticSummary) -> String {
        switch summary.severity {
        case .healthy:
            text(en: "No obvious sleep issue found", zh: "没有发现明显睡眠异常", ja: "明らかな異常はありません", ko: "뚜렷한 절전 문제가 없습니다")
        case .notice:
            text(en: "Minor activity needs context", zh: "检测到少量活动，建议结合实际使用判断", ja: "軽微な動作があります", ko: "일부 활동을 확인하세요")
        case .warning:
            text(en: "Sleep may be interrupted", zh: "睡眠可能受到干扰", ja: "スリープが妨げられている可能性", ko: "절전이 방해될 수 있습니다")
        case .critical:
            text(en: "Frequent wakes or heavy battery loss", zh: "唤醒频繁或电量下降明显", ja: "頻繁なウェイクまたは大きな電池消費", ko: "잦은 깨우기 또는 큰 배터리 소모")
        case .unavailable:
            text(en: "Sleep data is unavailable", zh: "无法读取睡眠数据", ja: "スリープデータを取得できません", ko: "절전 데이터를 사용할 수 없습니다")
        }
    }

    private func diagnosticMetric(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.caption.weight(.bold).monospacedDigit())
            Text(label).font(.system(size: 8)).foregroundStyle(AppTheme.textSecondary(colorScheme)).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(AppTheme.elevatedSurface(colorScheme), in: RoundedRectangle(cornerRadius: 7))
    }

    private func emptyCard(icon: String, title: String, detail: String) -> some View {
        ContentUnavailableView(title, systemImage: icon, description: Text(detail))
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .appCardSurface(cornerRadius: 11, showsShadow: false)
    }

    private func text(en: String, zh: String, ja: String, ko: String) -> String {
        LocalizedString.l(settings.language, en: en, zh: zh, ja: ja, ko: ko)
    }
}

private struct NetworkDiagnosticsSectionView: View {
    let model: DiagnosticsViewModel
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                DiagnosticsRunCard(
                    icon: "network",
                    title: text(en: "Network doctor", zh: "网络医生", ja: "ネットワーク診断", ko: "네트워크 진단"),
                    detail: text(en: "Tests each connection layer independently; usually finishes in a few seconds.", zh: "独立检查每一层连接，通常几秒内完成。", ja: "接続の各層を個別に確認します。", ko: "각 연결 단계를 독립적으로 확인합니다."),
                    buttonTitle: text(en: "Test network", zh: "检测网络", ja: "ネットワークを確認", ko: "네트워크 확인"),
                    isRunning: model.isRunningNetwork,
                    action: model.runNetworkDiagnostics
                )

                if let summary = model.latestNetwork {
                    VStack(alignment: .leading, spacing: 8) {
                        DiagnosticStatusHeader(
                            severity: summary.severity,
                            title: causeTitle(summary.likelyCause),
                            timestamp: summary.timestamp
                        )
                        if let interfaceName = summary.interfaceName {
                            Text([interfaceName, summary.localAddress, summary.gateway].compactMap { $0 }.joined(separator: "  →  "))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                                .lineLimit(1)
                        }
                    }
                    .padding(10)
                    .appCardSurface(cornerRadius: 11, showsShadow: false)

                    VStack(spacing: 0) {
                        ForEach(summary.checks) { check in
                            networkCheckRow(check)
                            if check.id != summary.checks.last?.id { Divider().padding(.leading, 28) }
                        }
                    }
                    .padding(.horizontal, 10)
                    .appCardSurface(cornerRadius: 11, showsShadow: false)

                    if model.networkHistory.count > 1 {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(text(en: "Recent tests", zh: "最近检测", ja: "最近のテスト", ko: "최근 테스트"))
                                .font(.caption.weight(.semibold))
                            ForEach(model.networkHistory.dropFirst().prefix(3)) { item in
                                HStack {
                                    Circle().fill(item.severity.tint).frame(width: 6, height: 6)
                                    Text(item.timestamp.formatted(date: .omitted, time: .shortened))
                                        .font(.caption2)
                                    Spacer()
                                    Text(item.latencyMilliseconds.map { String(format: "%.0f ms", $0) } ?? "—")
                                        .font(.system(size: 9, design: .monospaced))
                                }
                            }
                        }
                        .padding(10)
                        .appCardSurface(cornerRadius: 11, showsShadow: false)
                    }
                } else if !model.isRunningNetwork {
                    ContentUnavailableView(
                        text(en: "No network report yet", zh: "还没有网络报告", ja: "レポートはまだありません", ko: "아직 네트워크 보고서가 없습니다"),
                        systemImage: "network",
                        description: Text(text(en: "CoolRun does not capture packets or browsing history.", zh: "CoolRun 不抓包，也不记录浏览历史。", ja: "パケットや閲覧履歴は記録しません。", ko: "패킷이나 탐색 기록을 수집하지 않습니다."))
                    )
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .appCardSurface(cornerRadius: 11, showsShadow: false)
                }
            }
            .padding(1)
        }
        .scrollIndicators(.hidden)
    }

    private func networkCheckRow(_ check: NetworkCheckResult) -> some View {
        HStack(spacing: 8) {
            Image(systemName: check.state.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(check.state.tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(checkTitle(check.kind)).font(.caption2.weight(.semibold))
                Text(check.detail)
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    .lineLimit(2)
            }
            Spacer()
            if let duration = check.durationMilliseconds {
                Text(String(format: "%.0f ms", duration))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }
        }
        .padding(.vertical, 7)
    }

    private func causeTitle(_ cause: NetworkLikelyCause) -> String {
        switch cause {
        case .none: text(en: "Connection looks healthy", zh: "网络连接正常", ja: "接続は正常です", ko: "네트워크 연결이 정상입니다")
        case .localInterface: text(en: "No active network interface", zh: "没有活动的网络接口", ja: "有効な接続がありません", ko: "활성 네트워크가 없습니다")
        case .gateway: text(en: "Default gateway is unavailable", zh: "默认网关不可用", ja: "ゲートウェイに接続できません", ko: "기본 게이트웨이를 사용할 수 없습니다")
        case .dns: text(en: "DNS is the likely problem", zh: "问题可能出在 DNS", ja: "DNSに問題がある可能性", ko: "DNS 문제일 가능성이 높습니다")
        case .internet: text(en: "Internet reachability failed", zh: "互联网连接失败", ja: "インターネットに接続できません", ko: "인터넷 연결에 실패했습니다")
        case .unstable: text(en: "Connection is unstable", zh: "网络连接不稳定", ja: "接続が不安定です", ko: "네트워크가 불안정합니다")
        case .partial: text(en: "Connection works, but one probe was blocked", zh: "网络可用，但有一项检测受阻", ja: "接続可能ですが一部確認できません", ko: "연결되었지만 일부 확인이 차단되었습니다")
        }
    }

    private func checkTitle(_ kind: NetworkCheckKind) -> String {
        switch kind {
        case .interface: text(en: "Interface", zh: "网络接口", ja: "接続", ko: "인터페이스")
        case .gateway: text(en: "Gateway", zh: "网关", ja: "ゲートウェイ", ko: "게이트웨이")
        case .dns: "DNS"
        case .ping: text(en: "Latency & loss", zh: "延迟与丢包", ja: "遅延と損失", ko: "지연 및 손실")
        case .https: "HTTPS"
        case .vpn: "VPN"
        }
    }

    private func text(en: String, zh: String, ja: String, ko: String) -> String {
        LocalizedString.l(settings.language, en: en, zh: zh, ja: ja, ko: ko)
    }
}

private struct DiagnosticsRunCard: View {
    let icon: String
    let title: String
    let detail: String
    let buttonTitle: String
    let isRunning: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.caption.weight(.semibold))
                    Text(detail).font(.system(size: 9)).foregroundStyle(AppTheme.textSecondary(colorScheme)).fixedSize(horizontal: false, vertical: true)
                }
            }
            Button(action: action) {
                HStack(spacing: 6) {
                    if isRunning { ProgressView().controlSize(.small) }
                    Text(isRunning ? "…" : buttonTitle)
                }
                .font(.caption2.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 24)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
            .disabled(isRunning)
        }
        .padding(10)
        .appCardSurface(cornerRadius: 11, showsShadow: false)
    }
}

private struct DiagnosticStatusHeader: View {
    let severity: DiagnosticSeverity
    let title: String
    let timestamp: Date
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: severity.symbol)
                .foregroundStyle(severity.tint)
                .font(.system(size: 14, weight: .semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.weight(.semibold))
                Text(timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }
            Spacer()
        }
    }
}

private extension DiagnosticSeverity {
    var tint: Color {
        switch self {
        case .healthy: AppTheme.healthy
        case .notice: AppTheme.accent
        case .warning: AppTheme.warning
        case .critical: AppTheme.critical
        case .unavailable: .secondary
        }
    }

    var symbol: String {
        switch self {
        case .healthy: "checkmark.circle.fill"
        case .notice: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "exclamationmark.octagon.fill"
        case .unavailable: "questionmark.circle.fill"
        }
    }
}

private extension DiagnosticCheckState {
    var tint: Color {
        switch self {
        case .success: AppTheme.healthy
        case .warning: AppTheme.warning
        case .failure: AppTheme.critical
        case .unavailable, .skipped: .secondary
        }
    }

    var symbol: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failure: "xmark.circle.fill"
        case .unavailable: "questionmark.circle"
        case .skipped: "minus.circle"
        }
    }
}
