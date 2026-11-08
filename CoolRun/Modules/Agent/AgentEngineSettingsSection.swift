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

            Text(settings.engineKind == .native
                 ? "内置引擎，体积为零，覆盖绝大多数场景。"
                 : "DSH 引擎，能力更强，需要一份运行时。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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
