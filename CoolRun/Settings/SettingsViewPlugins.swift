import AppKit
import SwiftUI

// MARK: - 设置 · 插件

extension SettingsView {
    /// 「插件」设置页：本地安装、启停、卸载。
    @MainActor
    var pluginsContent: some View {
        let lang = settings.language
        return VStack(spacing: 14) {
            SettingsCard(
                icon: "puzzlepiece.extension",
                title: LocalizedString.l(lang, en: "Local Plugins", zh: "本地插件", ja: "ローカルプラグイン", ko: "로컬 플러그인"),
                description: LocalizedString.l(
                    lang,
                    en: "A plugin is a .coolplugin folder containing manifest.json and main.js. Once installed, the tools it declares show up in the Agent tool list and the model can call them directly.",
                    zh: "插件是一个 .coolplugin 目录，里面放 manifest.json 和 main.js。装好后，它声明的工具会出现在 Agent 的工具列表里，模型可以直接调用。",
                    ja: "プラグインは manifest.json と main.js を含む .coolplugin フォルダです。インストールすると、宣言したツールが Agent のツール一覧に表示され、モデルから直接呼び出せます。",
                    ko: "플러그인은 manifest.json 과 main.js 를 담은 .coolplugin 폴더입니다. 설치하면 선언한 도구가 Agent 도구 목록에 나타나 모델이 직접 호출할 수 있습니다."
                )
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Button {
                            installPlugin()
                        } label: {
                            Label(
                                LocalizedString.l(lang, en: "Install Plugin…", zh: "安装插件…", ja: "プラグインをインストール…", ko: "플러그인 설치…"),
                                systemImage: "plus"
                            )
                        }

                        Button {
                            try? FileManager.default.createDirectory(
                                at: PluginManager.rootDirectory,
                                withIntermediateDirectories: true
                            )
                            NSWorkspace.shared.open(PluginManager.rootDirectory)
                        } label: {
                            Label(
                                LocalizedString.l(lang, en: "Open Plugin Folder", zh: "打开插件目录", ja: "プラグインフォルダを開く", ko: "플러그인 폴더 열기"),
                                systemImage: "folder"
                            )
                        }

                        Spacer()

                        Text(
                            LocalizedString.l(
                                lang,
                                en: "\(PluginManager.shared.plugins.count) installed",
                                zh: "\(PluginManager.shared.plugins.count) 个已安装",
                                ja: "\(PluginManager.shared.plugins.count) 件インストール済み",
                                ko: "\(PluginManager.shared.plugins.count)개 설치됨"
                            )
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let error = PluginManager.shared.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    if PluginManager.shared.plugins.isEmpty {
                        emptyPlugins
                    } else {
                        ForEach(PluginManager.shared.plugins) { plugin in
                            pluginRow(plugin)
                        }
                    }
                }
            }

            SettingsCard(
                icon: "chevron.left.forwardslash.chevron.right",
                title: LocalizedString.l(lang, en: "Write a Plugin", zh: "写一个插件", ja: "プラグインを書く", ko: "플러그인 작성하기"),
                description: LocalizedString.l(
                    lang,
                    en: "manifest.json declares the tools and main.js implements them in plain JavaScript. The only available APIs are coolrun.log / storage / httpGet / notify / copy; declare the capabilities you need in permissions.",
                    zh: "manifest.json 声明工具，main.js 用普通 JavaScript 实现。可用的接口只有 coolrun.log / storage / httpGet / notify / copy，需要什么能力就在 permissions 里声明。",
                    ja: "manifest.json でツールを宣言し、main.js を素の JavaScript で実装します。利用できる API は coolrun.log / storage / httpGet / notify / copy のみで、必要な権限は permissions に宣言します。",
                    ko: "manifest.json 에서 도구를 선언하고 main.js 를 순수 JavaScript 로 구현합니다. 사용 가능한 API 는 coolrun.log / storage / httpGet / notify / copy 뿐이며, 필요한 권한은 permissions 에 선언합니다."
                )
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("manifest.json")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(manifestSample(lang))
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            Color(nsColor: .textBackgroundColor).opacity(0.6),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )

                    Text("main.js")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(scriptSample(lang))
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            Color(nsColor: .textBackgroundColor).opacity(0.6),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                }
            }
        }
    }

    // MARK: 空状态

    private var emptyPlugins: some View {
        let lang = settings.language
        return VStack(spacing: 8) {
            Image(systemName: "shippingbox")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text(LocalizedString.l(lang, en: "No plugins installed yet", zh: "还没有装插件", ja: "プラグインはまだありません", ko: "아직 설치된 플러그인이 없습니다"))
                .font(.callout)
            Text(
                LocalizedString.l(
                    lang,
                    en: "Click \"Install Plugin…\" and pick a .coolplugin folder, or copy the folder straight into the plugin directory.",
                    zh: "点「安装插件…」选一个 .coolplugin 目录，或者把目录直接拷进插件文件夹。",
                    ja: "「プラグインをインストール…」から .coolplugin フォルダを選ぶか、フォルダをプラグインディレクトリに直接コピーしてください。",
                    ko: "\"플러그인 설치…\"를 눌러 .coolplugin 폴더를 선택하거나, 폴더를 플러그인 디렉터리에 직접 복사하세요."
                )
            )
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    // MARK: 单个插件

    @ViewBuilder
    private func pluginRow(_ plugin: InstalledPlugin) -> some View {
        let enabled = PluginManager.isEnabled(plugin.manifest.id)
        let lang = settings.language

        HStack(alignment: .top, spacing: 10) {
            Image(systemName: plugin.isValid ? "shippingbox.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(plugin.isValid ? AppTheme.accent : .orange)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(plugin.manifest.name)
                        .font(.callout.weight(.medium))
                    Text("v\(plugin.manifest.version)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if !plugin.manifest.author.isEmpty {
                        Text("· \(plugin.manifest.author)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if !plugin.manifest.summary.isEmpty {
                    Text(plugin.manifest.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    if !plugin.manifest.permissions.isEmpty {
                        ForEach(plugin.manifest.permissions, id: \.rawValue) { permission in
                            Text(permission.displayName)
                                .font(.system(size: 9, weight: .medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                        }
                    }
                    Text(
                        LocalizedString.l(
                            lang,
                            en: "\(plugin.toolCount) tools",
                            zh: "\(plugin.toolCount) 个工具",
                            ja: "\(plugin.toolCount) 個のツール",
                            ko: "도구 \(plugin.toolCount)개"
                        )
                    )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let error = plugin.loadError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { enabled },
                set: { PluginManager.shared.setEnabled($0, pluginID: plugin.manifest.id) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)

            Button {
                try? PluginManager.shared.remove(plugin.manifest.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(LocalizedString.l(lang, en: "Remove this plugin", zh: "删除这个插件", ja: "このプラグインを削除", ko: "이 플러그인 삭제"))
        }
        .padding(10)
        .background(
            Color.secondary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .opacity(enabled ? 1 : 0.55)
    }

    // MARK: 安装

    @MainActor
    private func installPlugin() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        let lang = settings.language
        panel.prompt = LocalizedString.l(lang, en: "Install", zh: "安装", ja: "インストール", ko: "설치")
        panel.message = LocalizedString.l(
            lang,
            en: "Choose a folder ending in .coolplugin",
            zh: "选一个以 .coolplugin 结尾的目录",
            ja: ".coolplugin で終わるフォルダを選択してください",
            ko: ".coolplugin 으로 끝나는 폴더를 선택하세요"
        )

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try PluginManager.shared.install(from: url)
        } catch {
            PluginManager.shared.reportError(error.localizedDescription)
        }
    }

    // MARK: 示例

    private func manifestSample(_ lang: AppLanguage) -> String {
        let sampleName = LocalizedString.l(lang, en: "Example Plugin", zh: "示例插件", ja: "サンプルプラグイン", ko: "예제 플러그인")
        let sampleDescription = LocalizedString.l(lang, en: "Say hello", zh: "打个招呼", ja: "あいさつする", ko: "인사하기")
        let sampleSummary = LocalizedString.l(lang, en: "Say a greeting", zh: "说一句问候", ja: "あいさつを返す", ko: "인사말을 말합니다")
        let sampleWho = LocalizedString.l(lang, en: "Recipient name", zh: "对方名字", ja: "相手の名前", ko: "상대방 이름")
        return """
        {
          "id": "com.example.hello",
          "name": "\(sampleName)",
          "version": "1.0.0",
          "description": "\(sampleDescription)",
          "main": "main.js",
          "permissions": ["notify"],
          "tools": [
            {
              "name": "hello",
              "summary": "\(sampleSummary)",
              "handler": "hello",
              "parameters": {
                "type": "object",
                "properties": {
                  "who": { "type": "string", "description": "\(sampleWho)" }
                }
              }
            }
          ]
        }
        """
    }

    private func scriptSample(_ lang: AppLanguage) -> String {
        let fallbackName = LocalizedString.l(lang, en: "there", zh: "主人", ja: "あなた", ko: "여러분")
        let greeting = LocalizedString.l(lang, en: "Hello, ", zh: "你好，", ja: "こんにちは、", ko: "안녕하세요, ")
        let suffix = LocalizedString.l(lang, en: "!", zh: "！", ja: "！", ko: "!")
        return """
        function hello(args) {
          var who = args.who || "\(fallbackName)";
          coolrun.log("hello: " + who);
          return "\(greeting)" + who + "\(suffix)";
        }
        """
    }
}
