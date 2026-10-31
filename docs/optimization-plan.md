# CoolRun 优化计划与执行记录

更新时间：2026-08-01

## 目标

在保持菜单栏轻量、本地优先和权限透明的前提下，把 CoolRun 从状态展示工具完善为能够解释问题、提供安全处理入口的 Mac 日常工作台。

## 当前状态

- [x] 已完成第一批优化：资源策略、隐私开关、登录项、菜单栏显示扩展、基础单元测试目标。
- [x] 已修复 `MenuBarMonitorView` 默认参数跨 actor 初始化错误，改为显式注入监控实例。
- [x] 已完成工程结构、scheme、entitlements、Swift 语法解析和 diff 空白检查。
- [x] 已完成完整 Debug 构建、诊断聚焦测试和全量单元测试。
- [x] 已完成睡眠、网络、System Data 与应用残留四项 Mac 诊断。
- [x] 自动界面渲染测试已覆盖菜单栏宽度下的主要模块；手动冒烟检查保留为每次打包前的发布流程。

## 第一批：稳定性与常驻体验

- [x] 菜单栏动画支持关闭。
- [x] 动画刷新率可配置，默认从高频刷新降到更节能档位。
- [x] 系统采样间隔可配置，并避免重复启动刷新任务。
- [x] 菜单栏弹窗复用后台监控实例，避免打开弹窗时重复采样。
- [x] 金价轮询间隔可配置，设置变更后即时生效。
- [x] 设置页提供匿名使用数据开关。
- [x] 关闭匿名统计后立即停止事件上报，重启后保持选择。
- [x] 界面说明不采集生日和持仓金额等敏感内容。
- [x] 增加“登录时启动”开关，并展示注册失败状态。
- [x] 菜单栏支持显示金价、日期、CPU、内存和实时网速。

## 发布检查清单：每次生成 DMG 前重复执行

- [x] 联网解析依赖后运行：
  - `xcodebuild -project CoolRun.xcodeproj -scheme CoolRun -configuration Debug -derivedDataPath /private/tmp/CoolRun-derived CODE_SIGNING_ALLOWED=NO test`
- [ ] 在 macOS 本机启动 App，检查设置变更是否无需重启生效。
- [ ] 检查菜单栏文字在 CPU、内存、网速、金价和日期模式下是否过宽。
- [ ] 检查关闭动画后菜单栏仍能正常显示当前选择内容。
- [ ] 检查关闭匿名统计后 `Analytics.capture` 不再发送事件。
- [ ] 检查登录项开关失败时 UI 有可理解的提示。

## 第三批：可以继续加的功能

- [x] 统一提醒中心：生日、金价阈值、系统异常提醒统一管理。
- [x] 黄金模块增强：交易流水、持仓收益、预测复盘、CSV 导出。
- [x] 系统监控增强：本地历史、进程排行和异常峰值记录。
- [x] Mac 诊断：睡眠、网络、System Data 和应用残留。
- [ ] 日历增强：真实节假日远程更新、数据签名、离线回退。
- [ ] 英语学习模块增强：学习计划、复习提醒、错词本、语音跟读评分。
- [ ] 发布体验：自动更新、公证发布、版本更新提示。

## 下一批：Mac 原生体验

- [ ] 完善诊断权限提示、历史对比和脱敏报告导出。
- [ ] 第 5 项：输出设备快速切换，先覆盖设备列表、收藏、快捷键和断开回退。
- [ ] 第 6 项：外接屏工作区恢复，先覆盖手动快照、预览、恢复和撤销。
- [ ] 根据真实反馈评估分应用音量、菜单栏整理和截图收件箱。

详细范围见 [Mac 诊断与后续路线](mac-diagnostics-roadmap.md)。

## 暂不建议立刻做

- iCloud 同步：会牵涉数据模型、冲突处理和隐私说明，适合等本地数据结构稳定后再做。
- 大规模 UI 重构：当前更值得先把常驻资源、构建验证和已有功能闭环做好。
- 多端同步或账号系统：收益大，但实现半径明显变大，容易拖慢当前版本收尾。

## 验收标准

1. 旧用户设置兼容，首次升级不丢失原有选择。
2. 菜单栏和设置页面在浅色、深色模式下均不新增固定尺寸溢出。
3. 关闭动画或统计后无需重启即可生效。
4. 登录项注册失败不会导致应用崩溃，界面给出可理解的状态。
5. Debug 配置可以使用仓库锁定的 Swift Package 依赖完成构建。
6. 单元测试目标可以稳定运行，后续优化不再只靠手动点 UI 验证。

## 执行记录

- 2026-07-14：建立计划；确认工作区已有 `.idea/workspace.xml` 与 `CoolRun.dmg` 用户改动，本轮不修改这两项。
- 2026-07-14：完成资源策略、隐私开关、登录项和菜单栏显示扩展；加入三组单元测试。
- 2026-07-14：菜单栏弹窗改为复用后台监控实例，消除打开弹窗时的重复系统采样。
- 2026-07-14：修复 `MenuBarMonitorView` 默认参数跨 actor 初始化错误，改为显式注入监控实例。
- 2026-07-14：Swift 语法解析与工程结构校验通过；完整构建因 PostHog 依赖解析受网络沙箱限制，待授权后继续。
- 2026-07-19：整理本文件为长期接力文档，补充当前状态、下一批验证项和后续功能路线。
- 2026-08-01：完成四项 Mac 诊断、隐私边界、聚焦测试与全量测试；明确输出设备切换和工作区恢复为第 5、6 项。
- **2026-10-30**：代码审核与优化执行：
  - [x] 拆分 `GoldAnalysisView.swift`（3,432 行 → 3 个文件：主视图 ~750 行、ViewModel ~430 行、卡片 ~2,200 行）
  - [x] 新增 LLM 助手模块（`LLMService.swift` + `AIAssistantView.swift`），支持 OpenAI/Anthropic/Ollama 多 Provider
  - [x] 新增 `ViewMode.aiAssistant`，集成到导航栏和 ContentView
  - [x] 更新 `CLAUDE.md` 反映 10 模块实际架构
  - [x] 拆分 `SettingsView.swift`（2,109 行 → 9 个文件，主文件降至 163 行）：
    - `SettingsView.swift`（163）主壳层：侧边栏 + 页头 + 分类分发
    - `SettingsCategory.swift`（63）分类枚举
    - `SettingsViewGeneral.swift`（196）/ `SettingsViewMonitors.swift`（151）/ `SettingsViewReminders.swift`（164）/ `SettingsViewMenuBar.swift`（331）/ `SettingsViewEnglish.swift`（276）/ `SettingsViewData.swift`（66）各分类页内容
    - `SettingsComponents.swift`（735）共享卡片与行组件
  - [x] 拆分后全量 `swiftc -parse` 通过；跨文件引用改为 internal，组件可见性校验通过
  - [x] 拆分 `ContentView.swift`（1,907 行 → 5 个文件）：
    - `ContentView.swift`（294）导航壳层：`ViewMode` + `ContentView` + `ModuleNavigationRail`
    - `AppTheme.swift`（104）主题色板 + `AppCardSurface` + `appCardSurface()`
    - `MonitorPanel.swift`（214）展开状态 + `MonitorPanel`
    - `MonitorSections.swift`（451）可折叠 Section、状态头、资源与温度卡片
    - `ProcessAndDeviceSections.swift`（606）进程明细、存储、电池、网络、运行时长
    - `MonitorComponents.swift`（262）`MetricRow`、`Separator`、迷你图表、进度条、毛玻璃、数字格式化
  - [x] 静态校验：顶层类型无重名、无跨文件引用 `private` 类型、扩展成员无冲突
  - 剩余较大文件（非阻塞）：`GoldAnalysisCards.swift` 2,290 / `AppSettings.swift` 1,347 / `MacAppDelegate.swift` 1,210
  - [x] **目录分组**：116 个 Swift 文件从平铺结构迁到 `App/`、`Core/`、`Settings/`、`Modules/{Today,Monitor,Gold,Calendar,English,AIQuota,Assistant,Notes,Clipboard,Diagnostics,Shelf}`；JSON 词库、`Info.plist`、`Assets.xcassets`、entitlements 保留在根目录以免改变 bundle 路径（`Bundle.main.url(forResource:withExtension:)` 不带 subdirectory）
  - [x] **面板尺寸自适应**：`ViewMode.panelContentSize` / `panelSize` 统一尺寸来源，`MacAppDelegate` 在模块切换时调整 `popover.contentSize`。监控 320×512，黄金 384×616，诊断 376×596，其余 340~356 宽
  - [x] **修复编译错误**：`MenuBarMonitorView` 的 `switch viewMode` 缺少 `.aiAssistant` 分支（新增模块时漏改），会导致 `switch must be exhaustive`。已补上
  - [x] 新增 `scripts/verify.sh`：无 `xcodebuild` 环境下的三项静态自检（语法解析 / 类型可见性 / 枚举 switch 完备性）

- **2026-10-31**：接入真实 Xcode 后的编译验证与收尾：
  - [x] 确认本机已装 Xcode 26.6，`xcode-select` 仍指向 CommandLineTools；改用 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` 直接调用 `xcodebuild`，无需 `sudo xcode-select -s`
  - [x] **Debug 全量 clean build 通过**，0 error；初次统计出 36 条警告
  - [x] **Release 构建通过**，产物 `CoolRun.app`（27 MB），同样 0 error / 0 warning
  - [x] 单元测试 **260 通过 / 0 失败**
  - [x] 修复既有红测试 `GoldMarketContextTests.testFetchContextFiltersIrrelevantAndSyndicatedNews`：夹具 `pubDate` 硬编码为 `Sat, 29 Aug 2026`，而 `GoldMarketContext.swift:224` 只保留最近 4 天新闻，导致用例随真实日期推移必然失败（时间炸弹）。改为以 `Date()` 为基准生成 `pubDate`
  - [x] 已确认该测试失败在 HEAD 上同样存在（用 `git worktree` 拉 HEAD 复现），与本次重构无关
  - [x] **并发警告清零**（36 → 0），全部是 `-default-isolation MainActor` 下纯常量/纯函数被推断为主线程隔离：
    - `GoldNewsClassifier` 12 个词表常量、`GoldEventImpactAnalyzer` 3 个阈值 → `nonisolated static let`
    - `AppResidueService` 的 6 个纯函数 + `minimumAge` → `nonisolated`
    - `GoldDataStorage` 全部路径辅助函数 → `nonisolated`
    - `FixedCommandRunner.limitedString` → `nonisolated`（此前从 `Task.detached` 调用被当作隐式 async）
    - `GoldAnalysisViewModel.init` 的三个默认参数改为可选、在 init 内部兜底
  - [x] 运行时冒烟测试：Debug 产物独立启动，稳定运行 20 秒无崩溃、无 stderr 输出
  - [x] `scripts/verify.sh` 升级：有 Xcode 时执行真实 `xcodebuild build` 并统计 error/warning，无 Xcode 时降级为 `swiftc -parse`；新增 `--test` 跑单测

- **2026-10-31（续）**：授权屏幕录制 + 辅助功能后做真实 UI 实测：
  - [x] **修复「升级用户看不到新模块」**：`visible_tabs` 已持久化在老用户机器上，`defaultVisible` 改动对老用户无效。
    引入 `ViewMode.visibleTabsSchemaVersion` + `modulesAdded(after:)`，升级时把新模块并入已保存集合并写回。
    以后新增模块必须 +1 版本号并登记，已写入 `CLAUDE.md`
  - [x] 实测面板按模块自适应尺寸生效：监控 362×554 → AI 398×602 → 黄金 426×658
  - [x] 实测 AI 助手：空状态、隐私说明、三张服务商卡片渲染正常；配置表单 420×420 字段齐全
  - [x] 实测黄金模块：拆分三个文件后渲染无异常
  - [ ] 待决策：涨跌配色为欧美惯例（涨绿跌红），中文应用通常期望涨红跌绿
  - [ ] 待决策：面板底部约 100pt 空白，需内容自适应高度（跨 10 模块改动）
