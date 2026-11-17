# 国际化规范（i18n）

CoolRun 支持 4 种界面语言：简体中文、English、日本語、한국어。用户切换语言后，
所有**用户可见文案**（菜单、按钮、标题、开关、状态、提示、空状态、确认框、
无障碍标签）都必须跟随切换，不允许残留硬编码中文。

## 唯一写法

所有界面文案通过 `LocalizedString` 输出，底层只有一个函数：

```swift
nonisolated static func l(
    _ lang: AppLanguage,
    en: String,
    zh: String,
    ja: String? = nil,
    ko: String? = nil
) -> String
```

- `en` / `zh` 必填，`ja` / `ko` 省略时回退英文。
- 禁止新增第二套本地化机制（不要再写 `NSLocalizedString` 或 `.strings` 文件）。
- 多个界面复用同一句时，优先用 `LocalizedString` 里已有的分类 key 函数
  （`common` / `settings` / `monitor` / `menuBar` / `batteryState` /
  `memoryPressure` / `label` / `calendar` / `countdown` / `data` /
  `goldPrice` / `goldAge` / `gold` / `english` / `update` / `migration`），
  没有合适 key 时再用 `l(...)` 内联。

## 在视图里怎么拿语言

```swift
@ObservedObject private var settings = AppSettings.shared
```

- `AppSettings` 是 `ObservableObject`，`settings.language` 是 `@Published`。
  必须用 `@ObservedObject`（或已有的 `@ObservedObject var settings`）订阅，
  否则切换语言时视图不刷新。
- 视图里读取一次即可：

```swift
private var lang: AppLanguage { settings.language }
```

- 非 View 的展示型模型（例如 `PetModel`、`CountdownModel` 的展示文案）：
  不要把语言存成全局单例状态，方法接收 `lang: AppLanguage` 参数，由视图传入。

## 示例

```swift
// ✅
Text(LocalizedString.l(lang, en: "Cancel", zh: "取消", ja: "キャンセル", ko: "취소"))

// ✅ 复用已有 key
Text(LocalizedString.settings("general", lang: lang))

// ❌ 硬编码
Text("取消")

// ❌ 缺 ja/ko（可接受但应尽量补齐）
Text(LocalizedString.l(lang, en: "Cancel", zh: "取消"))
```

## 不要本地化的内容

| 类别 | 例子 | 原因 |
| --- | --- | --- |
| 数据表 | 词库、例句、节假日表、农历/节气名、新闻关键词 | 内容本身是数据，不是界面文案 |
| 给 LLM 的提示词与工具 schema | `AgentPrompts.swift`、`AgentRecipe.swift`、`AgentTools*.swift` | 模型输入，保持中文即可 |
| 开发者日志 | `print`、`os_log`、`assert` 消息 | 不面向用户 |
| 持久化 key / 枚举 rawValue / URL / JSON 字段名 | `"app_language"`、`"visible_tabs"` | 改动会破坏已有用户数据 |
| 注释 | `// 刷新数据` | 不显示 |

### 标注"故意保留"：`// i18n-allow`

上表这几类中文无法靠位置判断，所以要在行尾（多行字符串写在上一行独占一行）标注：

```swift
// i18n-allow: 农历月名与日名（文化数据）
let monthNames = ["正", "二", "三", …]

if name.contains("新浪") {  // i18n-allow: 数据源中文名匹配（后端返回的原始名称）
```

- 注解独占一行时豁免**下一行**，行尾注解只豁免**本行**。
- 只用于上面表格里的类别；不要拿它掩盖真正的界面文案。
- 新增注解请在理由里写清"为什么不能本地化"，后来的人要能据此复核。

## 术语表

| 中文 | English | 日本語 | 한국어 |
| --- | --- | --- | --- |
| 取消 | Cancel | キャンセル | 취소 |
| 保存 | Save | 保存 | 저장 |
| 删除 | Delete | 削除 | 삭제 |
| 添加 | Add | 追加 | 추가 |
| 编辑 | Edit | 編集 | 편집 |
| 完成 | Done | 完了 | 완료 |
| 关闭 | Close | 閉じる | 닫기 |
| 搜索 | Search | 検索 | 검색 |
| 刷新 | Refresh | 更新 | 새로고침 |
| 加载中 | Loading… | 読み込み中… | 불러오는 중… |
| 暂无数据 | No data | データがありません | 데이터 없음 |
| 全部 | All | すべて | 전체 |
| 今日 | Today | 今日 | 오늘 |
| 确认 | Confirm | 確認 | 확인 |
| 复制 | Copy | コピー | 복사 |
| 粘贴 | Paste | ペースト | 붙여넣기 |
| 启用 | Enable | 有効 | 사용 |
| 停用 | Disable | 無効 | 사용 안 함 |
| 设置 | Settings | 設定 | 설정 |
| 分钟 | min | 分 | 분 |
| 小时 | h | 時間 | 시간 |
| 天 | d | 日 | 일 |

单位与时间格式用英文缩写 + 本地化词，例如 `"5 分钟"` → en `"5 min"`、
ja `"5分"`、ko `"5분"`。

## 验证

```bash
# 扫残留（有问题退出码 1）+ 全量语法检查
./scripts/verify_i18n.sh
./scripts/verify_i18n.sh --parse      # 额外跑 swiftc -parse

# 只扫残留
python3 scripts/check_i18n.py
```

`scripts/check_i18n.py` 把"位于同时带 `en:` 与 `zh:` 的调用内"的字面量视为已本地化；
白名单文件见脚本顶部 `WHITELIST`，`// i18n-allow` 标注与枚举 rawValue 定义自动豁免。

Xcode license 未同意时 `xcodebuild` 不可用，用脚本做真实类型检查（能查类型与
MainActor 隔离，比 `swiftc -parse` 强）：

```bash
./scripts/typecheck_stub.sh
```

它会把源码复制到临时目录、把 PostHog 换成桩、再用 Xcode 自带的 `swiftc`
跑 `-typecheck`。基线是 `error: 0  warning: 1`（`ToolRegistry.swift:227` 的既有
警告）；改动后 error 必须为 0，warning 不应超过基线。

## 切语言必须刷新

SwiftUI 只在被观察对象变化时重算 `body`。所以：

- 每个**读** `settings.language` 的 View 都要有 `@ObservedObject private var settings = AppSettings.shared`
  （或父视图已订阅且把 `lang` 传下来）。
- 被 `NSHostingView(rootView:)` 直接承载的根视图（`QuickSearchView`、
  `PetRootView`、`EnglishTextbookManagementView`）必须自己订阅——它们没有父视图帮忙重算。
- 计算型缓存（如 `GoldAnalysisViewModel` 的 key）要把语言拼进 key，否则切语言后
  拿到旧语言的缓存。

## 改动约束

- 只改文案，不改业务逻辑、不改持久化 key、不改枚举 rawValue。
- 保持项目零警告：新增 `@ObservedObject` 属性时确认类型已 `import SwiftUI`。
- 一个文件一次改完；改完用 `swiftc -parse` 确认语法。
