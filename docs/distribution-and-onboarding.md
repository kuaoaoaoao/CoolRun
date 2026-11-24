# CoolRun 双版本分发与"一键式"体验方案

> 状态：方案（待确认后实施）
> 关联：`docs/agent-engine-design.md`（引擎架构）、`docs/bot-and-plugin-design.md`（机器人与插件）

## 1. 结论先行

三句话：

1. **两个 dmg，一份代码**。Lite（~28 MB）和 Full（~120 MB）由同一个 Xcode 工程的两个 scheme 产出，用编译条件和 Info.plist 键区分，不维护两个分支。
2. **Full 版多出来的体积只有一个来源**：内置的 DSH 运行时（0.2.2rc2 实测 173 MB 解压 / dmg 里约 92 MB；这个数随 DSH 版本变，别写死）。其他所有功能（插件、桌宠、机器人、本地模型）都不增加体积。
3. **"一键式"不是版本差异，是产品差异**。Lite 和 Full 共享同一套场景卡、工具浏览器、结果卡片、首次引导 —— 区别只在引擎和离线能力。

## 2. 双版本定义

| | **CoolRun Lite** | **CoolRun Full** |
| --- | --- | --- |
| dmg 体积 | ~28 MB | ~120 MB |
| 10 个基础模块 | ✅ | ✅ |
| 原生 Agent 引擎 | ✅ | ✅ |
| 云端 LLM（OpenAI / Anthropic / 兼容网关） | ✅ | ✅ |
| 本地 LLM（Ollama / LM Studio / llama.cpp） | ✅ | ✅ |
| 工具（L0 只读 + L1/L2 写入 + 确认闸门） | ✅ | ✅ |
| 场景卡 / 工具浏览器 / 结果卡片 | ✅ | ✅ |
| 插件系统（JavaScriptCore，本地安装） | ✅ | ✅ |
| 桌宠（本鱼） | ✅ 标准素材 | ✅ 高清素材 |
| DSH 引擎 | ⬇️ 首次使用时一键下载（90 MB） | ✅ 内置，开箱即用 |
| 断网可用 | 部分（原生功能全可用，DSH 引擎需先下载） | ✅ 完全离线 |
| QQ 机器人（SnowLuma） | ✅ 检测外部实例 | ✅ 检测外部实例 + 内置引导 |
| 首次启动 | 直接可用 | 直接可用 + 预置示例插件 |

**为什么 Lite 不做功能阉割：** 用户说的"功能少或残缺"其实是最差的选择 —— 用户下载 Lite 发现缺功能，会觉得产品不行，而不是"我该买 Pro"。真正该砍的是**体积和离线能力**，不是功能。功能全给，体积上分档，用户升级的理由是"我想离线用 / 我不想配环境"。

## 3. 体积账

| 组件 | 未压缩 | dmg 内 | 进 Full？ |
| --- | --- | --- | --- |
| CoolRun 本体（含资源：桌宠视频为主） | 52 MB | 28 MB | ✅ |
| DSH 运行时 exe（0.2.2rc2） | 168 MB | ~92 MB | ✅ |
| DSH 附带 rg | 4.3 MB | 1.4 MB | ✅ |
| DSH spawn-helper | 49 KB | 20 KB | ✅ |
| 插件运行时（JavaScriptCore） | 0 | 0 | ✅ 系统自带 |
| 桌宠素材（标准 / 高清） | 2 / 12 MB | 1.5 / 9 MB | ✅ |
| SnowLuma 接入（纯 Swift OneBot 客户端） | ~200 KB 代码 | ~80 KB | ✅ |
| **合计** | | **Lite ≈ 28 MB / Full ≈ 120 MB**（2026-11-20 实测） | |

Full 版的 120 MB 对标：VS Code 100 MB+、Slack 200 MB、Discord 150 MB。对一个"完整版"来说不算离谱，但**不能是默认下载项**。

## 4. "一键式"体验设计

这是本次方案的核心。用户的原话是"选择工具，使用功能，解决问题" —— 翻译成产品语言就是：

> 用户不应该知道"工具"这个概念。用户只知道"我想干什么"，剩下的交给场景卡。

### 4.1 场景卡（Recipe）

预置 12 个场景，每个是一个 JSON 描述，点一下直接跑完整流程。

```swift
struct AgentRecipe: Identifiable, Codable, Sendable {
    let id: String
    let title: String          // "电脑体检"
    let subtitle: String       // "CPU / 内存 / 磁盘 / 电池一次看完"
    let symbol: String         // SF Symbol
    let prompt: String         // 发给模型的话
    let requiredTools: [String]
    let minimumLevel: ToolPermission
    let estimateSeconds: Int
}
```

预置清单：

| 场景 | 触发方式 | 用到的工具 |
| --- | --- | --- |
| 电脑体检 | 卡片 | system_snapshot / system_processes / system_battery / system_network |
| 金价快报 | 卡片 | gold_price / gold_signals |
| 今天有什么 | 卡片 | calendar_upcoming / english_daily |
| 帮我记一笔 | 卡片（带输入框） | notes_create |
| 谁在吃内存 | 卡片 | system_processes(sort_by=memory) |
| 电池还行吗 | 卡片 | system_battery / system_snapshot |
| 剪贴板找东西 | 卡片（带输入框） | clipboard_search |
| 提醒我一下 | 卡片（带输入框） | reminder_create |
| 电脑最近怎么样 | 卡片 | system_snapshot + 历史趋势（需新增 system_history 工具） |
| 截图存哪了 | 卡片 | screenshot |
| 切到金价 | 卡片 | ui_switch_panel |

实现要点：

- 卡片在 Agent 面板的空状态里以 2 列网格显示，滚动可见。
- 点击后：把 `prompt` 塞进输入框并直接发送，UI 立刻显示"正在执行 N 个步骤"的进度条（基于 `activities.count` 和 `requiredTools.count`）。
- `requiredTools` 只用于展示"这个场景会用到哪些能力"，不参与调度 —— 调度永远交给模型，避免写死流程。
- 场景 JSON 存在 `~/Library/Application Support/CoolRun/recipes.json`，可被插件追加（插件贡献的场景出现在网格末尾，带插件名角标）。

### 4.2 工具浏览器

给"想手动玩"的用户一个入口：设置面板 → "工具" 页。

- 按模块分组（系统 / 金价 / 日程 / 学习 / 笔记 / 剪贴板 / 界面 / 通知 / 截图）
- 每行显示：名称、一句话说明、权限徽章（L0 绿 / L1 蓝 / L2 橙 / L3 红）
- 点开 → 根据 `ToolDescriptor.parameters`（本身就是 JSON Schema）**自动生成参数表单**：string → TextField，integer → Stepper，boolean → Toggle，enum → Picker
- 底部"运行"按钮 → 直接 `ToolRegistry.shared.execute()` → 结果用同一套结果卡片渲染
- 运行结果落审计日志，和 Agent 调用完全同一条路径

这块几乎不用新写业务逻辑 —— `ToolDescriptor` 已经有完整的 `parameters: JSONValue` schema，写一个 200 行的 `SchemaFormView` 就够。

**这是"体现工具能力"最直接的方式**：用户能亲眼看到 27 个工具各自能干什么、参数长什么样、返回什么。

### 4.3 结果卡片

现在工具返回的 JSON 直接进模型上下文，用户只在 ToolActivityCard 里看到一坨 JSON。改成双通道：

```
ToolRegistry.execute()
   ├→ JSON 字符串 → 模型上下文（不变）
   └→ ToolResult.presentation? → 结构化卡片数据 → UI 渲染
```

`ToolResult` 加一个可选字段：

```swift
struct ToolResult {
    let content: String
    let isError: Bool
    var presentation: ToolPresentation?   // 新增
}

enum ToolPresentation: Sendable {
    case metrics([MetricItem])            // CPU 78% / 内存 12.4/32 GB
    case list([ListItem])                 // 进程列表、日程列表
    case price(PriceSnapshot)             // 金价 + 涨跌 + 迷你走势
    case text(String)                     // 兜底
}
```

只有 6 个高频工具实现 `presentation`，其余走 `.text` 兜底。UI 侧加 4 个渲染器，总计约 300 行。

好处：同样是"电脑体检"，用户看到的是环形进度条 + 数值卡片，不是 `{"cpu": 0.78, ...}`。

### 4.4 首次引导

首次打开 Agent 面板时，如果 `AgentSettings` 未配置，不显示聊天框，显示三步引导：

1. **选引擎** —— "云端 API（推荐）" / "本地模型" / "我有兼容网关"，三张卡
2. **填配置** —— 根据选择展示对应表单，带"测试连接"按钮（已有 `testConnection()`）
3. **试一下** —— 自动跑"电脑体检"场景，让用户第一眼看到工具调用的效果

配置完成后写入 `agent.onboarded = true`，之后不再出现。设置里可以"重新引导"。

### 4.5 斜杠命令

输入框支持 `/` 前缀：

- `/体检`、`/金价`、`/今天`、`/记 xxx`、`/提醒 30m 喝水` → 映射到场景
- `/tool system_snapshot` → 直接跑工具，不过模型
- `/clear`、`/settings`

斜杠命令走本地解析，不发模型请求，响应是即时的。对熟悉了的用户，这比点卡片快。

## 5. SnowLuma 接入（修正原方案）

`CollectWork/SnowLuma` 是个重要发现：它**已经自带 MCP server**（`@snowluma/mcp`），三种模式：

| 模式 | 能力 | 环境变量 |
| --- | --- | --- |
| `docs`（默认） | 只读动作目录，不连实例 | 无 |
| `read` | 调只读 action（`get_*` / `can_*`） | `SNOWLUMA_MCP_ENDPOINT` |
| `write` | 可调任意 action（发消息、管理群） | + `SNOWLUMA_MCP_MODE=write` |

工具：`list_actions` / `get_action` / `search_actions` / `list_categories` / `query_action` / `invoke_action`。

**这改变了原方案的判断。** 原来计划自己实现 OneBot v11 反向 WS（2 周），现在有两条更便宜的路：

### 路线 1：直连 OneBot HTTP（推荐给 Lite）

SnowLuma 暴露 OneBot v11 HTTP 端点，协议极简单：

```
POST http://127.0.0.1:3000/send_group_msg
Authorization: Bearer <token>
{"group_id": 123, "message": "..."}
→ {"status": "ok", "retcode": 0, "data": {"message_id": 456}}
```

Swift 侧只需 6 个 action 的封装，约 200 行：

| 工具 | OneBot action | 权限 |
| --- | --- | --- |
| `qq_send_private` | `send_private_msg` | L2 |
| `qq_send_group` | `send_group_msg` | L2 |
| `qq_list_groups` | `get_group_list` | L0 |
| `qq_list_friends` | `get_friend_list` | L0 |
| `qq_login_info` | `get_login_info` | L0 |
| `qq_recent_messages` | `get_group_msg_history` | L0 |

体积 +80 KB，零依赖，不需要 Node。

### 路线 2：走 MCP（推荐给 Full，或已装 Node 的用户）

`npx -y @snowluma/mcp` 起 stdio MCP server，CoolRun 作为 MCP 客户端接入。好处是动作目录完整（几百个 action）、schema 现成；代价是需要 Node 运行时。

Full 版可以内置一份精简 Node（~50 MB）—— 但**不建议**，为了一个可选功能再加 50 MB 不划算。改为：检测到 Node 就用路线 2，否则用路线 1。

### 部署形态（Mac 的现实约束）

`qq-bot/README.md` 已记录：SnowLuma 的 QQ hook 原生只支持 Windows / Linux，Mac 上必须跑 Docker（内含 Linux QQ + noVNC 扫码登录）。

所以 CoolRun 面板里的"QQ 机器人"页做成**宿主面板**：

```
┌─ QQ 机器人 ─────────────────────┐
│ 状态：● 运行中  端口 3000        │
│ [启动] [停止] [查看日志] [扫码登录] │
│                                  │
│ ┌─ 登录（noVNC 内嵌）──────────┐ │
│ │  WKWebView → localhost:6081  │ │
│ └──────────────────────────────┘ │
│                                  │
│ 接入方式：● OneBot HTTP  ○ MCP   │
└──────────────────────────────────┘
```

检测逻辑：`docker ps --filter name=snowluma` → 有则读容器端口 → 连 `/get_login_info` 验证 → 显示在线 QQ 号。

一键操作：点"启动"→ 跑 `docker compose -f <内置模板> up -d` → 轮询直到端口就绪 → 自动切到 noVNC 页。

## 6. 构建与分发

### 6.1 一份代码两个 target

不建两个 target，用**一个 target + 编译条件**：

```swift
// CoolRun/Core/Edition.swift
enum Edition {
    static var current: Self {
        #if COOLRUN_FULL
        return .full
        #else
        return .lite
        #endif
    }
    var displayName: String { self == .full ? "CoolRun" : "CoolRun Lite" }
    var bundledAgentRuntime: Bool { self == .full }
}
```

Xcode 侧：

| | Lite scheme | Full scheme |
| --- | --- | --- |
| `SWIFT_ACTIVE_COMPILATION_CONDITIONS` | （空） | `COOLRUN_FULL` |
| Copy Files 阶段 | 无 | `AgentRuntime/` → Contents/Resources |
| 产物名 | `CoolRun.app` | `CoolRun.app`（同 bundle id） |

**同一个 bundle id** 是有意的：用户装 Full 覆盖 Lite 时设置、笔记、keychain 全部保留，反过来也一样。版本号用 `CFBundleShortVersionString` 区分不了，改用 Info.plist 的 `CoolRunEdition` 键（`lite` / `pro`），启动时写入 UserDefaults 用于诊断上报。

### 6.2 打包脚本

改 `scripts/create-dmg.sh` 接受参数：

```bash
./scripts/create-dmg.sh --edition lite   # → dist/CoolRun-Lite-1.4.0.dmg
./scripts/create-dmg.sh --edition full   # → dist/CoolRun-Full-1.4.0.dmg
```

内部：`xcodebuild -scheme CoolRun-Lite|CoolRun-Full` → 拷 runtime → 逐文件 ad-hoc 签名 → hdiutil。

**签名注意**：`codesign --deep` 会破坏 DSH 的 pkg 内嵌签名，导致 Full 版首次运行 `Killed: 9`。必须逐文件签：

```bash
find "$APP/Contents/Resources/AgentRuntime" -type f -perm +111 -exec codesign -f -s - {} \;
codesign -f -s - "$APP"
```

Lite 版没有 runtime，`--deep` 无所谓，但为了统一流程，两个版本都逐文件签。

### 6.3 下载页文案

```
CoolRun Lite  ·  10 MB
开箱即用的菜单栏助手。AI、插件、桌宠全都有。
DSH 引擎首次使用时按需下载。

CoolRun Full  ·  120 MB
完整离线版。内置 DSH 引擎，断网也能跑 Agent。
适合不想折腾环境、或经常没网的用户。
```

**默认推荐 Lite**，Full 作为"高级下载"折叠在下面。理由：28 MB 的下载转化率远高于 120 MB，而 Full 的用户是明确知道自己要什么的那批。

## 7. 实施路线

按"体验收益 / 工期"排序：

| 阶段 | 内容 | 工期 | 收益 |
| --- | --- | --- | --- |
| **P2.1** | 场景卡 + 斜杠命令 | 1 周 | ⭐⭐⭐⭐⭐ 最大 |
| **P2.2** | 结果卡片（6 个工具 + 4 个渲染器） | 4 天 | ⭐⭐⭐⭐ |
| **P2.3** | 工具浏览器 + SchemaFormView | 1 周 | ⭐⭐⭐⭐ |
| **P2.4** | 首次引导 | 3 天 | ⭐⭐⭐ |
| **P2.5** | 双版本构建 + 打包脚本 + 签名 | 3 天 | ⭐⭐⭐ 分发前提 |
| **P2.6** | DSH 引擎接入（Full 专属） | 2 周 | ⭐⭐⭐ |
| **P3** | 桌宠（本鱼） | 1 周 | ⭐⭐ |
| **P3** | 插件系统 | 3 周 | ⭐⭐ |
| **P3** | QQ 机器人宿主面板 + OneBot 工具 | 1.5 周 | ⭐⭐ |

合计约 **11 周**。前 5 项（P2.1–P2.5）5 周内能让产品"看起来是个完整的东西"。

## 8. 风险

| 风险 | 影响 | 应对 |
| --- | --- | --- |
| 场景卡把模型能力锁死 | 用户只会点卡片，不会提问 | 卡片只填 prompt，仍走完整 Agent 循环；输入框始终可见 |
| 双版本导致测试矩阵翻倍 | CI 时间翻倍 | Lite 跑全量测试，Full 只跑冒烟（启动 + 引擎自检 + 一个端到端） |
| Full 版签名失败 | 用户下载后打不开 | 打包脚本里加 `codesign --verify --deep --strict` 门禁，失败即中断 |
| 场景 JSON 被插件写坏 | 面板打不开 | 解析失败时回退到内置默认集，坏文件重命名为 `.bak` |
| QQ 机器人合规风险 | 用户账号被封 | 首次启用时强制弹免责声明，需勾选"我已知悉风险"；不提供自动登录 |
| SnowLuma 只支持 Win/Linux | Mac 用户装不了 | 宿主面板内置 Docker Compose 模板 + noVNC 嵌入，把复杂度藏起来 |

## 9. 待确认

1. **Full 版是否真的需要内置 DSH？** 如果 Lite 的"按需下载"体验做得足够顺滑（点一下、等 30 秒、自动解压），Full 版的 120 MB 可能没必要。
2. **场景卡预置哪 12 个？** 上面的清单是草案，需要按实际使用频率调整。
3. **桌宠高清素材从哪来？** 本鱼形象需要生成一套序列帧（idle / walk / talk / drag / sleep 各 4–8 帧），这是美术工作量。
