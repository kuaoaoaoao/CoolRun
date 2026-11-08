import AppKit
import Foundation
import UserNotifications

// MARK: - 写入类工具（L1 / L2）

/// 与 `AgentTools` 分开：那边是只读观察，这边会改变软件状态或用户环境。
/// 权限等级决定引擎是否在调用前弹确认，以及设置里能不能启用。
@MainActor
enum AgentActionTools {
    static func registerAll() {
        registerNavigation()
        registerNotifications()
        registerClipboard()
        registerNotes()
        registerReminders()
        registerScreenshot()
    }

    // MARK: - L1 切面板

    private static func registerNavigation() {
        ToolRegistry.shared.register(
            ToolDescriptor(
                name: "ui_switch_panel",
                summary: "把 CoolRun 面板切换到指定模块。可用模块：today、monitor、gold、calendar、english、codex、notes、clipboard、diagnostics、aiAssistant。",
                parameters: ToolSchema.object(
                    properties: [
                        ("module", ToolSchema.string(
                            "模块标识",
                            enumValues: ViewMode.allCases.map(\.rawValue)
                        ))
                    ],
                    required: ["module"]
                ),
                permission: .reversible
            )
        ) { arguments in
            guard let raw = arguments["module"]?.stringValue else {
                return .failure("缺少 module 参数")
            }
            guard let mode = ViewMode(rawValue: raw) else {
                return .failure("未知模块：\(raw)。可用值：\(ViewMode.allCases.map(\.rawValue).joined(separator: "、"))")
            }
            AppNavigationRouter.shared.open(mode)
            return .text("已切换到「\(mode.rawValue)」面板。")
        }
    }

    // MARK: - L1 通知

    private static func registerNotifications() {
        ToolRegistry.shared.register(
            ToolDescriptor(
                name: "notify",
                summary: "给用户发一条 macOS 本地通知。适合提醒、汇报完成情况、需要用户注意的事。",
                parameters: ToolSchema.object(
                    properties: [
                        ("title", ToolSchema.string("通知标题")),
                        ("body", ToolSchema.string("通知正文")),
                        ("after_seconds", ToolSchema.integer(
                            "延迟多少秒后发出，默认 0（立即）",
                            minimum: 0,
                            maximum: 86_400
                        )),
                    ],
                    required: ["title", "body"]
                ),
                permission: .reversible
            )
        ) { arguments in
            guard let title = arguments["title"]?.stringValue, !title.isEmpty else {
                return .failure("缺少 title 参数")
            }
            let body = arguments["body"]?.stringValue ?? ""
            let delay = max(0, arguments["after_seconds"]?.intValue ?? 0)

            guard await ensureNotificationAuthorization() else {
                return .failure("系统通知权限未授予，无法发送。请到「系统设置 → 通知 → CoolRun」打开。")
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            let trigger = delay > 0
                ? UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(delay), repeats: false)
                : nil

            let request = UNNotificationRequest(
                identifier: "agent.notify.\(UUID().uuidString)",
                content: content,
                trigger: trigger
            )
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                return .failure("发送通知失败：\(error.localizedDescription)")
            }
            return .text(delay > 0 ? "通知已排程，\(delay) 秒后送达。" : "通知已发送。")
        }
    }

    private static func ensureNotificationAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            return false
        }
    }

    // MARK: - L1 剪贴板

    private static func registerClipboard() {
        ToolRegistry.shared.register(
            ToolDescriptor(
                name: "clipboard_copy",
                summary: "把一段文本写入系统剪贴板，用户可以直接粘贴。",
                parameters: ToolSchema.object(
                    properties: [
                        ("text", ToolSchema.string("要复制的文本"))
                    ],
                    required: ["text"]
                ),
                permission: .reversible
            )
        ) { arguments in
            guard let text = arguments["text"]?.stringValue else {
                return .failure("缺少 text 参数")
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            guard pasteboard.setString(text, forType: .string) else {
                return .failure("写入剪贴板失败")
            }
            return .text("已复制 \(text.count) 个字符到剪贴板。")
        }
    }

    // MARK: - L2 笔记

    private static func registerNotes() {
        ToolRegistry.shared.register(
            ToolDescriptor(
                name: "notes_create",
                summary: "在 CoolRun 笔记里新建一条笔记。可指定分组名，分组不存在时会自动创建。",
                parameters: ToolSchema.object(
                    properties: [
                        ("title", ToolSchema.string("笔记标题，可留空由正文首行推导")),
                        ("body", ToolSchema.string("笔记正文")),
                        ("group", ToolSchema.string("分组名称，可选")),
                    ],
                    required: ["body"]
                ),
                permission: .persistent
            )
        ) { arguments in
            guard let body = arguments["body"]?.stringValue,
                  !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return .failure("缺少 body 参数或正文为空")
            }
            let title = arguments["title"]?.stringValue ?? ""

            var groupID: UUID?
            if let groupName = arguments["group"]?.stringValue,
               !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let store = NotesStore.shared
                if let existing = store.groups.first(where: { $0.name == groupName }) {
                    groupID = existing.id
                } else {
                    groupID = store.addGroup(name: groupName)?.id
                }
            }

            guard let note = NotesStore.shared.saveNote(title: title, body: body, groupID: groupID) else {
                return .failure("笔记内容为空，未创建")
            }
            return .text("已创建笔记「\(note.title)」（id: \(note.id.uuidString)）")
        }

        ToolRegistry.shared.register(
            ToolDescriptor(
                name: "notes_toggle_pin",
                summary: "切换一条笔记的置顶状态。需要先通过 notes_search 拿到笔记 id。",
                parameters: ToolSchema.object(
                    properties: [
                        ("note_id", ToolSchema.string("笔记的 UUID"))
                    ],
                    required: ["note_id"]
                ),
                permission: .persistent
            )
        ) { arguments in
            guard let raw = arguments["note_id"]?.stringValue, let id = UUID(uuidString: raw) else {
                return .failure("note_id 不是合法的 UUID")
            }
            guard NotesStore.shared.notes.contains(where: { $0.id == id }) else {
                return .failure("找不到这条笔记")
            }
            NotesStore.shared.togglePin(id: id)
            let pinned = NotesStore.shared.notes.first(where: { $0.id == id })?.isPinned ?? false
            return .text(pinned ? "已置顶。" : "已取消置顶。")
        }
    }

    // MARK: - L2 提醒

    private static func registerReminders() {
        ToolRegistry.shared.register(
            ToolDescriptor(
                name: "reminder_create",
                summary: "创建一个一次性提醒，到点弹出系统通知。",
                parameters: ToolSchema.object(
                    properties: [
                        ("title", ToolSchema.string("提醒标题")),
                        ("body", ToolSchema.string("提醒正文，可选")),
                        ("after_minutes", ToolSchema.integer(
                            "多少分钟后提醒，范围 1–10080（一周）",
                            minimum: 1,
                            maximum: 10_080
                        )),
                    ],
                    required: ["title", "after_minutes"]
                ),
                permission: .persistent
            )
        ) { arguments in
            guard let title = arguments["title"]?.stringValue, !title.isEmpty else {
                return .failure("缺少 title 参数")
            }
            guard let minutes = arguments["after_minutes"]?.intValue, minutes > 0 else {
                return .failure("after_minutes 必须是正整数")
            }
            guard await ensureNotificationAuthorization() else {
                return .failure("系统通知权限未授予，无法创建提醒。")
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = arguments["body"]?.stringValue ?? ""
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "agent.reminder.\(UUID().uuidString)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(
                    timeInterval: TimeInterval(minutes * 60),
                    repeats: false
                )
            )
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                return .failure("创建提醒失败：\(error.localizedDescription)")
            }
            return .text("提醒已创建，\(minutes) 分钟后通知你。")
        }
    }

    // MARK: - L2 截图

    private static func registerScreenshot() {
        ToolRegistry.shared.register(
            ToolDescriptor(
                name: "screenshot",
                summary: "截取当前整个屏幕并保存为 PNG。不传 path 时存到桌面。",
                parameters: ToolSchema.object(
                    properties: [
                        ("path", ToolSchema.string("保存路径，可选。留空则保存到桌面"))
                    ]
                ),
                permission: .persistent
            )
        ) { arguments in
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let stamp = formatter.string(from: Date())

            let destination: URL
            if let custom = arguments["path"]?.stringValue,
               !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                destination = URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
            } else {
                let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                    ?? FileManager.default.homeDirectoryForCurrentUser
                destination = desktop.appendingPathComponent("CoolRun-\(stamp).png")
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-x", destination.path]

            let pipe = Pipe()
            process.standardError = pipe

            do {
                try process.run()
            } catch {
                return .failure("无法启动截图命令：\(error.localizedDescription)")
            }
            process.waitUntilExit()

            guard process.terminationStatus == 0,
                  FileManager.default.fileExists(atPath: destination.path)
            else {
                let message = String(
                    data: pipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
                return .failure("截图失败（退出码 \(process.terminationStatus)）：\(message)")
            }
            return .text("截图已保存到 \(destination.path)")
        }
    }
}
