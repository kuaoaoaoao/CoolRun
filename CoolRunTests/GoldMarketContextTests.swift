import XCTest
@testable import CoolRun

final class GoldMarketContextTests: XCTestCase {
    private var urlProtocolStub: GoldContextURLProtocolStub!

    override func setUp() async throws {
        try await super.setUp()
        urlProtocolStub = GoldContextURLProtocolStub()
        URLProtocol.registerClass(GoldContextURLProtocolStub.self)
        GoldContextURLProtocolStub.reset()
        // 服务缓存是进程级的，必须逐用例清空避免相互污染
        await GoldMarketContextService.resetCacheForTesting()
    }

    override func tearDown() {
        GoldContextURLProtocolStub.reset()
        URLProtocol.unregisterClass(GoldContextURLProtocolStub.self)
        super.tearDown()
    }

    private func makeService() -> GoldMarketContextService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GoldContextURLProtocolStub.self]
        return GoldMarketContextService(
            session: URLSession(configuration: configuration)
        )
    }

    // MARK: - 场景一：RSS 过滤、聚类与来源参与

    func testFetchContextFiltersIrrelevantAndSyndicatedNews() async throws {
        GoldContextURLProtocolStub.rssHandler = { _ in
            Self.makeRSSFeed()
        }
        GoldContextURLProtocolStub.treasuryHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let service = makeService()
        let now = Date()
        let context = try await service.fetchContext(
            now: now.addingTimeInterval(60),
            language: .chinese
        )

        // 一条 Reuters + 一条证券时报；Gold Cup 被拒；两条转载归并为一条
        XCTAssertEqual(context.newsItems.count, 2)
        XCTAssertFalse(context.newsItems.contains { $0.title.contains("Gold Cup") })
        XCTAssertEqual(Set(context.newsItems.map(\.eventKey)).count, context.newsItems.count)

        // 收益率请求失败 => partial
        XCTAssertTrue(context.isPartial)
        XCTAssertNotNil(context.missingDataDescription)
    }

    // MARK: - 场景二：全部请求失败

    func testFetchContextFailsClosedWhenAllRequestsFail() async throws {
        GoldContextURLProtocolStub.rssHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }
        GoldContextURLProtocolStub.treasuryHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let service = makeService()
        let context = try await service.fetchContext(
            now: Date(),
            language: .chinese
        )

        XCTAssertTrue(context.isPartial)
        XCTAssertNotNil(context.missingDataDescription)
        XCTAssertTrue(context.newsItems.isEmpty)
    }

    // MARK: - 固定 RSS 数据

    private static func makeRSSFeed() -> String {
        let items = [
            // Reuters 黄金/美联储新闻（保留）
            """
            <item>
                <title>Warsh signals inflation concern; gold market watches Fed - Reuters</title>
                <link>https://example.com/1</link>
                <pubDate>Sat, 29 Aug 2026 03:00:00 GMT</pubDate>
                <source url="https://reuters.com">Reuters</source>
            </item>
            """,
            // 证券时报黄金/收益率新闻（保留）
            """
            <item>
                <title>美芯片股大跌黄金跳水 美联储主席沃什鹰派发声 - 证券时报</title>
                <link>https://example.com/2</link>
                <pubDate>Sat, 29 Aug 2026 03:30:00 GMT</pubDate>
                <source url="https://stcn.com">证券时报</source>
            </item>
            """,
            // Gold Cup 赛车新闻（应被过滤）
            """
            <item>
                <title>2026 High Limit Racing Gold Cup results at Silver Dollar Speedway - FloRacing</title>
                <link>https://example.com/3</link>
                <pubDate>Sat, 29 Aug 2026 04:00:00 GMT</pubDate>
                <source url="https://floracing.com">FloRacing</source>
            </item>
            """,
            // 同一事件的轻微改写转载（应与第一条归并）
            """
            <item>
                <title>Warsh signals inflation concern as gold market watches Fed | Yahoo Finance</title>
                <link>https://example.com/4</link>
                <pubDate>Sat, 29 Aug 2026 04:30:00 GMT</pubDate>
                <source url="https://finance.yahoo.com">Yahoo Finance</source>
            </item>
            """
        ]
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel><title>Test</title>
        \(items.joined(separator: "\n"))
        </channel></rss>
        """
    }
}

// MARK: - URLProtocol Stub

final class GoldContextURLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var rssHandler: ((URLRequest) throws -> String)?
    nonisolated(unsafe) static var treasuryHandler: ((URLRequest) throws -> String)?

    static func reset() {
        rssHandler = nil
        treasuryHandler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let body: String
        do {
            if url.host?.contains("news.google.com") == true {
                guard let handler = Self.rssHandler else {
                    client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
                    return
                }
                body = try handler(request)
            } else {
                guard let handler = Self.treasuryHandler else {
                    client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
                    return
                }
                body = try handler(request)
            }
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/xml"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
