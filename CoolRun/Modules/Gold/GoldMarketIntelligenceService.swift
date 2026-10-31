import Foundation

// MARK: - 编排协议
//
// 窄协议：只暴露统一宏观编排所需的最小接口，
// 不包含 UI、AppSettings 或 ViewModel。

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

extension GoldMarketContextService: GoldMarketContextProviding {}
extension GoldGlobalMarketService: GoldGlobalMarketProviding {}

// MARK: - 统一宏观情报快照

/// 单一快照：宏观上下文 + 全球市场 + 事件影响解释。
/// context.overallScore 仍是唯一宏观策略数值输入；
/// eventImpact 只负责解释，不参与策略加权。
struct GoldMarketIntelligenceSnapshot: Sendable {
    let context: GoldMarketContext
    let globalSnapshot: GoldGlobalSnapshot?
    let eventImpact: GoldEventImpact
    let updatedAt: Date
}

extension GoldMarketIntelligenceSnapshot {
    /// 刷新失败后回退旧快照：标记 stale、置信度至少降一级，保留原更新时间。
    nonisolated func markedStale() -> GoldMarketIntelligenceSnapshot {
        guard eventImpact.dataState != .unavailable else { return self }
        let downgraded: GoldImpactConfidence
        switch eventImpact.confidence {
        case .high: downgraded = .medium
        case .medium: downgraded = .low
        case .low, .unavailable: downgraded = .unavailable
        }
        let staleImpact = GoldEventImpact(
            direction: eventImpact.direction,
            confidence: downgraded,
            volatilityRisk: eventImpact.volatilityRisk,
            headline: eventImpact.headline,
            evidence: eventImpact.evidence,
            counterRisks: eventImpact.counterRisks,
            updatedAt: eventImpact.updatedAt,
            dataState: .stale
        )
        return GoldMarketIntelligenceSnapshot(
            context: context,
            globalSnapshot: globalSnapshot,
            eventImpact: staleImpact,
            updatedAt: updatedAt
        )
    }
}

// MARK: - 统一宏观编排服务

/// 同时编排 GoldMarketContextService 与 GoldGlobalMarketService：
/// - 两个数据源并发请求，部分失败时安全降级；
/// - 15 分钟新鲜缓存与 in-flight 任务合并；
/// - 刷新失败回退旧快照标 stale（最多 6 小时），否则 fail closed。
final class GoldMarketIntelligenceService: GoldMarketIntelligenceProviding {
    /// 新鲜缓存边界：15 分钟。
    private static let freshInterval: TimeInterval = 15 * 60
    /// stale 数据最大展示时间：6 小时。
    private static let maxStaleAge: TimeInterval = 6 * 60 * 60

    private let contextProvider: any GoldMarketContextProviding
    private let globalProvider: any GoldGlobalMarketProviding
    private let cache = GoldMarketIntelligenceCache()

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
        await cache.resolve(now: now) { [contextProvider, globalProvider] in
            await Self.makeSnapshot(
                contextProvider: contextProvider,
                globalProvider: globalProvider,
                now: now,
                language: language
            )
        }
    }

    // MARK: - 快照组装

    /// 组装单一快照并计算 eventImpact，不修改 context.overallScore。
    private static func makeSnapshot(
        contextProvider: any GoldMarketContextProviding,
        globalProvider: any GoldGlobalMarketProviding,
        now: Date,
        language: AppLanguage
    ) async -> GoldMarketIntelligenceSnapshot {
        async let contextResult = capture {
            try await contextProvider.fetchContext(now: now, language: language)
        }
        async let globalResult = capture {
            try await globalProvider.fetchSnapshot(now: now)
        }

        let context = await contextResult
        let global = await globalResult

        // context 失败：构造安全上下文，事件影响 fail closed，不生成方向证据。
        guard case .success(let rawContext) = context else {
            let safeContext = GoldMarketContext(
                macroScore: 0,
                newsScore: 0,
                overallScore: 0,
                macro: nil,
                newsItems: [],
                reasons: [],
                updatedAt: now,
                isPartial: true,
                missingDataDescription: LocalizedString.l(
                    language,
                    en: "Macro context is unavailable",
                    zh: "宏观数据暂不可用",
                    ja: "マクロデータを利用できません",
                    ko: "거시 데이터를 사용할 수 없습니다"
                ),
                isFromCache: false
            )
            return GoldMarketIntelligenceSnapshot(
                context: safeContext,
                globalSnapshot: try? global.get(),
                eventImpact: .unavailable(now: now, language: language),
                updatedAt: now
            )
        }

        let globalSnapshot = try? global.get()

        // 超过 6 小时的数据不得继续参与证据计算。
        var usableGlobal = globalSnapshot
        if let globalSnapshot,
           now.timeIntervalSince(globalSnapshot.updatedAt) > maxStaleAge {
            usableGlobal = nil
        }
        var usableMacro = rawContext.macro
        if let macro = rawContext.macro, let observedAt = macro.observedAt,
           now.timeIntervalSince(observedAt) > maxStaleAge {
            usableMacro = nil
        }

        // sourceAge 只统计实际使用的数据。
        var ages: [TimeInterval] = [now.timeIntervalSince(rawContext.updatedAt)]
        if let usableGlobal {
            ages.append(now.timeIntervalSince(usableGlobal.updatedAt))
        }
        if let usableMacro, let observedAt = usableMacro.observedAt {
            ages.append(now.timeIntervalSince(observedAt))
        }
        let maxAge = ages.max() ?? 0

        // dataState：stale 优先于 partial；
        // 15 分钟内只要没有失败且 context 完整即 live。
        let dataState: GoldIntelligenceDataState
        if maxAge > maxStaleAge {
            dataState = .unavailable
        } else if maxAge > freshInterval {
            dataState = .stale
        } else if globalSnapshot == nil || rawContext.isPartial {
            dataState = .partial
        } else {
            dataState = .live
        }

        let eventImpact = GoldEventImpactAnalyzer.analyze(
            GoldEventImpactInput(
                newsItems: rawContext.newsItems,
                macro: usableMacro,
                globalSnapshot: usableGlobal,
                dataState: dataState,
                now: now
            ),
            language: language
        )

        return GoldMarketIntelligenceSnapshot(
            context: rawContext,
            globalSnapshot: globalSnapshot,
            eventImpact: eventImpact,
            updatedAt: now
        )
    }

    /// 保留失败信息，不使用 try? 丢弃数据源归属。
    private static func capture<T>(
        _ body: @Sendable () async throws -> T
    ) async -> Result<T, Error> {
        do {
            return .success(try await body())
        } catch {
            return .failure(error)
        }
    }
}

// MARK: - 缓存与并发合并

private actor GoldMarketIntelligenceCache {
    private static let freshInterval: TimeInterval = 15 * 60
    private static let maxStaleAge: TimeInterval = 6 * 60 * 60

    private var entry: (snapshot: GoldMarketIntelligenceSnapshot, savedAt: Date)?
    private var inFlight: Task<GoldMarketIntelligenceSnapshot, Never>?

    /// 15 分钟内直接返回缓存（保留原 live/partial 状态和原 updatedAt）；
    /// 已有 in-flight 时合并等待；刷新失败回退旧快照标 stale。
    func resolve(
        now: Date,
        fetch: @escaping @Sendable () async -> GoldMarketIntelligenceSnapshot
    ) async -> GoldMarketIntelligenceSnapshot {
        if let entry, now.timeIntervalSince(entry.savedAt) < Self.freshInterval {
            return entry.snapshot
        }

        if let inFlight {
            return await inFlight.value
        }

        let task = Task { await fetch() }
        inFlight = task
        let snapshot = await task.value
        inFlight = nil

        // 刷新结果不可用：旧数据不超过 6 小时回退并标 stale，否则 fail closed。
        if snapshot.eventImpact.dataState == .unavailable, let entry {
            let age = now.timeIntervalSince(entry.savedAt)
            return age <= Self.maxStaleAge ? entry.snapshot.markedStale() : snapshot
        }

        entry = (snapshot, now)
        return snapshot
    }
}
