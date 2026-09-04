import AppKit
import SwiftUI

struct ClipboardHistoryView: View {
    @State private var store: ClipboardHistoryStore
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var query = ""
    @AppStorage(ClipboardQuickPasteController.enabledDefaultsKey) private var quickPasteEnabled = false
    @State private var entryPendingDelete: ClipboardHistoryEntry?
    @State private var showsClearConfirmation = false
    @State private var copiedEntryID: UUID?
    @State private var copyFeedbackTask: Task<Void, Never>?

    @MainActor
    init() {
        _store = State(initialValue: .shared)
    }

    @MainActor
    init(store: ClipboardHistoryStore) {
        _store = State(initialValue: store)
    }

    private var lang: AppLanguage { settings.language }
    private var visibleEntries: [ClipboardHistoryEntry] { store.filteredEntries(query: query) }

    var body: some View {
        VStack(spacing: 8) {
            header
            privacyBanner
            if !quickPasteEnabled {
                quickPasteBanner
            }
            searchField

            if visibleEntries.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 7) {
                        ForEach(visibleEntries) { entry in
                            entryCard(entry)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
        .onAppear { store.startMonitoring() }
        .onDisappear {
            copyFeedbackTask?.cancel()
            copyFeedbackTask = nil
        }
        .confirmationDialog(
            LocalizedString.l(lang, en: "Delete this clipboard entry?", zh: "删除这条剪切板记录？", ja: "このクリップボード項目を削除しますか？", ko: "이 클립보드 항목을 삭제하시겠습니까?"),
            isPresented: Binding(
                get: { entryPendingDelete != nil },
                set: { if !$0 { entryPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(LocalizedString.common("delete", lang: lang), role: .destructive) {
                if let entryPendingDelete { store.deleteEntry(id: entryPendingDelete.id) }
                entryPendingDelete = nil
            }
            Button(LocalizedString.common("cancel", lang: lang), role: .cancel) {
                entryPendingDelete = nil
            }
        }
        .confirmationDialog(
            LocalizedString.l(
                lang,
                en: "Clear all clipboard history, including pinned entries?",
                zh: "清空全部剪切板记录，包括已固定内容？",
                ja: "固定項目を含むすべての履歴を消去しますか？",
                ko: "고정 항목을 포함한 모든 클립보드 기록을 지우시겠습니까?"
            ),
            isPresented: $showsClearConfirmation,
            titleVisibility: .visible
        ) {
            Button(LocalizedString.l(lang, en: "Clear all", zh: "全部清空", ja: "すべて消去", ko: "모두 지우기"), role: .destructive) {
                store.clearHistory()
            }
            Button(LocalizedString.common("cancel", lang: lang), role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Label(
                LocalizedString.l(lang, en: "Clipboard", zh: "剪切板", ja: "クリップボード", ko: "클립보드"),
                systemImage: "doc.on.clipboard"
            )
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(AppTheme.textPrimary(colorScheme))

            Text("\(store.entries.count)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppTheme.accent.opacity(0.13), in: Capsule())

            Spacer(minLength: 4)

            Button {
                store.setMonitoringEnabled(!store.isMonitoringEnabled)
            } label: {
                Image(systemName: store.isMonitoringEnabled ? "pause.fill" : "play.fill")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(store.isMonitoringEnabled ? AppTheme.accent : AppTheme.warning)
            .help(store.isMonitoringEnabled
                ? LocalizedString.l(lang, en: "Pause collection", zh: "暂停记录", ja: "記録を一時停止", ko: "기록 일시 정지")
                : LocalizedString.l(lang, en: "Resume collection", zh: "继续记录", ja: "記録を再開", ko: "기록 재개"))

            Button { showsClearConfirmation = true } label: {
                Image(systemName: "trash")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.textSecondary(colorScheme))
            .disabled(store.entries.isEmpty)
            .help(LocalizedString.l(lang, en: "Clear history", zh: "清空记录", ja: "履歴を消去", ko: "기록 지우기"))
        }
    }

    private var privacyBanner: some View {
        HStack(spacing: 7) {
            Image(systemName: store.isMonitoringEnabled ? "lock.shield.fill" : "pause.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(store.isMonitoringEnabled ? AppTheme.healthy : AppTheme.warning)

            VStack(alignment: .leading, spacing: 1) {
                Text(store.isMonitoringEnabled
                    ? LocalizedString.l(lang, en: "Recording plain text", zh: "正在记录纯文本", ja: "プレーンテキストを記録中", ko: "일반 텍스트 기록 중")
                    : LocalizedString.l(lang, en: "Collection paused", zh: "记录已暂停", ja: "記録を一時停止中", ko: "기록 일시 정지"))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary(colorScheme))
                Text(LocalizedString.l(lang, en: "Stored only on this Mac · up to 200", zh: "仅保存在这台 Mac · 最多 200 条", ja: "この Mac のみに保存 · 最大200件", ko: "이 Mac에만 저장 · 최대 200개"))
                    .font(.system(size: 8.5))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }

            Spacer(minLength: 2)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            (store.isMonitoringEnabled ? AppTheme.healthy : AppTheme.warning).opacity(colorScheme == .dark ? 0.12 : 0.08),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    /// 提示用户到设置中开启 ⌃⌘1~9 快捷粘贴（功能默认关闭）。
    private var quickPasteBanner: some View {
        HStack(spacing: 7) {
            Image(systemName: "keyboard")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.accent)

            VStack(alignment: .leading, spacing: 1) {
                Text(LocalizedString.settings("quick_paste_banner_title", lang: lang))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary(colorScheme))
                Text(LocalizedString.settings("quick_paste_banner_desc", lang: lang))
                    .font(.system(size: 8.5))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }

            Spacer(minLength: 2)

            SettingsLink {
                Text(LocalizedString.settings("quick_paste_banner_enable", lang: lang))
                    .font(.system(size: 9.5, weight: .semibold))
            }
            .buttonStyle(.link)
            .font(.system(size: 9.5))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            AppTheme.accent.opacity(colorScheme == .dark ? 0.12 : 0.08),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))

            AppKitTextField(
                text: $query,
                placeholder: LocalizedString.l(lang, en: "Search copied text", zh: "搜索复制内容", ja: "コピーしたテキストを検索", ko: "복사한 텍스트 검색"),
                font: .systemFont(ofSize: 11)
            )
            .frame(height: 22)

            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(AppTheme.elevatedSurface(colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.stroke(colorScheme), lineWidth: 0.5)
        }
    }

    private func entryCard(_ entry: ClipboardHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                copy(entry)
            } label: {
                Text(entry.text)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary(colorScheme))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 5) {
                if entry.isPinned {
                    Label(
                        LocalizedString.l(lang, en: "Pinned", zh: "已固定", ja: "固定済み", ko: "고정됨"),
                        systemImage: "pin.fill"
                    )
                    .foregroundStyle(AppTheme.accent)
                }

                Text(relativeTime(entry.copiedAt))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))

                Spacer(minLength: 4)

                Button { store.togglePin(id: entry.id) } label: {
                    Image(systemName: entry.isPinned ? "pin.slash" : "pin")
                        .frame(width: 22, height: 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(entry.isPinned ? AppTheme.accent : AppTheme.textSecondary(colorScheme))
                .help(entry.isPinned
                    ? LocalizedString.l(lang, en: "Unpin", zh: "取消固定", ja: "固定解除", ko: "고정 해제")
                    : LocalizedString.l(lang, en: "Pin", zh: "固定", ja: "固定", ko: "고정"))

                Button { copy(entry) } label: {
                    Image(systemName: copiedEntryID == entry.id ? "checkmark" : "doc.on.doc")
                        .frame(width: 22, height: 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(copiedEntryID == entry.id ? AppTheme.healthy : AppTheme.textSecondary(colorScheme))
                .help(LocalizedString.l(lang, en: "Copy", zh: "复制", ja: "コピー", ko: "복사"))

                Button { entryPendingDelete = entry } label: {
                    Image(systemName: "trash")
                        .frame(width: 22, height: 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                .help(LocalizedString.common("delete", lang: lang))
            }
            .font(.system(size: 8.5, weight: .medium))
        }
        .padding(9)
        .background(AppTheme.surface(colorScheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .leading) {
            if entry.isPinned {
                Capsule()
                    .fill(AppTheme.accent)
                    .frame(width: 3)
                    .padding(.vertical, 8)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.stroke(colorScheme), lineWidth: 0.5)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: query.isEmpty ? (store.isMonitoringEnabled ? "doc.on.clipboard" : "pause.circle") : "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle((store.isMonitoringEnabled ? AppTheme.accent : AppTheme.warning).opacity(0.72))

            Text(emptyTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary(colorScheme))

            Text(emptyDetail)
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 230)

            if !store.isMonitoringEnabled, query.isEmpty {
                Button {
                    store.setMonitoringEnabled(true)
                } label: {
                    Label(
                        LocalizedString.l(lang, en: "Resume collection", zh: "继续记录", ja: "記録を再開", ko: "기록 재개"),
                        systemImage: "play.fill"
                    )
                    .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    private var emptyTitle: String {
        if !query.isEmpty {
            return LocalizedString.l(lang, en: "No matching clips", zh: "没有匹配的记录", ja: "一致する項目はありません", ko: "일치하는 항목이 없습니다")
        }
        if !store.isMonitoringEnabled {
            return LocalizedString.l(lang, en: "Collection is paused", zh: "剪切板记录已暂停", ja: "記録を一時停止しています", ko: "클립보드 기록이 일시 정지되었습니다")
        }
        return LocalizedString.l(lang, en: "Copy text to begin", zh: "复制一段文字即可开始", ja: "テキストをコピーして開始", ko: "텍스트를 복사해 시작하세요")
    }

    private var emptyDetail: String {
        if !query.isEmpty {
            return LocalizedString.l(lang, en: "Try a different keyword.", zh: "换个关键词试试。", ja: "別のキーワードをお試しください。", ko: "다른 검색어를 사용해 보세요.")
        }
        if !store.isMonitoringEnabled {
            return LocalizedString.l(lang, en: "Copies made while paused are not collected.", zh: "暂停期间复制的内容不会被记录。", ja: "一時停止中にコピーした内容は記録されません。", ko: "일시 정지 중 복사한 내용은 기록되지 않습니다.")
        }
        return LocalizedString.l(lang, en: "Only new plain text is stored locally on this Mac.", zh: "仅记录启动后复制的纯文本，并只保存在本机。", ja: "新しくコピーしたプレーンテキストだけをこの Mac に保存します。", ko: "새로 복사한 일반 텍스트만 이 Mac에 저장합니다.")
    }

    private func copy(_ entry: ClipboardHistoryEntry) {
        store.copyToPasteboard(id: entry.id)
        copiedEntryID = entry.id
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            copiedEntryID = nil
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = lang.locale
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
