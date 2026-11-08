import AppKit
import SwiftUI

// MARK: - 设置 · 插件

extension SettingsView {
    /// 「插件」设置页：本地安装、启停、卸载。
    @MainActor
    var pluginsContent: some View {
        VStack(spacing: 14) {
            SettingsCard(
                icon: "puzzlepiece.extension",
                title: "本地插件",
                description: "插件是一个 .coolplugin 目录，里面放 manifest.json 和 main.js。装好后，它声明的工具会出现在 Agent 的工具列表里，模型可以直接调用。"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Button {
                            installPlugin()
                        } label: {
                            Label("安装插件…", systemImage: "plus")
                        }

                        Button {
                            try? FileManager.default.createDirectory(
                                at: PluginManager.rootDirectory,
                                withIntermediateDirectories: true
                            )
                            NSWorkspace.shared.open(PluginManager.rootDirectory)
                        } label: {
                            Label("打开插件目录", systemImage: "folder")
                        }

                        Spacer()

                        Text("\(PluginManager.shared.plugins.count) 个已安装")
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
                title: "写一个插件",
                description: "manifest.json 声明工具，main.js 用普通 JavaScript 实现。可用的接口只有 coolrun.log / storage / httpGet / notify / copy，需要什么能力就在 permissions 里声明。"
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("manifest.json")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(manifestSample)
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
                    Text(scriptSample)
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
        VStack(spacing: 8) {
            Image(systemName: "shippingbox")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("还没有装插件")
                .font(.callout)
            Text("点「安装插件…」选一个 .coolplugin 目录，或者把目录直接拷进插件文件夹。")
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
                    Text("\(plugin.toolCount) 个工具")
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
            .help("删除这个插件")
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
        panel.prompt = "安装"
        panel.message = "选一个以 .coolplugin 结尾的目录"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try PluginManager.shared.install(from: url)
        } catch {
            PluginManager.shared.reportError(error.localizedDescription)
        }
    }

    // MARK: 示例

    private var manifestSample: String {
        """
        {
          "id": "com.example.hello",
          "name": "示例插件",
          "version": "1.0.0",
          "description": "打个招呼",
          "main": "main.js",
          "permissions": ["notify"],
          "tools": [
            {
              "name": "hello",
              "summary": "说一句问候",
              "handler": "hello",
              "parameters": {
                "type": "object",
                "properties": {
                  "who": { "type": "string", "description": "对方名字" }
                }
              }
            }
          ]
        }
        """
    }

    private var scriptSample: String {
        """
        function hello(args) {
          var who = args.who || "主人";
          coolrun.log("hello: " + who);
          return "你好，" + who + "！";
        }
        """
    }
}
