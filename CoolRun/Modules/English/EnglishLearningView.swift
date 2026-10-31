import SwiftUI
import AVFoundation
import AppKit

struct EnglishLearningView: View {
    @ObservedObject private var manager = EnglishLearningManager.shared
    @ObservedObject private var progressStore = EnglishProgressStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var textbookStore = EnglishTextbookStore.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showVoiceOnboarding = false
    @State private var showTextbookManager = false

    private var summary: EnglishDailySummary {
        progressStore.summary(dailyTarget: settings.englishDailyTarget)
    }

    private var dailyProgressText: String {
        if summary.isGoalComplete {
            return LocalizedString.english("goal_done")
        }
        return "\(LocalizedString.english("today_learning")) \(summary.learnedCount)/\(summary.dailyTarget)"
    }

    private var queueProgress: Double {
        guard manager.queueCount > 0 else { return 0 }
        return min(Double(manager.currentIndex + 1) / Double(manager.queueCount), 1)
    }

    var body: some View {
        VStack(spacing: 8) {
            dailyProgress
            categoryPicker

            // 关闭状态持久化，面板重建后不再反复弹出
            if !settings.englishVoiceHintDismissed && manager.needsHigherQualityEnglishVoice {
                voiceQualityBanner
            }

            if let item = manager.currentItem {
                learningCard(item)
                playbackControls
                feedbackControls(item)
            } else {
                // 空态给行动入口，不让用户卡在"暂无内容"
                ContentUnavailableView {
                    Label(LocalizedString.english("no_content"), systemImage: "character.book.closed")
                } actions: {
                    Button {
                        openTextbookManager()
                    } label: {
                        Label(LocalizedString.english("open_textbook_manager"), systemImage: "books.vertical")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 410, maxHeight: .infinity, alignment: .top)
        .appCardSurface(cornerRadius: 12)
        .overlay {
            if showVoiceOnboarding {
                voiceOnboardingOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .sheet(isPresented: $showTextbookManager) {
            EnglishTextbookManagementView()
        }
        .animation(.easeInOut(duration: 0.22), value: showVoiceOnboarding)
        .onAppear {
            manager.refreshQueue()
            manager.markCurrentViewed()
            presentVoiceOnboardingIfNeeded()
            syncEnglishToCloud()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            manager.refreshQueue()
        }
        .onChange(of: manager.currentItem) { _, _ in
            syncEnglishToCloud()
        }
        .onChange(of: summary) { _, _ in
            syncEnglishToCloud()
        }
    }

    /// 课本管理面板 660x520 远超 320pt 弹窗，经 MacAppDelegate 以独立窗口打开；取不到 delegate 时回退 sheet
    private func openTextbookManager() {
        if let delegate = NSApp.delegate as? MacAppDelegate {
            delegate.openEnglishTextbookManagerWindow()
        } else {
            showTextbookManager = true
        }
    }

    /// 将英语打卡快照镜像到 iCloud，供手表端抬手查看（未开 iCloud 能力时优雅降级）。
    private func syncEnglishToCloud() {
        CloudSyncStore.shared.pushEnglish(
            streak: summary.streak,
            learnedToday: summary.learnedCount,
            dailyTarget: summary.dailyTarget,
            word: manager.currentItem?.title,
            translation: manager.currentItem?.translation,
            wordID: manager.currentItem?.id,
            accent: settings.englishAccent.rawValue
        )
    }

    private var dailyProgress: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .stroke(AppTheme.progressBg(colorScheme), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: max(0.025, summary.progress))
                    .stroke(
                        summary.isGoalComplete ? AppTheme.healthy : AppTheme.accent,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                if summary.isGoalComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppTheme.healthy)
                } else {
                    Text("\(summary.learnedCount)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(dailyProgressText)
                    .font(.system(size: 11, weight: .semibold))

                HStack(spacing: 7) {
                    Label("\(summary.streak) \(LocalizedString.english("days"))", systemImage: "flame.fill")
                        .foregroundStyle(summary.streak > 0 ? AppTheme.warning : AppTheme.textSecondary(colorScheme))
                    Label("\(summary.masteredCount)", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(summary.masteredCount > 0 ? AppTheme.healthy : AppTheme.textSecondary(colorScheme))
                }
                .font(.system(size: 8.5, weight: .medium, design: .rounded))
            }

            Spacer(minLength: 4)
            textbookButton
        }
        .padding(9)
        .background(AppTheme.elevatedSurface(colorScheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.stroke(colorScheme), lineWidth: 0.5)
        }
    }

    private var masteryTint: Color {
        switch manager.currentProgress.mastery {
        case .new: AppTheme.textSecondary(colorScheme)
        case .unfamiliar: AppTheme.warning
        case .learning: AppTheme.accent
        case .familiar, .mastered: AppTheme.healthy
        }
    }

    private var masteryStatus: some View {
        Text(manager.currentProgress.mastery.title)
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(masteryTint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(masteryTint.opacity(0.12), in: Capsule())
    }

    private var textbookButton: some View {
        Button {
            openTextbookManager()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 9, weight: .semibold))
                Text(textbookStore.selectedTextbook.stage.shortTitle)
                    .font(.system(size: 10, weight: .semibold))
                Text("\(textbookStore.selectedTextbook.wordCount)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(AppTheme.accent)
            .background(AppTheme.accent.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(LocalizedString.english("open_textbook_manager"))
    }

    private var categoryPicker: some View {
        HStack(spacing: 5) {
            ForEach(EnglishLearningCategory.allCases) { category in
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        manager.selectCategory(category)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: category.icon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(category.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .padding(.vertical, 6)
                    .foregroundStyle(manager.category == category ? AppTheme.accent : AppTheme.textSecondary(colorScheme))
                    .background {
                        if manager.category == category {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(AppTheme.accent.opacity(0.14))
                        }
                    }
                }
                .buttonStyle(.plain)
                .help("\(LocalizedString.english("study_category")) \(category.title)")
            }
        }
        .padding(4)
        .background(AppTheme.progressBg(colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func learningCard(_ item: EnglishLearningItem) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(cardEyebrow(item))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .textCase(.uppercase)
                    Text(manager.positionText)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                }
                Spacer()
                masteryStatus
                Button(action: manager.toggleFavorite) {
                    Image(systemName: manager.currentProgress.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 13))
                        .foregroundStyle(manager.currentProgress.isFavorite ? AppTheme.warning : AppTheme.textSecondary(colorScheme))
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(.plain)
                .help(manager.currentProgress.isFavorite ? LocalizedString.english("unfavorite") : LocalizedString.english("favorite"))
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.progressBg(colorScheme))
                    Capsule()
                        .fill(AppTheme.accent.opacity(0.78))
                        .frame(width: max(2, geometry.size.width * queueProgress))
                }
            }
            .frame(height: 2.5)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 9) {
                    switch item.category {
                    case .words:
                        wordContent(item)
                    case .sentences:
                        sentenceContent(item)
                    case .passages:
                        passageContent(item)
                    case .daily:
                        quoteContent(item)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 208, maxHeight: 236, alignment: .topLeading)
        .background(AppTheme.elevatedSurface(colorScheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    manager.state == .idle ? AppTheme.stroke(colorScheme) : AppTheme.accent.opacity(0.34),
                    lineWidth: manager.state == .idle ? 0.5 : 1
                )
        }
    }

    private func wordContent(_ item: EnglishLearningItem) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary(colorScheme))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let pronunciation = item.pronunciation {
                    Text(pronunciation)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            if settings.englishShowTranslation {
                Text("\(item.partOfSpeech ?? "")  \(item.translation)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.healthy)
            }
            if let example = item.example {
                Divider().opacity(0.5)
                Text(example)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary(colorScheme))
                    .lineSpacing(2)
                if settings.englishShowTranslation, let translation = item.exampleTranslation {
                    Text(translation)
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                }
            }
        }
    }

    private func sentenceContent(_ item: EnglishLearningItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.title)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary(colorScheme))
                .lineSpacing(4)
                .textSelection(.enabled)
            if settings.englishShowTranslation {
                Text(item.translation)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }
        }
    }

    private func passageContent(_ item: EnglishLearningItem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(item.title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
            ForEach(Array(item.passageSentences.enumerated()), id: \.offset) { _, sentence in
                Text(sentence)
                    .font(.system(size: 11, weight: manager.currentSpokenText == sentence ? .semibold : .regular))
                    .foregroundStyle(manager.currentSpokenText == sentence ? AppTheme.accent : AppTheme.textPrimary(colorScheme))
                    .lineSpacing(2)
            }
            if settings.englishShowTranslation {
                Divider().opacity(0.5)
                Text(item.translation)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }
        }
    }

    private func quoteContent(_ item: EnglishLearningItem) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("“\(item.title)”")
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .lineSpacing(4)
                .foregroundStyle(AppTheme.textPrimary(colorScheme))
                .textSelection(.enabled)
            if let source = item.source {
                Text("— \(source)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
            }
            if settings.englishShowTranslation {
                Text(item.translation)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 7) {
            controlButton("backward.end.fill", help: LocalizedString.common("previous"), action: manager.previous)
            controlButton("tortoise.fill", help: LocalizedString.english("slow_read")) { manager.replay(slow: true) }

            Button(action: manager.toggleContinuousPlayback) {
                Image(systemName: primaryPlaybackIcon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 32)
                    .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(primaryPlaybackHelp)

            controlButton("speaker.wave.2.fill", help: LocalizedString.english("read_once")) { manager.replay() }
            controlButton("forward.end.fill", help: LocalizedString.common("next"), action: manager.next)

            if manager.state != .idle {
                controlButton("stop.fill", help: LocalizedString.common("stop"), action: manager.stop)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(5)
        .background(AppTheme.progressBg(colorScheme).opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func feedbackControls(_ item: EnglishLearningItem) -> some View {
        HStack(spacing: 8) {
            feedbackButton(
                LocalizedString.english("not_known"),
                icon: "arrow.counterclockwise",
                color: AppTheme.warning,
                action: manager.markUnfamiliar
            )
            feedbackButton(
                manager.currentProgress.mastery >= .familiar ? LocalizedString.english("mastered") : LocalizedString.english("known"),
                icon: "checkmark",
                color: AppTheme.healthy,
                filled: true,
                action: manager.markKnown
            )
        }
    }

    private func feedbackButton(
        _ title: String,
        icon: String,
        color: Color,
        filled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(filled ? Color.white : color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    filled ? color : color.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay {
                    if !filled {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(color.opacity(0.20), lineWidth: 0.5)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func controlButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                .frame(width: 30, height: 30)
                .background(AppTheme.progressBg(colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func cardEyebrow(_ item: EnglishLearningItem) -> String {
        switch manager.state {
        case .playing:
            return LocalizedString.english("listening")
        case .paused:
            return LocalizedString.english("paused")
        case .idle:
            return item.category == .daily ? LocalizedString.english("daily_sentence") : item.category.title
        }
    }

    private var primaryPlaybackIcon: String {
        switch manager.state {
        case .idle: return "play.fill"
        case .playing: return "pause.fill"
        case .paused: return "play.fill"
        }
    }

    private var primaryPlaybackHelp: String {
        switch manager.state {
        case .idle: return LocalizedString.english("continuous_read")
        case .playing: return LocalizedString.english("pause_read")
        case .paused: return LocalizedString.english("resume_read")
        }
    }

    private var voiceQualityBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.warning)
            Text(LocalizedString.english("download_voice"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppTheme.textPrimary(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 6)
            Button {
                EnglishLearningManager.openSystemVoiceDownloadSettings()
            } label: {
                Text(LocalizedString.english("download"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(AppTheme.warning, in: Capsule())
            }
            .buttonStyle(.plain)
            .help(LocalizedString.english("open_voice_download"))
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { settings.englishVoiceHintDismissed = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help(LocalizedString.english("dismiss"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(AppTheme.warning.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - 首次高质量语音引导

    private func presentVoiceOnboardingIfNeeded() {
        guard !settings.englishHasSeenVoiceOnboarding else { return }
        guard manager.needsHigherQualityEnglishVoice else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeInOut(duration: 0.25)) { showVoiceOnboarding = true }
        }
    }

    private func dismissVoiceOnboarding() {
        settings.englishHasSeenVoiceOnboarding = true
        withAnimation(.easeInOut(duration: 0.2)) { showVoiceOnboarding = false }
    }

    private var voiceOnboardingOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(colorScheme == .dark ? 0.55 : 0.32))

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 11) {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "waveform.badge.mic")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizedString.english("voice_better_title"))
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(AppTheme.textPrimary(colorScheme))
                            Text(LocalizedString.english("voice_better_subtitle"))
                                .font(.system(size: 10))
                                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                        }
                        Spacer()
                        Button {
                            dismissVoiceOnboarding()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                        }
                        .buttonStyle(.plain)
                        .help(LocalizedString.english("close_hint"))
                    }

                    Divider().opacity(0.5)

                    VStack(alignment: .leading, spacing: 8) {
                        stepRow(number: 1, text: LocalizedString.english("voice_step1"))
                        stepRow(number: 2, text: LocalizedString.english("voice_step2"))
                        stepRow(number: 3, text: LocalizedString.english("voice_step3"))
                    }

                    Divider().opacity(0.5)

                    Text(LocalizedString.english("voice_recommend"))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                        .textCase(.uppercase)

                    VStack(alignment: .leading, spacing: 6) {
                        voiceRecommendation(flag: "🇺🇸", name: "Zoe", quality: "Enhanced", installed: isVoiceInstalled(name: "Zoe", quality: .enhanced))
                        voiceRecommendation(flag: "🇺🇸", name: "Ava", quality: "Premium", installed: isVoiceInstalled(name: "Ava", quality: .premium))
                        voiceRecommendation(flag: "🇬🇧", name: "Serena", quality: "Premium", installed: isVoiceInstalled(name: "Serena", quality: .premium))
                        voiceRecommendation(flag: "🇬🇧", name: "Daniel", quality: "Enhanced", installed: isVoiceInstalled(name: "Daniel", quality: .enhanced))
                    }

                    HStack(spacing: 8) {
                        Button {
                            dismissVoiceOnboarding()
                        } label: {
                            Text(LocalizedString.english("later"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(AppTheme.progressBg(colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            EnglishLearningManager.openSystemVoiceDownloadSettings()
                            dismissVoiceOnboarding()
                        } label: {
                            Label(LocalizedString.english("download_now"), systemImage: "arrow.down.circle.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 2)
                }
                .padding(13)
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(colorScheme == .dark ? Color(nsColor: .windowBackgroundColor).opacity(0.98) : Color.white.opacity(0.98))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.10), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 14, x: 0, y: 6)
            .padding(8)
        }
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(AppTheme.healthy, in: Circle())
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textPrimary(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
    }

    private func voiceRecommendation(flag: String, name: String, quality: String, installed: Bool) -> some View {
        HStack(spacing: 6) {
            Text(flag)
                .font(.system(size: 13))
            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary(colorScheme))
            Text("·")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
            Text(quality)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(quality == "Premium" ? AppTheme.healthy : AppTheme.warning)
            Spacer(minLength: 4)
            if installed {
                Label(LocalizedString.english("installed"), systemImage: "checkmark.seal.fill")
                    .font(.system(size: 9, weight: .bold))
                    .labelStyle(.iconOnly)
                    .foregroundStyle(AppTheme.healthy)
                    .help(LocalizedString.english("installed"))
            }
        }
    }

    private func isVoiceInstalled(name: String, quality: AVSpeechSynthesisVoiceQuality) -> Bool {
        AVSpeechSynthesisVoice.speechVoices().contains { $0.name == name && $0.quality == quality }
    }
}
