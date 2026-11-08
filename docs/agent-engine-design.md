# CoolRun Agent 引擎设计方案

> 状态：设计稿（v1，2026-11-07）
> 目标：把 CoolRun 从"菜单栏工具集合"升级为"能自己动手的菜单栏助手"，同时不牺牲它的轻量与原生体验。

---

## 0. 一句话结论

**想法成立，但不要把 DeepSeek Harness 当成地基，而要把它当成可插拔的"重引擎"。**

CoolRun 现有 8.5 MB 的 dmg 是它最重要的产品资产之一；DSH 的单文件运行时解压后是 **297 MB**，塞进 dmg 会让安装包膨胀到 ~100 MB（压缩后），是 12 倍。正确的做法是：

1. 在 Swift 里定义一层 **AgentEngine 协议** + **ToolRegistry** + **权限分级**，这是产品真正的护城河；
2. 先实现 `SwiftAgentEngine`（原生，体积 +0，覆盖 90% 场景）；
3. 把 `DSHAgentEngine`（子进程 + JSON-RPC + MCP）做成**可选安装的增强包**，用户要"长任务、多步规划、子 agent、代码执行"时才下载；
4. 两者共用同一套工具与权限，UI 无感知。

这样既拿到了 DSH 的全部能力，又不把 300 MB 强加给每个用户。

---

## 1. 可行性核验（已实测，非推测）

本机（macOS 26.6 / arm64 / Xcode 26.6 / Node 24.14.1）实测结论：

| 验证项 | 结果 | 说明 |
|---|---|---|
| DSH 单文件运行时可直接执行 | ✅ | `deepseek-harness-sdk-runtime-macos-arm64 --help` 正常输出 |
| 运行时不需要系统 Node | ✅ | 内嵌 Node 24 SEA + 完整依赖树 |
| 解压体积 | ⚠️ **297 MB** exe + 4.3 MB ripgrep + 49 KB spawn-helper | wheel 压缩后 86–90 MB |
| JSON-RPC over stdio | ✅ | `initialize` 返回结构化错误、`shutdown` 返回 `{}`，通道正常 |
| `--patch` 注入自定义 provider | ✅ | 注入 `dsh-llm-pi-ai`（openai-completions）成功，`--dump-config` 可见 |
| `--patch` 注入 MCP client | ✅ | 注入 `dsh-mcp-client`（streamable-http）成功 |
| CoolRun 可 spawn 子进程 | ✅ | `ENABLE_APP_SANDBOX = NO`，entitlements 里 `app-sandbox=false` |
| 三种 API 协议 | ✅ | `openai-completions` / `openai-responses` / `anthropic-messages` 原生支持 |

**实测踩到的坑（必须写进实现）：**

```
Error: dsh: host preparation failed:
No usable native binding found for node-addon-require-builtin-darwin-arm64 (auto)
```

pkg 打包的 native addon 会解压到 `~/.cache/pkg/<sha>/`。该目录被其他 pkg 应用污染或写坏时，运行时直接起不来。**解决方案：spawn 时强制注入 `PKG_NATIVE_CACHE_PATH` 指向 app 自己的容器目录**，例如：

```
PKG_NATIVE_CACHE_PATH = ~/Library/Application Support/CoolRun/AgentRuntime/pkgcache
```

加了这个环境变量后同一份二进制立刻恢复正常。这一条不做，用户机器上迟早炸。

---

## 2. 三条路线对比

| 维度 | A. 纯 Swift 原生 Agent | B. DSH 内嵌（sidecar） | C. DSH 外挂（用户自装） |
|---|---|---|---|
| dmg 体积 | +0（~8.5 MB） | **+90 MB 压缩 / +300 MB 安装** | +0 |
| 启动开销 | 0 | 首次 ~1.5–3 s，常驻内存 +150–300 MB | 同 B |
| 用户安装门槛 | 无 | 无 | 需装 Node 22+ 与 dsh，劝退 90% 用户 |
| 多步任务/子 agent | 需自研 | 开箱即用 | 开箱即用 |
| 代码执行/shell | 需自研且危险 | 自带沙箱与审批策略 | 自带 |
| 多 provider 适配 | 需自研（3 种 wire） | 开箱即用（3 种 wire + 目录发现） | 开箱即用 |
| 上下文压缩/长会话 | 需自研 | 自带 compaction | 自带 |
| 维护成本 | 中（自己写循环） | 低（跟版本） | 低 |
| 与 Swift 生态契合 | 最高 | 进程边界清晰 | 进程边界清晰 |
| 断网/离线 | 本地 LLM 可用 | 本地 LLM 可用 | 本地 LLM 可用 |
| 失败模式 | 自己修 | 子进程崩溃需重启 | 用户环境问题甩锅 |

**结论：A 做主线，B 做可选增强，C 作为开发期调试通道（同一套代码，切换 launch 策略即可）。**

C 其实零成本：`DSHAgentEngine` 的"可执行文件路径"既可以指向 app bundle 内的 runtime，也可以指向 `which dsh`。开发时用 C 迭代，发布时按用户选择决定是否装 B。

---

## 3. 目标架构

```
┌──────────────────────────────────────────────────────────────┐
│ CoolRun.app (SwiftUI, LSUIElement)                           │
│                                                              │
│  AIAssistantView / AgentPanel                                │
│         │  @Observable AgentSession                           │
│         ▼                                                    │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ AgentCoordinator                                       │  │
│  │  · 会话历史（本地 JSONL，可回放）                       │  │
│  │  · 工具调用循环 / 中断 / 重试                            │  │
│  │  · 权限闸门（L0–L3）                                    │  │
│  └───────┬───────────────────────────────┬────────────────┘  │
│          │                               │                   │
│          ▼                               ▼                   │
│  ┌───────────────────┐          ┌─────────────────────────┐  │
│  │ AgentEngine 协议   │          │ ToolRegistry            │  │
│  │  (可插拔)          │          │  · 工具元数据/schema     │  │
│  │                   │          │  · 权限级别              │  │
│  │ SwiftAgentEngine  │          │  · 审计日志              │  │
│  │ DSHAgentEngine ───┼──┐       └───────────┬─────────────┘  │
│  └───────────────────┘  │                   │                │
│                         │                   ▼                │
│                         │        ┌────────────────────────┐  │
│                         │        │ CoolRunMCPHost         │  │
│                         │        │ (localhost HTTP MCP)   │  │
│                         │        └────────────────────────┘  │
└─────────────────────────┼────────────────────────────────────┘
                          │ spawn + NDJSON JSON-RPC (stdin/stdout)
                          ▼
              ┌───────────────────────────────┐
              │ dsh runtime (单文件, 297 MB)   │
              │  profile: coolrun (自定义)     │
              │  · llm-pi-ai (3 种 wire)      │
              │  · mcp-client → CoolRunMCPHost│
              │  · 无 shell / 无 fs 写（默认） │
              └───────────────────────────────┘
```

### 3.1 关键设计决策

**决策 1：引擎接口在 Swift，不在 DSH。**
所有 UI、会话、权限、工具都归 Swift 管。DSH 只是一个"会思考的子进程"，它唯一能做的事就是：读上下文、调工具、产出文本。换引擎 = 换一个类，产品不受制于 DSH 的版本与协议演进。

**决策 2：工具边界用 MCP，而不是 DSH 插件。**
DSH 的插件需要 pnpm 安装、打进 runtime 闭包，每次升级都要重打包。MCP 是进程外标准协议，Swift 侧实现一次，DSH、未来任何 agent 客户端（Claude Desktop、Cursor）都能复用。工具名形如 `mcp__coolrun__system_snapshot`。

**决策 3：默认不给 shell、不给任意文件读写。**
sdk-minimal 默认是 `danger-full-access` + 持久 shell。对菜单栏 app 这是灾难：模型一句 `rm -rf ~` 就完了。自定义 profile 必须删掉 shell 行，只留 MCP 工具 + 只读 fs。需要代码执行时，走显式的"高级模式"并逐次审批。

**决策 4：本地 LLM 走同一套 provider 抽象。**
Ollama / LM Studio / llama.cpp 都是 `openai-completions` 兼容端点，指向 `http://127.0.0.1:11434/v1` 即可。离线可用性来自这里，不需要额外工作。

---

## 4. Swift 侧设计

### 4.1 引擎协议

```swift
// Modules/Agent/AgentEngine.swift

/// 一次 agent 运行的可观测事件流。
enum AgentEvent: Sendable {
    case textDelta(String)
    case reasoningDelta(String)
    case toolCallStarted(id: String, name: String, input: JSONValue)
    case toolCallFinished(id: String, name: String, output: String, isError: Bool)
    case turnFinished(stopReason: String)
    case failed(AgentError)
}

protocol AgentEngine: AnyObject, Sendable {
    var kind: AgentEngineKind { get }          // .native / .dsh
    var displayName: String { get }
    var isAvailable: Bool { get async }

    /// 启动或复用一个会话。
    func run(
        prompt: String,
        history: [AgentMessage],
        tools: [ToolDescriptor],
        config: AgentRunConfig
    ) -> AsyncThrowingStream<AgentEvent, Error>

    /// 中断当前轮次（用户点"停止"）。
    func cancel() async

    func shutdown() async
}
```

`AgentRunConfig` 里放 provider / model / baseURL / apiKeyRef / reasoningEffort / maxTokens / 工作目录 / 超时。

### 4.2 SwiftAgentEngine（P0 主线）

自己实现 OpenAI 兼容的 tool-calling 循环。这是整个方案里工作量最大、但最不可替代的一块。

```
循环：
  messages = [system] + history + [user]
  loop (max 8 rounds):
      resp = stream(chat.completions, tools: toolSchemas)
      累积 textDelta → UI
      if resp.finish_reason == "tool_calls":
          for each call: 权限闸门 → ToolRegistry.execute → 追加 tool 消息
          continue
      else:
          return
```

要点：

- **流式**：已有 `LLMService.stream` 可以复用，但要扩成解析 `tool_calls` 增量（`delta.tool_calls[i].function.arguments` 是分片字符串，要按 index 拼接）。
- **provider 差异**：Anthropic Messages 的 tool 格式是 `content: [{type:"tool_use"}]` + `tool_result` block；OpenAI Responses 是 `input` 数组 + `function_call` item。建议**内部统一成 OpenAI Chat 形状**，适配器负责翻译。这样 `ToolDescriptor` 只有一份。
- **离线兜底**：Ollama 的 tool calling 支持不完整，检测到模型不支持时降级为"文本 JSON 协议"（让模型输出 `<tool>{"name":...}</tool>`，正则解析）。这条降级路径必须有，否则本地小模型完全不可用。
- **上下文预算**：菜单栏面板小，历史不能无限长。按 token 估算裁剪，保留 system + 最近 N 轮 + 工具结果摘要。

### 4.3 ToolRegistry

```swift
struct ToolDescriptor: Sendable {
    let name: String              // system_snapshot
    let displayName: String
    let summary: String
    let inputSchema: JSONSchema   // 生成给模型的 JSON Schema
    let permission: ToolPermission
    let handler: @Sendable (JSONValue) async throws -> ToolResult
}

enum ToolPermission: Int, Comparable {
    case read = 0        // 只读，直接执行
    case reversible = 1  // 可撤销（通知、切面板、复制），直接执行
    case persistent = 2  // 持久写入（笔记、提醒、设置），需确认
    case dangerous = 3   // 危险（shell、删文件、外部发送），默认关闭 + 每次确认
}
```

工具注册在 `AgentToolCatalog` 里，启动时统一装配。**工具名与 MCP 名一致**，保证两个引擎看到同一份能力清单。

### 4.4 工具清单（v1）

按模块划分，标注权限级别。这张表就是"agent 能做什么、不能做什么"的产品定义。

| 工具 | 级别 | 说明 |
|---|---|---|
| `system_snapshot` | L0 | CPU/内存/磁盘/电池/网络/温度/负载 |
| `system_processes` | L0 | Top N 进程（CPU/内存） |
| `system_battery_health` | L0 | 循环次数、健康度、温度 |
| `network_status` | L0 | 主接口、IP、上下行速率 |
| `gold_price_now` | L0 | 当前金价 + 涨跌 + 数据新鲜度 |
| `gold_history` | L0 | 指定周期 K 线/记录 |
| `gold_signals` | L0 | 技术指标与交易信号 |
| `gold_portfolio` | L0 | 持仓与盈亏 |
| `calendar_upcoming` | L0 | 未来 N 天事件/生日/倒计时 |
| `calendar_lunar` | L0 | 农历、节气、节假日 |
| `english_daily` | L0 | 今日单词/句子/名言 |
| `english_progress` | L0 | 学习进度与统计 |
| `quota_status` | L0 | Codex / Claude 额度 |
| `notes_search` | L0 | 全文检索笔记 |
| `notes_list` | L0 | 分组与列表 |
| `clipboard_search` | L0 | 历史检索（敏感，默认只在本地模型下开放） |
| `diagnostics_sleep` | L0 | 睡眠/唤醒分析 |
| `diagnostics_network` | L0 | 网络诊断报告 |
| `diagnostics_storage` | L0 | 磁盘占用分析 |
| `ui_show_module` | L1 | 切换当前面板（"给我看金价"） |
| `ui_notify` | L1 | 发本地通知 |
| `clipboard_copy` | L1 | 写入剪贴板 |
| `notes_create` | L2 | 新建笔记（需确认） |
| `notes_update` | L2 | 修改笔记（需确认） |
| `reminder_create` | L2 | 创建本地提醒（需确认） |
| `schedule_create` | L2 | 创建定时任务（需确认） |
| `settings_update` | L2 | 修改设置项（白名单字段） |
| `screenshot_capture` | L2 | 截屏（需屏幕录制授权，需确认） |
| `shell_exec` | L3 | **默认不注册**，仅高级模式 |
| `file_write` | L3 | **默认不注册** |

设计原则：

1. **能读的都开放，能写的都分级**。用户对"看数据"零戒心，对"改东西"有戒心。
2. **L2 确认 UI 必须轻**：在对话流里插一张卡片（"要创建这条提醒吗？"），不要弹系统模态。
3. **每个工具调用写审计日志**（时间、工具、参数摘要、结果、耗时），存 `Application Support/CoolRun/agent-audit.jsonl`，设置页可查看与清空。这是"可信"的基础。

### 4.5 CoolRunMCPHost（给 DSH 用的工具入口）

Swift 侧起一个只监听 `127.0.0.1` 的 HTTP 服务，实现 MCP Streamable HTTP 传输的最小集合：

```
POST /mcp
  headers: Authorization: Bearer <每进程随机 token>
           Content-Type: application/json
           Mcp-Session-Id: <init 时返回>

方法：
  initialize            → protocolVersion / capabilities.tools / serverInfo
  notifications/initialized  (通知，无响应)
  tools/list            → 返回 ToolRegistry 全部工具
  tools/call            → 权限闸门 → handler → content[]
  ping                  → {}
GET /mcp（可选）        → SSE 流，用于服务端推送；v1 可不实现
```

实现要点：

- 用 `Network.framework` 的 `NWListener`（`NWParameters.tcp` + 端口 0 自动分配），不要用 `NWConnection` 手写 HTTP 解析之外的依赖。
- 端口随机，写进 `~/.coolrun-agent.json` 或通过启动参数传给 dsh。
- **token 每次启动重新生成**，只传给子进程，防止本机其他进程乱调。
- 请求处理必须回到 `@MainActor`（工具要读 UI 状态），用 `MainActor.assumeIsolated` 或 `await MainActor.run`。
- 单请求超时 30 s，工具自身可长跑但要支持取消（`CancellationToken` → `Task.cancel`）。

> 如果觉得 HTTP 太重，还有一条更轻的路：让 dsh 的 MCP client 用 `transport: stdio` 启动一个 20 行的 Swift helper，helper 通过 Unix domain socket 转发到主 app。但要多一个 Xcode target + 签名对象，v1 不建议。

### 4.6 会话与持久化

- 会话存 JSONL：`Application Support/CoolRun/agent/sessions/<uuid>.jsonl`，一行一个事件。
- 面板只渲染最近 200 条，滚动加载更早的。
- 会话可命名、可删除、可导出 Markdown。
- **不写 UserDefaults**（大对象会拖慢启动）。

---

## 5. DSH 侧集成

### 5.1 自定义 profile

不修改 DSH 源码，用 `--patch` 叠加。CoolRun 随 app 打包一份 `coolrun.patch.yml`：

```yaml
# Resources/AgentRuntime/coolrun.patch.yml
# 基于 sdk-minimal，去掉 shell，只留 MCP 工具 + 只读 fs
- id: sandbox-policy
  config:
    mode: read-only
    workspaceRoot: !!js process.env.COOLRUN_WORKSPACE

# 移除持久 shell（sdk-minimal 自带，必须显式禁用）
- id: terminal-bash
  disabled: true
- id: tool-shell
  disabled: true

- insert:
    # 多 provider：三种 wire 都从 CoolRun 的设置写入
    - id: llm-pi-ai
      name: '@deepseek-ai/dsh-llm-pi-ai'
      config:
        providers:
          coolrun-cloud:
            apiKeyEnv: COOLRUN_LLM_KEY
            api: openai-completions
            baseURL: !!js process.env.COOLRUN_LLM_BASEURL
            models:
              - id: !!js process.env.COOLRUN_LLM_MODEL
          coolrun-local:
            api: openai-completions
            baseURL: http://127.0.0.1:11434/v1
            models:
              - id: qwen2.5:7b

    # 工具入口
    - id: mcp-coolrun
      name: '@deepseek-ai/dsh-mcp-client'
      config:
        serverName: coolrun
        transport: streamable-http
        url: !!js process.env.COOLRUN_MCP_URL
        headers:
          Authorization: !!js `Bearer ${process.env.COOLRUN_MCP_TOKEN}`
        toolCallTimeoutMs: 60000
        failOnStartupError: true
```

**注意：`failOnStartupError: true` 很重要。** 默认 false 时 MCP 连不上 dsh 照样启动，模型会以为自己没有工具，静默降级成纯聊天——这种"看起来能用其实残废"的故障最难查。

具体 id 以 `--dump-config` 输出为准（不同版本行 id 会变），实现时用脚本校验。

### 5.2 进程管理（DSHAgentEngine）

```swift
final class DSHAgentEngine: AgentEngine {
    private var process: Process?
    private var stdin: FileHandle?
    private var stdoutBuffer = Data()
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]

    func start() throws {
        let rt = try RuntimeLocator.resolve()   // bundle 内 or which dsh
        let p = Process()
        p.executableURL = rt.executable
        p.arguments = ["--profile", "sdk-minimal", "--patch", patchPath]
        var env = ProcessInfo.processInfo.environment
        env["DSH_HOME"] = homeDir.path
        env["PKG_NATIVE_CACHE_PATH"] = pkgCacheDir.path   // ← 实测必须
        env["COOLRUN_MCP_URL"] = "http://127.0.0.1:\(mcpPort)/mcp"
        env["COOLRUN_MCP_TOKEN"] = mcpToken
        env["COOLRUN_LLM_KEY"] = key
        env["COOLRUN_LLM_BASEURL"] = baseURL
        env["COOLRUN_LLM_MODEL"] = model
        env["PATH"] = "\(rt.directory.path):/usr/bin:/bin"  // 让 -rg sidecar 可被找到
        p.environment = env
        p.currentDirectoryURL = workspace
        // stdout/stderr 走 Pipe，stderr 单独收集用于诊断
        ...
    }
}
```

必须处理的细节：

| 问题 | 处理 |
|---|---|
| stdout 是 NDJSON，会分片 | 累积到 `Data`，按 `\n` 切；一行可能跨多次 read |
| 子进程崩溃 | `terminationHandler` → 清理 pending → 上报 UI（"Agent 引擎已退出"）并允许重启 |
| stdin EOF = 客户端走了 | dsh 会把 EOF 当断连并退出。**app 退出前先发 `shutdown`**，不要直接 kill |
| 首次启动初始化 profile | 会写 `$DSH_HOME/profiles/`，放 `Application Support/CoolRun/agent-home/`，别污染用户 `~/.dsh` |
| 版本升级 | runtime 与 patch 一起版本化；patch 里引用的 row id 变了会启动失败，要有降级到 SwiftAgentEngine 的兜底 |
| 冷启动 1.5–3 s | 首次对话时后台预热；面板显示"引擎启动中"而不是转圈假装在思考 |
| 内存常驻 150–300 MB | 空闲 10 分钟自动 `shutdown`，下次用到再起 |

### 5.3 SDK 协议调用序列

```
→ initialize {cwd, provider:"coolrun-cloud", model:"gpt-4o", maxTokens:4096}
← {serverInfo:{name:"deepseek-harness-sdk-runtime", version:"0.0.1"}}

→ session/prompt {sessionId:"<uuid>", contentBlocks:[{type:"text", text:"..."}]}
← {messageId:"..."}

← session.event (多条)   逐条渲染：assistant 文本增量、tool_use、tool_result
← session.status {status:"running"|"idle"}

（可选）→ session/wait {sessionId}  等到整轮结束
→ shutdown
```

`session.event` 的 `event` 是完整的 `SessionEvent` 联合类型，Swift 侧用 `type` 字段做多态解码，未知类型忽略（向前兼容）。**不要对 event schema 做严格校验**，否则 dsh 升个小版本 app 就崩。

---

## 6. 打包与签名

### 6.1 目录布局

```
CoolRun.app/Contents/
├── MacOS/CoolRun
├── Frameworks/...
└── Resources/
    ├── AgentRuntime/                 ← 可选安装时才有
    │   ├── deepseek-harness-sdk-runtime-macos-arm64        (297 MB)
    │   ├── deepseek-harness-sdk-runtime-macos-arm64-rg     (4.3 MB)
    │   ├── deepseek-harness-sdk-runtime-macos-arm64-spawn-helper
    │   └── coolrun.patch.yml
    └── ...
```

**放 Resources 而不是 Frameworks**：它不是动态库，是独立可执行文件，放 Resources 不参与 dyld 链接，也不会被 `strip` 破坏。

### 6.2 签名顺序（关键）

```
1. 先给三个可执行文件单独签名（带 hardened runtime + 各自 entitlements）
   codesign --force --options runtime --timestamp \
            --sign "Developer ID Application: ..." \
            Resources/AgentRuntime/deepseek-harness-sdk-runtime-macos-arm64
2. 再签主 app（不要 --deep，会破坏内嵌签名）
   codesign --force --options runtime --timestamp \
            --entitlements CoolRun.entitlements \
            --sign "..." CoolRun.app
3. 验证
   codesign --verify --deep --strict --verbose=2 CoolRun.app
   spctl -a -vvv -t exec CoolRun.app
```

注意事项：

- **`--deep` 是毒药**。它会把 pkg 生成的 ad-hoc 签名覆盖成不匹配的组合，公证必挂。逐个签。
- runtime 是 pkg/SEA 产物，本身带 ad-hoc 签名。用 Developer ID 重签是允许的，但要**保持 Mach-O 完整**（不要 strip、不要修改段）。
- 如果走 **ad-hoc 分发**（现在的 `package-macos-unsigned.yml` 就是这样），`--deep` 反而能用，因为没有公证要求。两条路径都要在 CI 里跑通。
- 公证（notarization）：`xcrun notarytool submit CoolRun.zip --wait`，然后 `xcrun stapler staple CoolRun.app`。
- **首次运行 Gatekeeper**：未公证的 app 用户要右键打开。这和现在 CoolRun 的分发方式一致，不是新增问题。

### 6.3 体积策略（三选一，建议 3）

| 策略 | dmg 体积 | 体验 |
|---|---|---|
| 1. 全量内置 | ~100 MB | 开箱即用，但劝退 |
| 2. 完全不内置，只支持外挂 dsh | 8.5 MB | 高级用户才用得上 |
| 3. **按需下载（推荐）** | 8.5 MB 起 | 设置里"启用深度 Agent（约 90 MB）"→ 后台下载 wheel → 解压到 Application Support |

策略 3 的实现：

- 下载源：PyPI `deepseek-harness-runtime-bin` 的 macos-arm64 wheel（固定版本 + SHA256 校验），或自己的 CDN。
- 解压：wheel 就是 zip，`unzip` 到 `Application Support/CoolRun/AgentRuntime/<version>/`。
- 校验：`codesign --verify` + 版本号匹配 app 内 `AgentRuntime.version`。
- 失败可重试，下载中显示进度，支持取消。
- **离线安装包**另出一个 `CoolRun-Full.dmg`（内置 runtime），给内网/无网用户。

### 6.4 Xcode 配置

- 新增 `AgentRuntime.version` 到 Info.plist（字符串），app 用它判断本地 runtime 是否匹配。
- 如果选策略 1，runtime 作为 folder reference 加进 target（**不要**勾 "Copy only when installing"）。
- 关闭 `ENABLE_APP_SANDBOX` 是现状，保持不变。若将来要上架 App Store，这条路线整体不成立（沙箱禁止 spawn 任意可执行文件），只能走 SwiftAgentEngine。

---

## 7. 分阶段实施

### P0：骨架 + 原生引擎（约 2–3 周）

- [ ] `Modules/Agent/` 目录：`AgentEngine.swift`、`AgentCoordinator.swift`、`ToolRegistry.swift`、`AgentMessage.swift`
- [ ] `SwiftAgentEngine`：OpenAI Chat 流式 + tool_calls 解析 + 8 轮循环 + 取消
- [ ] provider 适配层：OpenAI Chat / OpenAI Responses / Anthropic Messages / Ollama
- [ ] 首批 12 个 L0 工具（system / gold / calendar / english / quota）
- [ ] 对话 UI 改造：现有 `AIAssistantView` 升级为可渲染工具调用卡片
- [ ] 审计日志 + 设置页"Agent"分页（provider 选择、权限开关、日志查看）

**验收**：问"我的 Mac 为什么卡"，agent 自己调 `system_snapshot` + `system_processes`，给出带数据的回答；点停止能中断；断网切 Ollama 仍可用。

### P1：写入能力 + 权限闸门（约 1–2 周）

- [ ] L1/L2 工具：切面板、通知、剪贴板、笔记、提醒、定时任务
- [ ] 权限确认卡片（对话内联，不弹模态）
- [ ] `schedule_create` + `ScheduleRunner`（本地定时触发 agent 任务，比如"每天 9 点汇报金价"）
- [ ] 设置页权限矩阵（每个工具可单独关）

**验收**："每天早上九点把金价和 CPU 情况发通知给我"→ 生成定时任务 → 次日 9:00 真的收到。

### P2：DSH 引擎接入（约 2–3 周）

- [ ] `RuntimeLocator` + `RuntimeInstaller`（下载/校验/解压/版本管理）
- [ ] `CoolRunMCPHost`（NWListener + MCP Streamable HTTP 最小实现）
- [ ] `DSHAgentEngine`（spawn / NDJSON 编解码 / pending 请求表 / 崩溃恢复 / 空闲回收）
- [ ] `coolrun.patch.yml` + 启动自检（`--dump-config` 校验行 id）
- [ ] 引擎切换 UI + 健康检查（启动失败自动回落原生引擎）

**验收**：同一句"分析我今天的系统负载并写成笔记"，两个引擎都能完成；拔掉网络、关掉 dsh 进程，app 不崩且能降级。

### P3：增强（按需）

- [ ] 截图工具（ScreenCaptureKit + 屏幕录制授权引导）
- [ ] 多步任务进度视图（DSH 的 subagent 事件 → 树形展示）
- [ ] 会话导出/分享
- [ ] 高级模式（shell / 文件写），默认关闭，二次确认 + 白名单目录

---

## 8. 风险清单

| 风险 | 影响 | 缓解 |
|---|---|---|
| dmg 体积膨胀 | 转化率下降 | 按需下载（策略 3），主包保持 8.5 MB |
| 子进程签名/公证失败 | 无法分发 | 逐文件签名，CI 双路径（ad-hoc + Developer ID）验证 |
| DSH 版本升级破坏 patch | 引擎起不来 | 启动自检 + 自动回落原生引擎 + 版本锁定 |
| 模型幻觉调用不存在的工具 | 体验差 | 工具清单严格按 registry 生成；未知工具返回明确错误 |
| 工具越权 | 安全事件 | L0–L3 分级 + 默认不给 shell/fs 写 + 审计日志 |
| 剪贴板/笔记隐私 | 用户信任崩塌 | 默认只在本地模型下开放剪贴板；发云端前脱敏提示 |
| 内存常驻 | 菜单栏 app 变重 | 空闲 10 分钟回收子进程 |
| MCP 端口被占用/被扫 | 本地攻击面 | 随机端口 + 每进程 token + 只绑 127.0.0.1 |
| 冷启动慢 | 用户以为卡死 | 预热 + 明确的"引擎启动中"状态 |
| `~/.cache/pkg` 污染 | 引擎起不来 | 强制 `PKG_NATIVE_CACHE_PATH`（已实测） |

---

## 9. 与"以 DSH 为基础改造整个 app"的对比

用户提的另一个方向是"以 deepseekharness 为基础把 CoolRun 改造成它的形态"。明确不建议：

- DSH 的桌面端是 Electron，CoolRun 是 8.5 MB 原生 SwiftUI 菜单栏 app。换成 Electron 意味着体积 ×30、内存 ×5、失去 `NSStatusItem` 的原生手感与低功耗。
- CoolRun 的 10 个模块（系统采样、金价、日历、剪贴板……）全部要重写，收益为零。
- 正确的复用方式是**进程级复用**：DSH 提供"思考"，CoolRun 提供"身体"和"界面"。

---

## 10. 下一步

1. 确认路线（建议 P0 → P1 → P2，按需下载策略）。
2. 先做 P0 的 `AgentEngine` + `ToolRegistry` 骨架与 3 个工具，跑通一轮真实对话。
3. 骨架稳定后再决定 P2 是否值得——如果 P0+P1 已经覆盖 90% 场景，DSH 引擎可以无限期延后。

---

## 11. P0 落地记录（已完成）

P0 全部代码已合入 `CoolRun/Modules/Agent/`，`xcodebuild build` 零错误零警告，单元测试通过。

| 文件 | 职责 |
| --- | --- |
| `AgentMessage.swift` | `JSONValue`（含可写 subscript）、`AgentMessage`、`AgentToolCall` |
| `AgentEngine.swift` | `AgentEngine` 协议、`AgentRunConfig`、`AgentEvent`、`AgentError`、`AgentWireProtocol`（4 种协议） |
| `AgentWire.swift` | 4 个 wire 实现：OpenAI Chat(SSE)、OpenAI Responses(SSE)、Anthropic Messages(SSE)、Ollama(NDJSON) |
| `SwiftAgentEngine.swift` | 原生引擎主循环：流式文本 + 多轮工具调用 |
| `ToolRegistry.swift` | 工具注册/校验/执行/审计，`ToolPermission` 四级 |
| `AgentTools.swift` | 12 个 L0 只读工具 |
| `AgentAuditLog.swift` | 工具调用审计，落盘 `~/Library/Application Support/CoolRun/agent-audit.json` |
| `AgentSettings.swift` | 协议/baseURL/model/工具等级的持久化，可从旧 LLM 配置派生 |
| `AgentCoordinator.swift` | 会话状态机，把引擎事件流翻译成 UI 状态 |
| `AgentChatView.swift` | 聊天界面 + 工具调用卡片 + 配置面板 |

改造：`AIAssistantView.swift` 由 532 行旧聊天实现改为 `AgentChatView` 薄壳；`LLMService.swift` 从 667 行瘦身到 210 行，只保留配置层（`testConnection()` 复用 `AgentWire`，与实际调用同一条代码路径）。

**验证方式**：`CoolRunTests/AgentWireTests.swift` 用 `NWListener` 起本地假 LLM 服务，覆盖
1. OpenAI Chat 流式文本 + 分片 tool_calls 解析；
2. OpenAI Responses 事件解析；
3. **端到端**：`SwiftAgentEngine` → wire → 工具调用 → 工具结果回灌 → 第二轮文本，真实执行 `system_snapshot`。

这套测试不依赖任何真实 API key，可长期作为回归基线。

**尚未做**：真实云端模型联调（本机缺 key）、DSH 引擎（P2）、写类工具与权限闸门（P1）。

### 11.1 真实模型联调记录

**云端（OpenAI Chat 协议）—— 通过。** 用 workbuddy2api 网关（`http://localhost:7863`，模型 `global:deepseek-v4.1-flash`）跑 `AgentIntegrationTests`：

- `testRemoteChatCallsToolAndAnswers`：5.66s 通过，模型主动调用 `system_snapshot`、拿到工具结果后给出总结。
- `testRemoteMultiTurnHistory`：2.32s 通过，多轮历史正确回传。
- 该网关 `/v1/models` 返回的模型条目带 `supports_tool_call: true`，标准 OpenAI `tool_calls` 格式，与 `OpenAIChatWire` 完全兼容。

**本地 Ollama —— 通过（3B 及以上）。**
- `qwen2.5:0.5b`（397 MB）能连通 `/api/chat`，单工具 curl 也返回结构化 `tool_calls`；但在 Agent 完整场景（12 个工具 + 中文 prompt）下会把调用输出成 JSON 文本，不可用。
- `qwen2.5:3b`（1.9 GB）通过：`testOllamaLocalChatCallsTool` 连跑 3 次全过（3.92s / 2.64s / 3.10s），模型稳定主动调用 `system_snapshot` 并基于工具结果作答。
- 结论：本地模型做 Agent 的下限在 3B 参数左右，0.5B 这类模型不要指望工具调用能力。`qwen2.5:3b` 已作为推荐的本地默认模型写进 `AgentWireProtocol.ollama.defaultModel` 的候选。

**已知限制（P1 待办）**：弱模型把工具调用写成文本时，可以加一层兜底解析（识别形如 `[{"name":…,"arguments":…}]` 的文本并执行），但那属于增强项，不应默认开启，否则可能误伤正常回答。

**集成测试的开关**：`AgentIntegrationTests` 默认 `XCTSkip`，只有设置了环境变量才运行，因此不影响常规 CI：

```bash
TEST_RUNNER_AGENT_IT_BASEURL=http://localhost:7863 \
TEST_RUNNER_AGENT_IT_KEY=<key> \
TEST_RUNNER_AGENT_IT_MODEL=global:deepseek-v4.1-flash \
xcodebuild ... -only-testing:CoolRunTests/AgentIntegrationTests test

# 本地模型
TEST_RUNNER_AGENT_IT_OLLAMA_MODEL=qwen2.5:3b xcodebuild ... -only-testing:CoolRunTests/AgentIntegrationTests/testOllamaLocalChatCallsTool test
```

## 11.2 Agent 交互层（P2 前半，已完成）

P0/P1 解决的是"能不能用"，这一段解决的是"好不好用"。四项改动：

**场景卡。** 空对话界面不再是干巴巴一个输入框，而是 12 张卡片：电脑体检、金价快报、今天有什么、谁在吃内存、电池还行吗、能清理什么、记一笔、剪贴板找东西、提醒我、额度还剩多少、截个图、切到金价。点一下就跑，需要补充内容的卡片（记一笔、提醒、剪贴板搜索）会把提示词填进输入框并聚焦。卡片定义在 `CoolRun/Modules/Agent/AgentRecipe.swift`，用户自定义的落在 `~/Library/Application Support/CoolRun/recipes.json`。

**斜杠指令。** 输入框支持 `/体检`、`/金价`、`/记 买牛奶`、`/提醒 30m 喝水`、`/tool system_snapshot`、`/clear`、`/settings`、`/help`。解析器是 `AgentCommandParser`，斜杠后既认场景卡的 `slash` 也认 `id`。`/tool` 让用户绕过模型直接跑一个工具，是排查问题的快通道。

**对话历史持久化。** 之前关掉面板对话就没了。现在落盘到 `agent-history.json`，保留最近 200 条，每条消息右键可复制或删除，顶部按钮一键清空。喂给模型的上下文截取最近 24 条，避免长对话把 token 打爆。

**全局热键 ⌥⌘A。** 不管当前在哪个 app，按一下就弹出 Agent 面板并聚焦输入框。用 Carbon 的 `RegisterEventHotKey` 而不是 `NSEvent` 全局监听 —— 后者要辅助功能权限，对菜单栏工具太重。handler 里用 signature（"CAGR"）+ id 双重校验，避免误吞剪贴板快捷粘贴的 slot 0–8。

**工具浏览器。** 状态栏的网格按钮打开工具列表，按权限分组（只读 / 可撤销 / 需确认 / 危险），可搜索。点进去是按工具 JSON Schema 自动生成的表单 —— 布尔变开关、枚举变下拉、整数变数字框、其余变文本框。填完点运行，结果直接显示并可复制。超过当前权限等级的工具显示锁图标且不能运行；L2 及以上的运行按钮需要点两次（第一次变成"确认执行（会写入）"）。这是"选择工具 → 使用功能"那条链路的落点，也是排查"为什么模型没调某个工具"最快的地方。

对应新增文件：`AgentRecipe.swift`、`AgentCommand.swift`、`AgentHistoryStore.swift`、`AgentQuickAccess.swift`、`AgentToolsBrowser.swift`、`SchemaFormView.swift`。

## 11.3 双版本分发（已完成）

用户要两个安装包，但**不能是功能残缺版**。做法是两个版本共用同一份代码和 bundle id，唯一区别是 `.app` 里有没有内置 Agent 运行时：

| | CoolRun Lite | CoolRun Full |
|---|---|---|
| dmg 体积 | 约 8 MB | 约 100 MB |
| Agent 能力 | 完整（12 只读 + 7 写入工具） | 完整，且额外可用 DSH 引擎 |
| 首次使用 | 下载运行时（约 90 MB）后可用 | 装好即用，断网也行 |
| 适用 | 大多数用户 | 离线环境 / 想要 DSH 全套能力 |

版本判断不靠编译开关，而是运行时看 `Contents/Resources/AgentRuntime/deepseek-harness-sdk-runtime` 是否存在且可执行（`CoolRunEdition.current`）。这样打包脚本只需要决定拷不拷运行时，不需要第二个 Xcode target。

打包：

```bash
./scripts/create-dmg.sh --lite          # 出 CoolRun-Lite.dmg
./scripts/create-dmg.sh --full          # 出 CoolRun-Full.dmg（自动下载并塞入运行时）
```

`scripts/prepare-agent-runtime.sh` 负责从 PyPI 拉 wheel（缓存在 `.build/AgentRuntime`）、解包、拷进 app、重新做 ad-hoc 签名。签名必须逐文件做，`--deep` 会破坏 pkg 内置运行时的 ad-hoc 签名 —— 本地分发无碍，但上公证前要改。

---

## 12. DSH 引擎接入实测（P2 完成）

### 12.1 双引擎

设置里「引擎」一栏可在两者间切换，切完立刻生效（旧进程会 shutdown）：

| 引擎 | 体积成本 | 依赖 | 适用 |
|---|---|---|---|
| 原生 Swift | 0 | 无 | 默认。四种协议 + 工具循环 + 确认闸门 |
| DeepSeek Harness | 约 300 MB | 内置运行时或联网下载 | 需要 DSH 的多步任务、子代理、skill 等能力 |

原生引擎是默认值，因为它是这个 app 的主线；DSH 是可选的「重引擎」。

### 12.2 DSH 侧是怎么接进来的

```
CoolRun (Swift)
  ├─ DSHAgentEngine ──spawn──> dsh (单文件运行时)
  │     JSON-RPC over stdio（initialize / session/prompt / session/wait / shutdown）
  │
  └─ CoolRunMCPHost <──HTTP(127.0.0.1)── dsh 的 mcp-client
        工具由 ToolRegistry 提供，权限等级照样生效
```

关键点：

- **配置靠 `--patch` 注入，不改 DSH 源码**。生成的 `coolrun.patch.yml` 在
  `~/Library/Application Support/CoolRun/agent-home/`，里面声明自定义 provider
  （`llm-pi-ai`，可指 openai-completions / openai-responses / anthropic-messages）
  和 `mcp-client`（指向本机的 CoolRunMCPHost）。
- **patch 有两种写法，别混**：`- insert:` 是新增配置行；顶层 `- id: xxx` 是覆盖
  已有行，写一个不存在的 id 会直接报 `patch: entry "xxx" not found`。`mcp-coolrun`
  必须用 insert，因为 sdk-minimal 里没有它。
- **必须关掉 DSH 自带的 shell / 文件工具**：`persistent-bash`、`terminal-bash`、
  `terminal-pwsh` 三行在 patch 里覆盖成 `disabled: true`。否则模型能在用户不知情的
  情况下执行命令，而 CoolRun 的权限闸门管不到 DSH 内置工具。
- **必须注入两个环境变量**：`DSH_HOME`（指向 app 自己的目录，别污染 `~/.dsh`）和
  `PKG_NATIVE_CACHE_PATH`（pkg 打包的 native binding 解压目录，缺了会报
  `No usable native binding found for node-addon-require-builtin-darwin-arm64`）。
- **事件流没有增量 chunk**：文本一次性出现在 `assistant/message` 里，不是逐字推。
  所以 DSH 引擎下是「整段出现」而不是打字机效果；`turn/end` 不代表结束（多轮工具
  调用还会继续），只有 `session.status == idle` 才算一轮完成。
- **工具结果不回传**：DSH 自己执行工具，我们只能看到 `tool-call` 块。为了让 UI 的
  工具卡片能收尾，收到 `tool-call` 时记下 id，下一条 `assistant/message` 到来时补发
  `toolCallFinished`。

### 12.3 实测结果

用本地网关（`openai-completions`）+ 真实模型，问「查一下现在金价，并告诉我今天电脑
内存占用情况」，模型一轮里并行调了两个工具：

```
assistant/message step 1
  content: [reasoning, {type:"tool-call", name:"mcp__coolrun__gold_price"},
                       {type:"tool-call", name:"mcp__coolrun__system_snapshot"}]
assistant/message step 2
  reasoning: "price 871.44 CNY/g, unchanged ... Memory 31.62 ..."
turn/end completed → session.status idle
```

即 模型 → DSH → MCP → ToolRegistry → 真实系统数据 → 回答，全链路通。

### 12.4 打包

```bash
./scripts/create-dmg.sh --lite    # CoolRun-Lite.dmg   约 8.6 MB，原生引擎
./scripts/create-dmg.sh --full    # CoolRun-Full.dmg   约 100 MB，内置 DSH 运行时
```

`--full` 会先跑 `scripts/prepare-agent-runtime.sh`：查 PyPI 最新版 → 下载 wheel →
解包 → 只把 `deepseek-harness-sdk-runtime*` 三个文件放进
`CoolRun.app/Contents/Resources/AgentRuntime/` → ad-hoc 重签名。

两个脚本都优先使用 `.build/DerivedData/Build/Products/Release/CoolRun.app`，找不到
才回退到导出的时间戳目录 —— 否则很容易把旧包打进 dmg。

### 12.5 已知限制

- **弱模型会降级**：`qwen2.5:0.5b` 这类小模型会把工具调用写成 JSON 文本而不是
  `tool_calls` 字段。原生引擎暂时不做兜底解析（做了容易误判），换 7B 以上模型即可。
- **DSH 引擎下工具卡片是「已完成」占位**，看不到真实输出，因为结果在 DSH 进程内部。
- **测试环境**：本机 `xcodebuild test` 会卡在 `RegisterWithLaunchServices`，所以近期
  改动只做了编译验证与手工联调，单元测试待环境恢复后补。
- **Release 构建的编译器坑**：Swift 6.3.3 在 `-O` 下对「泛型类 + weak 存储属性」的
  自动 deinit 做 EarlyPerfInliner 时会段错误。已改成闭包弱捕获避开，代码里
  `DSHJSONRPCClient` 用 `[unowned self]` 是因为 `stop()` 会清空 handler。
