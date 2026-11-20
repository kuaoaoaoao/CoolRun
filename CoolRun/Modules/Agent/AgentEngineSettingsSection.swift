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

            if let note = runtimeNote {
                Text(note)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsPriorityToggle {
                Toggle(isOn: Binding(
                    get: { locator.preferDownloaded },
                    set: { locator.setPreferDownloaded($0) }
                )) {
                    Text(LocalizedString.l(
                        lang,
                        en: "Prefer the downloaded runtime",
                        zh: "优先使用已下载的运行时",
                        ja: "ダウンロードしたランタイムを優先",
                        ko: "다운로드한 런타임 우선"
                    ))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 10))
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

                // 完整版已经有内置的了，这里的下载只作为「试新版」的入口，
                // 所以不做成主按钮，也别让人以为不下载就用不了。
                if CoolRunEdition.current == .full,
                   locator.shadowed == nil,
                   locator.runtime?.source == .bundled,
                   !installer.state.isBusy {
                    Button(LocalizedString.l(
                        lang,
                        en: "Download a local copy",
                        zh: "下载本地副本",
                        ja: "ローカルコピーをダウンロード",
                        ko: "로컬 사본 다운로드"
                    )) {
                        Task { await installer.install(); locator.refresh() }
                    }
                    .controlSize(.small)
                }

                if locator.shadowed?.source == .downloaded || locator.runtime?.source == .downloaded {
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

    /// 只在「内置的正在生效、同时又存在一份下载的副本」时才有意义：
    /// 其它情况要么没有第二份可选，要么已经在用下载的那份了。
    private var showsPriorityToggle: Bool {
        guard CoolRunEdition.current == .full, locator.shadowed?.source == .downloaded else { return false }
        return true
    }

    /// 把「哪一份在生效、为什么」说清楚。完整版最容易在这里误会：
    /// 内置的永远赢过下载的（除非打开开关），不说清楚就会以为下载失败。
    private var runtimeNote: String? {
        switch (locator.runtime?.source, locator.shadowed?.source) {
        case (nil, _):
            return CoolRunEdition.current == .full
                ? LocalizedString.l(
                    lang,
                    en: "This build should include the runtime but it is missing. Reinstall CoolRun from the full installer.",
                    zh: "这个版本本应内置运行时，但没找到。请用完整版安装包重新安装。",
                    ja: "このビルドにはランタイムが含まれているはずですが見つかりません。フル版のインストーラで再インストールしてください。",
                    ko: "이 빌드에는 런타임이 포함되어야 하는데 찾을 수 없습니다. 전체 버전 설치 파일로 다시 설치하세요."
                )
                : LocalizedString.l(
                    lang,
                    en: "The lite build does not bundle the runtime; download it once (about 90 MB, ~170 MB on disk) to use this engine offline.",
                    zh: "轻量版没有内置运行时，下载一次（约 90 MB，装完占盘约 170 MB）之后就能离线用这个引擎。",
                    ja: "ライト版にはランタイムが含まれていません。一度ダウンロード（約 90 MB、展開後は約 170 MB）すればオフラインで使えます。",
                    ko: "라이트 빌드에는 런타임이 포함되어 있지 않습니다. 한 번 다운로드(약 90 MB, 설치 후 약 170 MB)하면 오프라인에서 사용할 수 있습니다."
                )
        case (.bundled, .some):
            let version = locator.shadowed?.version ?? LocalizedString.l(lang, en: "unknown version", zh: "版本未知", ja: "バージョン不明", ko: "버전 알 수 없음")
            return LocalizedString.l(
                lang,
                en: "A downloaded copy (\(version)) is being ignored: the bundled runtime takes priority. Turn on the switch below to use it.",
                zh: "本地已下载 \(version)，但内置的优先，所以没有生效。打开下面的开关就会改用它。",
                ja: "ローカルに \(version) をダウンロード済みですが、内蔵版が優先されるため使われていません。下のスイッチを入れると切り替わります。",
                ko: "로컬에 \(version)을(를) 내려받았지만 내장 버전이 우선이라 사용되지 않습니다. 아래 스위치를 켜면 전환됩니다."
            )
        case (.bundled, nil):
            let version = locator.runtime?.version ?? LocalizedString.l(lang, en: "unknown version", zh: "版本未知", ja: "バージョン不明", ko: "버전 알 수 없음")
            return LocalizedString.l(
                lang,
                en: "Bundled with the app (\(version)) and updated together with it — nothing to download.",
                zh: "随 App 内置（\(version)），跟着 App 一起更新，不需要额外下载。",
                ja: "アプリに内蔵（\(version)）されており、アプリと一緒に更新されます。追加のダウンロードは不要です。",
                ko: "앱에 내장(\(version))되어 앱과 함께 업데이트됩니다. 추가 다운로드가 필요 없습니다."
            )
        case (.downloaded, _):
            return LocalizedString.l(
                lang,
                en: "Using the copy you downloaded to Application Support; it survives app updates.",
                zh: "用的是下载到 Application Support 的那份，升级 App 不会覆盖它。",
                ja: "Application Support にダウンロードしたコピーを使用中です。アプリを更新しても残ります。",
                ko: "Application Support에 내려받은 사본을 사용 중입니다. 앱을 업데이트해도 유지됩니다."
            )
        case (.systemPath, _):
            return LocalizedString.l(
                lang,
                en: "Using the dsh found on your PATH. Installing the bundled or downloaded runtime is recommended for normal use.",
                zh: "用的是系统 PATH 里的 dsh。日常使用建议装内置或下载的运行时，那个不依赖你机器上装的 Node。",
                ja: "PATH 上の dsh を使用中です。通常は内蔵版かダウンロード版の利用を推奨します（Node の有無に依存しないため）。",
                ko: "PATH에 있는 dsh를 사용 중입니다. 일반적으로는 내장 또는 다운로드한 런타임 사용을 권장합니다(Node 설치 여부에 의존하지 않으므로)."
            )
        }
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
