import XCTest
@testable import CoolRun

/// 金价历史的落盘保护。
///
/// 背景：历史文件有 7 万条、7 MB 级别。把它改成后台解码之后，启动瞬间
/// 内存里只有刚抓到的一两条；这时如果照常落盘，整个历史就被覆盖成一条。
/// 这个函数就是那道闸：新数据明显小于盘上文件时，宁可这次不写。
@MainActor
final class GoldHistoryLoadTests: XCTestCase {

    private var url: URL!

    override func setUp() {
        super.setUp()
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gold-shrink-\\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
        super.tearDown()
    }

    private func writeFile(bytes: Int) throws {
        let data = Data(repeating: 0x41, count: bytes)
        try data.write(to: url)
    }

    func testTinySnapshotAgainstLargeFileIsBlocked() throws {
        try writeFile(bytes: 200 * 1024)
        XCTAssertTrue(GoldPriceStore.wouldShrinkTooMuch(existing: url, newByteCount: 1_000))
    }

    func testSimilarSizeIsAllowed() throws {
        try writeFile(bytes: 200 * 1024)
        XCTAssertFalse(GoldPriceStore.wouldShrinkTooMuch(existing: url, newByteCount: 190 * 1024))
    }

    func testSmallExistingFileIsNotProtected() throws {
        // 小文件（刚装、或者本来就没什么数据）不该被挡住。
        try writeFile(bytes: 10 * 1024)
        XCTAssertFalse(GoldPriceStore.wouldShrinkTooMuch(existing: url, newByteCount: 500))
    }

    func testMissingFileIsNotProtected() {
        XCTAssertFalse(GoldPriceStore.wouldShrinkTooMuch(existing: url, newByteCount: 0))
    }
}
