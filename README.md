# CoolRun

[![macOS CI](https://github.com/kuaoaoaoao/CoolRun/actions/workflows/build-macos.yml/badge.svg)](https://github.com/kuaoaoaoao/CoolRun/actions/workflows/build-macos.yml)
[![PolyForm Noncommercial License](https://img.shields.io/badge/license-PolyForm%20Noncommercial%201.0.0-orange.svg)](LICENSE)

CoolRun 是一款原生 macOS 菜单栏效率工具，把系统监控、Mac 诊断、实时金价、日历倒数日、备忘录、剪切板历史、英语学习和 AI 额度放进一个轻量悬浮窗。

它默认常驻菜单栏，不占 Dock，也不会打扰你正在做的事。菜单栏上可以显示金价、日期、系统状态、英语内容、最近倒数日或 Codex/Claude 剩余额度；左键点开悬浮面板就能查看全部内容，面板还能固定，适合边工作边瞄一眼数据或学两个单词。

面板顶部有 9 个功能模块可以切换，**默认只显示监控、金价、日历、剪切板四个**，其他模块在「设置 → 通用 → 面板模块」里按需打开，界面清清爽爽。

![CoolRun 动态演示](docs/images/CoolRunShowDemo.gif)

官网：[kuaoaoaoao.github.io/CoolRun](https://kuaoaoaoao.github.io/CoolRun/) ｜ 下载：[GitHub Releases](https://github.com/kuaoaoaoao/CoolRun/releases)

## 它能做什么

- **系统监控**：CPU、内存、储存、电池、网络、温度、运行时间和进程排行，一眼看清 Mac 状态。
- **金价分析**：浙商银行积存金实时价格、历史走势、技术指标，并用大白话给出新手结论。
- **个人持仓**：输入克数和买入均价，自动算成本、市值、浮盈浮亏，并给出分批补仓或止盈建议。
- **日历与生日**：内置日历、农历、节假日调休，支持生日管理和公历/农历倒数日。
- **今天与提醒**：把系统健康、倒数日、生日、英语打卡和 AI 额度按紧急程度汇总排序，重要事项直接跳转。
- **备忘录与剪切板**：支持分组、搜索、固定的本地备忘录，以及纯文本剪切板历史。
- **英语学习**：内置日常、小学到 TOEFL 等分级词汇与短文，记录掌握度和连续学习天数，用系统语音朗读。
- **AI 额度**：统一展示 Codex 与 Claude Code 的剩余比例、重置时间和使用节奏。
- **Mac 诊断**：排查睡眠耗电、逐层检测网络、分析 System Data 占用，并安全清理高置信度应用残留。
- **菜单栏自定义**：菜单栏可显示单项、双项组合或定时轮播，金币图标支持 5 种动作和 5 种外观。

## 适合你如果

- 你想把金价固定在 macOS 菜单栏里，随手看一眼。
- 你想知道 Mac 当前是不是高负载、内存是否紧张、温度是否偏高。
- 你想排查 Mac 为什么睡不着、网络哪一层异常，或 System Data 为什么变大。
- 你想要一个小白也能看懂的金价分析面板，而不只是技术指标。
- 你同时使用 Codex 或 Claude Code，希望随手查看额度和重置时间。
- 你想把考试、纪念日等公历或农历日期固定在菜单栏。
- 你喜欢小巧、原生、不会占 Dock 的菜单栏工具。
- 你想参考一个 SwiftUI + AppKit 的 macOS 菜单栏应用实现。

## 界面预览

<table>
  <tr>
    <td align="center">
      <img src="docs/images/menu-popover-monitor.png" width="300" alt="菜单栏悬浮窗">
      <br>
      <sub>菜单栏悬浮窗</sub>
    </td>
    <td align="center">
      <img src="docs/images/money.png" width="260" alt="菜单栏金价">
      <br>
      <sub>菜单栏金价</sub>
    </td>
  </tr>
  <tr>
    <td align="center">
      <img src="docs/images/gold-analyze.png" width="300" alt="金价分析">
      <br>
      <sub>金价分析</sub>
    </td>
    <td align="center">
      <img src="docs/images/dark-main.png" width="300" alt="深色主界面">
      <br>
      <sub>深色主界面</sub>
    </td>
  </tr>
  <tr>
    <td align="center">
      <img src="docs/images/calendar.png" width="300" alt="日历">
      <br>
      <sub>日历</sub>
    </td>
    <td align="center">
      <img src="docs/images/settings-monitor.png" width="300" alt="设置页面">
      <br>
      <sub>设置页面</sub>
    </td>
  </tr>
  <tr>
    <td align="center">
      <img src="docs/images/feature-notes.png" width="300" alt="分组备忘录">
      <br>
      <sub>分组备忘录</sub>
    </td>
    <td align="center">
      <img src="docs/images/feature-clipboard.png" width="300" alt="剪切板历史">
      <br>
      <sub>剪切板历史</sub>
    </td>
  </tr>
  <tr>
    <td align="center">
      <img src="docs/images/feature-english.png" width="300" alt="英语学习">
      <br>
      <sub>英语学习</sub>
    </td>
    <td align="center">
      <img src="docs/images/feature-ai.png" width="300" alt="AI 额度">
      <br>
      <sub>AI 额度</sub>
    </td>
  </tr>
</table>

## 安装

### 从 GitHub Releases 安装

1. 打开 [GitHub Releases](https://github.com/kuaoaoaoao/CoolRun/releases)。
2. 下载最新的 `CoolRun.dmg`，双击打开。
3. 将 `CoolRun.app` 拖入 `Applications` 文件夹。
4. 启动后，在 macOS 菜单栏找到金币图标。

> 请只从本项目的 GitHub Releases 下载安装包。

### 如果提示“文件已损坏”

如果打开 app 时提示“文件已损坏”，这是因为 CoolRun 目前未经过 Apple 公证，macOS 会阻止打开。安装后在终端执行：

```bash
sudo xattr -cr /Applications/CoolRun.app
```

执行后再打开即可。这只会移除 macOS 给下载文件添加的隔离标记，不会修改应用本身。

## 快速上手

- 左键点击菜单栏金币图标：打开或关闭悬浮面板。
- 点击图钉按钮：固定或取消固定悬浮面板，固定后可以一边使用其他应用一边查看数据。
- 面板顶部导航切换模块；想精简面板，到「设置 → 通用 → 面板模块」关掉不用的模块。
- 右键点击菜单栏金币图标：打开快捷菜单，可直接查看今天、添加倒数日、记录交易或刷新数据。
- 在 macOS“快捷指令”中搜索 CoolRun：可打开指定模块、刷新金价或控制英语播放。
- 快捷菜单中的“设置”：打开设置页面；“退出程序”：退出 CoolRun。

## GitHub Star History

[![CoolRun Star History Chart](https://api.star-history.com/svg?repos=kuaoaoaoao/CoolRun&type=Date)](https://star-history.com/#kuaoaoaoao/CoolRun&Date)

---

# 详细说明

## 功能特性

### 面板模块自定义

- 面板导航栏的 9 个功能模块（今天、监控、金价、日历、英语、Codex、备忘录、剪切板、诊断）都可在「设置 → 通用 → 面板模块」中独立开关。
- 默认只显示监控、金价、日历、剪切板；其余模块按需开启。
- 至少保留一个模块可见，最后一个模块的开关会被锁定，导航栏不会变空。
- 关闭当前正在查看的模块时会自动切换到第一个可见模块。
- 显隐配置保存在本机，并随数据备份与迁移一同导出导入。

### 菜单栏常驻

- 不占用 Dock，不打断当前工作。
- 菜单栏可显示实时金价、日期、CPU、内存、实时网速、英语内容、AI 额度或最近倒数日，并支持双项组合与定时轮播。
- 金币图标根据 CPU 占用动态加速，负载越高动作越快。
- 支持经典翻面、招财弹跳、抛金币、金币滚动和金光闪闪 5 种动作。
- 支持人民币金币、招财福币、上涨金币、方孔古钱和星光金币 5 种外观。
- 动画流畅度可以关闭，或选择节能与流畅档位。
- 左键打开悬浮面板，右键打开快捷菜单。
- 右键快捷菜单可一键查看今天、添加倒数日、记录黄金交易和刷新数据。
- 悬浮面板支持固定，固定后可以停在屏幕上继续操作其他应用。

### 系统监控

- CPU：核心数、实时占用、动态占用条、趋势图、健康状态颜色。
- 内存：已用内存、总内存、内存压力、趋势图。
- 储存：已用空间、可用空间、使用进度。
- 电池：电量、充电状态、健康度、循环次数、温度、功率和预计充放电时间。
- 网络：连接状态、本地 IP、活动接口数量、上传/下载速度。
- 温度：CPU 和 GPU 温度，通过 SMC 传感器读取。
- 运行时间：系统已运行时长。
- 进程：按 CPU 或内存排序，可合并同名进程，并在确认后结束进程。
- 点击指标可复制到剪贴板。
- 自动记录最近 7 天的本地趋势，并保留 30 天持续异常事件；高负载需连续出现才会记录，避免瞬时抖动误报。

### Mac 诊断

- 睡眠与耗电：读取 macOS 电源断言和最近 24 小时睡眠/唤醒记录，指出可能阻止休眠的进程与异常唤醒。
- 网络诊断：依次检查本地接口、默认路由、DNS、外网连通与 HTTPS，并提示 VPN 接口；不抓包、不保存浏览历史。
- System Data 洞察：只读统计缓存、日志、应用支持、容器、开发文件和设备备份，展示大目录并支持在 Finder 中定位。
- 应用残留：只列出符合严格规则的高置信度候选，删除前再次校验并要求确认，文件仅移入废纸篓；不永久删除。
- 睡眠与网络诊断只保留有上限的本地摘要；原始系统日志、完整目录清单和文件内容不会保存。

### 今天与本地提醒

- “今天”按严重程度和时间远近汇总各模块信息，重要事项优先显示，点击即可进入详情。
- 倒数日、生日、英语打卡和系统异常共用一套本地提醒设置。
- 支持提前提醒、固定时刻、跨午夜免打扰和“稍后提醒”。
- 提醒、历史和设置均使用本机存储，不依赖 iCloud 或 Apple 开发者账号。

### 备忘录与剪切板

- 备忘录支持创建、编辑、分组、搜索和固定，标题留空时会从正文首行自动生成。
- 可创建、重命名和删除自定义分组；删除分组不会删除其中内容，备忘会自动归入“未分组”。
- 剪切板记录应用启动后新复制的纯文本，重复内容会刷新到顶部而不是重复堆积。
- 剪切板支持搜索、固定、一键重新复制、逐条删除和确认后清空，最多保留 200 条。
- 支持 ⌃⌘1~⌃⌘9 在任意应用直接粘贴剪切板历史（需在设置中开启并授权辅助功能）。
- 剪切板采集可随时暂停；备忘与剪切板内容均只写入本机 Application Support，不进入匿名统计或网络请求。

### 金价分析

- 查询浙商银行积存金价格，人民币/克展示。
- 自动记录历史价格，生成最近走势。
- 支持折线图、迷你 K 线、周期切换。
- 技术指标：RSI、MACD、SMA20、波动率、支撑位、压力位。
- 交易信号：偏多、偏空、观望，以及入场、止损、止盈参考。
- 新手结论：用“可小额分批观察”“观望为主”“暂不建议买入”“不建议追买”等直白语言解释行情。
- 术语解释：把 RSI、MACD、均值回归、网格、建议仓位、买入均价、浮盈浮亏等概念写成普通人能看懂的话。
- 高级策略分析：市场状态识别、均值回归、蒙特卡洛模拟、网格区间与风险仓位。
- 一周预判：基于历史样本的滚动验证与预测复盘；预测自动校准可关闭，关闭后只观察历史表现。

### 个人持仓建议

- 输入当前持有黄金克数和买入均价。
- 自动计算成本、市值、浮盈/浮亏和收益率。
- 亏损时根据行情强弱提示是否分批补仓、如何降低均价、什么时候先观望。
- 盈利时提示继续持有、设置保本线或部分卖出锁定利润。
- 输入内容会保存在本机，下次打开仍然可见。

> 金价分析仅用于信息展示和个人记录，不构成投资建议。黄金价格可能波动，任何买卖都需要自行判断风险。

### 日历与生日

- 菜单栏面板内置日历视图。
- 支持农历显示、节假日/调休标记。
- 支持生日管理和选中日期详情。
- 支持公历/农历倒数日，并可直接为选中日期创建事件。
- 菜单栏也可切换为日期显示模式。

### AI 额度

- 统一展示 Codex 与 Claude Code 用量状态。
- 自动选择剩余最少的额度窗口作为总览重点。
- 展示剩余比例、预计重置时间和当前使用节奏。
- Codex 可查看近期本地任务；Claude 使用本机 Claude Code 登录凭据读取官方 usage 接口。
- 只在 AI 面板可见时刷新，避免后台空转和接口限频。
- 额度提醒默认关闭，用户主动开启后才请求通知权限。

### 英语学习

- 内置日常、小学、初中、高中、CET、IELTS、TOEFL 等词汇内容。
- 支持单词、句子、短文与每日内容。
- 记录学习次数、掌握程度、收藏、待复习项目和连续学习天数。
- 使用 macOS 系统语音朗读；高级用户可配置本机 Kokoro TTS。
- 英语内容也可以显示在菜单栏，连续播放时无需打开面板。

### 设置与更新

- 多语言：简体中文、English、日本語、한국어。
- 可选择菜单栏单项显示、双项组合或定时轮播金价、日期、CPU、内存、实时网速等信息。
- 支持登录 Mac 时自动启动。
- 可分别调整金币外观、动作、动画流畅度、系统采样和金价更新频率。
- 匿名使用数据统计默认关闭；未配置分析令牌的源码构建无法开启。
- 可开关各个系统监控模块，以及面板导航栏显示哪些功能模块。
- 支持本地备份和兼容旧版本的合并导入。
- 设置页可打开 GitHub 项目主页和 Releases。

## 从源码运行

### 环境要求

- macOS 15 或更高版本
- Xcode 16.4 或更高版本，建议使用最新稳定版
- Swift Package Manager（Xcode 内置）

### 运行项目

1. 克隆项目：

   ```bash
   git clone https://github.com/kuaoaoaoao/CoolRun.git
   cd CoolRun
   ```

2. 使用 Xcode 打开：

   ```bash
   open CoolRun.xcodeproj
   ```

3. 选择 `CoolRun` scheme。
4. 运行目标选择 `My Mac`。
5. 点击运行。

### 运行测试

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild \
  -project CoolRun.xcodeproj \
  -scheme CoolRun \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/CoolRun-derived \
  CODE_SIGNING_ALLOWED=NO \
  test
```

匿名统计不参与测试。fork 或本地构建默认不配置 PostHog；维护者配置方式见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 打包发布

仓库的 `Package unsigned macOS build` Action 可以在不配置 Apple 账号的情况下生成 `CoolRun.dmg`。它会先运行 Release 构建，再应用 ad hoc 临时签名并验证 App Bundle。该签名不能代替 Developer ID 或 Apple 公证。Action 生成的文件默认保留 30 天，发布者核对后可手动上传到 GitHub Release。

### 制作 DMG

项目提供了 DMG 打包脚本：

```bash
./scripts/create-dmg.sh
```

也可以手动指定 app 路径：

```bash
./scripts/create-dmg.sh /path/to/CoolRun.app
```

DMG 不会自动获得 Developer ID 签名或公证，公开发布时需要明确说明，并请在下载页提示用户上述“文件已损坏”的处理方式。

脚本会在项目根目录生成 `CoolRun.dmg`。

## 平台状态

- `CoolRun`：主要维护的 macOS SwiftUI + AppKit 应用；Xcode project、target 和 scheme 均使用 `CoolRun`。
- `coolrun-windows`：Tauri 实验版，不保证与 macOS 功能一致。
- `coolrun-avalonia`：Avalonia 技术验证版本，不保证功能一致。

## 金价数据说明

当前行情与市场背景来自多个公开接口：

```text
ms.jr.jd.com
api.jdjygold.com
gold.rsky.cn
hq.sinajs.cn
news.google.com
home.treasury.gov
```

接口均由第三方提供，稳定性和数据准确性取决于服务方。部分数据不可用时，应用会使用缓存或降低分析完整度。CoolRun 仅展示接口数据和基于历史样本的规则分析，不构成投资建议。

## 项目结构

```text
CoolRun
├── CoolRun.xcodeproj
├── CoolRun
│   ├── CoolRunApp.swift
│   ├── MacAppDelegate.swift
│   ├── ContentView.swift
│   ├── MenuBarMonitorView.swift
│   ├── AppSettings.swift
│   ├── SettingsView.swift
│   ├── GoldPriceService.swift
│   ├── GoldPriceStore.swift
│   ├── GoldAnalysisView.swift
│   ├── GoldAnalysisEngine.swift
│   ├── GoldAdvancedStrategy.swift
│   ├── GoldPositionAdvisor.swift
│   ├── GoldTradeStore.swift
│   ├── CalendarView.swift
│   ├── CountdownModel.swift
│   ├── CodexMonitor.swift
│   ├── ClaudeMonitor.swift
│   ├── EnglishLearningManager.swift
│   ├── SystemMonitorViewModel.swift
│   ├── SystemSampler.swift
│   ├── SystemMetrics.swift
│   ├── AppVersion.swift
│   ├── CoolRun.entitlements
│   └── Assets.xcassets
├── docs
│   └── index.html
├── scripts
│   └── create-dmg.sh
├── CoolRunTests
├── CONTRIBUTING.md
├── PRIVACY.md
├── SECURITY.md
├── README.md
└── LICENSE
```

主要文件说明：

- `MacAppDelegate.swift`：菜单栏图标、金币动画、悬浮窗、固定逻辑、右键菜单和金价刷新。
- `ContentView.swift`：主面板视图模式、模块导航栏、系统监控面板和公共 UI 组件。
- `MenuBarMonitorView.swift`：菜单栏悬浮面板。
- `AppSettings.swift`：应用设置与多语言文案，包含面板模块显隐的持久化逻辑。
- `DiagnosticsView.swift`、`DiagnosticsViewModel.swift`：Mac 诊断界面与状态协调。
- `SleepDiagnostics.swift`、`NetworkDiagnostics.swift`：睡眠耗电和分层网络诊断。
- `StorageDiagnostics.swift`、`AppResidueService.swift`：System Data 只读分析与应用残留安全清理。
- `GoldAnalysisView.swift`：金价分析 UI。
- `GoldAnalysisEngine.swift`：基础统计、技术指标快照和交易信号。
- `GoldAdvancedStrategy.swift`：高级量化策略分析。
- `GoldPositionAdvisor.swift`：个人持仓盈亏和建议。
- `CalendarView.swift`：日历、农历、节假日和生日入口。
- `NotesStore.swift`、`NotesView.swift`：本地分组备忘录数据与界面。
- `ClipboardHistoryStore.swift`、`ClipboardHistoryView.swift`：本地纯文本剪切板历史与管理界面。
- `CountdownModel.swift`：公历/农历倒数日和日期匹配。
- `CodexMonitor.swift`、`ClaudeMonitor.swift`：本机 AI 客户端额度与任务状态。
- `EnglishLearningManager.swift`：英语内容队列、学习进度和语音流程。
- `SettingsView.swift`：设置页面。
- `scripts/create-dmg.sh`：DMG 打包脚本。

## 隐私说明

系统监控、诊断摘要、生日、倒数日、备忘录、剪切板历史、学习进度和持仓默认只保存在本机。System Data 与残留扫描在本地进行，清理操作只会把确认的项目移入废纸篓。匿名统计默认关闭，AI 凭据不会进入备份或统计。完整的数据保存位置、网络目标和统计事件范围见 [PRIVACY.md](PRIVACY.md)。

## 版本与开发路线

- [当前版本更新总结](docs/release-summary.md)
- [v4.2.0 面板模块自定义显隐](docs/release-v4.2.0.md)
- [Mac 诊断与后续路线](docs/mac-diagnostics-roadmap.md)
- 下一项计划：输出设备快速切换。
- 后续计划：外接屏工作区快照与恢复。

## 贡献

欢迎提交 Issue 和 Pull Request。开始前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)；涉及凭据或隐私泄露的问题请按 [SECURITY.md](SECURITY.md) 私下报告。

可以改进的方向：

- 诊断权限提示、历史趋势和脱敏报告导出。
- 输出设备快速切换，以及后续的分应用音量评估。
- 外接屏工作区快照、预览、恢复和撤销。
- 更多贵金属数据源、金价回测与多平台功能对齐。

## 许可证

本项目源代码采用 [PolyForm Noncommercial License 1.0.0](LICENSE)：

- 个人学习、研究、实验、测试及其他非商业用途可以免费使用；
- 任何商业用途都必须事先取得版权所有者的明确书面授权；
- 商业用途范围、独立实现边界及授权方式详见 [商业使用与授权说明](COMMERCIAL_USE.md)。

这是一份源码可见的非商业许可证，不是 OSI 定义的开源许可证。第三方内容仍适用其各自的许可证。

## 作者

- 作者：kuaoaoaoao
- GitHub：[github.com/kuaoaoaoao/CoolRun](https://github.com/kuaoaoaoao/CoolRun)
