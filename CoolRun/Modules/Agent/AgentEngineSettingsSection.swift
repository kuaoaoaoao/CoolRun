import SwiftUI

/// 引擎选择 + DSH 运行时状态。单独成文件，因为这段的交互比其它设置项复杂。
struct AgentEngineSettingsSection: View {
    @State private var settings = AgentSettings.shared
    @State private var locator = AgentRuntimeLocator.shared
    @State private var installer = AgentRuntimeInstaller.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $settings.engineKind) {
                ForEach(AgentEngineKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(engineSummary)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if settings.engineKind == .dsh {
                runtimeStatus
            }
        }
        .onAppear { locator.refresh() }
    }

    @ViewBuilder
    private var runtimeStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: statusIcon)
                    .font(.system(size: 11))
                    .foregroundStyle(statusColor)
                Text(statusText)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
            }

            switch installer.state {
            case .downloading(let progress):
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                Text("正在下载 \(Int(progress * 100))%")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

            case .verifying:
                ProgressView().controlSize(.small)
                Text("正在校验文件")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

            case .extracting:
                ProgressView().controlSize(.small)
                Text("正在解压")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

            case .failed(let message):
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)

            default:
                EmptyView()
            }

            HStack(spacing: 8) {
                if locator.runtime == nil, !installer.state.isBusy {
                    Button("下载运行时") {
                        Task { await installer.install(); locator.refresh() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                if locator.runtime != nil, locator.runtime?.source == .downloaded {
                    Button("移除") {
                        installer.uninstall()
                        locator.refresh()
                    }
                    .controlSize(.small)
                }

                if installer.state.isBusy {
                    Text("安装中…")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    /// 两个引擎用的是同一套工具、同一套模型配置，区别只在「谁在跑」。
    private var engineSummary: String {
        switch settings.engineKind {
        case .native:
            return "App 自带，不额外占空间；对话和工具都跑在本进程里，回得快，改配置立刻生效。日常用这个就够。"
        case .dsh:
            return "另起一个进程跑 DeepSeek Harness（独立的一份 Node 运行时，不是你在用的那个 DeepSeek Harness.app）。多步任务、技能、子代理更强，代价是首次启动要等 2–3 秒、常驻内存更高。"
        }
    }

    private var statusText: String {
        guard let runtime = locator.runtime else {
            return "运行时未安装"
        }
        let source = switch runtime.source {
        case .bundled: "已内置"
        case .downloaded: "已下载"
        case .systemPath: "系统 PATH"
        }
        if let version = runtime.version {
            return "\(source) · \(version)"
        }
        return source
    }

    private var statusIcon: String {
        locator.runtime == nil ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }

    private var statusColor: Color {
        locator.runtime == nil ? .orange : .green
    }
}
