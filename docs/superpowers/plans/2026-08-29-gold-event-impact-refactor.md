# 黄金事件影响引擎重构 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** 把当前独立、基于标题词频并直接输出“持有/减仓/卖出”的局势感知实验，重构为复用现有黄金宏观数据链路、区分事实与推断、显式展示置信度和数据状态的事件影响解释引擎。

**Architecture:** 保留 GoldMarketContextService 作为新闻与美债数据入口，并由新的 GoldMarketIntelligenceService 同时编排宏观上下文和 GoldGlobalMarketService；GoldEventImpactAnalyzer 只消费结构化输入并生成方向、置信度、波动风险和证据链。GoldAnalysisViewModel 只保留一条宏观刷新任务，策略继续以 GoldMarketContext.overallScore 为唯一宏观数值输入，事件影响只负责解释，不能二次加权或独立生成交易动作。

**Tech Stack:** Swift 5 language mode、Swift Concurrency、Foundation URLSession/XMLParser、SwiftUI/Observation、XCTest、macOS 15.0；不新增第三方依赖。

**Spec:** docs/gold-analysis-roadmap.md（目标、阶段三数据质量、阶段四新闻语义增强、风险原则）

## Global Constraints

- 最低运行目标保持 macOS 15.0；不得更改项目部署版本、签名、Bundle Identifier 或现有 PostHog 依赖。
- 项目启用了 SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor；纯计算函数必须显式 nonisolated，语言设置必须在 MainActor 捕获后作为参数传入。
- 不增加 Python、SQLite、LLM、正文抓取器、浏览器自动化或新的 Swift Package。
- 第一版只输出事件对黄金的短线方向、证据强度、波动风险、证据链和反方风险；禁止输出 buy、sell、exit、减仓、卖出等独立交易动作。
- GoldAdvancedStrategy 只能消费一份 GoldMarketContext.overallScore；不得把 eventImpact.direction 再次加权，否则同一新闻会被重复计算。
- 数据为空、全部失败或超出最大陈旧时间时必须 fail closed：显示 unavailable，不得生成“宏观利好”“资金流入”“机会成本下降”等推断。
- 人名、机构名和会场名只能作为实体，不得单独代表方向；Warsh 不得命中 war。
- 每条可见结论必须能追溯到至少一条 observed 证据；没有 observed 证据时不得生成 inferred 传导节点。
- Google News RSS 仅作为当前兼容数据入口，不得宣称为“直接爬取证券时报/凤凰网”；不得新增绕过访问控制或授权条款的抓取逻辑。
- CME FedWatch 概率、实际利率、ETF 持仓等尚无已授权稳定接口的数据不在本计划实现范围内。UI 可以表达“未提供”，不得通过抓网页补齐。
- 所有新增用户可见文案必须同时提供中文、英文、日文、韩文。
- 当前工作区包含用户的 Watch 删除、剪贴板功能及其他未提交改动。执行时只能暂存本任务明确列出的文件，禁止 git add -A、git add .、git reset --hard 或回退用户改动。
- CoolRun 和 CoolRunTests 使用 PBXFileSystemSynchronizedRootGroup；新增 CoolRun/ 或 CoolRunTests/ 文件后通常不需要手工修改 project.pbxproj。只有 Xcode 明确未包含文件时才检查项目配置。

---

## 1. 当前问题与目标状态

### 1.1 当前实现

当前 GoldSituationAwarenessService.swift：

- 独立发起三组 Google News RSS 请求，与 GoldMarketContextService 重复。
- 只分析标题，用 contains 匹配鹰派、鸽派和避险词。
- 把沃什、鲍威尔、杰克逊霍尔等实体直接计为鹰派。
- 按新闻命中次数累加，不按事件聚类，不限制同一事件的媒体转载贡献。
- 用固定阈值生成 hold、watch、reduce、exit。
- 空数据也会生成 Assessment，并自动补齐因果链。
- UI 与 GoldAdvancedStrategy、GoldPositionAdvisor 并列展示，可能产生互相冲突的动作。

### 1.2 目标数据流

~~~text
GoldMarketContextService ── 新闻标题、来源、美债变化 ─┐
                                                     ├─> GoldMarketIntelligenceService
GoldGlobalMarketService ── XAUUSD、美元指数、汇率 ───┘              │
                                                                    ▼
                                                       GoldEventImpactAnalyzer
                                                                    │
                          ┌─────────────────────────────────────────┴──────────────────────┐
                          ▼                                                                ▼
              GoldMarketContext.overallScore                                  GoldEventImpact
              唯一宏观策略数值输入                                   解释：方向/置信度/风险/证据链
                          │                                                                │
                          ▼                                                                ▼
              GoldAdvancedStrategy / PositionAdvisor                           EventImpactCard
              统一生成最终策略或持仓建议                              不生成独立交易动作
~~~

### 1.3 第一版明确不做

- 不解析新闻正文，不声称理解完整讲话语义。
- 不使用一个沃什案例校准全部阈值。
- 不自动下单，不发送交易通知。
- 不新增后台常驻新闻轮询；只在黄金分析页进入和手动刷新时更新。
- 不持久化新闻全文。
- 不推断没有数据支持的美元涨跌、收益率涨跌或资金流入流出。

---

## 2. 文件结构与责任边界

### 新建

- CoolRun/GoldEventImpactModels.swift
  - 定义事件影响方向、置信度、波动风险、数据状态、证据类型、证据节点和最终 GoldEventImpact。
- CoolRun/GoldNewsClassifier.swift
  - 负责金融相关性过滤、英文词边界、否定窗口、来源等级、标题标准化和事件聚类。
- CoolRun/GoldEventImpactAnalyzer.swift
  - 纯函数分析器；从聚类后的新闻、美债和全球市场快照生成 GoldEventImpact。
- CoolRun/GoldMarketIntelligenceService.swift
  - 统一并发编排 GoldMarketContextService 与 GoldGlobalMarketService，返回单一快照。
- CoolRunTests/GoldNewsClassifierTests.swift
- CoolRunTests/GoldEventImpactAnalyzerTests.swift
- CoolRunTests/GoldMarketIntelligenceServiceTests.swift

### 修改

- CoolRun/GoldMarketContext.swift
  - GoldNewsItem 增加稳定 eventKey 和 sourceTier。
  - fetchContext 显式接收 language。
  - 复用 GoldNewsClassifier 过滤与聚类，不再让无关 Gold Cup 新闻进入结果。
- CoolRun/GoldGlobalMarketService.swift
  - 仅增加协议适配或测试所需接口；不得猜测新浪未验证字段。
- CoolRun/GoldAnalysisView.swift
  - ViewModel 合并三条刷新任务。
  - SituationAwarenessCard 替换为 EventImpactCard。
  - 删除独立动作、鹰鸽原始分和重复新闻列表。
- CoolRun/GoldAdvancedStrategy.swift
  - 只做兼容性确认；确保 eventImpact 不被二次加权。
- CoolRunTests/GoldSituationAwarenessTests.swift
  - 删除或迁移到新测试文件，不能保留以“沃什样例必须卖出”为验收目标的测试。
- CoolRunTests/InterfaceRenderTests.swift
  - 增加事件卡片状态文案覆盖。
- docs/gold-analysis-roadmap.md
  - 实现结束后记录统一事件影响引擎、数据状态与新闻聚类已完成。

### 删除

- CoolRun/GoldSituationAwarenessService.swift
  - 只在新分析器、新编排服务和 UI 替代均通过测试后删除。

---

## 3. 固定接口

后续任务必须沿用这些名称和语义，避免不同执行代理各自发明类型。

~~~swift
enum GoldImpactDirection: String, Sendable, Equatable {
    case bullish
    case neutral
    case bearish
}

enum GoldImpactConfidence: String, Sendable, Equatable, Comparable {
    case unavailable
    case low
    case medium
    case high
}

enum GoldVolatilityRisk: String, Sendable, Equatable {
    case normal
    case elevated
    case high
}

enum GoldEvidenceState: String, Sendable, Equatable {
    case observed
    case inferred
}

enum GoldEvidenceKind: String, Sendable, Equatable {
    case centralBankStatement
    case policyExpectation
    case treasuryYield
    case dollar
    case goldPrice
    case geopolitical
    case mediaReport
}

enum GoldIntelligenceDataState: String, Sendable, Equatable {
    case live
    case partial
    case stale
    case unavailable
}

struct GoldEventEvidence: Identifiable, Sendable, Equatable {
    let id: String
    let kind: GoldEvidenceKind
    let state: GoldEvidenceState
    let direction: GoldImpactDirection
    let summary: String
    let source: String?
    let link: URL?
    let observedAt: Date?
}

struct GoldEventImpact: Sendable, Equatable {
    let direction: GoldImpactDirection
    let confidence: GoldImpactConfidence
    let volatilityRisk: GoldVolatilityRisk
    let headline: String
    let evidence: [GoldEventEvidence]
    let counterRisks: [String]
    let updatedAt: Date
    let dataState: GoldIntelligenceDataState
}

struct GoldMarketIntelligenceSnapshot: Sendable {
    let context: GoldMarketContext
    let globalSnapshot: GoldGlobalSnapshot?
    let eventImpact: GoldEventImpact
    let updatedAt: Date
}
~~~

GoldEventImpact 的硬性不变量：

- dataState == unavailable 时 direction == neutral、confidence == unavailable、evidence 为空。
- direction != neutral 时至少存在一条 state == observed 且方向一致的证据。
- inferred 证据不能作为数组第一项，必须排在其依赖的 observed 证据之后。
- evidence 为空时只允许 unavailable；neutral 结论仍需 observed 证据说明为何中性或冲突。
- headline 只能概括已有证据，不能出现未观测到的具体概率或价格变化。
- volatilityRisk 与 direction 独立；地缘事件可以 bullish 且 high risk。

---

### Task 1: 建立事件影响领域模型和不变量

**Files:**
- Create: CoolRun/GoldEventImpactModels.swift
- Create: CoolRunTests/GoldEventImpactAnalyzerTests.swift

**Interfaces:**
- Consumes: Foundation Date、URL、AppLanguage、LocalizedString.l。
- Produces: 第 3 节列出的全部模型；GoldEventImpact.unavailable(now:language:)。

- [ ] **Step 1: 写失败测试，锁定 unavailable 和证据约束**

在 GoldEventImpactAnalyzerTests.swift 先加入：

~~~swift
import XCTest
@testable import CoolRun

final class GoldEventImpactAnalyzerTests: XCTestCase {
    func testUnavailableImpactIsNeutralAndContainsNoEvidence() {
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let impact = GoldEventImpact.unavailable(now: now, language: .chinese)

        XCTAssertEqual(impact.direction, .neutral)
        XCTAssertEqual(impact.confidence, .unavailable)
        XCTAssertEqual(impact.dataState, .unavailable)
        XCTAssertTrue(impact.evidence.isEmpty)
        XCTAssertEqual(impact.updatedAt, now)
    }

    func testDirectionalFactoryRejectsDirectionWithoutObservedEvidence() {
        let impact = GoldEventImpact.make(
            direction: .bearish,
            confidence: .high,
            volatilityRisk: .elevated,
            headline: "短线偏空",
            evidence: [],
            counterRisks: [],
            updatedAt: Date(timeIntervalSince1970: 1_788_000_000),
            dataState: .live,
            language: .chinese
        )

        XCTAssertEqual(impact.direction, .neutral)
        XCTAssertEqual(impact.confidence, .unavailable)
        XCTAssertEqual(impact.dataState, .unavailable)
    }
}
~~~

- [ ] **Step 2: 运行测试并确认因类型不存在而失败**

Run:

~~~bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CoolRun.xcodeproj -scheme CoolRun -configuration Debug -derivedDataPath /private/tmp/coolRun-event-impact CODE_SIGNING_ALLOWED=NO -only-testing:CoolRunTests/GoldEventImpactAnalyzerTests test
~~~

Expected: 编译失败，报告 GoldEventImpact、GoldImpactDirection 等类型不存在。

- [ ] **Step 3: 实现模型与安全工厂**

GoldEventImpactModels.swift 中使用显式工厂，而不是允许调用方随意构造违反约束的结果：

~~~swift
import Foundation

enum GoldImpactDirection: String, Sendable, Equatable {
    case bullish, neutral, bearish
}

enum GoldImpactConfidence: String, Sendable, Equatable, Comparable {
    case unavailable, low, medium, high

    nonisolated static func < (lhs: Self, rhs: Self) -> Bool {
        let order: [Self] = [.unavailable, .low, .medium, .high]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

enum GoldVolatilityRisk: String, Sendable, Equatable {
    case normal, elevated, high
}

enum GoldEvidenceState: String, Sendable, Equatable {
    case observed, inferred
}

enum GoldEvidenceKind: String, Sendable, Equatable {
    case centralBankStatement
    case policyExpectation
    case treasuryYield
    case dollar
    case goldPrice
    case geopolitical
    case mediaReport
}

enum GoldIntelligenceDataState: String, Sendable, Equatable {
    case live, partial, stale, unavailable
}

struct GoldEventEvidence: Identifiable, Sendable, Equatable {
    let id: String
    let kind: GoldEvidenceKind
    let state: GoldEvidenceState
    let direction: GoldImpactDirection
    let summary: String
    let source: String?
    let link: URL?
    let observedAt: Date?
}

struct GoldEventImpact: Sendable, Equatable {
    let direction: GoldImpactDirection
    let confidence: GoldImpactConfidence
    let volatilityRisk: GoldVolatilityRisk
    let headline: String
    let evidence: [GoldEventEvidence]
    let counterRisks: [String]
    let updatedAt: Date
    let dataState: GoldIntelligenceDataState

    nonisolated static func unavailable(now: Date, language: AppLanguage) -> Self {
        Self(
            direction: .neutral,
            confidence: .unavailable,
            volatilityRisk: .normal,
            headline: LocalizedString.l(
                language,
                en: "Event impact is unavailable",
                zh: "事件影响数据暂不可用",
                ja: "イベント影響データを利用できません",
                ko: "이벤트 영향 데이터를 사용할 수 없습니다"
            ),
            evidence: [],
            counterRisks: [],
            updatedAt: now,
            dataState: .unavailable
        )
    }

    nonisolated static func make(
        direction: GoldImpactDirection,
        confidence: GoldImpactConfidence,
        volatilityRisk: GoldVolatilityRisk,
        headline: String,
        evidence: [GoldEventEvidence],
        counterRisks: [String],
        updatedAt: Date,
        dataState: GoldIntelligenceDataState,
        language: AppLanguage
    ) -> Self {
        guard dataState != .unavailable, !evidence.isEmpty else {
            return .unavailable(now: updatedAt, language: language)
        }
        let hasObservedSupport = evidence.contains {
            $0.state == .observed && $0.direction == direction
        }
        let hasAnyObserved = evidence.contains { $0.state == .observed }
        let firstInferredIndex = evidence.firstIndex { $0.state == .inferred }
        let lastObservedIndex = evidence.lastIndex { $0.state == .observed }
        let evidenceOrderIsValid = firstInferredIndex == nil || (
            lastObservedIndex != nil && lastObservedIndex! < firstInferredIndex!
        )
        guard hasAnyObserved,
              (direction == .neutral || hasObservedSupport),
              evidenceOrderIsValid else {
            return .unavailable(now: updatedAt, language: language)
        }
        return Self(
            direction: direction,
            confidence: confidence,
            volatilityRisk: volatilityRisk,
            headline: headline,
            evidence: evidence,
            counterRisks: counterRisks,
            updatedAt: updatedAt,
            dataState: dataState
        )
    }
}
~~~

- [ ] **Step 4: 运行模型测试**

Run: 使用 Step 2 的同一命令。

Expected: GoldEventImpactAnalyzerTests 当前 2 项通过。

- [ ] **Step 5: 只提交本任务文件**

~~~bash
git add CoolRun/GoldEventImpactModels.swift CoolRunTests/GoldEventImpactAnalyzerTests.swift
git commit -m "refactor: define safe gold event impact models"
~~~

---

### Task 2: 建立金融新闻过滤、词边界和事件聚类

**Files:**
- Create: CoolRun/GoldNewsClassifier.swift
- Create: CoolRunTests/GoldNewsClassifierTests.swift
- Modify: CoolRun/GoldMarketContext.swift:17-24

**Interfaces:**
- Consumes: RSSParsedItem、GoldNewsItem。
- Produces:
  - GoldNewsSourceTier
  - GoldNewsClassification
  - GoldNewsClassifier.classify(title:source:)
  - GoldNewsClassifier.eventKey(title:)
  - GoldNewsClassifier.deduplicate(items:)

- [ ] **Step 1: 写反例测试**

GoldNewsClassifierTests.swift 必须包含以下完整场景：

~~~swift
import XCTest
@testable import CoolRun

final class GoldNewsClassifierTests: XCTestCase {
    func testWarshDoesNotMatchWarRiskKeyword() {
        let result = GoldNewsClassifier.classify(
            title: "Warsh discusses the policy framework",
            source: "Federal Reserve"
        )
        XCTAssertFalse(result.isGeopolitical)
        XCTAssertEqual(result.direction, .neutral)
        XCTAssertEqual(result.sentimentScore, 0)
    }

    func testPersonAndVenueDoNotImplyHawkishDirection() {
        let result = GoldNewsClassifier.classify(
            title: "Powell and Warsh attend the Jackson Hole symposium",
            source: "Reuters"
        )
        XCTAssertEqual(result.direction, .neutral)
    }

    func testNegatedRateHikeDoesNotBecomeBearish() {
        let result = GoldNewsClassifier.classify(
            title: "Fed chair says a rate hike is not decided",
            source: "Reuters"
        )
        XCTAssertNotEqual(result.direction, .bearish)
        XCTAssertGreaterThanOrEqual(result.sentimentScore, 0)
    }

    func testDownwardYieldAndDollarSignalsRemainBullishForGold() {
        let result = GoldNewsClassifier.classify(
            title: "Dollar index falls as Treasury yields decline, gold rises",
            source: "Reuters"
        )
        XCTAssertEqual(result.direction, .bullish)
    }

    func testGoldCupRacingTitleIsRejected() {
        let result = GoldNewsClassifier.classify(
            title: "2026 High Limit Racing Gold Cup results at Silver Dollar Speedway",
            source: "FloRacing"
        )
        XCTAssertFalse(result.isFinanciallyRelevant)
    }

    func testSyndicatedTitlesShareOneEventKey() {
        let lhs = GoldNewsClassifier.eventKey(
            title: "Warsh signals inflation concern; gold falls - Reuters"
        )
        let rhs = GoldNewsClassifier.eventKey(
            title: "Warsh signals inflation concern as gold falls | Yahoo Finance"
        )
        XCTAssertEqual(lhs, rhs)
    }
}
~~~

- [ ] **Step 2: 运行并确认反例测试失败**

Run:

~~~bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CoolRun.xcodeproj -scheme CoolRun -configuration Debug -derivedDataPath /private/tmp/coolRun-event-impact CODE_SIGNING_ALLOWED=NO -only-testing:CoolRunTests/GoldNewsClassifierTests test
~~~

Expected: 编译失败，因为 GoldNewsClassifier 尚不存在。

- [ ] **Step 3: 实现词边界、否定窗口和相关性规则**

分类器必须遵守：

- 中文短语可以使用 contains，但“沃什、鲍威尔、杰克逊霍尔、美联储”只能标记主题，不增加方向分。
- 英文使用正则词边界，例如 \bwar\b；不得用任意子串 contains 匹配短词。
- 否定词窗口至少覆盖目标短语前后各 24 个字符：not、no、unlikely、undecided、not decided、rules out、won't、不会、并未、否认、不考虑、尚未决定；命中后该短语不计方向分。
- 金融相关性允许两条明确路径，避免把美联储原始讲话过滤掉：
  - 黄金市场路径：黄金资产词（黄金、金价、贵金属、gold price、gold market、gold rises、gold falls、bullion、XAUUSD、XAU/USD）与金融上下文词（price、market、inflation、rate、yield、美元指数、收益率、避险）同时出现。
  - 宏观事件路径：政策实体（Fed、Federal Reserve、美联储、央行、FOMC）与政策事实（inflation、rate hike、rate cut、policy、通胀、加息、降息、货币政策）同时出现；这类标题可作为央行事件证据，即使没有 gold 一词。
- 单独的 gold、gold cup、silver dollar、人物名或 Jackson Hole 不足以通过过滤；赛车、足球、奖杯等排除词优先于包含词。

核心实现形状：

~~~swift
import Foundation

enum GoldNewsSourceTier: Int, Sendable, Equatable {
    case primary = 3
    case established = 2
    case secondary = 1
    case unknown = 0
}

struct GoldNewsClassification: Sendable, Equatable {
    let isFinanciallyRelevant: Bool
    let isGeopolitical: Bool
    let direction: GoldImpactDirection
    let sentimentScore: Double
    let matchedFacts: [GoldEvidenceKind]
    let sourceTier: GoldNewsSourceTier
}

enum GoldNewsClassifier {
    nonisolated static func classify(title: String, source: String?) -> GoldNewsClassification {
        let normalized = title.lowercased()
        let normalizedWithSource = normalized + " " + (source ?? "").lowercased()
        let relevant = !hasExcludedSportsContext(normalized) && (
            (hasGoldAssetPhrase(normalized) && hasFinancialContext(normalized)) ||
            (hasPolicyEntity(normalizedWithSource) && hasPolicyFact(normalized))
        )
        guard relevant else {
            return GoldNewsClassification(
                isFinanciallyRelevant: false,
                isGeopolitical: false,
                direction: .neutral,
                sentimentScore: 0,
                matchedFacts: [],
                sourceTier: sourceTier(source)
            )
        }

        let bearishMatches = affirmedMatches(
            in: normalized,
            phrases: ["加息", "鹰派", "美元指数上涨", "收益率上行",
                      "金价下跌", "黄金下跌", "rate hike", "hawkish",
                      "dollar index rises", "dollar index strengthens", "yields rise",
                      "yields climb", "gold price falls", "gold falls"]
        )
        let bullishMatches = affirmedMatches(
            in: normalized,
            phrases: ["降息", "鸽派", "美元指数下跌", "收益率下行",
                      "金价上涨", "黄金上涨", "避险需求", "rate cut", "dovish",
                      "dollar index falls", "dollar index weakens", "yields fall",
                      "yields decline", "gold price rises", "gold rises",
                      "safe-haven demand", "safe haven demand"]
        )
        let bearish = !bearishMatches.isEmpty
        let bullish = !bullishMatches.isEmpty
        let geopolitical = containsWholePhrase(
            in: normalized,
            phrases: ["战争", "冲突", "地缘", "war", "conflict", "geopolitical"]
        )

        let direction: GoldImpactDirection =
            bearish == bullish ? .neutral : (bearish ? .bearish : .bullish)

        return GoldNewsClassification(
            isFinanciallyRelevant: true,
            isGeopolitical: geopolitical,
            direction: direction,
            sentimentScore: makeSentimentScore(
                bearishMatches: bearishMatches,
                bullishMatches: bullishMatches
            ),
            matchedFacts: matchedKinds(in: normalized),
            sourceTier: sourceTier(source)
        )
    }
}
~~~

辅助函数必须是确定性纯函数，不读 AppSettings.shared。

makeSentimentScore 和 matchedKinds 都只能使用已经通过词边界和否定窗口确认的事实：每个独立方向事实贡献 18 分，范围限制在 -54...54；人名、机构、地点和单独的 inflation 不贡献分数。GoldMarketContextScorer.scoreNewsText 改为兼容包装并委托 GoldNewsClassifier，禁止保留旧的 raw contains 关键词计数，否则 Warsh 仍可能通过 war 被重复误判。

- [ ] **Step 4: 实现事件键和聚类去重**

eventKey 处理顺序固定为：

1. 小写。
2. 去掉常见来源后缀，例如 - Reuters、| Yahoo Finance、- 证券时报。
3. 去掉标点。
4. 把连续空白合并。
5. 去掉纯百分比、时间快照数字和无信息连接词（as、the、a、an、称、表示、据悉），保留主体词。
6. 对剩余 token 排序并连接。

完全相同 eventKey 直接归并；同一 48 小时窗口内，主体实体相同且内容 token 的 Jaccard 相似度 >= 0.72 时也归为同一事件。相似度阈值必须由测试固定，不能用标题条数动态调整。

deduplicate(items:) 规则：

- eventKey 相同只保留一条。
- 优先 sourceTier 高的条目。
- 同等级优先发布时间更新且链接存在的条目。
- 同一 eventKey 对后续评分只贡献一次。

- [ ] **Step 5: 扩展 GoldNewsItem**

将 GoldNewsItem 改为显式初始化：

~~~swift
struct GoldNewsItem: Identifiable, Sendable {
    let id: UUID
    let title: String
    let source: String?
    let link: URL?
    let publishedAt: Date?
    let sentimentScore: Double
    let eventKey: String
    let sourceTier: GoldNewsSourceTier

    nonisolated init(
        id: UUID = UUID(),
        title: String,
        source: String?,
        link: URL?,
        publishedAt: Date?,
        sentimentScore: Double,
        eventKey: String? = nil,
        sourceTier: GoldNewsSourceTier? = nil
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.link = link
        self.publishedAt = publishedAt
        self.sentimentScore = sentimentScore
        self.eventKey = eventKey ?? GoldNewsClassifier.eventKey(title: title)
        self.sourceTier = sourceTier ?? GoldNewsClassifier.sourceTier(source)
    }
}
~~~

默认参数用于兼容现有测试构造器；不得批量修改所有旧测试。

- [ ] **Step 6: 运行分类器和现有黄金测试**

Run:

~~~bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CoolRun.xcodeproj -scheme CoolRun -configuration Debug -derivedDataPath /private/tmp/coolRun-event-impact CODE_SIGNING_ALLOWED=NO -only-testing:CoolRunTests/GoldNewsClassifierTests -only-testing:CoolRunTests/GoldSituationAwarenessTests -only-testing:CoolRunTests/GoldSignalEngineTests test
~~~

Expected: 新反例测试全部通过；旧黄金分析测试仍编译通过。

- [ ] **Step 7: 提交**

~~~bash
git add CoolRun/GoldNewsClassifier.swift CoolRun/GoldMarketContext.swift CoolRunTests/GoldNewsClassifierTests.swift
git commit -m "fix: classify and cluster gold financial news"
~~~

---

### Task 3: 用结构化证据生成事件影响，不生成交易动作

**Files:**
- Create: CoolRun/GoldEventImpactAnalyzer.swift
- Modify: CoolRunTests/GoldEventImpactAnalyzerTests.swift

**Interfaces:**
- Consumes:
  - GoldEventImpactInput
  - [GoldNewsItem]
  - GoldMacroSnapshot?
  - GoldGlobalSnapshot?
- Produces:
  - GoldEventImpactAnalyzer.analyze(_:language:)

定义输入：

~~~swift
struct GoldEventImpactInput: Sendable {
    let newsItems: [GoldNewsItem]
    let macro: GoldMacroSnapshot?
    let globalSnapshot: GoldGlobalSnapshot?
    let dataState: GoldIntelligenceDataState
    let now: Date
}
~~~

dataState 由 GoldMarketIntelligenceService 根据各数据源是否成功以及数据年龄计算；分析器不自行猜测“缓存是否陈旧”。15 分钟内的内存缓存仍属于新鲜数据，只有刷新失败后回退到超过 15 分钟但不超过 6 小时的旧快照才是 stale。

- [ ] **Step 1: 写分析器失败测试**

在 GoldEventImpactAnalyzerTests.swift 增加：

~~~swift
func testEmptyInputFailsClosed() {
    let now = Date(timeIntervalSince1970: 1_788_000_000)
    let impact = GoldEventImpactAnalyzer.analyze(
        GoldEventImpactInput(
            newsItems: [],
            macro: nil,
            globalSnapshot: nil,
            dataState: .unavailable,
            now: now
        ),
        language: .chinese
    )

    XCTAssertEqual(impact.dataState, .unavailable)
    XCTAssertEqual(impact.direction, .neutral)
    XCTAssertTrue(impact.evidence.isEmpty)
}

func testHawkishNewsWithoutMarketConfirmationIsLowConfidenceBearish() {
    let now = Date(timeIntervalSince1970: 1_788_000_000)
    let item = GoldNewsItem(
        title: "Fed keeps rate hike option open; gold market watches inflation",
        source: "Reuters",
        link: URL(string: "https://example.com/fed"),
        publishedAt: now.addingTimeInterval(-600),
        sentimentScore: -18
    )

    let impact = GoldEventImpactAnalyzer.analyze(
        GoldEventImpactInput(
            newsItems: [item],
            macro: nil,
            globalSnapshot: nil,
            dataState: .partial,
            now: now
        ),
        language: .english
    )

    XCTAssertEqual(impact.direction, .bearish)
    XCTAssertEqual(impact.confidence, .low)
    XCTAssertEqual(impact.dataState, .partial)
    XCTAssertFalse(impact.headline.lowercased().contains("sell"))
}

func testHawkishNewsWithYieldRiseAndGoldDropReachesHighConfidence() {
    let now = Date(timeIntervalSince1970: 1_788_000_000)
    let item = GoldNewsItem(
        title: "Fed rate hike odds rise as gold price falls",
        source: "Reuters",
        link: URL(string: "https://example.com/market"),
        publishedAt: now.addingTimeInterval(-300),
        sentimentScore: -36
    )
    let macro = GoldMacroSnapshot(
        tenYearYield: 4.72,
        tenYearYieldChangeBps: 5.6,
        observedAt: now
    )
    let global = GoldGlobalSnapshot(
        xauUsd: 4_454.52,
        xauPrevClose: 4_601.30,
        usdCny: 7.10,
        dollarIndex: 99.71,
        updatedAt: now
    )

    let impact = GoldEventImpactAnalyzer.analyze(
        GoldEventImpactInput(
            newsItems: [item],
            macro: macro,
            globalSnapshot: global,
            dataState: .live,
            now: now
        ),
        language: .english
    )

    XCTAssertEqual(impact.direction, .bearish)
    XCTAssertEqual(impact.confidence, .high)
    XCTAssertTrue(impact.evidence.contains { $0.kind == .treasuryYield })
    XCTAssertTrue(impact.evidence.contains { $0.kind == .goldPrice })
}

func testGeopoliticalBullishImpactKeepsHighVolatilityRisk() {
    let now = Date(timeIntervalSince1970: 1_788_000_000)
    let item = GoldNewsItem(
        title: "Gold price rises on geopolitical conflict and safe-haven demand",
        source: "Reuters",
        link: nil,
        publishedAt: now,
        sentimentScore: 36
    )

    let impact = GoldEventImpactAnalyzer.analyze(
        GoldEventImpactInput(
            newsItems: [item],
            macro: nil,
            globalSnapshot: nil,
            dataState: .partial,
            now: now
        ),
        language: .english
    )

    XCTAssertEqual(impact.direction, .bullish)
    XCTAssertEqual(impact.volatilityRisk, .high)
}
~~~

- [ ] **Step 2: 运行并确认分析器不存在**

Run: 使用 Task 1 Step 2 的测试命令。

Expected: 编译失败，GoldEventImpactAnalyzer 或 GoldEventImpactInput 不存在。

- [ ] **Step 3: 实现按事件而非按标题数量聚合**

评分约束：

- 每个 eventKey 最多贡献一次方向证据。
- primary/established/secondary/unknown 的基础证据权重分别为 1.0、0.8、0.5、0.25。
- 24 小时内时间权重为 1.0，24–72 小时线性降至 0.4；无发布时间按 0.35。
- 单个事件方向绝对贡献上限为 1.0。
- 方向总分必须除以有效事件权重总和，最终范围固定为 -1...1。
- bearish 阈值 <= -0.25，bullish 阈值 >= 0.25，其余 neutral。
- 只凭媒体标题最多 low confidence。
- 至少两个独立 observed 维度一致时为 medium；至少三个维度且包含价格或收益率确认时为 high。
- dataState == partial 时 confidence 最高为 low。
- dataState == stale 时 confidence 至少下降一级且最高为 medium。
- dataState == unavailable 时直接返回 GoldEventImpact.unavailable，不运行方向聚合。

实现轮廓：

~~~swift
enum GoldEventImpactAnalyzer {
    nonisolated static func analyze(
        _ input: GoldEventImpactInput,
        language: AppLanguage
    ) -> GoldEventImpact {
        let news = GoldNewsClassifier.deduplicate(items: input.newsItems)
        let observed = makeObservedEvidence(
            news: news,
            macro: input.macro,
            global: input.globalSnapshot,
            now: input.now,
            language: language
        )
        guard !observed.isEmpty else {
            return .unavailable(now: input.now, language: language)
        }

        let direction = aggregateDirection(observed)
        guard input.dataState != .unavailable else {
            return .unavailable(now: input.now, language: language)
        }
        let dataState = input.dataState
        let confidence = makeConfidence(
            evidence: observed,
            dataState: dataState
        )
        let inferred = makeInferences(
            from: observed,
            direction: direction,
            language: language
        )

        return .make(
            direction: direction,
            confidence: confidence,
            volatilityRisk: makeVolatilityRisk(observed),
            headline: makeHeadline(direction, confidence, language),
            evidence: observed + inferred,
            counterRisks: makeCounterRisks(direction, observed, language),
            updatedAt: input.now,
            dataState: dataState,
            language: language
        )
    }
}
~~~

- [ ] **Step 4: 限制传导推断**

makeInferences 只能按已有节点生成：

- centralBankStatement bearish + treasuryYield bearish：
  - 可推断“利率环境对无息资产估值形成压力”。
- dollar bearish + goldPrice bearish：
  - 可推断“美元与黄金价格反向变化相互印证”。
- geopolitical bullish：
  - 可推断“避险需求可能支撑黄金”，同时必须加入“地缘溢价可能快速回吐”。
- 只有新闻、没有收益率/价格/美元确认：
  - 不得生成“资金撤出黄金”或“资金流入黄金”。
- dollarIndex 只有当前值，没有前值：
  - 不得生成 dollar 方向证据。

- [ ] **Step 5: 运行分析器测试**

Run: 使用 Task 1 Step 2 的测试命令。

Expected: 所有 GoldEventImpactAnalyzerTests 通过。

- [ ] **Step 6: 提交**

~~~bash
git add CoolRun/GoldEventImpactAnalyzer.swift CoolRunTests/GoldEventImpactAnalyzerTests.swift
git commit -m "feat: explain gold event impact from observed evidence"
~~~

---

### Task 4: 让现有宏观服务复用分类器并显式传入语言

**Files:**
- Modify: CoolRun/GoldMarketContext.swift:32-140,150-240,321-395
- Create: CoolRunTests/GoldMarketContextTests.swift

**Interfaces:**
- Consumes: GoldNewsClassifier。
- Produces:
  - GoldMarketContextService.fetchContext(now:language:)
  - 可注入 URLSession 的稳定行为。

- [ ] **Step 1: 写 RSS 过滤与失败状态测试**

GoldMarketContextTests.swift 使用自定义 URLProtocol 返回固定 RSS，不访问真实网络。固定 RSS 至少包含：

- 一条 Reuters 黄金/美联储新闻。
- 一条证券时报黄金/收益率新闻。
- 一条 Gold Cup 赛车新闻。
- 两条同一事件的轻微改写转载。

断言：

~~~swift
XCTAssertEqual(context.newsItems.count, 2)
XCTAssertFalse(context.newsItems.contains { $0.title.contains("Gold Cup") })
XCTAssertEqual(Set(context.newsItems.map(\.eventKey)).count, context.newsItems.count)
~~~

同时增加全部请求失败时：

~~~swift
XCTAssertTrue(context.isPartial)
XCTAssertNotNil(context.missingDataDescription)
~~~

- [ ] **Step 2: 运行并确认测试失败**

Run:

~~~bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CoolRun.xcodeproj -scheme CoolRun -configuration Debug -derivedDataPath /private/tmp/coolRun-event-impact CODE_SIGNING_ALLOWED=NO -only-testing:CoolRunTests/GoldMarketContextTests test
~~~

Expected: RSS 仍会保留无关和重复结果，或 fetchContext 仍会隐式读取全局语言。

- [ ] **Step 3: 修改 fetchContext 接口，消除主线程隔离警告**

接口改为：

~~~swift
func fetchContext(
    now: Date = Date(),
    language: AppLanguage
) async throws -> GoldMarketContext
~~~

服务内部不得再读取 AppSettings.shared.language。调用方 GoldAnalysisViewModel 在 MainActor 上先捕获：

~~~swift
let language = AppSettings.shared.language
~~~

再传入异步服务。

- [ ] **Step 4: 在一处完成过滤和聚类**

fetchGoldNews 返回前执行：

~~~swift
let classified = merged.compactMap { item -> GoldNewsItem? in
    let classification = GoldNewsClassifier.classify(
        title: item.title,
        source: item.source
    )
    guard classification.isFinanciallyRelevant else { return nil }
    return GoldNewsItem(
        title: item.title,
        source: item.source,
        link: item.link,
        publishedAt: item.publishedAt,
        sentimentScore: classification.sentimentScore,
        eventKey: GoldNewsClassifier.eventKey(title: item.title),
        sourceTier: classification.sourceTier
    )
}
return Array(GoldNewsClassifier.deduplicate(items: classified).prefix(30))
~~~

GoldMarketContextScorer 只能消费已经去重的 items。
GoldMarketContextScorer.scoreNewsText 必须委托 GoldNewsClassifier，不得保留第二套关键词表。

- [ ] **Step 5: 保持 GoldMarketContext 的策略边界**

不要把 eventImpact 写进 GoldMarketContext。GoldMarketContext 继续只承载现有宏观评分与原始上下文，GoldMarketIntelligenceSnapshot 在外层并列持有 context 与 eventImpact。这样 GoldAdvancedStrategy 无法因为类型扩展而意外重复消费同一事件。

- [ ] **Step 6: 运行上下文、分类器和信号测试**

Run:

~~~bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CoolRun.xcodeproj -scheme CoolRun -configuration Debug -derivedDataPath /private/tmp/coolRun-event-impact CODE_SIGNING_ALLOWED=NO -only-testing:CoolRunTests/GoldMarketContextTests -only-testing:CoolRunTests/GoldNewsClassifierTests -only-testing:CoolRunTests/GoldSignalEngineTests test
~~~

Expected: 三组测试通过，无 main actor-isolated AppSettings.shared.language 警告来自 GoldMarketContextService。

- [ ] **Step 7: 提交**

~~~bash
git add CoolRun/GoldMarketContext.swift CoolRunTests/GoldMarketContextTests.swift
git commit -m "refactor: reuse one filtered gold news context"
~~~

---

### Task 5: 建立统一宏观编排服务

**Files:**
- Create: CoolRun/GoldMarketIntelligenceService.swift
- Create: CoolRunTests/GoldMarketIntelligenceServiceTests.swift
- Modify: CoolRun/GoldMarketContext.swift
- Modify: CoolRun/GoldGlobalMarketService.swift

**Interfaces:**
- Consumes:
  - GoldMarketContextProviding.fetchContext(now:language:)
  - GoldGlobalMarketProviding.fetchSnapshot(now:)
  - GoldEventImpactAnalyzer.analyze(_:language:)
- Produces:
  - GoldMarketIntelligenceProviding.fetchSnapshot(now:language:)
  - GoldMarketIntelligenceService.fetchSnapshot(now:language:)
  - GoldMarketIntelligenceSnapshot

- [ ] **Step 1: 为底层服务定义窄协议**

~~~swift
protocol GoldMarketContextProviding: Sendable {
    func fetchContext(now: Date, language: AppLanguage) async throws -> GoldMarketContext
}

protocol GoldGlobalMarketProviding: Sendable {
    func fetchSnapshot(now: Date) async throws -> GoldGlobalSnapshot
}

protocol GoldMarketIntelligenceProviding: Sendable {
    func fetchSnapshot(
        now: Date,
        language: AppLanguage
    ) async -> GoldMarketIntelligenceSnapshot
}
~~~

让 GoldMarketContextService、GoldGlobalMarketService 和 GoldMarketIntelligenceService 遵循对应协议。不要把 UI、AppSettings 或 ViewModel 放入协议。

- [ ] **Step 2: 写编排服务失败测试**

使用 actor stub 记录调用次数，并覆盖：

1. 两个数据源都成功：各调用一次，snapshot 同时包含原始 context 与 eventImpact。
2. global 失败：context 仍返回，eventImpact.dataState 为 partial。
3. context 抛错：返回安全的不可用快照，不生成方向证据。
4. 两个并发调用：服务的 15 分钟缓存或 in-flight task 合并，底层每个源只调用一次。

关键断言：

~~~swift
XCTAssertEqual(await contextStub.callCount, 1)
XCTAssertEqual(await globalStub.callCount, 1)
XCTAssertEqual(snapshot.eventImpact.dataState, .partial)
XCTAssertEqual(snapshot.context.overallScore, expectedContext.overallScore)
~~~

- [ ] **Step 3: 运行并确认编排类型不存在**

Run:

~~~bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CoolRun.xcodeproj -scheme CoolRun -configuration Debug -derivedDataPath /private/tmp/coolRun-event-impact CODE_SIGNING_ALLOWED=NO -only-testing:CoolRunTests/GoldMarketIntelligenceServiceTests test
~~~

Expected: 编译失败，GoldMarketIntelligenceService 尚不存在。

- [ ] **Step 4: 实现单一刷新与安全降级**

服务实现形状：

~~~swift
final class GoldMarketIntelligenceService: Sendable {
    private let contextProvider: any GoldMarketContextProviding
    private let globalProvider: any GoldGlobalMarketProviding

    init(
        contextProvider: any GoldMarketContextProviding = GoldMarketContextService(),
        globalProvider: any GoldGlobalMarketProviding = GoldGlobalMarketService.shared
    ) {
        self.contextProvider = contextProvider
        self.globalProvider = globalProvider
    }

    func fetchSnapshot(
        now: Date = Date(),
        language: AppLanguage
    ) async -> GoldMarketIntelligenceSnapshot {
        async let contextResult = captureContext(now: now, language: language)
        async let globalResult = captureGlobal(now: now)

        let context = await contextResult
        let global = await globalResult
        return makeSnapshot(
            contextResult: context,
            globalResult: global,
            now: now,
            language: language
        )
    }

    private func captureContext(
        now: Date,
        language: AppLanguage
    ) async -> Result<GoldMarketContext, Error> {
        do {
            return .success(try await contextProvider.fetchContext(now: now, language: language))
        } catch {
            return .failure(error)
        }
    }

    private func captureGlobal(
        now: Date
    ) async -> Result<GoldGlobalSnapshot, Error> {
        do {
            return .success(try await globalProvider.fetchSnapshot(now: now))
        } catch {
            return .failure(error)
        }
    }
}
~~~

不得使用 try? 后丢失是哪个数据源失败的信息；makeSnapshot 必须能区分 context 失败、global 失败和双失败。

- [ ] **Step 5: 组装 eventImpact，避免二次打分**

makeSnapshot：

- context 成功时，用 context.newsItems、context.macro 和 globalSnapshot 运行 analyzer。
- 不修改 context.overallScore。
- context 失败时构造 isPartial == true、overallScore == 0 的安全上下文，并让 snapshot.eventImpact == unavailable。
- context 成功、global 失败时传 nil，并向 analyzer 传 dataState == partial。
- 先计算 sourceAge = now - min(context.updatedAt, global.updatedAt)；任一实际使用的数据超过 15 分钟且不超过 6 小时时，dataState 优先为 stale。
- 数据均不超过 15 分钟时：若任一数据源失败或 context.isPartial 为 true，dataState == partial；否则为 live。
- 任一方向分析必需的数据超过 6 小时不得继续参与证据计算。

- [ ] **Step 6: 实现并发请求合并**

使用 actor 缓存：

~~~swift
private actor GoldMarketIntelligenceCache {
    var entry: (snapshot: GoldMarketIntelligenceSnapshot, savedAt: Date)?
    var inFlight: Task<GoldMarketIntelligenceSnapshot, Never>?
}
~~~

规则：

- 15 分钟内直接返回缓存，保留原 live 或 partial 状态和原 updatedAt；这是新鲜缓存，不标 stale。
- 已有 inFlight 时 await 同一任务。
- 任务结束后保存快照并清空 inFlight。
- 超过 15 分钟后先刷新；刷新失败才允许回退旧快照并标 stale。
- stale 数据最多展示 6 小时；超过 6 小时返回 unavailable。
- context.isFromCache 只说明来源于内存，不等于陈旧；陈旧状态只由 now - snapshot.updatedAt > 15 分钟且本次刷新失败确定。

- [ ] **Step 7: 运行编排服务测试**

Run: 使用 Step 3 的命令。

Expected: 所有成功、部分失败、全部失败、并发合并场景通过。

- [ ] **Step 8: 提交**

~~~bash
git add CoolRun/GoldMarketIntelligenceService.swift CoolRun/GoldMarketContext.swift CoolRun/GoldGlobalMarketService.swift CoolRunTests/GoldMarketIntelligenceServiceTests.swift
git commit -m "refactor: unify gold market intelligence refresh"
~~~

---

### Task 6: ViewModel 改为单一宏观状态源并移除旧服务

**Files:**
- Modify: CoolRun/GoldAnalysisView.swift:34-218,520-610,1010-1050
- Delete: CoolRun/GoldSituationAwarenessService.swift
- Delete or rewrite: CoolRunTests/GoldSituationAwarenessTests.swift
- Modify: CoolRunTests/GoldSignalEngineTests.swift

**Interfaces:**
- Consumes: GoldMarketIntelligenceService.fetchSnapshot(now:language:)。
- Produces:
  - GoldAnalysisViewModel.marketIntelligence
  - refreshMarketIntelligence(records:candlePeriod:)
  - eventImpact 从 marketIntelligence.eventImpact 派生。

- [ ] **Step 1: 写 ViewModel 状态一致性测试**

如果 GoldAnalysisViewModel 的 private 可见性阻止单测，先把它从 private 改为 internal，不要暴露为 public。

测试使用 stub intelligence service，断言一次刷新后：

~~~swift
XCTAssertEqual(viewModel.marketIntelligence?.eventImpact, viewModel.eventImpact)
XCTAssertEqual(viewModel.marketContext?.overallScore, snapshot.context.overallScore)
XCTAssertEqual(viewModel.globalSnapshot?.xauUsd, snapshot.globalSnapshot?.xauUsd)
XCTAssertFalse(viewModel.isMarketIntelligenceLoading)
~~~

再覆盖 cancel 后 loading 为 false、迟到任务不得覆盖新快照。

- [ ] **Step 2: 运行并确认当前 ViewModel 没有统一接口**

Run:

~~~bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CoolRun.xcodeproj -scheme CoolRun -configuration Debug -derivedDataPath /private/tmp/coolRun-event-impact CODE_SIGNING_ALLOWED=NO -only-testing:CoolRunTests/GoldSignalEngineTests test
~~~

Expected: 新测试因统一状态属性或注入构造器不存在而失败。

- [ ] **Step 3: 合并 ViewModel 状态和任务**

删除：

- situationService
- situationTask
- refreshSituationAwareness()
- globalMarketTask
- 独立 refreshGlobalMarket()
- marketContextTask

新增：

~~~swift
private(set) var marketIntelligence: GoldMarketIntelligenceSnapshot?
private(set) var isMarketIntelligenceLoading = false
private let marketIntelligenceService: any GoldMarketIntelligenceProviding
private var marketIntelligenceTask: Task<Void, Never>?

var eventImpact: GoldEventImpact? {
    marketIntelligence?.eventImpact
}
~~~

refreshMarketIntelligence 必须：

1. 在 MainActor 捕获 language。
2. 取消上一任务。
3. 请求统一 snapshot。
4. 一次性写入 marketIntelligence、marketContext、globalSnapshot。
5. 清空 lastRecordsSignature 并触发一次 refresh(records:candlePeriod:)。
6. 无论成功、取消还是失败都正确结束 loading；取消任务不得写入旧数据。

- [ ] **Step 4: 合并 View 生命周期调用**

页面 task 和手动刷新只调用：

~~~swift
viewModel.refreshMarketIntelligence(
    records: store.records,
    candlePeriod: candlePeriod
)
~~~

不得再出现 refreshMarketContext、refreshGlobalMarket、refreshSituationAwareness 三连调用。

- [ ] **Step 5: 删除旧服务和旧目标测试**

在下列条件均满足后删除 GoldSituationAwarenessService.swift：

- GoldEventImpactAnalyzerTests 通过。
- GoldMarketIntelligenceServiceTests 通过。
- GoldAnalysisView 不再引用 GoldSituationAssessment、GoldSituationAction 或 GoldSituationDetector。

GoldSituationAwarenessTests.swift 中有价值的反例迁移到新测试文件；删除“沃什场景必须减仓或卖出”的断言，因为它违反统一策略边界。

- [ ] **Step 6: 确认高级策略没有重复加权**

GoldAdvancedStrategy.swift 中仍只读取 marketContext.overallScore。增加测试：

- 相同 overallScore、不同 eventImpact explanation 得到相同 compositeDirection 和 suggestedExposure。
- 这证明 eventImpact 未被重复计入策略。

- [ ] **Step 7: 运行黄金核心测试**

Run:

~~~bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CoolRun.xcodeproj -scheme CoolRun -configuration Debug -derivedDataPath /private/tmp/coolRun-event-impact CODE_SIGNING_ALLOWED=NO -only-testing:CoolRunTests/GoldEventImpactAnalyzerTests -only-testing:CoolRunTests/GoldNewsClassifierTests -only-testing:CoolRunTests/GoldMarketContextTests -only-testing:CoolRunTests/GoldMarketIntelligenceServiceTests -only-testing:CoolRunTests/GoldSignalEngineTests -only-testing:CoolRunTests/GoldPositionAdvisorTests test
~~~

Expected: 所列测试全部通过；源码搜索不再找到 GoldSituationAssessment、GoldSituationAction、GoldSituationDetector。

- [ ] **Step 8: 提交**

~~~bash
git add CoolRun/GoldAnalysisView.swift CoolRun/GoldAdvancedStrategy.swift CoolRunTests/GoldSignalEngineTests.swift CoolRunTests/GoldSituationAwarenessTests.swift
git add CoolRun/GoldSituationAwarenessService.swift
git commit -m "refactor: replace standalone situation awareness pipeline"
~~~

注意：git add 已删除路径是为了记录删除，不是恢复文件。

---

### Task 7: 用事件影响卡片替换交易动作卡片

**Files:**
- Modify: CoolRun/GoldAnalysisView.swift:2038-2308
- Modify: CoolRunTests/InterfaceRenderTests.swift

**Interfaces:**
- Consumes: GoldEventImpact?、isMarketIntelligenceLoading。
- Produces: EventImpactCard。

- [ ] **Step 1: 写文案与状态测试**

至少覆盖：

- unavailable：显示“事件影响数据暂不可用”，没有“卖出/减仓/持有”。
- partial：显示“数据不完整”，置信度最高为低。
- stale：显示缓存标识和更新时间。
- bearish high：显示“短线偏空”“证据强度高”“波动风险升高”。
- bullish high risk：方向利多但风险仍高，颜色和标签不能把 high risk 显示为 low。
- evidence：observed 与 inferred 有不同标签。

如果 InterfaceRenderTests 只验证关键字符串，新增纯文案辅助：

~~~swift
struct GoldEventImpactPresentation: Equatable {
    let directionText: String
    let confidenceText: String
    let dataStateText: String
    let riskText: String
}
~~~

将文案映射做成纯函数后测试，不要求引入 UI snapshot 框架。

- [ ] **Step 2: 运行并确认旧卡片仍暴露动作**

Run:

~~~bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CoolRun.xcodeproj -scheme CoolRun -configuration Debug -derivedDataPath /private/tmp/coolRun-event-impact CODE_SIGNING_ALLOWED=NO -only-testing:CoolRunTests/InterfaceRenderTests test
~~~

Expected: 新状态文案测试失败，旧 UI 仍引用 assessment.action。

- [ ] **Step 3: 实现 EventImpactCard**

卡片固定结构：

~~~text
事件影响                         数据截至 14:03
短线偏空   证据强度：高   波动风险：升高
美联储抗通胀立场与收益率、黄金价格反应相互印证

已确认
• 美联储讲话强调通胀目标
• 10 年期美债收益率上行 5.6bp
• XAUUSD 当日下跌 3.2%

推断
• 利率环境可能提高持有无息资产的机会成本

反方风险
• 市场已快速定价，后续数据转弱可能逆转走势
~~~

实现约束：

- 不显示 hawkishScore、dovishScore 或无单位数字分。
- 不显示 hold、reduce、exit。
- observed 证据放在 inferred 之前。
- evidence 为空时不展示空 DisclosureGroup。
- stale/partial/unavailable 都必须用文字和图标表达，不能只靠颜色。
- 新闻链接只挂在对应 observed 媒体证据上。
- 默认展开最多 3 条 observed、2 条 inferred；其余用 DisclosureGroup。

- [ ] **Step 4: 删除旧 UI 类型**

删除 SituationAwarenessCard 及其 actionRow、scorePill。若其中 newsRow 可复用，应迁移到 EventImpactCard 内并按 GoldEventEvidence 渲染，不能继续依赖 GoldSituationAssessment。

- [ ] **Step 5: 加入风险说明**

卡片底部固定小字：

- 中文：“事件影响为基于公开数据的逻辑分析，不构成投资建议。”
- 英文：“Event impact is a logical analysis of public data, not investment advice.”
- 日文和韩文提供等义表达。

- [ ] **Step 6: 运行 UI 与黄金核心测试**

Run:

~~~bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CoolRun.xcodeproj -scheme CoolRun -configuration Debug -derivedDataPath /private/tmp/coolRun-event-impact CODE_SIGNING_ALLOWED=NO -only-testing:CoolRunTests/InterfaceRenderTests -only-testing:CoolRunTests/GoldPositionAdvisorTests -only-testing:CoolRunTests/GoldSignalEngineTests test
~~~

Expected: 所列测试通过；搜索 GoldAnalysisView.swift 不再包含 assessment.action、鹰派分、鸽派分。

- [ ] **Step 7: 提交**

~~~bash
git add CoolRun/GoldAnalysisView.swift CoolRunTests/InterfaceRenderTests.swift
git commit -m "feat: present evidence-based gold event impact"
~~~

---

### Task 8: 完成缓存、错误状态和可维护性验收

**Files:**
- Modify: CoolRunTests/GoldMarketIntelligenceServiceTests.swift
- Modify: CoolRunTests/GoldEventImpactAnalyzerTests.swift
- Modify: docs/gold-analysis-roadmap.md

**Interfaces:**
- Consumes: 完成后的全部统一宏观接口。
- Produces: 回归保护、文档记录和发布验收证据。

- [ ] **Step 1: 增加缓存边界测试**

固定 now，不使用真实 Date() 漂移：

- 14 分 59 秒：live cache hit。
- 15 分 01 秒：重新拉取。
- 新拉取失败但旧数据 5 小时 59 分：stale。
- 旧数据 6 小时 01 分：unavailable。
- stale 不得保留 high confidence。

- [ ] **Step 2: 增加矛盾证据测试**

场景：

- 新闻偏空、收益率下行、黄金上涨。
- 预期结果 direction == neutral 或 confidence == low。
- counterRisks 至少包含一条“市场数据未确认媒体方向”的本地化提示。

不得用简单票数让三篇转载新闻压过两个真实市场维度。

- [ ] **Step 3: 增加来源质量测试**

- 官方美联储来源识别为 primary。
- Reuters、AP、证券时报、凤凰财经识别为 established。
- 未知博客为 unknown。
- 来源等级只影响 confidence，不得改变一条证据本身的方向。

来源表必须集中在 GoldNewsClassifier.swift，不能散落在 UI 和服务中。

- [ ] **Step 4: 更新路线图**

在 docs/gold-analysis-roadmap.md 的阶段三与阶段四记录：

- 宏观与事件影响已统一为一个刷新链路。
- 新闻完成金融相关性过滤、词边界、否定处理、事件聚类和来源等级。
- 事件卡片区分 observed/inferred、数据状态、置信度与波动风险。
- 未接入 CME/实际利率/ETF，原因是尚无明确授权且稳定的数据接口。

- [ ] **Step 5: 执行源码静态检查**

Run:

~~~bash
rg -n "GoldSituationAssessment|GoldSituationAction|GoldSituationDetector|refreshSituationAwareness|situationTask|assessment\.action|鹰派分|鸽派分" CoolRun CoolRunTests
~~~

Expected: 无匹配。

Run:

~~~bash
rg -n "AppSettings\.shared\.language" CoolRun/GoldEventImpactModels.swift CoolRun/GoldNewsClassifier.swift CoolRun/GoldEventImpactAnalyzer.swift CoolRun/GoldMarketIntelligenceService.swift
~~~

Expected: 无匹配；语言由调用方显式传入。

- [ ] **Step 6: 运行完整测试**

Run:

~~~bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CoolRun.xcodeproj -scheme CoolRun -configuration Debug -derivedDataPath /private/tmp/coolRun-event-impact CODE_SIGNING_ALLOWED=NO test
~~~

Expected: TEST SUCCEEDED，0 个失败。

- [ ] **Step 7: 运行 Release 构建**

Run:

~~~bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CoolRun.xcodeproj -scheme CoolRun -configuration Release -derivedDataPath /private/tmp/coolRun-event-impact-release CODE_SIGNING_ALLOWED=NO build
~~~

Expected: BUILD SUCCEEDED；事件影响相关文件无 actor isolation 警告。

- [ ] **Step 8: 检查最终 diff 范围**

Run:

~~~bash
git status --short
git diff --stat
git diff -- CoolRun/GoldEventImpactModels.swift CoolRun/GoldNewsClassifier.swift CoolRun/GoldEventImpactAnalyzer.swift CoolRun/GoldMarketIntelligenceService.swift CoolRun/GoldMarketContext.swift CoolRun/GoldGlobalMarketService.swift CoolRun/GoldAnalysisView.swift CoolRun/GoldAdvancedStrategy.swift CoolRunTests/GoldNewsClassifierTests.swift CoolRunTests/GoldEventImpactAnalyzerTests.swift CoolRunTests/GoldMarketContextTests.swift CoolRunTests/GoldMarketIntelligenceServiceTests.swift CoolRunTests/GoldSignalEngineTests.swift CoolRunTests/InterfaceRenderTests.swift docs/gold-analysis-roadmap.md
~~~

Expected:

- 只审查本计划文件。
- 用户原有 Watch 删除、剪贴板改动和其他工作仍保持原状态。
- project.pbxproj 未因新增同步目录文件产生无意义的手工条目。

- [ ] **Step 9: 提交最终测试与文档**

~~~bash
git add CoolRunTests/GoldMarketIntelligenceServiceTests.swift CoolRunTests/GoldEventImpactAnalyzerTests.swift docs/gold-analysis-roadmap.md
git commit -m "test: verify gold event impact reliability"
~~~

---

## 4. 人工验收清单

执行 AI 完成自动化测试后，必须在真实 App 中检查：

- [ ] 进入黄金分析页只发起一组宏观情报刷新，不出现重复 Google News 请求。
- [ ] 无网首次打开时显示“事件影响数据暂不可用”，不显示利多、利空或交易动作。
- [ ] 有缓存但网络失败时显示“缓存/数据陈旧”和具体更新时间。
- [ ] 沃什新闻可以显示“短线偏空”，但不能出现“卖出”。
- [ ] Gold Cup 赛车新闻不出现在证据列表。
- [ ] 新闻偏空但市场数据反向时显示“证据冲突/置信度低”，不能高置信度偏空。
- [ ] 地缘冲突可以显示利多黄金，同时显示高波动风险。
- [ ] 主结论、宏观卡片和持仓建议不存在相互冲突的独立动作。
- [ ] 中文、英文、日文、韩文切换后没有残留硬编码中文。
- [ ] VoiceOver 能读出方向、置信度、数据状态和风险，信息不只依赖红绿颜色。

---

## 5. 执行中的停止条件

遇到以下情况，执行 AI 必须停止扩展范围并向用户说明，不得自行发明替代方案：

- 需要一个新的付费或要求 API Key 的数据源。
- 需要解析受登录、验证码或反爬保护的网页。
- 需要修改 GoldAdvancedStrategy 的核心阈值才能让 UI 看起来一致。
- 发现新浪美元指数响应没有已验证的昨收字段，却想推断美元涨跌。
- 完整测试失败来自用户其他未提交功能，且无法通过只运行本任务测试隔离。
- 需要删除或覆盖与本任务无关的用户改动。

---

## 6. 完成定义

只有同时满足以下条件，才可以宣称重构完成：

1. 独立 GoldSituationAwarenessService 和 GoldSituationAction 已删除。
2. 宏观新闻只抓取、过滤、聚类一次。
3. 空数据严格返回 unavailable，不生成任何因果链。
4. Warsh/war、否定句、方向矛盾、Gold Cup、重复转载都有自动化回归测试。
5. UI 不再显示独立持有/减仓/卖出动作。
6. EventImpactCard 显示方向、置信度、数据状态、更新时间、observed/inferred 证据和反方风险。
7. GoldAdvancedStrategy 仍只使用 GoldMarketContext.overallScore 一次。
8. 完整测试和 Release 构建成功。
9. 没有引入新依赖、正文抓取、CME 网页爬虫或 LLM。
10. 最终 diff 未覆盖用户其他未提交工作。
