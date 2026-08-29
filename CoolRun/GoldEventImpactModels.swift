import Foundation

// MARK: - 事件影响领域模型
//
// 定义事件影响方向、置信度、波动风险、数据状态、证据类型、证据节点和最终 GoldEventImpact。
// 第一版只输出事件对黄金的短线方向、证据强度、波动风险、证据链和反方风险；
// 禁止输出 buy、sell、exit、减仓、卖出等独立交易动作。

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
