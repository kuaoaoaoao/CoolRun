# 浙商积存金一周方向预测 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 App 当前展示的浙商积存金人民币/克增加可解释、可走步回测、可在第 7 天验证的一周上涨/震荡/下跌预测。

**Architecture:** 新的 `GoldWeeklyForecastEngine` 只消费标准化日线，组合趋势、动量、均值回归和区块自助法区间；`GoldWeeklyForecastBacktester` 用无泄漏走步验证决定是否允许发布方向；`GoldWeeklyForecastService` 负责编排一年日线、来源兼容性和事件信心修正。周预测使用独立 Store 和 UI，不进入现有 30 分钟自动校准、交易策略或持仓建议。

**Tech Stack:** Swift 5 language mode、Foundation、Swift Concurrency、Observation、SwiftUI、XCTest、macOS 15.0；不新增第三方依赖。

**Spec:** `docs/superpowers/specs/2026-08-30-weekly-czb-gold-forecast-design.md`

## Global Constraints

- 预测标的是 App 展示的浙商积存金人民币/克，目标为生成时间后第 7 个自然日的第一笔有效同标的价格。
- 实际收益率 > 0.5% 为 up，-0.5%...0.5% 为 flat，< -0.5% 为 down。
- 只有 `ready` 状态可展示方向；数据、来源或回测不合格时必须说明原因并停止发布方向。
- 一周预测不得改变 `GoldAdvancedStrategy`、`GoldPositionAdvisor`、`TradingSignalEngine` 或建议仓位。
- `GoldEventImpact` 只能把 confidence 调整一级，不能改变 direction、expectedReturn、expectedPrice 或 P10/P50/P90。
- 不得把现有 `MonteCarloForecast.forecastSteps == 7` 解释为 7 天。
- 一周记录不得进入 `GoldPredictionLearningStore.summary`，避免污染 30 分钟自动校准。
- 不增加 Python、Core ML、LLM、付费 API、API Key 或受限网页抓取。
- 新增用户可见文案必须同时提供中文、英文、日文、韩文，不能只靠红绿颜色表达方向。
- 项目使用 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`；纯计算入口必须显式 `nonisolated`，语言由 MainActor 调用方捕获后传入。
- 当前工作区有 Watch 删除、剪贴板及其他用户未提交改动。只能暂存本任务列出的文件；禁止 `git add -A`、`git add .`、`git reset --hard` 或回退无关改动。
- `CoolRun` 和 `CoolRunTests` 使用文件系统同步组；新增 Swift 文件通常不需要修改 `project.pbxproj`。

---

## 1. 文件结构

### 新建

- `CoolRun/GoldWeeklyForecastModels.swift`：领域模型、状态、固定阈值和安全快照工厂。
- `CoolRun/GoldDailyCloseNormalizer.swift`：上海日历归并、异常过滤和历史质量判断。
- `CoolRun/GoldWeeklyForecastEngine.swift`：纯统计组合模型与确定性区块自助模拟。
- `CoolRun/GoldWeeklyForecastBacktester.swift`：无泄漏走步回测与发布门槛。
- `CoolRun/GoldWeeklyForecastService.swift`：历史数据、来源兼容性、缓存和事件信心编排。
- `CoolRun/GoldWeeklyForecastStore.swift`：每日正式预测、7 天验证和本地持久化。
- `CoolRun/GoldWeeklyForecastCard.swift`：分析页一周预测卡片。
- `CoolRun/GoldWeeklyForecastReviewView.swift`：独立周预测复盘区块。
- `CoolRunTests/GoldDailyCloseNormalizerTests.swift`
- `CoolRunTests/GoldWeeklyForecastEngineTests.swift`
- `CoolRunTests/GoldWeeklyForecastBacktesterTests.swift`
- `CoolRunTests/GoldWeeklyForecastServiceTests.swift`
- `CoolRunTests/GoldWeeklyForecastStoreTests.swift`

### 修改

- `CoolRun/GoldMarketDataService.swift`：增加窄历史数据协议和明确历史来源 ID。
- `CoolRun/GoldAnalysisView.swift`：ViewModel 注入周预测服务、管理任务并插入卡片。
- `CoolRun/PredictionReviewView.swift`：挂载独立周预测复盘区块。
- `CoolRun/DataMigrationManager.swift`：备份版本升级并增加可选周预测记录。
- `CoolRunTests/GoldMarketDataServiceTests.swift`：协议和历史来源回归。
- `CoolRunTests/GoldSignalEngineTests.swift`：证明周预测不改变策略结果。
- `CoolRunTests/InterfaceRenderTests.swift`：四语言状态和禁止交易动作检查。
- `CoolRunTests/CountdownModelTests.swift`：旧备份解码兼容。
- `docs/gold-analysis-roadmap.md`：记录周预测模型、门槛和未解决的数据来源限制。

### 不修改

- `CoolRun/GoldAdvancedStrategy.swift`
- `CoolRun/GoldPositionAdvisor.swift`
- `CoolRun/GoldPredictionLearningStore.swift`
- `CoolRun/GoldEventImpactAnalyzer.swift`

若实现者认为必须修改以上文件才能让预测“生效”，应先停下检查是否把预测错误地接入了交易决策。

---

## 2. 固定公共接口

后续任务沿用这些名字，不得各自创建同义类型。

```swift
enum GoldWeeklyForecastDirection: String, Codable, Sendable, Equatable {
    case up, flat, down

    nonisolated static func classify(actualReturn: Double) -> Self {
        if actualReturn > GoldWeeklyForecastPolicy.flatReturnThreshold { return .up }
        if actualReturn < -GoldWeeklyForecastPolicy.flatReturnThreshold { return .down }
        return .flat
    }
}

enum GoldWeeklyForecastConfidence: String, Codable, Sendable, Equatable, Comparable {
    case unavailable, low, medium, high
}

enum GoldWeeklyForecastStatus: String, Codable, Sendable, Equatable {
    case ready
    case insufficientHistory
    case staleData
    case sourceMismatch
    case validationFailed
    case sourceUnavailable
}

enum GoldForecastSourceCompatibility: String, Codable, Sendable, Equatable {
    case verified, proxy, incompatible
}

enum GoldWeeklyForecastPolicy {
    nonisolated static let modelVersion = "gold-weekly-2026.08.30.1"
    nonisolated static let flatReturnThreshold = 0.005
    nonisolated static let scoreDirectionThreshold = 0.18
    nonisolated static let minimumDailyCloses = 120
    nonisolated static let normalDailyCloses = 180
    nonisolated static let highDailyCloses = 240
    nonisolated static let horizonDays = 7
    nonisolated static let validationGraceDays = 3
    nonisolated static let maximumLatestAge: TimeInterval = 96 * 60 * 60
    nonisolated static let simulationCount = 2_000
}

struct GoldDailyClose: Codable, Sendable, Equatable {
    let date: Date
    let close: Double
}

struct GoldWeeklyForecastComponents: Codable, Sendable, Equatable {
    let trend: Double
    let momentum: Double
    let meanReversion: Double
    let bootstrap: Double
    let composite: Double
}

struct GoldWeeklyForecastBacktestSummary: Codable, Sendable, Equatable {
    let resolvedCount: Int
    let classCounts: [GoldWeeklyForecastDirection: Int]
    let overallAccuracy: Double?
    let balancedAccuracy: Double?
    let majorityBaselineAccuracy: Double?
    let meanAbsoluteReturnError: Double?
    let confusionMatrix: [GoldWeeklyForecastDirection: [GoldWeeklyForecastDirection: Int]]
    let passedReleaseGate: Bool
    let failureReasons: [String]
}

struct GoldWeeklyForecast: Codable, Sendable, Equatable {
    let direction: GoldWeeklyForecastDirection
    let confidence: GoldWeeklyForecastConfidence
    let startPrice: Double
    let expectedPrice: Double
    let expectedReturn: Double
    let p10: Double
    let p50: Double
    let p90: Double
    let generatedAt: Date
    let targetDate: Date
    let dataUpdatedAt: Date
    let currentPriceSource: String
    let historySource: String
    let sourceCompatibility: GoldForecastSourceCompatibility
    let components: GoldWeeklyForecastComponents
    let reasons: [String]
    let counterRisks: [String]
    let modelVersion: String
}

struct GoldWeeklyForecastSnapshot: Sendable, Equatable {
    let status: GoldWeeklyForecastStatus
    let forecast: GoldWeeklyForecast?
    let backtest: GoldWeeklyForecastBacktestSummary?
    let message: String
    let updatedAt: Date
}
```

硬性不变量：

- `status == .ready` 当且仅当 `forecast != nil` 且 `backtest.passedReleaseGate == true`。
- 非 ready 快照不能带方向、预期价格或陈旧的上次预测作为当前结论。
- `p10 <= p50 <= p90`，所有价格和收益必须有限且大于零。
- `targetDate` 使用 Asia/Shanghai 日历在 generatedAt 上增加 7 天。
- proxy 来源 confidence 最高为 low。

---

### Task 1: 建立周预测领域模型与安全状态

**Files:**
- Create: `CoolRun/GoldWeeklyForecastModels.swift`
- Create: `CoolRunTests/GoldWeeklyForecastEngineTests.swift`

**Interfaces:**
- Consumes: `Date`、`AppLanguage`、`LocalizedString.l`。
- Produces: 第 2 节全部模型、`GoldWeeklyForecastSnapshot.unavailable(status:message:now:)`、`GoldWeeklyForecastConfidence.downgraded/upgraded`。

- [ ] **Step 1: 写分类边界和快照不变量失败测试**

```swift
import XCTest
@testable import CoolRun

final class GoldWeeklyForecastEngineTests: XCTestCase {
    func testActualReturnClassificationUsesHalfPercentBand() {
        XCTAssertEqual(GoldWeeklyForecastDirection.classify(actualReturn: 0.005_001), .up)
        XCTAssertEqual(GoldWeeklyForecastDirection.classify(actualReturn: 0.005), .flat)
        XCTAssertEqual(GoldWeeklyForecastDirection.classify(actualReturn: 0), .flat)
        XCTAssertEqual(GoldWeeklyForecastDirection.classify(actualReturn: -0.005), .flat)
        XCTAssertEqual(GoldWeeklyForecastDirection.classify(actualReturn: -0.005_001), .down)
    }

    func testUnavailableSnapshotContainsNoForecast() {
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let snapshot = GoldWeeklyForecastSnapshot.unavailable(
            status: .insufficientHistory,
            message: "历史不足",
            now: now
        )
        XCTAssertNil(snapshot.forecast)
        XCTAssertNil(snapshot.backtest)
        XCTAssertEqual(snapshot.updatedAt, now)
    }

    func testConfidenceCannotUpgradePastHighOrBelowUnavailable() {
        XCTAssertEqual(GoldWeeklyForecastConfidence.high.upgraded, .high)
        XCTAssertEqual(GoldWeeklyForecastConfidence.low.downgraded, .unavailable)
    }
}
```

- [ ] **Step 2: 运行并确认类型不存在**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CoolRun.xcodeproj -scheme CoolRun -configuration Debug -derivedDataPath /private/tmp/coolRun-weekly-forecast CODE_SIGNING_ALLOWED=NO -only-testing:CoolRunTests/GoldWeeklyForecastEngineTests test
```

Expected: 编译失败，报告 `GoldWeeklyForecastDirection` 等类型不存在。

- [ ] **Step 3: 实现固定类型和安全工厂**

`GoldWeeklyForecastModels.swift` 必须包含第 2 节定义，并加入：

```swift
extension GoldWeeklyForecastConfidence {
    nonisolated static func < (lhs: Self, rhs: Self) -> Bool {
        let order: [Self] = [.unavailable, .low, .medium, .high]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }

    nonisolated var upgraded: Self {
        switch self {
        case .unavailable: .low
        case .low: .medium
        case .medium, .high: .high
        }
    }

    nonisolated var downgraded: Self {
        switch self {
        case .high: .medium
        case .medium: .low
        case .low, .unavailable: .unavailable
        }
    }
}

extension GoldWeeklyForecastSnapshot {
    nonisolated static func unavailable(
        status: GoldWeeklyForecastStatus,
        message: String,
        now: Date
    ) -> Self {
        precondition(status != .ready)
        return Self(status: status, forecast: nil, backtest: nil, message: message, updatedAt: now)
    }
}

extension Calendar {
    nonisolated static var goldShanghai: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }
}
```

- [ ] **Step 4: 运行测试并确认通过**

Run: 使用 Step 2 命令。

Expected: 当前 3 个模型测试通过。

- [ ] **Step 5: 提交本任务文件**

```bash
git add CoolRun/GoldWeeklyForecastModels.swift CoolRunTests/GoldWeeklyForecastEngineTests.swift
git commit -m "feat: define weekly gold forecast models"
```

---

### Task 2: 标准化一年日线并判定数据质量

**Files:**
- Create: `CoolRun/GoldDailyCloseNormalizer.swift`
- Create: `CoolRunTests/GoldDailyCloseNormalizerTests.swift`
- Modify: `CoolRun/GoldMarketDataService.swift`
- Modify: `CoolRunTests/GoldMarketDataServiceTests.swift`

**Interfaces:**
- Consumes: `[GoldRemotePricePoint]`、`now`。
- Produces: `GoldDailyHistoryQuality`、`GoldDailyCloseNormalizer.normalize(points:now:)`、`GoldWeeklyHistoryProviding`。

- [ ] **Step 1: 写日线归并、异常和陈旧测试**

```swift
import XCTest
@testable import CoolRun

final class GoldDailyCloseNormalizerTests: XCTestCase {
    private let shanghai = TimeZone(identifier: "Asia/Shanghai")!

    func testKeepsLastValidPointPerShanghaiDayAndSortsAscending() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = shanghai
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 20)))
        let points = [
            GoldRemotePricePoint(price: 600, timestamp: day.addingTimeInterval(9 * 3600)),
            GoldRemotePricePoint(price: 602, timestamp: day.addingTimeInterval(15 * 3600)),
            GoldRemotePricePoint(price: 603, timestamp: day.addingTimeInterval(24 * 3600 + 10 * 3600))
        ]
        let quality = GoldDailyCloseNormalizer.normalize(
            points: points,
            now: day.addingTimeInterval(25 * 3600)
        )
        XCTAssertEqual(quality.closes.map(\.close), [602, 603])
    }

    func testRejectsOutOfRangeAndEightPercentSpike() {
        let points = makeDailyPoints(prices: [600, 602, 700, 603, 50])
        let quality = GoldDailyCloseNormalizer.normalize(points: points, now: points.last!.timestamp)
        XCTAssertEqual(quality.closes.map(\.close), [600, 602, 603])
        XCTAssertEqual(quality.rejectedCount, 2)
    }

    func testHistoryOlderThanNinetySixHoursIsStale() {
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let points = makeDailyPoints(count: 130, endingAt: now.addingTimeInterval(-97 * 3600))
        let quality = GoldDailyCloseNormalizer.normalize(points: points, now: now)
        XCTAssertTrue(quality.isStale)
    }
}
```

测试文件加入确定性辅助，不能使用真实网络：

```swift
private func makeDailyPoints(
    prices: [Double],
    endingAt: Date = Date(timeIntervalSince1970: 1_788_000_000)
) -> [GoldRemotePricePoint] {
    let calendar = Calendar.goldShanghai
    return prices.enumerated().map { index, price in
        let offset = index - (prices.count - 1)
        let timestamp = calendar.date(byAdding: .day, value: offset, to: endingAt)!
        return GoldRemotePricePoint(price: price, timestamp: timestamp)
    }
}

private func makeDailyPoints(count: Int, endingAt: Date) -> [GoldRemotePricePoint] {
    makeDailyPoints(
        prices: (0..<count).map { 580 + Double($0) * 0.1 },
        endingAt: endingAt
    )
}
```

- [ ] **Step 2: 运行并确认 normalizer 不存在**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CoolRun.xcodeproj -scheme CoolRun -configuration Debug -derivedDataPath /private/tmp/coolRun-weekly-forecast CODE_SIGNING_ALLOWED=NO -only-testing:CoolRunTests/GoldDailyCloseNormalizerTests test
```

Expected: 编译失败，`GoldDailyCloseNormalizer` 不存在。

- [ ] **Step 3: 实现质量模型和标准化**

```swift
struct GoldDailyHistoryQuality: Sendable, Equatable {
    let closes: [GoldDailyClose]
    let rejectedCount: Int
    let maximumGapDays: Int
    let latestAge: TimeInterval?
    let isStale: Bool
}

enum GoldDailyCloseNormalizer {
    nonisolated static func normalize(
        points: [GoldRemotePricePoint],
        now: Date,
        calendar: Calendar = .goldShanghai
    ) -> GoldDailyHistoryQuality {
        let valid = points.filter { $0.price.isFinite && (100...2_000).contains($0.price) }
        let grouped = Dictionary(grouping: valid) { calendar.startOfDay(for: $0.timestamp) }
        let candidates = grouped.compactMap { day, values -> GoldDailyClose? in
            guard let latest = values.max(by: { $0.timestamp < $1.timestamp }) else { return nil }
            return GoldDailyClose(date: day, close: latest.price)
        }.sorted { $0.date < $1.date }

        var accepted: [GoldDailyClose] = []
        var rejected = points.count - valid.count
        for candidate in candidates {
            if let previous = accepted.last,
               abs(candidate.close / previous.close - 1) > 0.08 {
                rejected += 1
                continue
            }
            accepted.append(candidate)
        }

        let gaps = zip(accepted, accepted.dropFirst()).map {
            calendar.dateComponents([.day], from: $0.0.date, to: $0.1.date).day ?? 0
        }
        let latestAge = accepted.last.map { max(0, now.timeIntervalSince($0.date)) }
        return GoldDailyHistoryQuality(
            closes: accepted,
            rejectedCount: rejected,
            maximumGapDays: gaps.max() ?? 0,
            latestAge: latestAge,
            isStale: (latestAge ?? .infinity) > GoldWeeklyForecastPolicy.maximumLatestAge
        )
    }
}
```

实现必须按以上五步，异常点不能成为下一个点的比较基准。

- [ ] **Step 4: 为历史源增加窄协议和固定来源 ID**

在 `GoldMarketDataService.swift` 增加：

```swift
protocol GoldWeeklyHistoryProviding: Sendable {
    func fetchHistoryPrices(
        range: GoldHistoryRange,
        now: Date
    ) async throws -> [GoldRemotePricePoint]
}

extension GoldMarketDataService: GoldWeeklyHistoryProviding {}

extension GoldMarketDataService {
    nonisolated static let historySourceID = "JD-MS-history"
}
```

现有默认参数不妨碍协议遵循；不要改变请求 URL、period 或缓存时长。

- [ ] **Step 5: 运行日线和现有市场数据测试**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CoolRun.xcodeproj -scheme CoolRun -configuration Debug -derivedDataPath /private/tmp/coolRun-weekly-forecast CODE_SIGNING_ALLOWED=NO -only-testing:CoolRunTests/GoldDailyCloseNormalizerTests -only-testing:CoolRunTests/GoldMarketDataServiceTests test
```

Expected: 两组测试通过；不发真实网络请求。

- [ ] **Step 6: 提交**

```bash
git add CoolRun/GoldDailyCloseNormalizer.swift CoolRun/GoldMarketDataService.swift CoolRunTests/GoldDailyCloseNormalizerTests.swift CoolRunTests/GoldMarketDataServiceTests.swift
git commit -m "feat: normalize weekly gold forecast history"
```

---

### Task 3: 实现确定性一周统计组合模型

**Files:**
- Create: `CoolRun/GoldWeeklyForecastEngine.swift`
- Modify: `CoolRunTests/GoldWeeklyForecastEngineTests.swift`

**Interfaces:**
- Consumes: `GoldWeeklyForecastEngineInput`。
- Produces: `GoldWeeklyForecastDraft`、`GoldWeeklyForecastEngine.makeDraft(_:)`。

- [ ] **Step 1: 写上涨、震荡、下跌和确定性失败测试**

```swift
func testRisingDailySeriesProducesUpDraft() throws {
    let closes = makeCloses(count: 220) { 520 + Double($0) * 0.45 }
    let input = makeEngineInput(closes: closes, seed: 42)
    let draft = try XCTUnwrap(GoldWeeklyForecastEngine.makeDraft(input))
    XCTAssertEqual(draft.direction, .up)
    XCTAssertGreaterThan(draft.components.composite, 0.18)
    XCTAssertLessThanOrEqual(draft.p10, draft.p50)
    XCTAssertLessThanOrEqual(draft.p50, draft.p90)
}

func testFlatSeriesProducesFlatDraft() throws {
    let closes = makeCloses(count: 220) { 600 + sin(Double($0)) * 0.3 }
    XCTAssertEqual(
        GoldWeeklyForecastEngine.makeDraft(makeEngineInput(closes: closes, seed: 7))?.direction,
        .flat
    )
}

func testFallingDailySeriesProducesDownDraft() throws {
    let closes = makeCloses(count: 220) { 720 - Double($0) * 0.4 }
    XCTAssertEqual(
        GoldWeeklyForecastEngine.makeDraft(makeEngineInput(closes: closes, seed: 8))?.direction,
        .down
    )
}

func testSameSeedProducesIdenticalRange() throws {
    let closes = makeNoisyCloses(count: 220)
    let lhs = try XCTUnwrap(GoldWeeklyForecastEngine.makeDraft(makeEngineInput(closes: closes, seed: 99)))
    let rhs = try XCTUnwrap(GoldWeeklyForecastEngine.makeDraft(makeEngineInput(closes: closes, seed: 99)))
    XCTAssertEqual(lhs, rhs)
}

func testFewerThanOneHundredTwentyClosesReturnsNil() {
    XCTAssertNil(GoldWeeklyForecastEngine.makeDraft(
        makeEngineInput(closes: makeCloses(count: 119) { 600 + Double($0) * 0.1 }, seed: 1)
    ))
}
```

测试文件加入以下确定性 fixture：

```swift
private func makeCloses(
    count: Int,
    price: (Int) -> Double
) -> [GoldDailyClose] {
    let start = Date(timeIntervalSince1970: 1_740_000_000)
    return (0..<count).map { index in
        GoldDailyClose(
            date: Calendar.goldShanghai.date(byAdding: .day, value: index, to: start)!,
            close: price(index)
        )
    }
}

private func makeNoisyCloses(count: Int) -> [GoldDailyClose] {
    makeCloses(count: count) { index in
        580 + Double(index) * 0.08 + sin(Double(index) * 0.71) * 2.4
    }
}

private func makeEngineInput(
    closes: [GoldDailyClose],
    seed: UInt64
) -> GoldWeeklyForecastEngineInput {
    let generatedAt = closes.last!.date
    return GoldWeeklyForecastEngineInput(
        closes: closes,
        startPrice: closes.last!.close,
        generatedAt: generatedAt,
        targetDate: Calendar.goldShanghai.date(byAdding: .day, value: 7, to: generatedAt)!,
        seed: seed
    )
}
```

- [ ] **Step 2: 运行并确认 engine 接口不存在**

Run: 使用 Task 1 Step 2 命令。

Expected: 编译失败，`GoldWeeklyForecastEngineInput` 或 `GoldWeeklyForecastEngine` 不存在。

- [ ] **Step 3: 定义输入和草稿**

```swift
struct GoldWeeklyForecastEngineInput: Sendable {
    let closes: [GoldDailyClose]
    let startPrice: Double
    let generatedAt: Date
    let targetDate: Date
    let seed: UInt64
}

struct GoldWeeklyForecastDraft: Sendable, Equatable {
    let direction: GoldWeeklyForecastDirection
    let expectedPrice: Double
    let expectedReturn: Double
    let p10: Double
    let p50: Double
    let p90: Double
    let components: GoldWeeklyForecastComponents
}
```

- [ ] **Step 4: 实现四个分量和固定权重**

`makeDraft` 必须使用以下公式，所有 `clamp` 范围为 -1...1：

```swift
let returns = logReturns(closes.map(\.close))
let sigma20 = max(standardDeviation(Array(returns.suffix(20))), 0.000_1)
let last = closes.last!.close
let sma20 = mean(closes.suffix(20).map(\.close))
let sma60 = mean(closes.suffix(60).map(\.close))
let trend = tanh(((sma20 - sma60) / last) / (sigma20 * sqrt(7)))

let return5 = last / closes[closes.count - 6].close - 1
let return20 = last / closes[closes.count - 21].close - 1
let momentum = tanh((0.55 * return5 + 0.45 * return20) / (sigma20 * sqrt(7)))

let std20Price = max(standardDeviation(closes.suffix(20).map(\.close)), 0.000_1)
let z20 = (last - sma20) / std20Price
let meanReversion = -tanh(z20 / 2)

let distribution = blockBootstrapFinalPrices(
    logReturns: Array(returns.suffix(120)),
    startPrice: input.startPrice,
    steps: effectiveStepsForSevenCalendarDays(closes: input.closes),
    blockLength: 3,
    simulations: GoldWeeklyForecastPolicy.simulationCount,
    seed: input.seed
)
let upCount = distribution.filter { $0 / input.startPrice - 1 > 0.005 }.count
let downCount = distribution.filter { $0 / input.startPrice - 1 < -0.005 }.count
let bootstrap = Double(upCount - downCount) / Double(distribution.count)

let composite = 0.35 * trend
    + 0.25 * momentum
    + 0.15 * meanReversion
    + 0.25 * bootstrap
```

方向使用 +/-0.18 阈值。`blockBootstrapFinalPrices` 从最近 120 个日收益抽取长度为 3 的连续区块，模拟步数取历史数据中 7 个自然日窗口包含的有效收盘点中位数并限制在 3...7，执行 2,000 次。P10/P50/P90 使用有序数组的线性百分位函数。

- [ ] **Step 5: 增加数值安全测试**

追加恒定价格、极低波动、包含重复价格三组测试，断言 draft 的所有 Double 都 `isFinite`、价格大于零、区间有序。恒定价格必须得到 flat，不得除零或产生 NaN。

- [ ] **Step 6: 运行引擎测试**

Run: 使用 Task 1 Step 2 命令。

Expected: 分类边界、三种合成序列、固定 seed 和数值安全测试全部通过。

- [ ] **Step 7: 提交**

```bash
git add CoolRun/GoldWeeklyForecastEngine.swift CoolRunTests/GoldWeeklyForecastEngineTests.swift
git commit -m "feat: add deterministic weekly gold forecast engine"
```

---

### Task 4: 建立无泄漏走步回测和发布门槛

**Files:**
- Create: `CoolRun/GoldWeeklyForecastBacktester.swift`
- Create: `CoolRunTests/GoldWeeklyForecastBacktesterTests.swift`

**Interfaces:**
- Consumes: `[GoldDailyClose]`、`seed`。
- Produces: `GoldWeeklyForecastBacktestObservation`、`GoldWeeklyForecastBacktester.evaluate(closes:seed:)`、`GoldWeeklyForecastBacktestSummary`。

在 backtester 文件中定义 internal 观察值；它不是 UI 或持久化模型：

```swift
struct GoldWeeklyForecastBacktestObservation: Sendable, Equatable {
    let anchorDate: Date
    let inputLastDate: Date
    let predicted: GoldWeeklyForecastDirection
    let actual: GoldWeeklyForecastDirection
    let predictedReturn: Double
    let actualReturn: Double
}

struct GoldWeeklyForecastBacktestTrace: Sendable, Equatable {
    let anchorDate: Date
    let inputLastDate: Date
}
```

- [ ] **Step 1: 写无泄漏、间隔和门槛失败测试**

```swift
import XCTest
@testable import CoolRun

final class GoldWeeklyForecastBacktesterTests: XCTestCase {
    func testAnchorsUseOnlyTheirHistoricalPrefixAndAreSevenDaysApart() {
        let closes = makeBacktestCloses(count: 420)
        let trace = GoldWeeklyForecastBacktester.debugTrace(closes: closes, seed: 10)
        XCTAssertTrue(trace.allSatisfy { $0.inputLastDate <= $0.anchorDate })
        for pair in zip(trace, trace.dropFirst()) {
            XCTAssertGreaterThanOrEqual(
                pair.1.anchorDate.timeIntervalSince(pair.0.anchorDate),
                7 * 24 * 60 * 60
            )
        }
    }

    func testReleaseGateRejectsFewerThanTwentyFourResolvedSamples() {
        let summary = GoldWeeklyForecastBacktester.evaluate(
            closes: makeBacktestCloses(count: 220),
            seed: 11
        )
        XCTAssertFalse(summary.passedReleaseGate)
        XCTAssertTrue(summary.failureReasons.contains("resolved_samples"))
    }

    func testMajorityClassOnlyModelCannotPassBalancedAccuracyGate() {
        let summary = GoldWeeklyForecastBacktester.makeSummary(
            observations: makeObservationsAlwaysPredictingUp()
        )
        XCTAssertFalse(summary.passedReleaseGate)
        XCTAssertLessThan(summary.balancedAccuracy ?? 1, 0.38)
    }
}
```

测试文件加入：

```swift
private func makeBacktestCloses(count: Int) -> [GoldDailyClose] {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    return (0..<count).map { index in
        GoldDailyClose(
            date: Calendar.goldShanghai.date(byAdding: .day, value: index, to: start)!,
            close: 520 + Double(index) * 0.12 + sin(Double(index) / 9) * 5
        )
    }
}

private func makeObservationsAlwaysPredictingUp() -> [GoldWeeklyForecastBacktestObservation] {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let actuals: [GoldWeeklyForecastDirection] = [.up, .up, .up, .flat, .flat, .flat, .down, .down, .down]
    return actuals.enumerated().map { index, actual in
        let date = Calendar.goldShanghai.date(byAdding: .day, value: index * 7, to: start)!
        let actualReturn: Double = actual == .up ? 0.01 : (actual == .down ? -0.01 : 0)
        return GoldWeeklyForecastBacktestObservation(
            anchorDate: date,
            inputLastDate: date,
            predicted: .up,
            actual: actual,
            predictedReturn: 0.01,
            actualReturn: actualReturn
        )
    }
}
```

- [ ] **Step 2: 运行并确认 backtester 不存在**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CoolRun.xcodeproj -scheme CoolRun -configuration Debug -derivedDataPath /private/tmp/coolRun-weekly-forecast CODE_SIGNING_ALLOWED=NO -only-testing:CoolRunTests/GoldWeeklyForecastBacktesterTests test
```

Expected: 编译失败，`GoldWeeklyForecastBacktester` 不存在。

- [ ] **Step 3: 实现走步样本生成**

固定流程：

```swift
// 第一个 anchor 必须已经拥有 120 个历史收盘点。
let shanghaiCalendar = Calendar.goldShanghai
var anchorIndex = GoldWeeklyForecastPolicy.minimumDailyCloses - 1
while anchorIndex < closes.count {
    let anchor = closes[anchorIndex]
    let prefix = Array(closes[...anchorIndex])
    let targetDate = shanghaiCalendar.date(byAdding: .day, value: 7, to: anchor.date)!
    let deadline = shanghaiCalendar.date(byAdding: .day, value: 3, to: targetDate)!
    guard let outcome = closes.first(where: { $0.date >= targetDate && $0.date <= deadline }) else {
        anchorIndex = nextAnchorIndex(
            after: anchorIndex,
            closes: closes,
            calendar: shanghaiCalendar
        ) ?? closes.count
        continue
    }
    let draft = GoldWeeklyForecastEngine.makeDraft(
        GoldWeeklyForecastEngineInput(
            closes: prefix,
            startPrice: anchor.close,
            generatedAt: anchor.date,
            targetDate: targetDate,
            seed: seed ^ UInt64(max(0, Int(anchor.date.timeIntervalSince1970)))
        )
    )
    // 保存 predicted、actual、predictedReturn、actualReturn。
    anchorIndex = nextAnchorIndex(
        after: anchorIndex,
        closes: closes,
        calendar: shanghaiCalendar
    ) ?? closes.count
}
```

不得在 anchor 特征、波动率或模拟收益中读取 `outcome` 或完整数组的未来部分。`debugTrace` 仅为 internal 测试接口。

- [ ] **Step 4: 实现指标和门槛**

`makeSummary` 必须计算混淆矩阵、每类 recall 的平均值、总体准确率、多数类基准和平均绝对收益误差。发布门槛逐项加入稳定 reason key：

```swift
if resolvedCount < 24 { reasons.append("resolved_samples") }
if classCounts.values.filter({ $0 >= 3 }).count < 3 { reasons.append("class_coverage") }
if (balancedAccuracy ?? 0) < 0.38 { reasons.append("balanced_accuracy") }
if (overallAccuracy ?? 0) < (majorityBaselineAccuracy ?? 1) { reasons.append("majority_baseline") }
if !allMetricsAreFinite { reasons.append("non_finite_metric") }
```

`passedReleaseGate = reasons.isEmpty`。

- [ ] **Step 5: 增加结果反转防泄漏测试**

用完全相同的前 200 个点构造两组数据，只修改第 200 点之后的未来价格；断言第 199 点 anchor 的预测完全一致，但 actual label 可以不同。这是防止未来数据进入预测的关键回归测试。

- [ ] **Step 6: 运行回测和引擎测试**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CoolRun.xcodeproj -scheme CoolRun -configuration Debug -derivedDataPath /private/tmp/coolRun-weekly-forecast CODE_SIGNING_ALLOWED=NO -only-testing:CoolRunTests/GoldWeeklyForecastBacktesterTests -only-testing:CoolRunTests/GoldWeeklyForecastEngineTests test
```

Expected: 全部通过；固定输入重复运行指标完全一致。

- [ ] **Step 7: 提交**

```bash
git add CoolRun/GoldWeeklyForecastBacktester.swift CoolRunTests/GoldWeeklyForecastBacktesterTests.swift
git commit -m "feat: gate weekly forecast with walk-forward validation"
```

---

### Task 5: 编排历史数据、来源兼容性和事件信心

**Files:**
- Create: `CoolRun/GoldWeeklyForecastService.swift`
- Create: `CoolRunTests/GoldWeeklyForecastServiceTests.swift`

**Interfaces:**
- Consumes: `GoldWeeklyHistoryProviding`、`GoldWeeklyForecastModelRunner`、`GoldEventImpact?`、当前价格和 source。
- Produces: `GoldWeeklyForecastProviding.fetchSnapshot(request:language:)`。

- [ ] **Step 1: 定义请求和可注入协议**

```swift
struct GoldWeeklyForecastRequest: Sendable {
    let currentPrice: Double
    let currentPriceSource: String
    let eventImpact: GoldEventImpact?
    let now: Date
}

protocol GoldWeeklyForecastProviding: Sendable {
    func fetchSnapshot(
        request: GoldWeeklyForecastRequest,
        language: AppLanguage
    ) async -> GoldWeeklyForecastSnapshot
}

struct GoldWeeklyForecastModelRunner: Sendable {
    let makeDraft: @Sendable (GoldWeeklyForecastEngineInput) -> GoldWeeklyForecastDraft?
    let backtest: @Sendable ([GoldDailyClose], UInt64) -> GoldWeeklyForecastBacktestSummary

    nonisolated static let live = Self(
        makeDraft: { GoldWeeklyForecastEngine.makeDraft($0) },
        backtest: { GoldWeeklyForecastBacktester.evaluate(closes: $0, seed: $1) }
    )
}
```

`GoldWeeklyForecastService` 构造器必须接收 `historyProvider` 和 `modelRunner`，默认分别为 `GoldMarketDataService.shared` 与 `.live`。单测注入固定 backtest/draft，不能为了制造状态去调整生产模型 fixture。

- [ ] **Step 2: 写六种服务状态失败测试**

使用 actor stub 覆盖：

1. 119 个点 -> insufficientHistory。
2. 最新点 97 小时前 -> staleData。
3. 未知当前来源 -> sourceMismatch。
4. 回测失败 -> validationFailed，forecast nil，message 包含样本或准确率原因。
5. JD 历史 + `CZB-JCJ` -> proxy，ready 时 confidence 最高 low。
6. JD 历史 + `JD-MS` -> verified，允许 medium/high。

关键断言：

```swift
XCTAssertEqual(snapshot.status, .validationFailed)
XCTAssertNil(snapshot.forecast)
XCTAssertEqual(proxySnapshot.forecast?.sourceCompatibility, .proxy)
XCTAssertLessThanOrEqual(proxySnapshot.forecast?.confidence ?? .unavailable, .low)
```

- [ ] **Step 3: 运行并确认服务不存在**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CoolRun.xcodeproj -scheme CoolRun -configuration Debug -derivedDataPath /private/tmp/coolRun-weekly-forecast CODE_SIGNING_ALLOWED=NO -only-testing:CoolRunTests/GoldWeeklyForecastServiceTests test
```

Expected: 编译失败，`GoldWeeklyForecastProviding` 不存在。

- [ ] **Step 4: 集中实现来源兼容性**

```swift
enum GoldForecastSourceCompatibilityResolver {
    nonisolated static func resolve(
        currentSource: String,
        historySource: String
    ) -> GoldForecastSourceCompatibility {
        guard historySource == GoldMarketDataService.historySourceID else { return .incompatible }
        switch currentSource {
        case "JD-MS", "JD-official": return .verified
        case "CZB-JCJ": return .proxy
        default: return .incompatible
        }
    }
}
```

这是基于代码中固定 source contract 的映射。若执行者找到接口响应中的明确产品字段，应增加解析和测试后再升级兼容性；不得只比较价格接近就改为 verified。

- [ ] **Step 5: 实现服务状态机**

顺序固定：

1. 验证 currentPrice 有限且位于 100...2,000，否则 sourceUnavailable。
2. 拉取 `.year` 历史；失败返回 sourceUnavailable。
3. normalize；少于 120 返回 insufficientHistory；超过 96 小时返回 staleData。
4. resolve source；incompatible 返回 sourceMismatch。
5. backtest；未过门槛返回 validationFailed，并保留 backtest。
6. 以 Asia/Shanghai 生成 targetDate，运行 engine。
7. 计算基础 confidence。
8. 只调整 confidence 并组装 ready snapshot。

基础 confidence：

- 120...179 个点为 low。
- >=180 且 verified、至少三个分量与最终方向一致、回测通过为 medium。
- >=240、verified、回测样本 >=36、balanced accuracy >=0.45、overall accuracy >= baseline + 0.05 才为 high。
- proxy 最终强制 cap 到 low。
- 最大自然日缺口 >14 天时降一级。

- [ ] **Step 6: 锁定事件只改信心**

增加同一 engine/backtest 输入、不同 `GoldEventImpact` 的测试：

```swift
XCTAssertEqual(aligned.direction, conflicted.direction)
XCTAssertEqual(aligned.expectedReturn, conflicted.expectedReturn)
XCTAssertEqual(aligned.p10, conflicted.p10)
XCTAssertEqual(aligned.p50, conflicted.p50)
XCTAssertEqual(aligned.p90, conflicted.p90)
XCTAssertGreaterThan(aligned.confidence, conflicted.confidence)
```

只有 event dataState 为 live、confidence 至少 medium 时允许调整。冲突时增加本地化 counterRisk；一致时增加本地化 reason。事件不得把 proxy 提升到 medium，也不得单独把 medium 提升到 high。

- [ ] **Step 7: 实现 6 小时 actor 缓存和 in-flight 合并**

缓存键：上海 day key、最新历史日线 date、modelVersion、sourceCompatibility。两个并发请求必须共享同一 Task；测试断言历史 stub 只调用一次。超过 6 小时重新计算，但正式记录的冻结由 Task 6 Store 负责。

- [ ] **Step 8: 运行服务、回测和 normalizer 测试**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CoolRun.xcodeproj -scheme CoolRun -configuration Debug -derivedDataPath /private/tmp/coolRun-weekly-forecast CODE_SIGNING_ALLOWED=NO -only-testing:CoolRunTests/GoldWeeklyForecastServiceTests -only-testing:CoolRunTests/GoldWeeklyForecastBacktesterTests -only-testing:CoolRunTests/GoldDailyCloseNormalizerTests test
```

Expected: 所列测试通过，无真实网络请求。

- [ ] **Step 9: 提交**

```bash
git add CoolRun/GoldWeeklyForecastService.swift CoolRunTests/GoldWeeklyForecastServiceTests.swift
git commit -m "feat: orchestrate weekly gold forecast safely"
```

---

### Task 6: 独立保存、冻结和验证一周预测

**Files:**
- Create: `CoolRun/GoldWeeklyForecastStore.swift`
- Create: `CoolRunTests/GoldWeeklyForecastStoreTests.swift`
- Modify: `CoolRun/DataMigrationManager.swift`
- Modify: `CoolRunTests/CountdownModelTests.swift`

**Interfaces:**
- Consumes: ready `GoldWeeklyForecastSnapshot`、`[GoldPriceRecord]`、`now`。
- Produces: `GoldWeeklyForecastRecord`、`GoldWeeklyForecastRecord.frozenSnapshot(message:)`、`GoldWeeklyForecastStore.merge(_:)`、`GoldWeeklyForecastSummary`。

- [ ] **Step 1: 定义持久化记录**

```swift
struct GoldWeeklyForecastRecord: Codable, Identifiable, Sendable, Equatable {
    enum Status: String, Codable, Sendable { case pending, validated, expired }

    let id: UUID
    let forecast: GoldWeeklyForecast
    let backtest: GoldWeeklyForecastBacktestSummary
    var status: Status
    var resolvedAt: Date?
    var endPrice: Double?
    var actualReturn: Double?
    var actualDirection: GoldWeeklyForecastDirection?
    var wasDirectionalHit: Bool?
    var absoluteReturnError: Double?
}

struct GoldWeeklyForecastSummary: Sendable, Equatable {
    let totalCount: Int
    let pendingCount: Int
    let validatedCount: Int
    let expiredCount: Int
    let hitRate: Double?
    let balancedAccuracy: Double?
    let averageAbsoluteReturnError: Double?
}

extension GoldWeeklyForecastRecord {
    nonisolated func frozenSnapshot(message: String) -> GoldWeeklyForecastSnapshot {
        GoldWeeklyForecastSnapshot(
            status: .ready,
            forecast: forecast,
            backtest: backtest,
            message: message,
            updatedAt: forecast.generatedAt
        )
    }
}
```

- [ ] **Step 2: 写每日冻结、验证和过期失败测试**

至少覆盖：

```swift
@MainActor
func testSameShanghaiDayAndModelKeepsFirstReadyForecast() throws {
    let store = makeTemporaryStore()
    let day = Date(timeIntervalSince1970: 1_788_000_000)
    store.observe(snapshot: makeReadySnapshot(generatedAt: day, startPrice: 600))
    store.observe(snapshot: makeReadySnapshot(generatedAt: day.addingTimeInterval(3600), startPrice: 610))
    XCTAssertEqual(store.records.count, 1)
    XCTAssertEqual(store.records.first?.forecast.startPrice, 600)
}

@MainActor
func testNextShanghaiDayCreatesAnotherRecord() throws {
    let store = makeTemporaryStore()
    let day = Date(timeIntervalSince1970: 1_788_000_000)
    store.observe(snapshot: makeReadySnapshot(generatedAt: day, startPrice: 600))
    store.observe(snapshot: makeReadySnapshot(generatedAt: day.addingTimeInterval(24 * 3600), startPrice: 601))
    XCTAssertEqual(store.records.count, 2)
}

@MainActor
func testValidationUsesFirstCompatiblePriceOnOrAfterDaySeven() throws {
    let store = makeTemporaryStore()
    let createdAt = Date(timeIntervalSince1970: 1_788_000_000)
    store.observe(snapshot: makeReadySnapshot(generatedAt: createdAt, startPrice: 600, currentSource: "CZB-JCJ"))
    let target = Calendar.goldShanghai.date(byAdding: .day, value: 7, to: createdAt)!
    let prices = [
        GoldPriceRecord(price: 620, timestamp: target.addingTimeInterval(-1), source: "CZB-JCJ"),
        GoldPriceRecord(price: 630, timestamp: target, source: "JD-MS"),
        GoldPriceRecord(price: 606, timestamp: target.addingTimeInterval(60), source: "CZB-JCJ")
    ]
    store.validate(with: prices, now: target.addingTimeInterval(120))
    XCTAssertEqual(store.records.first?.endPrice, 606)
    XCTAssertEqual(store.records.first?.actualDirection, .up)
}

@MainActor
func testMissingOutcomeAfterGraceExpiresRecord() throws {
    let store = makeTemporaryStore()
    let createdAt = Date(timeIntervalSince1970: 1_788_000_000)
    store.observe(snapshot: makeReadySnapshot(generatedAt: createdAt, startPrice: 600))
    let afterDeadline = Calendar.goldShanghai.date(byAdding: .day, value: 11, to: createdAt)!
    store.validate(with: [], now: afterDeadline)
    XCTAssertEqual(store.records.first?.status, .expired)
}
```

测试文件加入以下 fixture；不得读写用户真实 Store：

```swift
@MainActor
private func makeTemporaryStore() -> GoldWeeklyForecastStore {
    GoldWeeklyForecastStore(
        fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("weekly-forecast-\(UUID().uuidString).json")
    )
}

private func makeReadySnapshot(
    generatedAt: Date,
    startPrice: Double,
    currentSource: String = "JD-MS"
) -> GoldWeeklyForecastSnapshot {
    let target = Calendar.goldShanghai.date(byAdding: .day, value: 7, to: generatedAt)!
    let backtest = GoldWeeklyForecastBacktestSummary(
        resolvedCount: 30,
        classCounts: [.up: 10, .flat: 10, .down: 10],
        overallAccuracy: 0.50,
        balancedAccuracy: 0.50,
        majorityBaselineAccuracy: 1.0 / 3.0,
        meanAbsoluteReturnError: 0.01,
        confusionMatrix: [
            .up: [.up: 5, .flat: 3, .down: 2],
            .flat: [.up: 2, .flat: 5, .down: 3],
            .down: [.up: 2, .flat: 3, .down: 5]
        ],
        passedReleaseGate: true,
        failureReasons: []
    )
    let forecast = GoldWeeklyForecast(
        direction: .up,
        confidence: .low,
        startPrice: startPrice,
        expectedPrice: startPrice * 1.01,
        expectedReturn: 0.01,
        p10: startPrice * 0.98,
        p50: startPrice * 1.01,
        p90: startPrice * 1.04,
        generatedAt: generatedAt,
        targetDate: target,
        dataUpdatedAt: generatedAt,
        currentPriceSource: currentSource,
        historySource: GoldMarketDataService.historySourceID,
        sourceCompatibility: currentSource == "CZB-JCJ" ? .proxy : .verified,
        components: GoldWeeklyForecastComponents(
            trend: 0.4, momentum: 0.3, meanReversion: -0.1,
            bootstrap: 0.3, composite: 0.275
        ),
        reasons: ["fixture"],
        counterRisks: [],
        modelVersion: GoldWeeklyForecastPolicy.modelVersion
    )
    return GoldWeeklyForecastSnapshot(
        status: .ready,
        forecast: forecast,
        backtest: backtest,
        message: "ready",
        updatedAt: generatedAt
    )
}
```

+/-0.5% 边界继续复用 Task 1 分类测试。另加一项测试，在调用周 Store 前后读取 `GoldPredictionLearningEngine.makeSummary` 的同一输入，断言结果相等，证明两个引擎没有共享记录。

测试必须使用临时 fileURL 注入 Store，不能写用户真实数据目录。

- [ ] **Step 3: 实现 Store 注入点和每日 key**

```swift
@MainActor
@Observable
final class GoldWeeklyForecastStore {
    static let shared = GoldWeeklyForecastStore()

    private(set) var records: [GoldWeeklyForecastRecord]
    private(set) var summary: GoldWeeklyForecastSummary
    private let fileURL: URL
    private let calendar: Calendar

    init(fileURL: URL = GoldDataStorage.fileURL(named: "gold_weekly_forecasts.json"),
         calendar: Calendar = .goldShanghai) {
        let loaded = Self.load(from: fileURL)
        self.fileURL = fileURL
        self.calendar = calendar
        self.records = loaded
        self.summary = Self.makeSummary(records: loaded)
    }

    func record(forShanghaiDay date: Date, modelVersion: String) -> GoldWeeklyForecastRecord? {
        let key = calendar.startOfDay(for: date)
        return records.first {
            calendar.startOfDay(for: $0.forecast.generatedAt) == key &&
            $0.forecast.modelVersion == modelVersion
        }
    }

    func observe(snapshot: GoldWeeklyForecastSnapshot) {
        guard snapshot.status == .ready,
              let forecast = snapshot.forecast,
              let backtest = snapshot.backtest,
              backtest.passedReleaseGate,
              record(forShanghaiDay: forecast.generatedAt, modelVersion: forecast.modelVersion) == nil else { return }
        records.append(GoldWeeklyForecastRecord(
            id: UUID(), forecast: forecast, backtest: backtest, status: .pending,
            resolvedAt: nil, endPrice: nil, actualReturn: nil,
            actualDirection: nil, wasDirectionalHit: nil, absoluteReturnError: nil
        ))
        summary = Self.makeSummary(records: records)
        save()
    }

    func validate(with priceRecords: [GoldPriceRecord], now: Date) {
        records = records.map { Self.validated($0, with: priceRecords, now: now, calendar: calendar) }
        summary = Self.makeSummary(records: records)
        save()
    }

    func merge(_ incoming: [GoldWeeklyForecastRecord]) {
        var byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        for record in incoming where byID[record.id] == nil {
            byID[record.id] = record
        }
        records = byID.values.sorted { $0.forecast.generatedAt < $1.forecast.generatedAt }
        summary = Self.makeSummary(records: records)
        save()
    }

    nonisolated private static func load(from url: URL) -> [GoldWeeklyForecastRecord] {
        guard let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([GoldWeeklyForecastRecord].self, from: data) else { return [] }
        return records.sorted { $0.forecast.generatedAt < $1.forecast.generatedAt }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    nonisolated private static func makeSummary(
        records: [GoldWeeklyForecastRecord]
    ) -> GoldWeeklyForecastSummary {
        let validated = records.filter { $0.status == .validated }
        let hits = validated.compactMap(\.wasDirectionalHit)
        let recalls = [GoldWeeklyForecastDirection.up, .flat, .down].compactMap { actual -> Double? in
            let group = validated.filter { $0.actualDirection == actual }
            guard !group.isEmpty else { return nil }
            return Double(group.filter { $0.forecast.direction == actual }.count) / Double(group.count)
        }
        let errors = validated.compactMap(\.absoluteReturnError)
        return GoldWeeklyForecastSummary(
            totalCount: records.count,
            pendingCount: records.filter { $0.status == .pending }.count,
            validatedCount: validated.count,
            expiredCount: records.filter { $0.status == .expired }.count,
            hitRate: hits.isEmpty ? nil : Double(hits.filter { $0 }.count) / Double(hits.count),
            balancedAccuracy: recalls.count == 3 ? recalls.reduce(0, +) / 3 : nil,
            averageAbsoluteReturnError: errors.isEmpty ? nil : errors.reduce(0, +) / Double(errors.count)
        )
    }
}
```

`observe` 只接受 ready + forecast + passed backtest；同 day key + modelVersion 已存在时保持第一条不变。

- [ ] **Step 4: 实现 7 天验证**

对每条 pending record：

- `targetDate` 已保存在 forecast。
- `deadline = targetDate + 3 天`。
- 从 `GoldPriceRecord` 中选择 `[targetDate, deadline]` 内最早且来源兼容的价格。`JD-MS` 与 `JD-official` 视为同一固定来源族；`CZB-JCJ` 只能用 `CZB-JCJ` 验证；未知来源不参与。
- 有结果时计算收益、调用 `GoldWeeklyForecastDirection.classify` 并标 validated。
- now > deadline 且无结果时标 expired。
- 未到 deadline 时保持 pending。

核心验证函数写成纯函数，Store 只负责 map、汇总和保存：

```swift
nonisolated private static func validated(
    _ record: GoldWeeklyForecastRecord,
    with priceRecords: [GoldPriceRecord],
    now: Date,
    calendar: Calendar
) -> GoldWeeklyForecastRecord {
    guard record.status == .pending else { return record }
    let target = record.forecast.targetDate
    let deadline = calendar.date(byAdding: .day, value: 3, to: target)!
    let compatible = priceRecords
        .filter {
            $0.timestamp >= target && $0.timestamp <= deadline &&
            GoldForecastSourceCompatibilityResolver.canValidate(
                forecastSource: record.forecast.currentPriceSource,
                outcomeSource: $0.source
            )
        }
        .sorted { $0.timestamp < $1.timestamp }

    guard let outcome = compatible.first else {
        guard now > deadline else { return record }
        var expired = record
        expired.status = .expired
        return expired
    }

    let actualReturn = outcome.price / record.forecast.startPrice - 1
    let actualDirection = GoldWeeklyForecastDirection.classify(actualReturn: actualReturn)
    var result = record
    result.status = .validated
    result.resolvedAt = outcome.timestamp
    result.endPrice = outcome.price
    result.actualReturn = actualReturn
    result.actualDirection = actualDirection
    result.wasDirectionalHit = actualDirection == record.forecast.direction
    result.absoluteReturnError = abs(record.forecast.expectedReturn - actualReturn)
    return result
}
```

在 `GoldForecastSourceCompatibilityResolver` 增加并测试 `canValidate`：完全相同 source 返回 true；`JD-MS` 与 `JD-official` 互相兼容；其他组合返回 false。

- [ ] **Step 5: 加入备份并保持旧档案兼容**

`DataArchive` 增加：

```swift
let goldWeeklyForecastRecords: [GoldWeeklyForecastRecord]?
```

`buildArchive` 将 version 从 2 提升到 3，并写入 Store records；`restoreArchive` 对可选字段调用 `GoldWeeklyForecastStore.shared.merge(records)`。追加旧 v2 JSON 没有该字段仍能 decode、v3 可以 round-trip 的测试；`buildImportSummary` 同时显示周预测记录数量。

- [ ] **Step 6: 运行 Store、旧学习系统和备份测试**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CoolRun.xcodeproj -scheme CoolRun -configuration Debug -derivedDataPath /private/tmp/coolRun-weekly-forecast CODE_SIGNING_ALLOWED=NO -only-testing:CoolRunTests/GoldWeeklyForecastStoreTests -only-testing:CoolRunTests/GoldSignalEngineTests -only-testing:CoolRunTests/CountdownModelTests test
```

Expected: 新旧预测分开统计；旧备份可解码。

- [ ] **Step 7: 提交**

```bash
git add CoolRun/GoldWeeklyForecastStore.swift CoolRun/DataMigrationManager.swift CoolRunTests/GoldWeeklyForecastStoreTests.swift CoolRunTests/CountdownModelTests.swift
git commit -m "feat: persist and validate weekly gold forecasts"
```

---

### Task 7: 接入 ViewModel、分析卡片和独立复盘

**Files:**
- Create: `CoolRun/GoldWeeklyForecastCard.swift`
- Create: `CoolRun/GoldWeeklyForecastReviewView.swift`
- Modify: `CoolRun/GoldAnalysisView.swift`
- Modify: `CoolRun/PredictionReviewView.swift`
- Modify: `CoolRunTests/InterfaceRenderTests.swift`
- Modify: `CoolRunTests/GoldSignalEngineTests.swift`

**Interfaces:**
- Consumes: `GoldWeeklyForecastProviding`、`GoldWeeklyForecastStore`。
- Produces: `GoldAnalysisViewModel.weeklyForecastSnapshot`、`refreshWeeklyForecast(records:eventImpact:)`、两张新 View。

- [ ] **Step 1: 写 ViewModel 冻结和取消测试**

把 `GoldAnalysisViewModel` 的周预测依赖注入为 protocol。测试：

- 当天已有正式 record 时不调用 service，直接还原 snapshot。
- 当天无 record 时调用一次 service，ready 后写 Store。
- 新任务取消旧任务，迟到结果不能覆盖当天快照。
- cancel 后 `isWeeklyForecastLoading == false`。

新增属性：

```swift
private(set) var weeklyForecastSnapshot: GoldWeeklyForecastSnapshot?
private(set) var isWeeklyForecastLoading = false
private let weeklyForecastService: any GoldWeeklyForecastProviding
private let weeklyForecastStore: GoldWeeklyForecastStore
private var weeklyForecastTask: Task<Void, Never>?
```

- [ ] **Step 2: 实现刷新链路**

`refreshWeeklyForecast(records:eventImpact:)`：

1. 在 MainActor 捕获 language、最后有效 price、source 和 now。
2. 先查 Store 当天同 modelVersion 正式记录；存在则显示它，不发请求。
3. 否则取消旧任务并调用 service。
4. 任务未取消时一次性写 snapshot；ready 时 Store.observe。
5. 使用传入的本地 `GoldPriceRecord` 运行 `Store.validate(with:now:)`；验证必须检查记录 source，不能拿不同来源的远程日线替代第 7 天真实标的价格。
6. 所有退出路径复位 loading。

`refreshMarketIntelligence` 写入 snapshot 后调用周预测刷新，把 `snapshot.eventImpact` 传入。金价 records 更新时也调用一次；Store 的每日冻结防止盘中改写正式预测。`cancel()` 必须取消 weekly task。

- [ ] **Step 3: 写卡片展示状态测试**

在 `InterfaceRenderTests` 覆盖四语言 presentation：

- ready/up：未来一周、上涨、目标日期、信心、区间、回测样本。
- ready/flat 与 ready/down。
- insufficientHistory：显示当前数量和至少需要 120。
- staleData、sourceMismatch、validationFailed、sourceUnavailable。
- proxy：显示“历史模型使用国内黄金参考日线”。
- 所有状态不含“买入、卖出、加仓、减仓”。

将文案映射放入可测试纯类型：

```swift
struct GoldWeeklyForecastPresentation: Equatable {
    let title: String
    let directionText: String?
    let confidenceText: String?
    let statusText: String
    let targetText: String?
    let sourceText: String?
}
```

- [ ] **Step 4: 实现分析页卡片**

`GoldWeeklyForecastCard` 放在 `GoldDecisionSummaryCard` 之后、`marketChartCard` 之前。ready 状态显示方向、信心、目标日期、当前/预期价格、P10-P90、预期涨跌幅、4 条以内 reasons、2 条以内 counterRisks 和回测指标。

非 ready 状态保持卡片可见并显示失败原因。方向使用文字 + SF Symbol + 颜色；不能只有颜色。底部固定四语言免责声明。

- [ ] **Step 5: 实现独立周预测复盘**

`GoldWeeklyForecastReviewView` 显示：总数、pending、validated、expired、命中率、balanced accuracy、平均误差，以及每条记录的目标日期、模型版本、来源、预测/实际方向。

在 `PredictionReviewView` 顶部增加紧凑 segmented Picker，固定两个选项“30 分钟”和“一周”：选择 30 分钟时渲染现有内容，选择一周时渲染 `GoldWeeklyForecastReviewView`。不得把两个 Store 的 summary 相加；现有自动校准提示仍只来自 30 分钟 Store。Picker 选项同样提供四语言文案。

- [ ] **Step 6: 证明策略不消费周预测**

在 `GoldSignalEngineTests` 构造相同 records、snapshot、marketContext，只改变周预测对象；调用 `GoldAdvancedStrategy.analyze` 的参数保持不含周预测，断言 compositeDirection、confidence 和 suggestedExposure 相同。静态搜索也必须确认 `GoldAdvancedStrategy.swift` 没有 `GoldWeeklyForecast`。

- [ ] **Step 7: 运行 UI、ViewModel 和策略测试**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CoolRun.xcodeproj -scheme CoolRun -configuration Debug -derivedDataPath /private/tmp/coolRun-weekly-forecast CODE_SIGNING_ALLOWED=NO -only-testing:CoolRunTests/InterfaceRenderTests -only-testing:CoolRunTests/GoldWeeklyForecastServiceTests -only-testing:CoolRunTests/GoldWeeklyForecastStoreTests -only-testing:CoolRunTests/GoldSignalEngineTests test
```

Expected: 所列测试通过，四语言状态完整，策略结果不变。

- [ ] **Step 8: 提交**

```bash
git add CoolRun/GoldWeeklyForecastCard.swift CoolRun/GoldWeeklyForecastReviewView.swift CoolRun/GoldAnalysisView.swift CoolRun/PredictionReviewView.swift CoolRunTests/InterfaceRenderTests.swift CoolRunTests/GoldSignalEngineTests.swift
git commit -m "feat: present and review weekly gold forecasts"
```

---

### Task 8: 完成可靠性、发布和文档验收

**Files:**
- Modify: `docs/gold-analysis-roadmap.md`
- Test: 全部周预测测试和完整 App 测试。

**Interfaces:**
- Consumes: 完成后的周预测链路。
- Produces: 发布证据和路线图记录。

- [ ] **Step 1: 增加日历边界回归**

追加测试：月末、年末、闰年 2 月、周末和 Asia/Shanghai 时区下，targetDate 都是 generatedAt 的日历第 7 天；验证使用目标后第一笔数据且不超过 3 天宽限期。

- [ ] **Step 2: 增加数据故障矩阵**

服务测试覆盖：网络失败、空数组、全异常点、119/120/179/180/239/240 点、最新 95:59/96:01 小时、14/15 天缺口、非有限指标、并发请求合并。

- [ ] **Step 3: 增加模型版本回归**

固定 220 点 fixture 和 seed，保存 direction、components、P10/P50/P90 预期值。未来修改权重或算法导致 fixture 改变时，测试必须要求同时提升 `modelVersion`，不能静默改变历史模型语义。

- [ ] **Step 4: 更新路线图**

在 `docs/gold-analysis-roadmap.md` 记录：

- 一周三分类预测和 +/-0.5% 标签定义。
- 一年日线、走步回测、发布门槛和独立复盘。
- 京东历史与 CZB 当前价可能是 proxy；未验证时 confidence 最高 low。
- 周预测不进入交易动作和 30 分钟自动校准。
- 多年同标的日线仍是后续数据质量工作。

- [ ] **Step 5: 执行禁止耦合静态检查**

```bash
rg -n "GoldWeeklyForecast" CoolRun/GoldAdvancedStrategy.swift CoolRun/GoldPositionAdvisor.swift CoolRun/GoldPredictionLearningStore.swift
```

Expected: 无匹配。

```bash
rg -n "买入|卖出|加仓|减仓|buy|sell" CoolRun/GoldWeeklyForecastModels.swift CoolRun/GoldWeeklyForecastEngine.swift CoolRun/GoldWeeklyForecastBacktester.swift CoolRun/GoldWeeklyForecastService.swift CoolRun/GoldWeeklyForecastCard.swift
```

Expected: 除四语言免责声明测试所需的禁止词断言外无匹配；生产周预测文件不生成交易动作。

- [ ] **Step 6: 运行所有周预测测试**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CoolRun.xcodeproj -scheme CoolRun -configuration Debug -derivedDataPath /private/tmp/coolRun-weekly-forecast CODE_SIGNING_ALLOWED=NO -only-testing:CoolRunTests/GoldDailyCloseNormalizerTests -only-testing:CoolRunTests/GoldWeeklyForecastEngineTests -only-testing:CoolRunTests/GoldWeeklyForecastBacktesterTests -only-testing:CoolRunTests/GoldWeeklyForecastServiceTests -only-testing:CoolRunTests/GoldWeeklyForecastStoreTests -only-testing:CoolRunTests/InterfaceRenderTests -only-testing:CoolRunTests/GoldSignalEngineTests -only-testing:CoolRunTests/CountdownModelTests test
```

Expected: TEST SUCCEEDED，0 failures。

- [ ] **Step 7: 运行完整测试和 Release 构建**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CoolRun.xcodeproj -scheme CoolRun -configuration Debug -derivedDataPath /private/tmp/coolRun-weekly-forecast CODE_SIGNING_ALLOWED=NO test
```

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CoolRun.xcodeproj -scheme CoolRun -configuration Release -derivedDataPath /private/tmp/coolRun-weekly-forecast-release CODE_SIGNING_ALLOWED=NO build
```

Expected: TEST SUCCEEDED 和 BUILD SUCCEEDED；周预测相关文件无 actor isolation 或 Sendable 警告。

- [ ] **Step 8: 检查最终 diff 范围**

```bash
git status --short
git diff --stat
git diff -- CoolRun/GoldWeeklyForecastModels.swift CoolRun/GoldDailyCloseNormalizer.swift CoolRun/GoldWeeklyForecastEngine.swift CoolRun/GoldWeeklyForecastBacktester.swift CoolRun/GoldWeeklyForecastService.swift CoolRun/GoldWeeklyForecastStore.swift CoolRun/GoldWeeklyForecastCard.swift CoolRun/GoldWeeklyForecastReviewView.swift CoolRun/GoldMarketDataService.swift CoolRun/GoldAnalysisView.swift CoolRun/PredictionReviewView.swift CoolRun/DataMigrationManager.swift CoolRunTests/GoldDailyCloseNormalizerTests.swift CoolRunTests/GoldWeeklyForecastEngineTests.swift CoolRunTests/GoldWeeklyForecastBacktesterTests.swift CoolRunTests/GoldWeeklyForecastServiceTests.swift CoolRunTests/GoldWeeklyForecastStoreTests.swift CoolRunTests/GoldMarketDataServiceTests.swift CoolRunTests/GoldSignalEngineTests.swift CoolRunTests/InterfaceRenderTests.swift CoolRunTests/CountdownModelTests.swift docs/gold-analysis-roadmap.md
```

Expected: 只包含本计划文件；Watch 删除、剪贴板和其他用户改动仍保持执行前状态。

- [ ] **Step 9: 提交文档和最终验收**

```bash
git add docs/gold-analysis-roadmap.md
git commit -m "docs: document weekly gold forecast safeguards"
```

---

## 3. 人工验收

- [ ] 首次进入黄金分析页，一周预测卡在主策略摘要之后可见。
- [ ] ready 时明确显示“上涨/震荡/下跌”“未来一周”和目标日期。
- [ ] 少于 120 个日线点时显示历史不足，不显示任何方向。
- [ ] 回测未通过时显示失败指标，不用旧结果伪装当前预测。
- [ ] proxy 来源明确写明参考日线，信心不超过 low。
- [ ] 同一天多次刷新仍显示第一条正式预测，记录数不增加。
- [ ] 第 7 天后的第一笔有效价格可以把 pending 更新为 validated。
- [ ] 超过 3 天宽限期没有结果时显示 expired。
- [ ] 事件方向冲突只降低信心，不改变方向和价格区间。
- [ ] 一周预测变化不会改变策略结论、持仓建议或 30 分钟自动校准。
- [ ] 中文、英文、日文、韩文均无缺失或残留硬编码中文。
- [ ] VoiceOver 能读出周期、方向、信心、目标日期、区间、数据来源和风险。

## 4. 执行停止条件

执行 AI 遇到以下情况必须暂停并报告：

- 一年历史接口无法返回至少 120 个可用日线点。
- 无法确定历史价格单位为人民币/克。
- 想把 `CZB-JCJ` 与 `JD-MS-history` 直接标为 verified，却没有接口字段、文档或 30 日重叠验证证据。
- 只有修改策略阈值或持仓建议才能让预测“看起来有效”。
- 需要新增付费数据源、API Key、网页登录或反爬绕过。
- 走步回测无法达到发布门槛；不得降低门槛或调 fixture 让测试通过。
- 完整测试失败源于用户其他未提交功能，且无法用本任务测试隔离。
- 需要删除、覆盖或暂存与本任务无关的用户改动。

## 5. 完成定义

只有同时满足以下条件才可宣称完成：

1. 一周预测使用标准化日线，而非最近 24 小时价格点或“7 步等于 7 天”。
2. up/flat/down 与实际验证统一使用 +/-0.5% 阈值。
3. 回测严格走步、无未来数据泄漏并通过固定发布门槛。
4. 非 ready 状态不发布方向。
5. 来源兼容性可见，proxy confidence 最高 low。
6. 事件影响只能调整 confidence。
7. 一周预测和 30 分钟学习分开保存、分开统计。
8. 每个上海自然日和模型版本最多一条正式预测。
9. 预测可以在第 7 天验证或在宽限期后过期。
10. UI 显示方向、信心、区间、数据状态、来源、回测表现和免责声明。
11. 一周预测不改变交易策略或持仓建议。
12. 完整测试与 Release 构建成功，最终 diff 未覆盖用户其他工作。
