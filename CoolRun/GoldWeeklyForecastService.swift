import Foundation

// MARK: - 请求与协议

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

// MARK: - 可注入模型运行器

/// 单测注入固定 draft/backtest；生产使用 `.live`，不得为制造状态调整生产模型。
struct GoldWeeklyForecastModelRunner: Sendable {
    let makeDraft: @Sendable (GoldWeeklyForecastEngineInput) -> GoldWeeklyForecastDraft?
    let backtest: @Sendable ([GoldDailyClose], UInt64) -> GoldWeeklyForecastBacktestSummary

    nonisolated static let live = Self(
        makeDraft: { GoldWeeklyForecastEngine.makeDraft($0) },
        backtest: { GoldWeeklyForecastBacktester.evaluate(closes: $0, seed: $1) }
    )
}

// MARK: - 来源兼容性

/// 基于代码中固定 source contract 的映射。
/// 只有接口字段、文档或重叠验证证据才能升级兼容性；不得只比较价格接近就改为 verified。
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

// MARK: - 服务

/// 编排一年日线、来源兼容性、回测门槛和事件信心修正。
/// 事件影响只能调整 confidence 一级，不得改变方向、价格或区间。
final class GoldWeeklyForecastService: GoldWeeklyForecastProviding {

    private let historyProvider: any GoldWeeklyHistoryProviding
    private let modelRunner: GoldWeeklyForecastModelRunner
    private let cache = GoldWeeklyForecastServiceCache()

    init(
        historyProvider: any GoldWeeklyHistoryProviding = GoldMarketDataService.shared,
        modelRunner: GoldWeeklyForecastModelRunner = .live
    ) {
        self.historyProvider = historyProvider
        self.modelRunner = modelRunner
    }

    func fetchSnapshot(
        request: GoldWeeklyForecastRequest,
        language: AppLanguage
    ) async -> GoldWeeklyForecastSnapshot {
        let requestKey = Self.cacheRequestKey(request: request)
        if let cached = await cache.cachedSnapshot(requestKey: requestKey, now: request.now) {
            return Self.applyEventImpact(to: cached, request: request, language: language)
        }
        let historyProvider = self.historyProvider
        let modelRunner = self.modelRunner
        let task = await cache.inflightTask(requestKey: requestKey) {
            await Self.runPipeline(
                request: request,
                language: language,
                historyProvider: historyProvider,
                modelRunner: modelRunner
            )
        }
        let base = await task.value
        return Self.applyEventImpact(to: base, request: request, language: language)
    }
}

// MARK: - 流水线（非隔离纯编排）

extension GoldWeeklyForecastService {

    /// 状态机顺序固定：价格 -> 历史 -> 标准化 -> 来源 -> 回测 -> 引擎 -> 信心 -> 组装。
    nonisolated private static func runPipeline(
        request: GoldWeeklyForecastRequest,
        language: AppLanguage,
        historyProvider: any GoldWeeklyHistoryProviding,
        modelRunner: GoldWeeklyForecastModelRunner
    ) async -> GoldWeeklyForecastSnapshot {
        // 1. 当前价格有限且在合理范围内，否则 sourceUnavailable。
        guard request.currentPrice.isFinite,
              (100...2_000).contains(request.currentPrice) else {
            return .unavailable(
                status: .sourceUnavailable,
                message: LocalizedString.l(
                    language,
                    en: "Current gold price is unavailable",
                    zh: "当前金价不可用",
                    ja: "現在の金価格を利用できません",
                    ko: "현재 금 가격을 사용할 수 없습니다"
                ),
                now: request.now
            )
        }

        // 2. 一年历史；失败返回 sourceUnavailable。
        let points: [GoldRemotePricePoint]
        do {
            points = try await historyProvider.fetchHistoryPrices(range: .year, now: request.now)
        } catch {
            return .unavailable(
                status: .sourceUnavailable,
                message: LocalizedString.l(
                    language,
                    en: "Historical daily closes are unavailable",
                    zh: "历史日线数据暂不可用",
                    ja: "履歴の日足データを利用できません",
                    ko: "과거 일봉 데이터를 사용할 수 없습니다"
                ),
                now: request.now
            )
        }

        // 3. 标准化；少于 120 个点或最新点超过 96 小时都停止发布。
        let quality = GoldDailyCloseNormalizer.normalize(points: points, now: request.now)
        if quality.closes.count < GoldWeeklyForecastPolicy.minimumDailyCloses {
            let template = LocalizedString.l(
                language,
                en: "Insufficient history: %d daily closes available, at least %d required",
                zh: "历史数据不足：当前 %d 个日线收盘点，至少需要 %d 个",
                ja: "履歴が不足しています：現在 %d 件の日足終値、最低 %d 件が必要です",
                ko: "과거 데이터 부족: 일봉 종가 %d개만 있으며 최소 %d개가 필요합니다"
            )
            return .unavailable(
                status: .insufficientHistory,
                message: String(
                    format: template, quality.closes.count, GoldWeeklyForecastPolicy.minimumDailyCloses
                ),
                now: request.now
            )
        }
        if quality.isStale {
            return .unavailable(
                status: .staleData,
                message: LocalizedString.l(
                    language,
                    en: "The latest daily close is older than 96 hours",
                    zh: "最新日线收盘已超过 96 小时",
                    ja: "最新の日足終値が96時間を超えています",
                    ko: "최신 일봉 종가가 96시간을 초과했습니다"
                ),
                now: request.now
            )
        }

        // 4. 来源兼容性；incompatible 返回 sourceMismatch。
        let compatibility = GoldForecastSourceCompatibilityResolver.resolve(
            currentSource: request.currentPriceSource,
            historySource: GoldMarketDataService.historySourceID
        )
        guard compatibility != .incompatible else {
            return .unavailable(
                status: .sourceMismatch,
                message: LocalizedString.l(
                    language,
                    en: "Current price source (\(request.currentPriceSource)) is not comparable with the weekly model history",
                    zh: "当前价格来源（\(request.currentPriceSource)）与周模型历史来源不兼容",
                    ja: "現在の価格ソース（\(request.currentPriceSource)）は週次モデルの履歴と互換性がありません",
                    ko: "현재 가격 출처(\(request.currentPriceSource))가 주간 모델 기록과 호환되지 않습니다"
                ),
                now: request.now
            )
        }

        // 5. 走步回测；未过发布门槛保留 backtest 并返回 validationFailed。
        let seed = UInt64(bitPattern: Int64(request.now.timeIntervalSince1970))
        let backtest = modelRunner.backtest(quality.closes, seed)
        guard backtest.passedReleaseGate else {
            return GoldWeeklyForecastSnapshot(
                status: .validationFailed,
                forecast: nil,
                backtest: backtest,
                message: validationFailedMessage(language, reasons: backtest.failureReasons),
                updatedAt: request.now
            )
        }

        // 6. 以 Asia/Shanghai 生成 targetDate 并运行引擎。
        let generatedAt = request.now
        let targetDate = Calendar.goldShanghai.date(
            byAdding: .day, value: GoldWeeklyForecastPolicy.horizonDays, to: generatedAt
        )!
        guard let draft = modelRunner.makeDraft(GoldWeeklyForecastEngineInput(
            closes: quality.closes,
            startPrice: request.currentPrice,
            generatedAt: generatedAt,
            targetDate: targetDate,
            seed: seed
        )) else {
            return GoldWeeklyForecastSnapshot(
                status: .validationFailed,
                forecast: nil,
                backtest: backtest,
                message: validationFailedMessage(language, reasons: ["engine_unavailable"]),
                updatedAt: request.now
            )
        }

        // 7. 基础信心 + 缺口降级 + proxy 封顶。
        var confidence = baseConfidence(
            quality: quality, compatibility: compatibility, backtest: backtest, draft: draft
        )
        var reasons: [String] = []
        var counterRisks: [String] = []
        if quality.maximumGapDays > 14 {
            if confidence > .low {
                confidence = confidence.downgraded
            }
            counterRisks.append(LocalizedString.l(
                language,
                en: "History has a \(quality.maximumGapDays)-day gap; confidence lowered",
                zh: "历史数据存在 \(quality.maximumGapDays) 天缺口，信心已下调",
                ja: "履歴に\(quality.maximumGapDays)日の欠落があり、信頼度を下げました",
                ko: "과거 데이터에 \(quality.maximumGapDays)일 격차가 있어 신뢰도를 낮췄습니다"
            ))
        }
        if compatibility == .proxy {
            reasons.append(LocalizedString.l(
                language,
                en: "The weekly model uses domestic gold reference daily closes",
                zh: "历史模型使用国内黄金参考日线",
                ja: "週次モデルは国内金の参考日足を使用しています",
                ko: "주간 모델은 국내 금 참고 일봉을 사용합니다"
            ))
            if confidence > .low {
                confidence = .low
            }
        }

        // 8. 组装 ready 快照（事件信心修正由 applyEventImpact 负责）。
        let forecast = GoldWeeklyForecast(
            direction: draft.direction,
            confidence: confidence,
            startPrice: request.currentPrice,
            expectedPrice: draft.expectedPrice,
            expectedReturn: draft.expectedReturn,
            p10: draft.p10,
            p50: draft.p50,
            p90: draft.p90,
            generatedAt: generatedAt,
            targetDate: targetDate,
            dataUpdatedAt: quality.closes.last?.date ?? generatedAt,
            currentPriceSource: request.currentPriceSource,
            historySource: GoldMarketDataService.historySourceID,
            sourceCompatibility: compatibility,
            components: draft.components,
            reasons: reasons,
            counterRisks: counterRisks,
            modelVersion: GoldWeeklyForecastPolicy.modelVersion
        )
        return GoldWeeklyForecastSnapshot(
            status: .ready,
            forecast: forecast,
            backtest: backtest,
            message: LocalizedString.l(
                language,
                en: "Weekly forecast generated",
                zh: "一周预测已生成",
                ja: "週間予測を生成しました",
                ko: "주간 예측이 생성되었습니다"
            ),
            updatedAt: generatedAt
        )
    }

    /// 基础信心：120–179 low；>=180 且 verified 且 >=3 个分量同向 medium；
    /// >=240 且回测样本 >=36、balanced >=0.45、overall >= baseline+0.05 为 high。
    nonisolated private static func baseConfidence(
        quality: GoldDailyHistoryQuality,
        compatibility: GoldForecastSourceCompatibility,
        backtest: GoldWeeklyForecastBacktestSummary,
        draft: GoldWeeklyForecastDraft
    ) -> GoldWeeklyForecastConfidence {
        guard compatibility == .verified, backtest.passedReleaseGate else { return .low }
        var confidence: GoldWeeklyForecastConfidence = .low
        if quality.closes.count >= GoldWeeklyForecastPolicy.normalDailyCloses,
           alignedComponentCount(draft) >= 3 {
            confidence = .medium
        }
        if quality.closes.count >= GoldWeeklyForecastPolicy.highDailyCloses,
           backtest.resolvedCount >= 36,
           (backtest.balancedAccuracy ?? 0) >= 0.45,
           let overall = backtest.overallAccuracy,
           let baseline = backtest.majorityBaselineAccuracy,
           overall >= baseline + 0.05 {
            confidence = .high
        }
        return confidence
    }

    /// 四个统计分量中与最终方向一致的个数。
    nonisolated private static func alignedComponentCount(
        _ draft: GoldWeeklyForecastDraft
    ) -> Int {
        let components = [
            draft.components.trend,
            draft.components.momentum,
            draft.components.meanReversion,
            draft.components.bootstrap
        ]
        switch draft.direction {
        case .up: return components.filter { $0 > 0 }.count
        case .down: return components.filter { $0 < 0 }.count
        case .flat: return components.filter {
            abs($0) <= GoldWeeklyForecastPolicy.scoreDirectionThreshold
        }.count
        }
    }

    /// 事件影响只允许在 dataState 为 live 且事件信心至少 medium 时调整 confidence 一级。
    /// 冲突降一级并追加 counterRisk；一致时追加 reason，且不得把 proxy 提升到 medium、
    /// 也不得单独把 medium 提升到 high。
    nonisolated private static func applyEventImpact(
        to snapshot: GoldWeeklyForecastSnapshot,
        request: GoldWeeklyForecastRequest,
        language: AppLanguage
    ) -> GoldWeeklyForecastSnapshot {
        guard snapshot.status == .ready,
              let forecast = snapshot.forecast,
              let event = request.eventImpact,
              event.dataState == .live,
              event.confidence >= .medium else { return snapshot }

        let isAligned: Bool
        switch (forecast.direction, event.direction) {
        case (.up, .bullish), (.down, .bearish):
            isAligned = true
        case (.up, .bearish), (.down, .bullish):
            isAligned = false
        default:
            return snapshot
        }

        let adjusted: GoldWeeklyForecast
        if isAligned {
            let upgradedConfidence: GoldWeeklyForecastConfidence =
                (forecast.sourceCompatibility == .verified && forecast.confidence == .low)
                    ? .medium : forecast.confidence
            adjusted = GoldWeeklyForecast(
                direction: forecast.direction,
                confidence: upgradedConfidence,
                startPrice: forecast.startPrice,
                expectedPrice: forecast.expectedPrice,
                expectedReturn: forecast.expectedReturn,
                p10: forecast.p10,
                p50: forecast.p50,
                p90: forecast.p90,
                generatedAt: forecast.generatedAt,
                targetDate: forecast.targetDate,
                dataUpdatedAt: forecast.dataUpdatedAt,
                currentPriceSource: forecast.currentPriceSource,
                historySource: forecast.historySource,
                sourceCompatibility: forecast.sourceCompatibility,
                components: forecast.components,
                reasons: forecast.reasons + [LocalizedString.l(
                    language,
                    en: "Event impact aligns with the model direction",
                    zh: "事件影响与模型方向一致",
                    ja: "イベント影響がモデルの方向と一致しています",
                    ko: "사건 영향이 모델 방향과 일치합니다"
                )],
                counterRisks: forecast.counterRisks,
                modelVersion: forecast.modelVersion
            )
        } else {
            adjusted = GoldWeeklyForecast(
                direction: forecast.direction,
                confidence: forecast.confidence.downgraded,
                startPrice: forecast.startPrice,
                expectedPrice: forecast.expectedPrice,
                expectedReturn: forecast.expectedReturn,
                p10: forecast.p10,
                p50: forecast.p50,
                p90: forecast.p90,
                generatedAt: forecast.generatedAt,
                targetDate: forecast.targetDate,
                dataUpdatedAt: forecast.dataUpdatedAt,
                currentPriceSource: forecast.currentPriceSource,
                historySource: forecast.historySource,
                sourceCompatibility: forecast.sourceCompatibility,
                components: forecast.components,
                reasons: forecast.reasons,
                counterRisks: forecast.counterRisks + [LocalizedString.l(
                    language,
                    en: "Event impact conflicts with the model direction; confidence lowered",
                    zh: "事件影响与模型方向冲突，信心已下调",
                    ja: "イベント影響がモデルの方向と相反するため信頼度を下げました",
                    ko: "사건 영향이 모델 방향과 상충하여 신뢰도를 낮췄습니다"
                )],
                modelVersion: forecast.modelVersion
            )
        }
        return GoldWeeklyForecastSnapshot(
            status: snapshot.status,
            forecast: adjusted,
            backtest: snapshot.backtest,
            message: snapshot.message,
            updatedAt: snapshot.updatedAt
        )
    }

    nonisolated private static func validationFailedMessage(
        _ language: AppLanguage,
        reasons: [String]
    ) -> String {
        let template = LocalizedString.l(
            language,
            en: "Walk-forward backtest did not pass the release gate: %@",
            zh: "走步回测未达发布门槛：%@",
            ja: "ウォークフォワード検証が公開ゲートを通過しませんでした：%@",
            ko: "워크포워드 백테스트가 공개 게이트를 통과하지 못했습니다: %@"
        )
        return String(format: template, reasons.joined(separator: ", "))
    }

    /// 缓存键的前置部分：上海 day key + 模型版本 + 当前价格来源。
    /// 最新历史日线日期在拉取前不可知；同一上海日内缓存条目在 TTL 内可信，
    /// 每日冻结由 GoldWeeklyForecastStore 负责（Task 6）。
    nonisolated private static func cacheRequestKey(
        request: GoldWeeklyForecastRequest
    ) -> String {
        let dayKey = Calendar.goldShanghai.startOfDay(for: request.now)
        return [
            String(Int(dayKey.timeIntervalSince1970)),
            GoldWeeklyForecastPolicy.modelVersion,
            request.currentPriceSource
        ].joined(separator: "|")
    }
}

// MARK: - 6 小时缓存与 in-flight 合并

/// 缓存键由请求级前缀（day key + modelVersion + 来源）组成；
/// 并发同键请求共享同一 Task，历史数据只拉取一次。
private actor GoldWeeklyForecastServiceCache {

    private struct Entry {
        let requestKey: String
        let snapshot: GoldWeeklyForecastSnapshot
        let createdAt: Date
    }

    private static let maximumAge: TimeInterval = 6 * 60 * 60

    private var entry: Entry?
    private var inflight: [String: Task<GoldWeeklyForecastSnapshot, Never>] = [:]

    func cachedSnapshot(requestKey: String, now: Date) -> GoldWeeklyForecastSnapshot? {
        guard let entry,
              entry.requestKey == requestKey,
              now.timeIntervalSince(entry.createdAt) <= Self.maximumAge else { return nil }
        return entry.snapshot
    }

    func inflightTask(
        requestKey: String,
        operation: @escaping @Sendable () async -> GoldWeeklyForecastSnapshot
    ) -> Task<GoldWeeklyForecastSnapshot, Never> {
        if let existing = inflight[requestKey] { return existing }
        let task = Task { () -> GoldWeeklyForecastSnapshot in
            let snapshot = await operation()
            finish(requestKey: requestKey, snapshot: snapshot)
            return snapshot
        }
        inflight[requestKey] = task
        return task
    }

    private func finish(requestKey: String, snapshot: GoldWeeklyForecastSnapshot) {
        inflight[requestKey] = nil
        // 只缓存 ready 快照（含基础信心）；事件修正在每次请求后独立应用。
        guard snapshot.status == .ready else { return }
        entry = Entry(
            requestKey: requestKey,
            snapshot: snapshot,
            createdAt: snapshot.updatedAt
        )
    }
}
