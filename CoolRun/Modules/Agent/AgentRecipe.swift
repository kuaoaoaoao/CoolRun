import Foundation

// MARK: - 场景

/// 场景来源。
enum AgentRecipeSource: String, Codable, Sendable {
    case builtin
    case user
    case plugin
}

/// 一个「点一下就干完」的场景。
///
/// 场景本身不写死执行流程 —— 它只是一段更好的提示词加上元信息，
/// 真正的调度仍然交给模型，这样模型随时可以用上清单之外的工具。
struct AgentRecipe: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var title: String
    var subtitle: String
    var symbol: String
    /// 发给模型的完整提示词。
    var prompt: String
    /// 这个场景预期会用到哪些工具，仅用于界面提示。
    var requiredTools: [String]
    /// 需要的最低工具等级，低于这个等级的场景在设置里会被标灰。
    var minimumLevel: ToolPermission
    /// 非空表示需要用户先在输入框补一句内容，点卡片只做预填。
    var inputHint: String?
    /// 斜杠命令的别名（不含斜杠）。
    var slash: String?
    var source: AgentRecipeSource

    nonisolated var needsInput: Bool { inputHint != nil }

    init(
        id: String,
        title: String,
        subtitle: String,
        symbol: String,
        prompt: String,
        requiredTools: [String],
        minimumLevel: ToolPermission = .read,
        inputHint: String? = nil,
        slash: String? = nil,
        source: AgentRecipeSource = .builtin
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.prompt = prompt
        self.requiredTools = requiredTools
        self.minimumLevel = minimumLevel
        self.inputHint = inputHint
        self.slash = slash
        self.source = source
    }
}

// MARK: - 内置场景

extension AgentRecipe {
    nonisolated static let builtins: [AgentRecipe] = [
        AgentRecipe(
            id: "health-check",
            title: "电脑体检",
            subtitle: "CPU、内存、磁盘、电池一次看完",
            symbol: "stethoscope",
            prompt: """
            帮我做一次电脑体检。用工具读取 CPU、内存、磁盘、电池和网络状态，\
            再挑出占用最高的几个进程。有明显问题就指出来并给建议，没问题就用一句话总结。
            """,
            requiredTools: ["system_snapshot", "system_processes", "system_battery", "system_network"],
            slash: "体检"
        ),
        AgentRecipe(
            id: "gold-brief",
            title: "金价快报",
            subtitle: "当前价格、涨跌和技术信号",
            symbol: "chart.line.uptrend.xyaxis",
            prompt: """
            帮我看看金价。读取最新价格和最近的技术信号，告诉我现在多少钱一克、\
            今天涨跌多少、信号偏多还是偏空。最后提醒我这是参考不是投资建议。
            """,
            requiredTools: ["gold_price", "gold_signals"],
            slash: "金价"
        ),
        AgentRecipe(
            id: "today-brief",
            title: "今天有什么",
            subtitle: "日程、倒计时、每日英语和额度",
            symbol: "sun.max",
            prompt: """
            帮我梳理一下今天：有哪些临近的日程和倒计时、今天的英语单词是什么、\
            Codex 和 Claude 的额度还剩多少。用清单形式回答，尽量短。
            """,
            requiredTools: ["calendar_upcoming", "english_daily", "quota_status"],
            slash: "今天"
        ),
        AgentRecipe(
            id: "memory-hog",
            title: "谁在吃内存",
            subtitle: "按内存占用排前几名进程",
            symbol: "memorychip",
            prompt: """
            按内存占用从高到低列出前 10 个进程，告诉我谁最占内存、占了多少，\
            以及哪些是可以安全关掉的。
            """,
            requiredTools: ["system_processes"],
            slash: "内存"
        ),
        AgentRecipe(
            id: "battery-report",
            title: "电池还行吗",
            subtitle: "健康度、循环次数、剩余续航",
            symbol: "battery.75percent",
            prompt: """
            帮我看看电池状态：健康度、循环次数、当前温度和剩余可用时间。\
            如果健康度低于 80% 或者循环次数偏高，提醒我该考虑换电池了。
            """,
            requiredTools: ["system_battery"],
            slash: "电池"
        ),
        AgentRecipe(
            id: "cleanup-advice",
            title: "能清理什么",
            subtitle: "磁盘占用和可回收空间",
            symbol: "trash",
            prompt: """
            看看磁盘还剩多少空间，结合当前进程情况，给我三条最值得做的清理建议。\
            不要自己删任何东西，只给建议。
            """,
            requiredTools: ["system_snapshot", "system_processes"],
            slash: "清理"
        ),
        AgentRecipe(
            id: "notes-capture",
            title: "记一笔",
            subtitle: "把想法存成笔记",
            symbol: "square.and.pencil",
            prompt: "帮我把下面这段内容记成一条笔记：",
            requiredTools: ["notes_create"],
            minimumLevel: .persistent,
            inputHint: "要记的内容…",
            slash: "记"
        ),
        AgentRecipe(
            id: "clipboard-find",
            title: "剪贴板找东西",
            subtitle: "在复制历史里搜索",
            symbol: "doc.on.clipboard",
            prompt: "在剪贴板历史里找找有没有包含这个关键词的内容：",
            requiredTools: ["clipboard_search"],
            inputHint: "关键词…",
            slash: "剪贴板"
        ),
        AgentRecipe(
            id: "remind-me",
            title: "提醒我",
            subtitle: "到点弹系统通知",
            symbol: "bell",
            prompt: """
            帮我设一个提醒。从下面这句话里判断要提醒什么、多久之后提醒，然后创建。
            """,
            requiredTools: ["reminder_create"],
            minimumLevel: .persistent,
            inputHint: "例如：30分钟后 喝水",
            slash: "提醒"
        ),
        AgentRecipe(
            id: "quota-check",
            title: "额度还剩多少",
            subtitle: "Codex 和 Claude 的用量上限",
            symbol: "gauge.with.dots.needle.50percent",
            prompt: """
            帮我看看 Codex 和 Claude Code 的额度还剩多少，快用完的窗口标出来，\
            再告诉我大概什么时候重置。
            """,
            requiredTools: ["quota_status"],
            slash: "额度"
        ),
        AgentRecipe(
            id: "screenshot-now",
            title: "截个图",
            subtitle: "全屏截图存到桌面",
            symbol: "camera",
            prompt: "帮我截一张全屏图，存到默认位置，然后告诉我文件路径。",
            requiredTools: ["screenshot"],
            minimumLevel: .persistent,
            slash: "截图"
        ),
        AgentRecipe(
            id: "gold-panel",
            title: "切到金价",
            subtitle: "直接跳到金价面板",
            symbol: "arrow.turn.down.right",
            prompt: "帮我把界面切到金价面板。",
            requiredTools: ["ui_switch_panel"],
            minimumLevel: .reversible,
            slash: "切金价"
        ),
    ]
}

// MARK: - 场景仓库

/// 内置场景 + 用户 / 插件追加的场景。落盘在 Application Support。
@MainActor
@Observable
final class AgentRecipeStore {
    static let shared = AgentRecipeStore()

    private(set) var custom: [AgentRecipe] = []
    private(set) var loadError: String?

    private let fileURL: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = support.appendingPathComponent("CoolRun", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("recipes.json")
        load()
    }

    var all: [AgentRecipe] { AgentRecipe.builtins + custom }

    func recipe(id: String) -> AgentRecipe? {
        all.first { $0.id == id }
    }

    func recipe(slash: String) -> AgentRecipe? {
        let key = slash.trimmingCharacters(in: .whitespaces)
        return all.first { $0.slash == key }
    }

    func add(_ recipe: AgentRecipe) {
        var stored = recipe
        stored.source = .user
        if let index = custom.firstIndex(where: { $0.id == stored.id }) {
            custom[index] = stored
        } else {
            custom.append(stored)
        }
        save()
    }

    func remove(id: String) {
        custom.removeAll { $0.id == id }
        save()
    }

    func resetCustom() {
        custom.removeAll()
        save()
    }

    // MARK: - 持久化

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            custom = try JSONDecoder().decode([AgentRecipe].self, from: data)
        } catch {
            // 坏文件留着排查，但不要影响面板打开。
            loadError = error.localizedDescription
            let backup = fileURL.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: fileURL, to: backup)
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(custom)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            loadError = error.localizedDescription
        }
    }
}
