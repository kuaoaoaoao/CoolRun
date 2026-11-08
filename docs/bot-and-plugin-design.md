# CoolRun 扩展设计：机器人宿主 · 插件系统 · 桌宠

> 状态：方案草案（P1 之后的路线）
> 关联：[agent-engine-design.md](agent-engine-design.md)

## 1. 目标与边界

用户设想：把 AstrBot 一类的机器人框架接进 CoolRun，让菜单栏软件同时是「AI 助手 + 虚拟机器人控制台」，能接 QQ / 微信，能在软件内操作，也能开 Web 页配置，还能装插件、养桌宠。

这一层要解决的核心矛盾是**体积与能力**：

- CoolRun 现在是 8 MB 的原生 Swift 应用，启动即用。
- AstrBot 是 Python 服务，依赖树 + 浏览器自动化 + 数据库，实打实几百 MB，还要 Docker 或独立 Python 环境。

**结论先说：不把机器人内核编译进 CoolRun，而是做成"可选侧车 + 宿主面板"。** 这与 Agent 引擎的路线一致——轻的部分自己写，重的部分按需挂载。

## 2. 三条架构路线

### 路线 A：内嵌 Python（打包 AstrBot 进 app）

用 PyInstaller 把 AstrBot 打成单文件，塞进 `Contents/Resources/`。

| 维度 | 结果 |
| --- | --- |
| 体积 | +250～400 MB，dmg 从 8 MB 涨到 300 MB+ |
| 启动 | 冷启动 5～15 s，菜单栏 app 无法接受 |
| 维护 | AstrBot 升级要重新打包，与上游版本强耦合 |
| 收益 | 开箱即用 |

**否决。** 为了一个"可选功能"把主力软件变成 300 MB，性价比不成立。

### 路线 B：宿主面板（管理外部实例）✅ 推荐主线

CoolRun 不内嵌机器人运行时，只做「控制台」：

```
CoolRun（Swift）
   ├── Bot 宿主面板：检测 / 安装 / 启动 / 停止 / 看日志 / 健康检查
   ├── WKWebView：直接嵌入 AstrBot 自带 WebUI
   └── HTTP 桥：调 AstrBot 的 API（发消息、查状态、改配置）
        ↓
AstrBot 实例（外部进程，用户自己的 Python/Docker 环境）
        ↓
NapCat / Lagrange（QQ 协议端）· 微信适配器 · Telegram · Discord
```

优点：体积 +0，CoolRun 只加几 MB 的面板与桥接代码；AstrBot 怎么升级都不影响 app。

代价：用户得先有 AstrBot 环境。缓解办法是「一键安装」——面板里检测到没有就引导，把 `docker compose up -d` 这类步骤包装成按钮，进度条 + 日志。

### 路线 C：Swift 原生极简 Bot 内核

不依赖 Python，Swift 直接实现 OneBot v11 的**反向 WebSocket 客户端**，连 NapCat 这类协议端。

| 维度 | 结果 |
| --- | --- |
| 体积 | +0.5 MB（URLSessionWebSocketTask 是系统自带的） |
| 能力 | 收发群/私聊消息、图片、@、撤回；没有插件市场、没有多平台 |
| 依赖 | 仍需外部跑一个协议端（NapCat），但那个是 Node 单文件，比 Python 栈轻得多 |

适合「我只想在菜单栏里有个自己的 QQ 小助手」这种个人场景。

**推荐组合：B 做主线（功能完整），C 做轻量选项（不想装 Python 的人）。**

## 3. QQ / 微信接入的现实约束

这一节必须写清楚，因为它是整个设想里风险最高的部分。

### QQ

- 官方没有开放个人号 API。
- 社区方案是协议端（NapCat、Lagrange.Core、go-cqhttp 已停更），它们本身也是非官方实现。
- OneBot v11 是事实标准，CoolRun 只需实现客户端，协议端由用户自己承担风险。
- **可行，但要明示：账号风控风险由用户承担。**

### 微信

- 官方无个人号 API（企业微信有，但那是另一回事）。
- 社区方案（wechaty 的 iPad 协议、hook 注入）**明确违反微信用户协议，封号概率高**，且部分方案需要付费 token。
- **建议：默认不提供，只在文档里说明「企业微信机器人 Webhook」这条合规路径。**

合规可做的微信形态：企业微信群机器人 Webhook —— 只能往群里推消息，不能读消息、不能私聊。作为「通知出口」够用。

### 结论

| 平台 | 路径 | 合规性 | 默认 |
| --- | --- | --- | --- |
| QQ | OneBot v11 + 用户自备协议端 | 灰色，用户自担 | 可选开启 |
| 企业微信 | 群机器人 Webhook | 合规 | 可选 |
| 个人微信 | — | 违规 | **不提供** |
| Telegram / Discord | 官方 Bot API | 合规 | 可选 |

## 4. 插件系统

CoolRun 自己的插件，与 AstrBot 插件是两回事。

### 4.1 为什么用 JavaScriptCore

- macOS 系统自带，零依赖零体积。
- 沙箱可控：JSContext 默认拿不到文件系统、网络、进程。
- 上手门槛低，用户能自己写。

Swift 插件（编译进 app）作为「官方扩展」的通道，不做第三方分发。

### 4.2 插件包结构

```
MyPlugin.coolplugin/          ← 就是个文件夹，.coolplugin 后缀
├── manifest.json
├── main.js
└── assets/…
```

```json
{
  "id": "com.example.weather",
  "name": "天气提醒",
  "version": "1.0.0",
  "author": "…",
  "minAppVersion": "1.4.0",
  "permissions": ["notify", "schedule", "net"],
  "contributes": {
    "tools": ["weather_now"],
    "panels": ["weather-panel"],
    "commands": ["/weather"]
  }
}
```

### 4.3 权限模型

直接复用 Agent 的 L0–L3 分级，插件声明所需权限，安装时逐项展示：

| 权限 | 能力 | 对应 Agent 等级 |
| --- | --- | --- |
| `read` | 读系统/金价/笔记等只读数据 | L0 |
| `notify` | 发通知 | L1 |
| `clipboard` | 读写剪贴板 | L1 |
| `net` | 发起 HTTP 请求（域名白名单） | L1 |
| `storage` | 插件私有目录读写 | L2 |
| `write` | 写笔记/提醒/设置 | L2 |
| `shell` | 执行命令 | L3，默认拒绝 |

### 4.4 插件能贡献什么

1. **工具** —— 注册成 Agent 工具，模型可以直接调用（这是最有价值的一条）
2. **面板** —— 一个 SwiftUI 视图宿主，插件提供 HTML/JS 渲染
3. **命令** —— Bot 聊天里的 `/command`
4. **定时任务** —— 注册 cron 表达式，到点跑 JS 函数

### 4.5 宿主实现要点

```swift
@MainActor
final class PluginHost {
    private var contexts: [String: JSContext] = [:]

    func load(_ bundle: PluginBundle) throws {
        let context = JSContext()!
        context.exceptionHandler = { _, error in … }
        // 只注入白名单 API，其余一律 undefined
        inject(Console.self, into: context)     // console.log
        inject(HTTPClient(allowlist: bundle.netAllowlist), into: context)
        inject(Storage(path: bundle.dataDirectory), into: context)
        inject(ToolBridge(registry: .shared), into: context)
        context.evaluateScript(bundle.mainScript)
        try context.callFunction("activate")
    }
}
```

关键约束：
- 每次调用设超时（JSContext 没有原生超时，用 `JSContextGroupSetExecutionTimeLimit`）。
- 插件崩溃只影响自己，不拖垮 app。
- 所有工具调用同样进审计日志。

## 5. 桌宠

### 5.1 形态

独立 `NSPanel`，不是菜单栏 popover：

```swift
let panel = NSPanel(
    contentRect: CGRect(x: 0, y: 0, width: 160, height: 160),
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)
panel.level = .floating          // 浮在普通窗口之上
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = false
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
```

### 5.2 动画

- 序列帧：`Assets.xcassets` 里放 spritesheet，用 `TimelineView` 或 `CADisplayLink` 驱动。
- 状态机：`idle` / `walk` / `talk` / `drag` / `sleep`。
- 与 Agent 联动：`isRunning` → 切到 `talk` 并冒气泡；空闲 5 分钟 → `sleep`。

### 5.3 交互

- 拖拽：`NSPanel.isMovableByWindowBackground = true`
- 点击穿透开关：`ignoresMouseEvents`
- 右键菜单：隐藏 / 切换角色 / 打开设置
- 记住位置：`NSScreen` 坐标系落盘

### 5.4 素材

可以用 `2dcs` 技能生成一套 3:2 绿幕的角色帧，再抠图成透明 PNG。

## 6. Web 配置页

两条路：

1. **嵌入 AstrBot 自带 WebUI**（推荐）—— `WKWebView` 加载 `http://127.0.0.1:6185`，CoolRun 只负责起停与登录态。
2. **CoolRun 自建配置页** —— 只暴露高频项（启用哪些平台、绑哪个模型、开哪些插件），底层还是调 AstrBot API。

推荐 1 + 2 组合：主界面用 WKWebView，顶部加一条 CoolRun 自己的状态栏（实例是否在跑、消息吞吐、最近错误）。

注意：WKWebView 加载 localhost 需要在 entitlements 里保留 `com.apple.security.network.client`（已有）。

## 7. 与现有 Agent 的关系

这是设计上最省事的一点：**机器人就是 Agent 的另一个前端。**

```
                 ┌──────────────┐
  菜单栏面板 ───→ │              │
  QQ / TG 消息 ──→│ AgentCoordinator │──→ ToolRegistry（同一套工具）
  定时任务 ─────→ │              │
                 └──────────────┘
```

- QQ 里收到「今天 CPU 怎么样」→ 转成 `AgentCoordinator.send()` → 走同一套工具 → 回复回 QQ。
- 权限闸门同样生效：L2 工具在 QQ 场景下默认拒绝（没人能点确认），只允许 L0/L1。
- 审计日志统一。

## 8. 分阶段与工作量

| 阶段 | 内容 | 预估 |
| --- | --- | --- |
| P2-Bot-1 | Bot 宿主面板：检测 Docker/进程、启停、日志流、WKWebView 嵌 WebUI | 1～1.5 周 |
| P2-Bot-2 | HTTP 桥：消息转发到 AgentCoordinator、回发、状态卡片 | 1 周 |
| P2-Bot-3 | Swift OneBot v11 客户端（反向 WS）：连 NapCat、收发消息、@、图片 | 1.5～2 周 |
| P3-Plugin-1 | 插件包格式 + JSCore 宿主 + 权限声明 + 工具贡献 | 2 周 |
| P3-Plugin-2 | 插件市场（本地目录 + 远程索引）、安装/卸载/更新 UI | 1 周 |
| P3-Pet | 桌宠窗口 + 状态机 + Agent 联动 + 素材 | 1 周 |

合计约 8～9 周。建议顺序：**Bot 宿主 → 桌宠 → 插件**（桌宠最快见效，插件最费工）。

## 9. 体积影响

| 功能 | dmg 增量 |
| --- | --- |
| Bot 宿主面板 + WKWebView | +0.3 MB（WKWebView 是系统框架） |
| Swift OneBot 客户端 | +0.2 MB |
| 插件宿主（JSCore） | +0.1 MB |
| 桌宠 | +1～3 MB（取决于素材） |
| **合计** | **+2～4 MB** |

依然是个位数 MB 的 app。AstrBot 本体不进包。

## 10. 待确认

1. **「Snow 项目」具体指哪个？** 如果是另一个机器人框架，需要确认它是否有 HTTP/WS API，以及能否像 AstrBot 一样外置运行。
2. 桌宠角色形象：用现有的「蓝色大肥鱼」还是另做？
3. 插件是否需要远程市场（涉及审核与签名），还是先只支持本地安装。
