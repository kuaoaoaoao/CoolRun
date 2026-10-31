import AppKit
import SwiftUI

struct NotesView: View {
    @State private var store: NotesStore
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var query = ""
    @State private var selectedFilter: NoteGroupFilter = .all
    @State private var editorContext: NoteEditorContext?
    @State private var showsGroupManager = false
    @State private var notePendingDelete: NoteRecord?

    @MainActor
    init() {
        _store = State(initialValue: .shared)
    }

    @MainActor
    init(store: NotesStore) {
        _store = State(initialValue: store)
    }

    private var lang: AppLanguage { settings.language }

    private var visibleNotes: [NoteRecord] {
        store.filteredNotes(group: selectedFilter, query: query)
    }

    var body: some View {
        VStack(spacing: 8) {
            header
            searchField
            groupStrip

            if visibleNotes.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 7) {
                        ForEach(visibleNotes) { note in
                            noteCard(note)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
        .sheet(item: $editorContext) { context in
            NoteEditorView(store: store, note: context.note, initialGroupID: context.initialGroupID)
        }
        .sheet(isPresented: $showsGroupManager, onDismiss: repairSelectedFilter) {
            NoteGroupManagerView(store: store)
        }
        .confirmationDialog(
            LocalizedString.l(
                lang,
                en: "Delete \"\(notePendingDelete?.title ?? "")\"?",
                zh: "删除“\(notePendingDelete?.title ?? "")”？",
                ja: "「\(notePendingDelete?.title ?? "")」を削除しますか？",
                ko: "\"\(notePendingDelete?.title ?? "")\" 메모를 삭제하시겠습니까?"
            ),
            isPresented: Binding(
                get: { notePendingDelete != nil },
                set: { if !$0 { notePendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(LocalizedString.common("delete", lang: lang), role: .destructive) {
                if let notePendingDelete { store.deleteNote(id: notePendingDelete.id) }
                notePendingDelete = nil
            }
            Button(LocalizedString.common("cancel", lang: lang), role: .cancel) {
                notePendingDelete = nil
            }
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Label(
                LocalizedString.l(lang, en: "Notes", zh: "备忘录", ja: "メモ", ko: "메모"),
                systemImage: "note.text"
            )
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(AppTheme.textPrimary(colorScheme))

            Text("\(store.notes.count)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppTheme.accent.opacity(0.13), in: Capsule())

            Spacer(minLength: 4)

            Button { showsGroupManager = true } label: {
                Image(systemName: "folder.badge.gearshape")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.textSecondary(colorScheme))
            .help(LocalizedString.l(lang, en: "Manage groups", zh: "管理分组", ja: "グループを管理", ko: "그룹 관리"))

            Button {
                editorContext = NoteEditorContext(note: nil, initialGroupID: selectedGroupID)
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(LocalizedString.l(lang, en: "New note", zh: "新建备忘", ja: "新規メモ", ko: "새 메모"))
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))

            AppKitTextField(
                text: $query,
                placeholder: LocalizedString.l(
                    lang,
                    en: "Search title or content",
                    zh: "搜索标题或内容",
                    ja: "タイトルや内容を検索",
                    ko: "제목 또는 내용 검색"
                ),
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

    private var groupStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                filterButton(
                    .all,
                    title: LocalizedString.l(lang, en: "All", zh: "全部", ja: "すべて", ko: "전체"),
                    icon: "tray.full"
                )
                filterButton(
                    .ungrouped,
                    title: LocalizedString.l(lang, en: "Ungrouped", zh: "未分组", ja: "未分類", ko: "미분류"),
                    icon: "tray"
                )
                ForEach(store.groups) { group in
                    filterButton(.group(group.id), title: group.name, icon: "folder")
                }
            }
        }
    }

    private func filterButton(_ filter: NoteGroupFilter, title: String, icon: String) -> some View {
        let isSelected = selectedFilter == filter
        return Button {
            withAnimation(.easeInOut(duration: 0.14)) { selectedFilter = filter }
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 9.5, weight: isSelected ? .semibold : .medium))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.textSecondary(colorScheme))
                .background(
                    isSelected ? AppTheme.accent.opacity(0.14) : AppTheme.progressBg(colorScheme),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private func noteCard(_ note: NoteRecord) -> some View {
        HStack(spacing: 0) {
            Capsule()
                .fill(note.isPinned ? AppTheme.accent : AppTheme.stroke(colorScheme))
                .frame(width: 3)
                .padding(.vertical, 8)

            Button {
                editorContext = NoteEditorContext(note: note, initialGroupID: note.groupID)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Text(note.title)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary(colorScheme))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(relativeTime(note.updatedAt))
                            .font(.system(size: 8.5))
                            .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    }

                    if !note.body.isEmpty {
                        Text(note.body)
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.textSecondary(colorScheme))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Label(
                        store.groupName(for: note.groupID)
                            ?? LocalizedString.l(lang, en: "Ungrouped", zh: "未分组", ja: "未分類", ko: "미분류"),
                        systemImage: note.groupID == nil ? "tray" : "folder.fill"
                    )
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme).opacity(0.9))
                }
                .contentShape(Rectangle())
                .padding(.leading, 8)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            VStack(spacing: 3) {
                Button { store.togglePin(id: note.id) } label: {
                    Image(systemName: note.isPinned ? "pin.fill" : "pin")
                        .frame(width: 22, height: 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(note.isPinned ? AppTheme.accent : AppTheme.textSecondary(colorScheme))
                .help(note.isPinned
                    ? LocalizedString.l(lang, en: "Unpin", zh: "取消固定", ja: "固定解除", ko: "고정 해제")
                    : LocalizedString.l(lang, en: "Pin", zh: "固定", ja: "固定", ko: "고정"))

                Button { notePendingDelete = note } label: {
                    Image(systemName: "trash")
                        .frame(width: 22, height: 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                .help(LocalizedString.common("delete", lang: lang))
            }
            .font(.system(size: 9.5, weight: .semibold))
            .padding(.horizontal, 5)
        }
        .background(AppTheme.surface(colorScheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.stroke(colorScheme), lineWidth: 0.5)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: query.isEmpty ? "note.text.badge.plus" : "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(AppTheme.accent.opacity(0.7))

            Text(query.isEmpty
                ? LocalizedString.l(lang, en: "No notes here", zh: "这里还没有备忘", ja: "メモはまだありません", ko: "아직 메모가 없습니다")
                : LocalizedString.l(lang, en: "No matching notes", zh: "没有匹配的备忘", ja: "一致するメモはありません", ko: "일치하는 메모가 없습니다"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary(colorScheme))

            Text(query.isEmpty
                ? LocalizedString.l(lang, en: "Capture an idea, then place it in a group.", zh: "先记下内容，再按分组整理。", ja: "アイデアを記録して、グループで整理しましょう。", ko: "내용을 기록한 다음 그룹으로 정리하세요.")
                : LocalizedString.l(lang, en: "Try another keyword or group.", zh: "换个关键词或分组试试。", ja: "別のキーワードやグループをお試しください。", ko: "다른 검색어나 그룹을 사용해 보세요."))
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                .multilineTextAlignment(.center)

            if query.isEmpty {
                Button {
                    editorContext = NoteEditorContext(note: nil, initialGroupID: selectedGroupID)
                } label: {
                    Label(
                        LocalizedString.l(lang, en: "Create note", zh: "新建备忘", ja: "メモを作成", ko: "메모 만들기"),
                        systemImage: "plus"
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

    private var selectedGroupID: UUID? {
        if case .group(let id) = selectedFilter { return id }
        return nil
    }

    private func repairSelectedFilter() {
        guard case .group(let id) = selectedFilter else { return }
        if !store.groups.contains(where: { $0.id == id }) { selectedFilter = .ungrouped }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = lang.locale
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct NoteEditorContext: Identifiable {
    let id = UUID()
    let note: NoteRecord?
    let initialGroupID: UUID?
}

private struct NoteEditorView: View {
    let store: NotesStore
    let note: NoteRecord?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings = AppSettings.shared
    @State private var title: String
    @State private var bodyText: String
    @State private var selectedGroupID: UUID?

    init(store: NotesStore, note: NoteRecord?, initialGroupID: UUID?) {
        self.store = store
        self.note = note
        _title = State(initialValue: note?.title ?? "")
        _bodyText = State(initialValue: note?.body ?? "")
        _selectedGroupID = State(initialValue: note?.groupID ?? initialGroupID)
    }

    private var lang: AppLanguage { settings.language }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(note == nil
                    ? LocalizedString.l(lang, en: "New note", zh: "新建备忘", ja: "新規メモ", ko: "새 메모")
                    : LocalizedString.l(lang, en: "Edit note", zh: "编辑备忘", ja: "メモを編集", ko: "메모 편집"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary(colorScheme))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }
            .padding(14)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(LocalizedString.l(lang, en: "Title", zh: "标题", ja: "タイトル", ko: "제목"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    AppKitTextField(
                        text: $title,
                        placeholder: LocalizedString.l(lang, en: "Optional — derived from content", zh: "可选，留空时从内容生成", ja: "任意 — 内容から自動生成", ko: "선택 사항 — 내용에서 자동 생성"),
                        font: .systemFont(ofSize: 12)
                    )
                    .frame(height: 24)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(LocalizedString.l(lang, en: "Group", zh: "分组", ja: "グループ", ko: "그룹"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    Picker("", selection: $selectedGroupID) {
                        Text(LocalizedString.l(lang, en: "Ungrouped", zh: "未分组", ja: "未分類", ko: "미분류"))
                            .tag(Optional<UUID>.none)
                        ForEach(store.groups) { group in
                            Text(group.name).tag(Optional(group.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(LocalizedString.l(lang, en: "Content", zh: "内容", ja: "内容", ko: "내용"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    ZStack(alignment: .topLeading) {
                        AppKitTextEditor(text: $bodyText)
                        if bodyText.isEmpty {
                            Text(LocalizedString.l(lang, en: "Write something to remember…", zh: "写下需要记住的内容…", ja: "覚えておきたいことを書く…", ko: "기억할 내용을 작성하세요…"))
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.textSecondary(colorScheme).opacity(0.7))
                                .padding(.leading, 7)
                                .padding(.top, 7)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(minHeight: 170)
                    .background(AppTheme.elevatedSurface(colorScheme), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(AppTheme.stroke(colorScheme), lineWidth: 0.7)
                    }
                }
            }
            .padding(14)

            Divider()

            HStack(spacing: 10) {
                Button(LocalizedString.common("cancel", lang: lang)) { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                Button(LocalizedString.common("save", lang: lang)) { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
            .padding(14)
        }
        .frame(width: 360, height: 430)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard store.saveNote(
            id: note?.id,
            title: title,
            body: bodyText,
            groupID: selectedGroupID
        ) != nil else { return }
        dismiss()
    }
}

private struct NoteGroupManagerView: View {
    let store: NotesStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings = AppSettings.shared
    @State private var editorContext: NoteGroupEditorContext?
    @State private var groupPendingDelete: NoteGroupRecord?

    private var lang: AppLanguage { settings.language }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(LocalizedString.l(lang, en: "Note groups", zh: "备忘分组", ja: "メモグループ", ko: "메모 그룹"))
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text("\(store.groups.count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }
            .padding(14)

            Divider()

            if store.groups.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(AppTheme.accent.opacity(0.7))
                    Text(LocalizedString.l(lang, en: "No custom groups", zh: "还没有自定义分组", ja: "カスタムグループはありません", ko: "사용자 그룹이 없습니다"))
                        .font(.system(size: 12, weight: .semibold))
                    Text(LocalizedString.l(lang, en: "Ungrouped notes always remain available.", zh: "未分组内容会一直保留。", ja: "未分類のメモは常に保持されます。", ko: "미분류 메모는 항상 유지됩니다."))
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(store.groups) { group in
                            HStack(spacing: 8) {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(AppTheme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.name)
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(AppTheme.textPrimary(colorScheme))
                                    Text(groupNoteCount(group.id))
                                        .font(.system(size: 9))
                                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                                }
                                Spacer()
                                Button {
                                    editorContext = NoteGroupEditorContext(group: group)
                                } label: {
                                    Image(systemName: "pencil")
                                        .frame(width: 22, height: 22)
                                }
                                .buttonStyle(.plain)
                                Button { groupPendingDelete = group } label: {
                                    Image(systemName: "trash")
                                        .frame(width: 22, height: 22)
                                }
                                .buttonStyle(.plain)
                            }
                            .font(.system(size: 10))
                            .padding(9)
                            .background(AppTheme.progressBg(colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .padding(12)
                }
            }

            Divider()

            Button {
                editorContext = NoteGroupEditorContext(group: nil)
            } label: {
                Label(
                    LocalizedString.l(lang, en: "New group", zh: "新建分组", ja: "新規グループ", ko: "새 그룹"),
                    systemImage: "plus"
                )
                .font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .padding(12)
        }
        .frame(width: 330, height: 360)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $editorContext) { context in
            NoteGroupEditorView(store: store, group: context.group)
        }
        .confirmationDialog(
            LocalizedString.l(
                lang,
                en: "Delete group \"\(groupPendingDelete?.name ?? "")\"? Notes will become ungrouped.",
                zh: "删除分组“\(groupPendingDelete?.name ?? "")”？其中备忘会移到未分组。",
                ja: "グループ「\(groupPendingDelete?.name ?? "")」を削除しますか？メモは未分類へ移動します。",
                ko: "\"\(groupPendingDelete?.name ?? "")\" 그룹을 삭제하시겠습니까? 메모는 미분류로 이동합니다."
            ),
            isPresented: Binding(
                get: { groupPendingDelete != nil },
                set: { if !$0 { groupPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(LocalizedString.common("delete", lang: lang), role: .destructive) {
                if let groupPendingDelete { store.deleteGroup(id: groupPendingDelete.id) }
                groupPendingDelete = nil
            }
            Button(LocalizedString.common("cancel", lang: lang), role: .cancel) {
                groupPendingDelete = nil
            }
        }
    }

    private func groupNoteCount(_ id: UUID) -> String {
        let count = store.notes.filter { $0.groupID == id }.count
        return LocalizedString.l(
            lang,
            en: "\(count) notes",
            zh: "\(count) 条备忘",
            ja: "\(count) 件のメモ",
            ko: "메모 \(count)개"
        )
    }
}

private struct NoteGroupEditorContext: Identifiable {
    let id = UUID()
    let group: NoteGroupRecord?
}

private struct NoteGroupEditorView: View {
    let store: NotesStore
    let group: NoteGroupRecord?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings = AppSettings.shared
    @State private var name: String
    @State private var showsError = false

    init(store: NotesStore, group: NoteGroupRecord?) {
        self.store = store
        self.group = group
        _name = State(initialValue: group?.name ?? "")
    }

    private var lang: AppLanguage { settings.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(group == nil
                ? LocalizedString.l(lang, en: "New group", zh: "新建分组", ja: "新規グループ", ko: "새 그룹")
                : LocalizedString.l(lang, en: "Rename group", zh: "重命名分组", ja: "グループ名を変更", ko: "그룹 이름 변경"))
                .font(.system(size: 14, weight: .bold))

            AppKitTextField(
                text: $name,
                placeholder: LocalizedString.l(lang, en: "Group name", zh: "分组名称", ja: "グループ名", ko: "그룹 이름"),
                font: .systemFont(ofSize: 12),
                onSubmit: save
            )
            .frame(height: 24)

            if showsError {
                Text(LocalizedString.l(lang, en: "Use a unique, non-empty name.", zh: "请输入不重复的分组名称。", ja: "空でない一意の名前を入力してください。", ko: "비어 있지 않은 고유한 이름을 입력하세요."))
                    .font(.system(size: 10))
                    .foregroundStyle(Color(nsColor: .systemRed))
            }

            HStack {
                Button(LocalizedString.common("cancel", lang: lang)) { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                Button(LocalizedString.common("save", lang: lang)) { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 300)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func save() {
        let succeeded: Bool
        if let group {
            succeeded = store.renameGroup(id: group.id, name: name)
        } else {
            succeeded = store.addGroup(name: name) != nil
        }
        if succeeded { dismiss() } else { showsError = true }
    }
}

private struct AppKitTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: 12)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 5, height: 5)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = text

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text { textView.string = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AppKitTextEditor

        init(_ parent: AppKitTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}
