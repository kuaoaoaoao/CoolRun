# CoolRun 项目审核与优化报告

> 审核时间：2026-10-30 · 代码量：96 Swift 文件 · ~39,400 行 · macOS 15.0+

---

## 一、总体评价

CoolRun 是一个**完成度很高的 macOS 菜单栏工具**，将系统监控、金价分析、日历、英语学习、AI 配额查看、备忘录、剪贴板和 Mac 诊断整合在 336×528 的弹窗面板中。隐私优先、本地存储、零第三方依赖（除 PostHog 可选）的设计理念值得肯定。

**核心优势：**
- 黄金分析模块是项目最成熟的部分，包含技术指标、市场状态识别、蒙特卡洛模拟、周预测+回测闭环，纯 Swift 实现，可解释可复盘
- 隐私设计极为严谨：PostHog 多层脱敏、敏感字段拦截、默认关闭
- 系统采样直接用 Darwin/IOKit/SMC 底层 API，不依赖第三方库
- 26 个测试文件覆盖了关键分析引擎和诊断功能
- 支持 4 语言（中英日韩），国际化基础扎实

---

## 二、审核发现

### 2.1 架构问题

| 问题 | 严重度 | 说明 |
|------|--------|------|
| **扁平文件结构** | 中 | 96 个 Swift 文件全部在 `CoolRun/` 一层目录，无子目录分组。CLAUDE.md 明确说这是约定，但随着文件增长到 96 个，可维护性已受影响 |
| **超大文件** | 高 | `GoldAnalysisView.swift` 3,432 行、`SettingsView.swift` 2,102 行、`ContentView.swift` 1,901 行。单文件承载过多职责 |
| **ViewModel 模式不统一** | 中 | 部分用 `@Observable` 宏（SystemMonitorViewModel），部分用 `ObservableObject`（AppSettings、AppNavigationRouter）。反映渐进式升级但没有统一 |
| **Singleton 滥用** | 中 | `AppSettings.shared`、`AppNavigationRouter.shared`、`EnglishProgressStore.shared`、`GoldPriceStore.shared` 等大量单例，耦合度高，测试隔离困难 |
| **CLAUDE.md 过时** | 低 | 文档仍描述"系统监控+金价"两模块，实际已有 9 模块。架构说明未更新 |

### 2.2 设计与美观问题

| 问题 | 说明 |
|------|------|
| **面板尺寸固定 336×528** | 在黄金分析这种信息密集模块中，空间极为局促。3,432 行 UI 代码挤在 528px 高度内，大量折叠/展开交互 |
| **导航栏图标过小** | 11pt 字号在 Retina 屏上偏小，辨识度一般 |
| **模块间视觉不统一** | 各模块独立开发，卡片样式、间距、配色未完全统一 |
| **深色模式适配不完整** | 毛玻璃效果在 dark/light 下用不同 material（`.hudWindow` vs `.menu`），但部分子视图的颜色硬编码 |

### 2.3 实用性问题

| 问题 | 说明 |
|------|------|
| **无全局搜索** | 9 个模块间的数据无法统一搜索（如搜"黄金"应同时展示金价、交易记录、预测） |
| **无快捷键直达** | 有 Cmd+0~8 切模块，但无全局唤出面板的快捷键 |
| **黄金模块信息过载** | 一个弹窗里塞了实时价格、技术指标、交易信号、市场状态、宏观新闻、事件影响、预测复盘、周预测、持仓建议。新手会被淹没 |
| **备忘录/剪贴板功能基础** | 与专业工具（如 Paste、Memos）相比功能较薄 |

### 2.4 可拓展性问题

| 问题 | 说明 |
|------|------|
| **无插件/模块注册机制** | 新增模块需要改 `ViewMode` 枚举、`ContentView` switch、`AppSettings` 可见性配置、导航栏，改动面大 |
| **数据层无抽象** | UserDefaults key 硬编码字符串散落在 AppSettings 中（1,347 行），无统一 key 管理 |
| **无 SQLite** | 价格历史、预测记录、交易流水用 JSON 文件存储，数据量增长后性能和查询能力受限 |
| **跨平台端口停滞** | `coolrun-windows/`（Tauri）和 `coolrun-avalonia/` 均未跟进功能 |

---

## 三、优化建议

### 3.1 架构重构（按优先级排序）

#### P0：文件拆分与目录分组

建议将 96 个扁平文件按功能分组：

```
CoolRun/
├── App/                    # 入口与生命周期
│   ├── CoolRunApp.swift
│   ├── MacAppDelegate.swift
│   └── AppSettings.swift
├── Modules/
│   ├── Monitor/            # 系统监控
│   ├── Gold/               # 黄金分析（当前最大的模块）
│   ├── Calendar/
│   ├── English/
│   ├── AIQuota/            # Codex/Claude 配额
│   ├── Notes/
│   ├── Clipboard/
│   ├── Diagnostics/
│   └── Shelf/              # 菜单栏整理
├── Core/                   # 共享基础设施
│   ├── Theme.swift         # AppTheme 颜色系统
│   ├── LocalizedString.swift
│   ├── Analytics.swift
│   ├── CloudSyncStore.swift
│   └── LocalReminderCenter.swift
├── Models/                 # 纯值类型
└── Views/                  # 共享 UI 组件
```

`GoldAnalysisView.swift`（3,432 行）应拆为：
- `GoldAnalysisView.swift` — 主容器与标签切换
- `GoldTechnicalView.swift` — 技术指标卡片
- `GoldSignalView.swift` — 交易信号展示
- `GoldMacroView.swift` — 宏观新闻与事件影响
- `GoldPredictionView.swift` — 预测复盘
- `GoldPortfolioView.swift` — 持仓建议
- `GoldWeeklyForecastView.swift` — 周预测

`SettingsView.swift`（2,102 行）应按设置分类拆分。

#### P1：模块注册协议

```swift
protocol AppModule: View, Sendable {
    static var mode: ViewMode { get }
    static var icon: String { get }
    static var displayName: String { get }
    static var defaultVisible: Bool { get }
    static var keyboardShortcut: KeyEquivalent { get }
}
```

将 `ViewMode` 枚举的 switch 替换为协议注册，新增模块只需实现协议 + 注册，无需改核心文件。

#### P2：统一 ViewModel 模式

全面迁移到 `@Observable` 宏（需要 macOS 14+，当前目标 15.0 已满足）。将 `AppSettings` 从 `ObservableObject` 迁移到 `@Observable`，统一数据流。

#### P3：引入 SQLite

当价格历史超过 1,000 条、预测记录持续积累时，引入 SQLite（SwiftData 或 GRDB）替代 JSON 文件。保留 JSON 作为导出格式。

### 3.2 UI/UX 优化

#### 面板自适应

```swift
// 当前：固定尺寸
popover.contentSize = NSSize(width: 336, height: 528)

// 建议：根据模块和内容自适应
let size = currentModule.preferredPanelSize
// Monitor: 336×528（紧凑）
// Gold: 420×640（展开分析）
// Diagnostics: 480×600（报告式）
```

#### 黄金模块信息分层

将黄金模块改为三标签：
1. **速览** — 当前价格、涨跌、核心信号、持仓盈亏
2. **分析** — 技术指标、市场状态、宏观新闻
3. **复盘** — 预测记录、周预测、回测结果

#### 全局搜索

添加 Cmd+Shift+F 全局搜索，结果聚合所有模块：
- 搜"825" → 金价记录 + 交易记录
- 搜"CPU" → 监控快照 + 诊断报告
- 搜单词 → 英语学习记录 + 备忘录

### 3.3 性能优化

| 优化项 | 说明 |
|--------|------|
| 金价轮询合并 | 当前 1s 间隔过于频繁，建议默认 5s，仅在用户激活面板时降到 1s |
| 进程采样缓存 | `ProcessSampler` 每次全量扫描进程列表，建议增量更新 |
| Sparkline 渲染 | 60 个数据点的折线图用 Path 手绘，可考虑缓存为 Image |
| iCloud 同步节流 | 当前每次变更都写 KVS，建议批量+延迟同步 |

---

## 四、LLM 集成方案

**可以加，而且非常适合。** CoolRun 已有的数据天然适合 LLM 增强。以下是分阶段落地方案：

### 4.1 集成定位

LLM 不是独立聊天机器人，而是**贯穿各模块的智能助手层**：

```
用户提问 → 路由到对应模块数据 → LLM 基于真实数据生成回答 → 展示来源
```

### 4.2 第一阶段：对话式查询（最小可用）

新增第 10 个模块 **AI 助手**（`.ai` ViewMode），功能：

1. **自然语言查询系统状态**
   - "我的 CPU 占用多少？哪些进程在吃资源？"
   - 数据来源：SystemSampler 实时快照 + 进程列表

2. **自然语言查询金价**
   - "金价现在多少？该不该买？"
   - 数据来源：GoldPriceStore + GoldAnalysisEngine 的信号
   - LLM 负责将信号翻译成人话，**不自行生成投资建议**

3. **自然语言查询 AI 配额**
   - "我的 Codex 还能用多少？什么时候重置？"
   - 数据来源：CodexMonitor + ClaudeMonitor

4. **剪贴板/备忘录智能整理**
   - "帮我整理今天的剪贴板内容"
   - 数据来源：ClipboardHistoryStore

### 4.3 第二阶段：智能增强

5. **黄金新闻摘要**
   - `GoldMarketIntelligenceService` 已经在抓 Google News RSS
   - LLM 对新闻标题做事件归因、影响判断（roadmap 已提到这个方向）
   - **必须保留原始新闻链接和关键词作为证据**

6. **诊断报告解读**
   - SleepDiagnostics / NetworkDiagnostics 的输出是技术性的
   - LLM 翻译为"你的 Mac 昨晚被 X 进程阻止睡眠 3 次，建议..."

7. **英语学习对话**
   - 当前是单向词汇播放
   - LLM 可做造句、释义、对话练习

### 4.4 技术架构

```swift
// 协议层 — 支持多 Provider
protocol LLMProvider: Sendable {
    func complete(messages: [LLMMessage], model: String?) async throws -> String
    var displayName: String { get }
}

// Provider 实现
struct OpenAIProvider: LLMProvider { ... }       // GPT-4o
struct AnthropicProvider: LLMProvider { ... }     // Claude
struct LocalProvider: LLMProvider { ... }         // Ollama / MLX
struct CloudServiceProvider: LLMProvider { ... }  // WorkBuddy cloud-service 免密钥调用

// 工具函数 — 将模块数据转为 LLM context
struct LLMContextBuilder {
    static func systemContext(_ snapshot: SystemSnapshot) -> String
    static func goldContext(_ store: GoldPriceStore, _ engine: GoldAnalysisEngine) -> String
    static func aiQuotaContext(_ codex: CodexMonitorViewModel, _ claude: ClaudeMonitorViewModel) -> String
}
```

### 4.5 关键设计原则

| 原则 | 说明 |
|------|------|
| **本地数据优先** | LLM 只接收已采集的结构化数据做摘要/翻译，不自行编造数字 |
| **保留证据** | 黄金新闻摘要必须附原始链接和关键词，与现有 `GoldNewsClassifier` 的证据链一致 |
| **免责声明** | 任何涉及金价的 LLM 回答必须附"仅供参考，不构成投资建议" |
| **API Key 安全** | Key 存储在 Keychain（不是 UserDefaults），用户自备 |
| **可选多 Provider** | 支持用户自带 API Key（OpenAI/Anthropic）或本地模型（Ollama） |
| **成本控制** | 系统状态查询可先用模板引擎判断是否需要调 LLM，简单查询直接格式化返回 |
| **隐私延续** | 不向 LLM 发送用户身份信息、持仓金额等敏感字段（与 PostHog 脱敏策略一致） |

### 4.6 推荐实现路径

1. **Step 1**：创建 `LLMProvider` 协议 + `LLMService` 单例 + 设置页 API Key 配置
2. **Step 2**：新增 `AIAssistantView.swift`，实现对话 UI + context 注入
3. **Step 3**：接入 OpenAI（最通用），后续加 Anthropic 和 Ollama
4. **Step 4**：为黄金新闻摘要做 LLM 增强（与 `GoldNewsClassifier` 配合）
5. **Step 5**：诊断报告自然语言解读

---

## 五、优先级路线图

```
P0（立刻做）
├── 拆分 GoldAnalysisView.swift（3,432 → 6 个文件）
├── 拆分 SettingsView.swift（2,102 → 4 个文件）
└── 更新 CLAUDE.md 架构文档

P1（近期做）
├── 文件目录分组（96 文件 → Modules/ 结构）
├── LLM 助手模块 MVP（对话查询系统/金价/AI配额）
└── 面板尺寸自适应

P2（中期做）
├── 模块注册协议（降低新增模块成本）
├── 全局搜索（Cmd+Shift+F）
├── 黄金新闻 LLM 摘要
└── 统一 @Observable 模式

P3（长期做）
├── 引入 SQLite/SwiftData
├── 诊断报告 LLM 解读
├── 英语学习对话模式
└── 插件系统设计
```

---

## 六、总结

CoolRun 是一个**工程质量和产品设计都相当出色**的个人项目。黄金分析模块的深度（技术指标、蒙特卡洛、回测闭环）在菜单栏工具中极为罕见。隐私设计比很多商业软件都更严谨。

主要瓶颈在于：
1. **超大文件**拖慢开发和维护
2. **固定面板尺寸**限制了信息密集模块的可用性
3. **无 LLM 集成**——而项目已有的丰富数据源（系统状态、金价分析、诊断报告）天然适合 LLM 增强

LLM 集成完全可行，建议从"对话式查询已有数据"这个最小场景切入，而非做通用聊天机器人。项目已有的结构化数据 + LLM 的语言能力 = 真正有用的桌面 AI 助手。
