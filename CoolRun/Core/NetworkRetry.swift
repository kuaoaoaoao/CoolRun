import Foundation

// MARK: - 重试策略

/// 网络请求重试策略：指数退避 + 最大重试次数 + 可重试状态码过滤。
struct RetryStrategy: Sendable {
    /// 最大重试次数（不含首次请求）
    var maxRetries: Int
    /// 首次重试前的基础延迟
    var baseDelay: Duration
    /// 退避乘数（每次延迟 = baseDelay × multiplier^(attempt-1)）
    var multiplier: Double
    /// 最大单次延迟上限
    var maxDelay: Duration
    /// 哪些 HTTP 状态码触发重试（默认 5xx + 429）
    var retryableStatusCodes: Set<Int>
    /// 哪些 Error 类型触发重试（默认网络层错误）
    var retryableErrors: ((Error) -> Bool)?

    static let `default` = RetryStrategy(
        maxRetries: 2,
        baseDelay: .milliseconds(500),
        multiplier: 2.0,
        maxDelay: .seconds(8),
        retryableStatusCodes: [429, 500, 502, 503, 504],
        retryableErrors: nil
    )

    /// 金价服务专用：对外部 API 更激进，因为用户盯着价格看。
    static let goldPrice = RetryStrategy(
        maxRetries: 3,
        baseDelay: .milliseconds(300),
        multiplier: 2.0,
        maxDelay: .seconds(5),
        retryableStatusCodes: [429, 500, 502, 503, 504],
        retryableErrors: nil
    )

    /// 保守策略：适合更新检查、LLM 等低频请求。
    static let conservative = RetryStrategy(
        maxRetries: 2,
        baseDelay: .seconds(1),
        multiplier: 2.0,
        maxDelay: .seconds(10),
        retryableStatusCodes: [429, 500, 502, 503, 504],
        retryableErrors: nil
    )

    func delay(for attempt: Int) -> Duration {
        let raw = Double(baseDelay.components.seconds) * pow(multiplier, Double(attempt - 1))
        let capped = min(raw, Double(maxDelay.components.seconds))
        return .seconds(capped)
    }
}

// MARK: - URLSession 重试扩展

extension URLSession {
    /// 带重试的 `data(for:)`。首次失败后会按策略退避重试。
    func data(
        for request: URLRequest,
        retryStrategy strategy: RetryStrategy
    ) async throws -> (Data, URLResponse) {
        var lastError: Error?

        for attempt in 0...strategy.maxRetries {
            do {
                let (data, response) = try await self.data(for: request)
                if let http = response as? HTTPURLResponse,
                   strategy.retryableStatusCodes.contains(http.statusCode) {
                    lastError = GoldPriceError.apiMessage("HTTP \(http.statusCode)")
                    if attempt < strategy.maxRetries {
                        try? await Task.sleep(for: strategy.delay(for: attempt + 1))
                        continue
                    }
                }
                return (data, response)
            } catch {
                lastError = error
                let shouldRetry = strategy.retryableErrors?(error) ?? Self.isRetryable(error)
                if shouldRetry && attempt < strategy.maxRetries {
                    try? await Task.sleep(for: strategy.delay(for: attempt + 1))
                    continue
                }
                throw error
            }
        }

        throw lastError ?? URLError(.unknown)
    }

    /// 带重试的 `data(from:)`。
    func data(
        from url: URL,
        retryStrategy strategy: RetryStrategy
    ) async throws -> (Data, URLResponse) {
        try await data(for: URLRequest(url: url), retryStrategy: strategy)
    }

    private static func isRetryable(_ error: Error) -> Bool {
        let nsError = error as NSError
        switch nsError.domain {
        case NSURLErrorDomain:
            switch nsError.code {
            case NSURLErrorTimedOut,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorNotConnectedToInternet,
                 NSURLErrorDNSLookupFailed,
                 NSURLErrorResourceUnavailable,
                 NSURLErrorBadServerResponse:
                return true
            default:
                return false
            }
        case "kCFErrorDomainCFNetwork":
            return true
        default:
            return false
        }
    }
}
