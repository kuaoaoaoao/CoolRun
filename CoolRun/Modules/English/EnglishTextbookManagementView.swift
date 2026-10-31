import SwiftUI
import UniformTypeIdentifiers

struct EnglishTextbookManagementView: View {
    // 以独立窗口宿主方式打开时由外部传入关闭回调；sheet 场景下回退到 dismiss
    var onRequestClose: (() -> Void)? = nil

    @ObservedObject private var textbookStore = EnglishTextbookStore.shared
    @ObservedObject private var progressStore = EnglishProgressStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var showingImporter = false
    @State private var importStage = AppSettings.shared.englishStage
    @State private var importError: String?
    @State private var showImportError = false
    // 浏览中的课本（仅看详情，不切换使用中课本，避免打断播放）
    @State private var browsingTextbookID: String?
    // hover 删除按钮与删除确认
    @State private var hoveredTextbookID: String?
    @State private var textbookPendingDelete: EnglishTextbook?
    // 导入成功提示
    @State private var importSuccessMessage: String?
    @State private var importSuccessDismissTask: Task<Void, Never>?

    private var lang: AppLanguage { settings.language }

    private var selectedTextbook: EnglishTextbook {
        textbookStore.selectedTextbook
    }

    // 详情区展示的课本：优先浏览中的，否则是使用中的
    private var displayedTextbook: EnglishTextbook {
        if let browsingTextbookID,
           let browsing = (textbookStore.builtinTextbooks + textbookStore.customTextbooks).first(where: { $0.id == browsingTextbookID }) {
            return browsing
        }
        return selectedTextbook
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            HStack(spacing: 0) {
                textbookList
                    .frame(width: 220)

                Divider()

                textbookDetail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 660, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: allowedContentTypes,
            allowsMultipleSelection: false,
            onCompletion: handleFileImport
        )
        .alert(LocalizedString.english("textbook_import_failed"), isPresented: $showImportError) {
            Button(LocalizedString.common("ok")) {
                importError = nil
            }
        } message: {
            Text(importError ?? "")
        }
        .confirmationDialog(
            LocalizedString.l(
                lang,
                en: "Delete textbook \"\(textbookPendingDelete?.title ?? "")\"?",
                zh: "删除课本“\(textbookPendingDelete?.title ?? "")”？",
                ja: "教材「\(textbookPendingDelete?.title ?? "")」を削除しますか？",
                ko: "교재 \"\(textbookPendingDelete?.title ?? "")\"을(를) 삭제하시겠습니까?"
            ),
            isPresented: Binding(
                get: { textbookPendingDelete != nil },
                set: { if !$0 { textbookPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(LocalizedString.common("delete"), role: .destructive) {
                if let textbook = textbookPendingDelete {
                    if browsingTextbookID == textbook.id { browsingTextbookID = nil }
                    textbookStore.removeTextbook(textbook)
                }
                textbookPendingDelete = nil
            }
            Button(LocalizedString.l(lang, en: "Cancel", zh: "取消", ja: "キャンセル", ko: "취소"), role: .cancel) {
                textbookPendingDelete = nil
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppTheme.healthy)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedString.english("textbook_management"))
                    .font(.system(size: 17, weight: .bold))
                Text(LocalizedString.english("textbook_source_hint"))
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    .lineLimit(1)
            }

            Spacer()

            Picker("", selection: $importStage) {
                ForEach(EnglishStage.allCases) { stage in
                    Text(stage.shortTitle).tag(stage)
                }
            }
            .labelsHidden()
            .frame(width: 112)
            .help(LocalizedString.english("import_stage_help"))

            Button {
                showingImporter = true
            } label: {
                Label(LocalizedString.english("import_textbook"), systemImage: "square.and.arrow.down")
            }

            Button {
                if let onRequestClose {
                    onRequestClose()
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }
            .buttonStyle(.plain)
            .help(LocalizedString.common("close"))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var textbookList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                textbookGroup(
                    title: LocalizedString.english("builtin_textbooks"),
                    textbooks: textbookStore.builtinTextbooks
                )

                if !textbookStore.customTextbooks.isEmpty {
                    textbookGroup(
                        title: LocalizedString.english("imported_textbooks"),
                        textbooks: textbookStore.customTextbooks
                    )
                }
            }
            .padding(12)
        }
        .background(AppTheme.progressBg(colorScheme).opacity(colorScheme == .dark ? 0.55 : 0.7))
    }

    private func textbookGroup(title: String, textbooks: [EnglishTextbook]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            ForEach(textbooks) { textbook in
                textbookRow(textbook)
            }
        }
    }

    private func textbookRow(_ textbook: EnglishTextbook) -> some View {
        let progress = textbookStore.progressSummary(for: textbook, progress: progressStore.records)
        let isSelected = textbook.id == textbookStore.selectedTextbookID
        let isBrowsing = textbook.id == displayedTextbook.id

        // 点击只浏览详情，真正切换靠详情区的"使用此课本"按钮，避免误碰打断播放
        return Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                browsingTextbookID = textbook.id
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Image(systemName: textbook.stage.icon)
                        .font(.system(size: 11, weight: .semibold))
                    Text(textbook.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    // hover 时显示删除按钮（仅导入课本）
                    if textbook.isImported, hoveredTextbookID == textbook.id {
                        Button {
                            textbookPendingDelete = textbook
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(AppTheme.critical)
                                .frame(width: 18, height: 18)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(LocalizedString.common("delete"))
                    }
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }

                Text("\(textbook.wordCount) \(LocalizedString.english("words_count")) · \(progress.viewedCount) \(LocalizedString.english("studied_count"))")
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? AppTheme.healthy.opacity(0.9) : AppTheme.textSecondary(colorScheme))

                ProgressView(value: progress.studiedRatio(total: textbook.wordCount))
                    .tint(isSelected ? AppTheme.healthy : AppTheme.textSecondary(colorScheme))
                    .scaleEffect(y: 0.7)
            }
            .padding(9)
            .foregroundStyle(isSelected ? AppTheme.healthy : AppTheme.textPrimary(colorScheme))
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? AppTheme.healthy.opacity(0.13) : (isBrowsing ? AppTheme.progressBg(colorScheme) : Color.clear))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            // 快速跨行移动时 enter/exit 事件可能乱序，只清除自己的 hover 状态
            if hovering {
                hoveredTextbookID = textbook.id
            } else if hoveredTextbookID == textbook.id {
                hoveredTextbookID = nil
            }
        }
        .contextMenu {
            if textbook.isImported {
                Button(LocalizedString.common("delete"), role: .destructive) {
                    textbookPendingDelete = textbook
                }
            }
        }
    }

    private var textbookDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                detailTitle
                statsGrid
                formatHint
                wordPreview
            }
            .padding(18)
        }
    }

    private var detailTitle: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(displayedTextbook.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary(colorScheme))
                Text(displayedTextbook.source == .builtin ? LocalizedString.english("builtin") : LocalizedString.english("imported"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(displayedTextbook.source == .builtin ? AppTheme.healthy : AppTheme.warning)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background((displayedTextbook.source == .builtin ? AppTheme.healthy : AppTheme.warning).opacity(0.13), in: Capsule())
            }

            Text(displayedTextbook.summary)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    textbookStore.selectTextbook(displayedTextbook)
                    settings.englishStage = displayedTextbook.stage
                }
            } label: {
                Label(LocalizedString.english("use_this_textbook"), systemImage: "checkmark.circle")
                    .font(.system(size: 12, weight: .semibold))
            }
            .disabled(textbookStore.selectedTextbookID == displayedTextbook.id)

            // 导入成功提示（短暂显示）
            if let message = importSuccessMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.healthy)
            }
        }
    }

    private var statsGrid: some View {
        let progress = textbookStore.progressSummary(for: displayedTextbook, progress: progressStore.records)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            statTile(title: LocalizedString.english("words_count"), value: "\(displayedTextbook.wordCount)", icon: "textformat.abc")
            statTile(title: LocalizedString.english("studied_count"), value: "\(progress.viewedCount)", icon: "eye")
            statTile(title: LocalizedString.english("known_count"), value: "\(progress.familiarOrBetterCount)", icon: "checkmark")
            statTile(title: LocalizedString.english("mastered"), value: "\(progress.masteredCount)", icon: "seal.fill")
        }
    }

    private func statTile(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.healthy)
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppTheme.progressBg(colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var formatHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedString.english("import_format_title"))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary(colorScheme))
            Text(LocalizedString.english("import_format_hint"))
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .background(AppTheme.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var wordPreview: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(LocalizedString.english("word_preview"))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary(colorScheme))

            LazyVStack(spacing: 0) {
                ForEach(displayedTextbook.items.prefix(160)) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary(colorScheme))
                            .frame(width: 112, alignment: .leading)
                            .lineLimit(1)
                        Text(item.translation)
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.textSecondary(colorScheme))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(progressStore.progress(for: item.id).mastery.title)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(AppTheme.healthy)
                    }
                    .padding(.vertical, 6)
                    Divider().opacity(0.45)
                }
            }
            .padding(.horizontal, 10)
            .background(AppTheme.progressBg(colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var allowedContentTypes: [UTType] {
        [
            .plainText,
            .commaSeparatedText,
            UTType(filenameExtension: "csv") ?? .commaSeparatedText,
            UTType(filenameExtension: "tsv") ?? .plainText
        ]
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let imported = try textbookStore.importTextbook(from: url, stage: importStage)
            // 导入成功：自动切换到新课本并给出提示
            withAnimation(.easeInOut(duration: 0.16)) {
                textbookStore.selectTextbook(imported)
                settings.englishStage = imported.stage
                browsingTextbookID = imported.id
            }
            importSuccessMessage = LocalizedString.l(
                lang,
                en: "Imported \"\(imported.title)\" (\(imported.wordCount) words), now in use",
                zh: "已导入“\(imported.title)”（\(imported.wordCount) 词）并切换使用",
                ja: "「\(imported.title)」（\(imported.wordCount) 語）を取り込み、使用中にしました",
                ko: "\"\(imported.title)\"(\(imported.wordCount)단어)를 가져와 사용 중으로 전환했습니다"
            )
            // 连续导入时先取消上一个清除任务，避免新提示被提前清掉
            importSuccessDismissTask?.cancel()
            importSuccessDismissTask = Task {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                importSuccessMessage = nil
            }
        } catch {
            importError = error.localizedDescription
            showImportError = true
        }
    }
}
