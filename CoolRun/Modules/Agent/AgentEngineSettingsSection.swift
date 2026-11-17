import SwiftUI

/// 引擎选择 + DSH 运行时状态。单独成文件，因为这段的交互比其它设置项复杂。
struct AgentEngineSettingsSection: View {
    @State private var settings = AgentSettings.shared
    @State private var locator = AgentRuntimeLocator.shared
    @State private var installer = AgentRuntimeInstaller.shared
    @ObservedObject private var appSettings = AppSettings.shared

    private var lang: AppLanguage { appSettings.language }

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
                Text(LocalizedString.l(lang, en: "Downloading \(Int(progress * 100))%", zh: "正在下载 \(Int(progress * 100))%", ja: "ダウンロード中 \(Int(progress * 100))%", ko: "다운로드 중 \(Int(progress * 100))%"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

            case .verifying:
                ProgressView().controlSize(.small)
                Text(LocalizedString.l(lang, en: "Verifying file", zh: "正在校验文件", ja: "ファイルを検証中", ko: "파일 검사 중"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

            case .extracting:
                ProgressView().controlSize(.small)
                Text(LocalizedString.l(lang, en: "Extracting", zh: "正在解压", ja: "展開中", ko: "압축 해제 중"))
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
                    Button(LocalizedString.l(lang, en: "Download runtime", zh: "下载运行时", ja: "ランタイムをダウンロード", ko: "런타임 다운로드")) {
                        Task { await installer.install(); locator.refresh() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                if locator.runtime != nil, locator.runtime?.source == .downloaded {
                    Button(LocalizedString.l(lang, en: "Remove", zh: "移除", ja: "削除", ko: "제거")) {
                        installer.uninstall()
                        locator.refresh()
                    }
                    .controlSize(.small)
                }

                if installer.state.isBusy {
                    Text(LocalizedString.l(lang, en: "Installing…", zh: "安装中…", ja: "インストール中…", ko: "설치 중…"))
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
            return LocalizedString.l(
                lang,
                en: "Built into the app, no extra disk space. Chat and tools run in this process, so replies are fast and config changes apply immediately. Good enough for everyday use.",
                zh: "App 自带，不额外占空间；对话和工具都跑在本进程里，回得快，改配置立刻生效。日常用这个就够。",
                ja: "アプリ内蔵で追加のディスク容量を使いません。会話もツールもこのプロセス内で動くので応答が速く、設定変更もすぐ反映されます。普段使いにはこれで十分です。",
                ko: "앱에 내장되어 추가 공간을 차지하지 않습니다. 대화와 도구가 이 프로세스 안에서 실행되어 응답이 빠르고 설정 변경이 즉시 반영됩니다. 일상적인 사용에는 충분합니다."
            )
        case .dsh:
            return LocalizedString.l(
                lang,
                en: "Runs DeepSeek Harness in a separate process (its own Node runtime, not the DeepSeek Harness.app you use). Stronger at multi-step tasks, skills and subagents; the cost is a 2–3 s first start and higher resident memory.",
                zh: "另起一个进程跑 DeepSeek Harness（独立的一份 Node 运行时，不是你在用的那个 DeepSeek Harness.app）。多步任务、技能、子代理更强，代价是首次启动要等 2–3 秒、常驻内存更高。",
                ja: "別プロセスで DeepSeek Harness を動かします（独立した Node ランタイムで、お使いの DeepSeek Harness.app とは別物です）。多段階タスク・スキル・サブエージェントに強く、代わりに初回起動に 2〜3 秒かかり常駐メモリも増えます。",
                ko: "별도 프로세스에서 DeepSeek Harness를 실행합니다(사용 중인 DeepSeek Harness.app이 아닌 독립된 Node 런타임). 다단계 작업, 스킬, 서브에이전트에 강하지만 첫 실행에 2~3초가 걸리고 상주 메모리가 더 높습니다."
            )
        }
    }

    private var statusText: String {
        guard let runtime = locator.runtime else {
            return LocalizedString.l(lang, en: "Runtime not installed", zh: "运行时未安装", ja: "ランタイム未インストール", ko: "런타임이 설치되지 않음")
        }
        let source = switch runtime.source {
        case .bundled: LocalizedString.l(lang, en: "Bundled", zh: "已内置", ja: "内蔵", ko: "내장됨")
        case .downloaded: LocalizedString.l(lang, en: "Downloaded", zh: "已下载", ja: "ダウンロード済み", ko: "다운로드됨")
        case .systemPath: LocalizedString.l(lang, en: "System PATH", zh: "系统 PATH", ja: "システム PATH", ko: "시스템 PATH")
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
