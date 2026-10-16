import SwiftUI
import Observation
import Combine

@MainActor
@Observable
final class PopoverPinState {
    var isPinned = false
}

struct MenuBarMonitorView: View {
    @State private var viewModel: SystemMonitorViewModel
    // 重启后回到上次使用的模块；若该模块已被隐藏则落到第一个可见模块
    @State private var viewMode: ViewMode = AppSettings.shared.initialViewMode
    @Bindable private var pinState: PopoverPinState
    private let onPinChange: (Bool) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var router = AppNavigationRouter.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var progressStore = EnglishProgressStore.shared
    @State private var goldStore = GoldPriceStore.shared
    @State private var tradeStore = GoldTradeStore.shared
    @State private var codexModel = CodexMonitorViewModel.shared
    @State private var claudeModel = ClaudeMonitorViewModel.shared

    init(
        viewModel: SystemMonitorViewModel,
        pinState: PopoverPinState,
        onPinChange: @escaping (Bool) -> Void
    ) {
        _viewModel = State(initialValue: viewModel)
        _pinState = Bindable(wrappedValue: pinState)
        self.onPinChange = onPinChange
    }

    var body: some View {
        VStack(spacing: 0) {
            ModuleNavigationRail(selection: $viewMode, todayAttention: todayAttention) {
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                        pinState.isPinned.toggle()
                    }
                    onPinChange(pinState.isPinned)
                } label: {
                    Image(systemName: pinState.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(pinState.isPinned ? AppTheme.warning : AppTheme.textSecondary(colorScheme))
                        .frame(width: 28, height: 28)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(pinState.isPinned ? AppTheme.warning.opacity(0.14) : Color.clear)
                        }
                }
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .help(pinState.isPinned ? LocalizedString.common("unpin_popover") : LocalizedString.common("pin_popover"))
            }
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
                }
            }
            .id(viewMode)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.opacity.combined(with: .scale(scale: 0.985)))
        }
        .frame(width: 320, height: 512, alignment: .top)
        .padding(8)
        .onChange(of: viewMode) { _, newValue in
            AppSettings.shared.lastViewModeRaw = newValue.rawValue
        }
        // 当前模块在设置中被隐藏时，自动切到第一个可见模块
        .onChange(of: settings.visibleTabRaws) { _, _ in
            if !settings.isTabVisible(viewMode) {
                viewMode = settings.visibleViewModes.first ?? .monitor
            }
        }
        .onReceive(router.$request.compactMap { $0 }) { request in
            viewMode = request.mode
        }
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
