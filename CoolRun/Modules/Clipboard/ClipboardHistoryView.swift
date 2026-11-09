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
    @State private var kindFilter: ClipKind?
    @State private var kinds: [UUID: ClipKind] = [:]
    @State private var kindCounts: [ClipKind: Int] = [:]
    @State private var semanticMatches: Set<UUID>?
    @State private var didSaveNote = false
    @State private var ai = ClipboardAI.shared

    @MainActor
    init() {
        _store = State(initialValue: .shared)
    }

    @MainActor
    init(store: ClipboardHistoryStore) {
        _store = State(initialValue: store)
    }

    private var lang: AppLanguage { settings.language }

    /// 关键词过滤 + 类型过滤的结果，语义搜索没跑的时候就是列表内容。
    ///
    /// 分类查的是 `kinds` 缓存，不在这里现算——现算的版本把 CPU 打满过，
    /// 详见 `ClipClassifier` 的注释。
    private var baseEntries: [ClipboardHistoryEntry] {
        let filtered = store.filteredEntries(query: query)
        guard let kind = kindFilter else { return filtered }
        return filtered.filter { kinds[$0.id] == kind }
    }

    private var visibleEntries: [ClipboardHistoryEntry] {
        guard let matches = semanticMatches else { return baseEntries }
        return store.entries.filter { matches.contains($0.id) }
    }

    /// 分类结果必须缓存：它依赖全部历史文本，body 每次失效都重算的话，
    /// 光是分类就能吃掉几十个百分点 CPU。
    private func refreshKinds() {
        // 增量：同一个 id 的文本不会再变（同样内容重新复制会复用原 id），
        // 所以只需要给新出现的条目分类。剪贴板每分钟都可能进新条目，
        // 全量重算等于每次复制都卡一下。
        var next = kinds
        let liveIDs = Set(store.entries.map(\.id))
        next = next.filter { liveIDs.contains($0.key) }
        for entry in store.entries where next[entry.id] == nil {
            next[entry.id] = ClipClassifier.kind(of: entry.text)
        }
        guard next != kinds else { return }
        kinds = next
        kindCounts = ClipClassifier.counts(from: next)
    }

    var body: some View {
        VStack(spacing: 8) {
            header
            privacyBanner
            if !quickPasteEnabled {
                quickPasteBanner
            }
            searchField

            if store.entries.count >= 6 {
                kindChips
            }
            aiSection
            if semanticMatches != nil {
                semanticBanner
            }

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
        .onAppear {
            store.startMonitoring()
            refreshKinds()
        }
        .onChange(of: store.revision) { _, _ in
            refreshKinds()
        }
        .task {
            // onAppear 在某些重建路径下不会重跑，task 兜一次。
            if kinds.isEmpty { refreshKinds() }
        }
        .onChange(of: query) { _, _ in
            semanticMatches = nil
            ai.clearSearchState()
        }
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

    /// 类型过滤条。分类是本地算的（`ClipClassifier`），点一下不联网、不花钱。
    private var kindChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                chip(nil, title: LocalizedString.l(lang, en: "All", zh: "全部", ja: "すべて", ko: "전체"), count: store.entries.count)
                ForEach(ClipKind.allCases) { kind in
                    if let count = kindCounts[kind], count > 0, kind != .text {
                        chip(kind, title: kind.title(lang), count: count, symbol: kind.symbol)
                    }
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func chip(_ kind: ClipKind?, title: String, count: Int, symbol: String? = nil) -> some View {
        let selected = kindFilter == kind
        return Button {
            kindFilter = selected ? nil : kind
        } label: {
            HStack(spacing: 3) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 8, weight: .semibold))
                }
                Text(title).font(.system(size: 9, weight: selected ? .semibold : .regular))
                Text("\(count)")
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .opacity(0.7)
            }
            .foregroundStyle(selected ? Color.white : AppTheme.textSecondary(colorScheme))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                selected ? AppTheme.accent : AppTheme.elevatedSurface(colorScheme),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }

    /// AI 整理结果的展示区。只在这条链路被用过之后才出现，平时不占地方。
    @ViewBuilder
    private var aiSection: some View {
        if ai.isWorking || !ai.output.isEmpty || ai.errorMessage != nil {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                    Text(ai.isWorking
                        ? LocalizedString.l(lang, en: "Tidying up…", zh: "本鱼在整理…", ja: "整えています…", ko: "정리 중…")
                        : (ai.lastAction?.title(lang) ?? LocalizedString.l(lang, en: "Result", zh: "整理结果", ja: "結果", ko: "결과")))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary(colorScheme))

                    if ai.wasTruncated, !ai.isWorking {
                        Text(LocalizedString.l(lang, en: "· first 6000 chars only", zh: "· 只看了前 6000 字", ja: "· 先頭6000字のみ", ko: "· 앞 6000자만"))
                            .font(.system(size: 8.5))
                            .foregroundStyle(AppTheme.warning)
                    }

                    Spacer(minLength: 2)

                    if !ai.isWorking {
                        Button {
                            ai.clearOutput()
                            didSaveNote = false
                        } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    }
                }

                if let error = ai.errorMessage {
                    Text(error)
                        .font(.system(size: 9.5))
                        .foregroundStyle(AppTheme.critical)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !ai.output.isEmpty {
                    ScrollView(.vertical) {
                        Text(ai.output)
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.textPrimary(colorScheme))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 110)

                    HStack(spacing: 6) {
                        Button {
                            copyText(ai.output)
                        } label: {
                            Label(LocalizedString.common("copy", lang: lang), systemImage: "doc.on.doc")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)

                        Button {
                            didSaveNote = ai.saveAsNote(ai.output)
                        } label: {
                            Label(
                                didSaveNote
                                    ? LocalizedString.l(lang, en: "Saved", zh: "已存", ja: "保存済み", ko: "저장됨")
                                    : LocalizedString.l(lang, en: "Save to Notes", zh: "存成笔记", ja: "ノートに保存", ko: "노트에 저장"),
                                systemImage: didSaveNote ? "checkmark" : "note.text.badge.plus"
                            )
                            .font(.system(size: 9, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .disabled(didSaveNote)

                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(9)
            .background(
                AppTheme.accent.opacity(colorScheme == .dark ? 0.14 : 0.09),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
    }

    private var semanticBanner: some View {
        let count = semanticMatches?.count ?? 0
        return HStack(spacing: 6) {
            Image(systemName: count > 0 ? "sparkles" : "questionmark.circle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(count > 0 ? AppTheme.accent : AppTheme.warning)

            Text(count > 0
                ? LocalizedString.l(lang, en: "Found \(count) by meaning", zh: "按意思找到 \(count) 条", ja: "意味で \(count) 件", ko: "의미로 \(count)개 찾음")
                : LocalizedString.l(lang, en: "Nothing matched by meaning either", zh: "按意思也没找到", ja: "意味でも見つかりません", ko: "의미로도 찾지 못함"))
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary(colorScheme))

            Spacer(minLength: 2)

            Button {
                semanticMatches = nil
                ai.clearSearchState()
            } label: {
                Text(LocalizedString.l(lang, en: "Clear", zh: "清除", ja: "解除", ko: "지우기"))
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.link)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            (count > 0 ? AppTheme.accent : AppTheme.warning).opacity(0.1),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    /// 每条记录上的「整理」菜单。内容太短就不给——整理一段 8 个字的文本没有意义，
    /// 反而让人以为按钮坏了。
    @ViewBuilder
    private func aiActionMenu(_ entry: ClipboardHistoryEntry) -> some View {
        if entry.text.count >= 20 {
            Menu {
                ForEach(ClipboardAI.Action.allCases) { action in
                    Button {
                        Task { await ai.transform(entry.text, action: action) }
                    } label: {
                        Label(action.title(lang), systemImage: action.symbol)
                    }
                }
                Divider()
                Button {
                    Task { await ai.transform(entry.text, action: .summarize) }
                } label: {
                    Label(
                        LocalizedString.l(lang, en: "Tidy + save to Notes", zh: "整理并存成笔记", ja: "整えてノートへ", ko: "정리 후 노트 저장"),
                        systemImage: "note.text.badge.plus"
                    )
                }
            } label: {
                Image(systemName: "sparkles")
                    .frame(width: 22, height: 20)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22, height: 20)
            .foregroundStyle(AppTheme.accent)
            .disabled(ai.isWorking)
            .help(LocalizedString.l(lang, en: "Tidy with AI", zh: "让本鱼整理", ja: "AI で整える", ko: "AI로 정리"))
        }
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func runSemanticSearch() {
        let target = query
        Task {
            let hits = await ai.findByMeaning(target, in: store.entries)
            semanticMatches = Set(hits)
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

                aiActionMenu(entry)

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

            // 关键词搜不到时，给一条"按意思找"的路——用户多半记得的是内容，
            // 不是原文里的字面词。
            if !query.isEmpty, semanticMatches == nil {
                Button {
                    runSemanticSearch()
                } label: {
                    Label(
                        ai.isSearching
                            ? LocalizedString.l(lang, en: "Looking…", zh: "正在找…", ja: "探しています…", ko: "찾는 중…")
                            : LocalizedString.l(lang, en: "Let the whale search by meaning", zh: "让本鱼按意思找找", ja: "AI に意味で探させる", ko: "AI에게 의미로 찾기"),
                        systemImage: "sparkles"
                    )
                    .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(ai.isSearching)

                if let error = ai.searchError {
                    Text(error)
                        .font(.system(size: 8.5))
                        .foregroundStyle(AppTheme.critical)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 230)
                }
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
