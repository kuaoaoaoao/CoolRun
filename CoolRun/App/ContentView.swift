import SwiftUI
import Combine
import AppKit
import Observation

// MARK: - 视图模式

enum ViewMode: String, CaseIterable, Sendable {
    case today
    case monitor
    case gold
    case calendar
    case english
    case codex
    case notes
    case clipboard
    case diagnostics
    case aiAssistant

    var icon: String {
        switch self {
        case .today: return "sun.max.fill"
        case .monitor: return "chart.bar.fill"
        case .gold: return "chart.line.uptrend.xyaxis"
        case .calendar: return "calendar"
        case .english: return "character.book.closed"
        case .codex: return "sparkles"
        case .notes: return "note.text"
        case .clipboard: return "doc.on.clipboard"
        case .diagnostics: return "stethoscope"
        case .aiAssistant: return "brain.head.profile"
        }
    }

    var displayName: String {
        switch self {
        case .today: return LocalizedString.l(AppSettings.shared.language, en: "Today", zh: "今天", ja: "今日", ko: "오늘")
        case .monitor: return LocalizedString.calendar("monitor")
        case .gold: return LocalizedString.goldPrice("gold_price")
        case .calendar: return LocalizedString.calendar("calendar")
        case .english: return LocalizedString.english("english")
        case .codex: return "Codex"
        case .notes: return LocalizedString.l(AppSettings.shared.language, en: "Notes", zh: "备忘录", ja: "メモ", ko: "메모")
        case .clipboard: return LocalizedString.l(AppSettings.shared.language, en: "Clipboard", zh: "剪切板", ja: "クリップボード", ko: "클립보드")
        case .diagnostics: return LocalizedString.l(AppSettings.shared.language, en: "Diagnostics", zh: "诊断", ja: "診断", ko: "진단")
        case .aiAssistant: return LocalizedString.l(AppSettings.shared.language, en: "AI", zh: "AI", ja: "AI", ko: "AI")
        }
    }

    var keyboardShortcut: KeyEquivalent {
        switch self {
        case .today: return "0"
        case .monitor: return "1"
        case .gold: return "2"
        case .calendar: return "3"
        case .english: return "4"
        case .codex: return "5"
        case .notes: return "6"
        case .clipboard: return "7"
        case .diagnostics: return "8"
        case .aiAssistant: return "9"
        }
    }

    /// 面板外边距，需与 `MenuBarMonitorView` 的 `.padding(panelOuterInset)` 保持一致。
    static let panelOuterInset: CGFloat = 8

    /// 各模块在菜单栏面板中的内容尺寸（不含外边距）。
    /// 信息密度高的模块（黄金、诊断）需要更大的画布，否则只能靠层层折叠塞进去。
    var panelContentSize: CGSize {
        switch self {
        case .today, .monitor:
            return CGSize(width: 320, height: 512)
        case .gold:
            return CGSize(width: 384, height: 616)
        case .calendar:
            return CGSize(width: 344, height: 560)
        case .english, .codex, .notes, .clipboard:
            return CGSize(width: 340, height: 540)
        case .diagnostics:
            return CGSize(width: 376, height: 596)
        case .aiAssistant:
            return CGSize(width: 356, height: 560)
        }
    }

    /// `NSPopover.contentSize` 需要的总尺寸（内容 + 两侧外边距）。
    var panelSize: CGSize {
        CGSize(
            width: panelContentSize.width + Self.panelOuterInset * 2,
            height: panelContentSize.height + Self.panelOuterInset * 2
        )
    }

    /// 默认在导航栏显示的模块，其余模块需在设置中手动开启。
    /// AI 助手是核心卖点，默认可见；否则新用户根本发现不了它。
    static let defaultVisible: Set<ViewMode> = [.monitor, .gold, .calendar, .clipboard, .aiAssistant]

    /// 可见模块集合的结构版本。**新增模块时 +1**，并在 `modulesAdded(after:)` 里登记。
    /// 老用户机器上已存过 `visible_tabs`，不做迁移的话新模块永远不会出现。
    static let visibleTabsSchemaVersion = 2

    /// 某个结构版本之后新增的模块，用于升级时并入老用户的可见集合。
    static func modulesAdded(after schema: Int) -> [ViewMode] {
        if schema < 2 { return [.aiAssistant] }
        return []
    }
}

struct ContentView: View {
    @State private var viewModel = SystemMonitorViewModel()
    // 重启后回到上次使用的模块；若该模块已被隐藏则落到第一个可见模块
    @State private var viewMode: ViewMode = AppSettings.shared.initialViewMode
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var router = AppNavigationRouter.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var progressStore = EnglishProgressStore.shared
    @State private var goldStore = GoldPriceStore.shared
    @State private var tradeStore = GoldTradeStore.shared
    @State private var codexModel = CodexMonitorViewModel.shared
    @State private var claudeModel = ClaudeMonitorViewModel.shared

    var body: some View {
        VStack(spacing: 0) {
            ModuleNavigationRail(selection: $viewMode, todayAttention: todayAttention)
                .padding(.bottom, 8)

            Group {
                switch viewMode {
                case .today:
                    TodayOverviewView(snapshot: viewModel.snapshot)
                case .monitor:
                    MonitorPanel(
                        snapshot: viewModel.snapshot,
                        cpuHistory: viewModel.cpuHistory,
                        memoryHistory: viewModel.memoryHistory,
                        downloadHistory: viewModel.downloadHistory,
                        uploadHistory: viewModel.uploadHistory,
                        cpuTempHistory: viewModel.cpuTempHistory,
                        gpuTempHistory: viewModel.gpuTempHistory
                    )
                case .gold:
                    GoldAnalysisView()
                case .calendar:
                    CalendarView()
                case .english:
                    EnglishLearningView()
                case .codex:
                    AIMonitorView()
                case .notes:
                    NotesView()
                case .clipboard:
                    ClipboardHistoryView()
                case .diagnostics:
                    DiagnosticsView()
                case .aiAssistant:
                    AIAssistantView()
                }
            }
            .id(viewMode)
            .transition(.opacity.combined(with: .scale(scale: 0.985)))
        }
        .padding(8)
        .background {
            ZStack {
                VisualEffectBlur(material: colorScheme == .dark ? .hudWindow : .menu, blendingMode: .behindWindow)
                AppTheme.canvas(colorScheme)
                LinearGradient(
                    colors: [
                        AppTheme.accent.opacity(colorScheme == .dark ? 0.08 : 0.055),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .center
                )
            }
        }
        .onAppear { viewModel.start() }
        .onReceive(router.$request.compactMap { $0 }) { request in
            viewMode = request.mode
        }
        .onDisappear { viewModel.stop() }
        .onChange(of: viewMode) { _, newValue in
            AppSettings.shared.lastViewModeRaw = newValue.rawValue
        }
        // 当前模块在设置中被隐藏时，自动切到第一个可见模块
        .onChange(of: settings.visibleTabRaws) { _, _ in
            if !settings.isTabVisible(viewMode) {
                viewMode = settings.visibleViewModes.first ?? .monitor
            }
        }
    }

    private var todayAttention: TodaySeverity? {
        TodaySummaryBuilder.maximumSeverity(in: TodaySummaryBuilder.current(
            snapshot: viewModel.snapshot,
            settings: settings,
            progressStore: progressStore,
            goldStore: goldStore,
            tradeStore: tradeStore,
            codexModel: codexModel,
            claudeModel: claudeModel
        ))
    }
}

// MARK: - 全局模块导航

struct ModuleNavigationRail<Trailing: View>: View {
    @Binding var selection: ViewMode
    @ViewBuilder let trailing: Trailing
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var settings = AppSettings.shared
    @Namespace private var selectionAnimation
    @State private var hoveredMode: ViewMode?
    var todayAttention: TodaySeverity?

    init(
        selection: Binding<ViewMode>,
        todayAttention: TodaySeverity? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        _selection = selection
        self.todayAttention = todayAttention
        self.trailing = trailing()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            navigationContent(showsSelectionTitle: true)
                .fixedSize(horizontal: true, vertical: false)

            navigationContent(showsSelectionTitle: false)
        }
        .frame(maxWidth: .infinity)
        .padding(4)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(AppTheme.chromeSurface(colorScheme))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(AppTheme.stroke(colorScheme), lineWidth: 0.5)
        }
        .shadow(color: AppTheme.shadow(colorScheme), radius: 8, y: 3)
        .animation(.easeOut(duration: 0.12), value: hoveredMode)
    }

    private func navigationContent(showsSelectionTitle: Bool) -> some View {
        HStack(spacing: 3) {
            ForEach(settings.visibleViewModes, id: \.self) { mode in
                Button {
                    guard selection != mode else { return }
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.22, extraBounce: 0.02)) {
                        selection = mode
                    }
                    Analytics.capture(.viewTabSwitched, properties: [
                        "tab": mode.rawValue,
                    ])
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .overlay(alignment: .topTrailing) {
                                if mode == .today, let todayAttention, todayAttention >= .warning {
                                    Circle()
                                        .fill(todayAttention.color)
                                        .frame(width: 5, height: 5)
                                        .offset(x: 3, y: -3)
                                }
                            }

                        if selection == mode, showsSelectionTitle {
                            Text(mode.displayName)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                    }
                    .frame(
                        minWidth: selection == mode ? (showsSelectionTitle ? 28 : 24) : 24,
                        minHeight: 32
                    )
                    .padding(.horizontal, selection == mode ? (showsSelectionTitle ? 5 : 2) : 0)
                    .foregroundStyle(selection == mode ? AppTheme.accent : AppTheme.textSecondary(colorScheme))
                    .background {
                        if selection == mode {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AppTheme.accent.opacity(colorScheme == .dark ? 0.20 : 0.13))
                                .matchedGeometryEffect(
                                    id: showsSelectionTitle ? "selected-module-titled" : "selected-module-compact",
                                    in: selectionAnimation
                                )
                        } else if hoveredMode == mode {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AppTheme.accent.opacity(0.07))
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(mode.keyboardShortcut, modifiers: .command)
                .help(mode.displayName)
                .accessibilityLabel(mode.displayName)
                .accessibilityAddTraits(selection == mode ? .isSelected : [])
                .onHover { isHovering in
                    if isHovering {
                        hoveredMode = mode
                    } else if hoveredMode == mode {
                        hoveredMode = nil
                    }
                }
            }

            Spacer(minLength: 2)
            trailing
        }
    }
}

extension ModuleNavigationRail where Trailing == EmptyView {
    init(selection: Binding<ViewMode>, todayAttention: TodaySeverity? = nil) {
        self.init(selection: selection, todayAttention: todayAttention) { EmptyView() }
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .frame(width: 220, height: 360)
    }
}
