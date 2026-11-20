import XCTest
@testable import CoolRun

/// 运行时优先级是纯函数（`AgentRuntimeLocator.resolve`），不碰文件系统，单独测。
/// 完整版里最容易出的误会是「下载了却没生效」，所以「被遮蔽的那一份」也要测出来。
final class RuntimePriorityTests: XCTestCase {
    private func runtime(_ source: AgentRuntimeLocator.Source, _ version: String?) -> AgentRuntimeLocator.Runtime {
        AgentRuntimeLocator.Runtime(
            executable: URL(fileURLWithPath: "/tmp/\(source.rawValue)"),
            source: source,
            version: version
        )
    }

    func testBundledWinsByDefault() {
        let bundled = runtime(.bundled, "0.2.2rc2")
        let downloaded = runtime(.downloaded, "0.2.3rc1")
        let resolved = AgentRuntimeLocator.resolve(
            bundled: bundled,
            downloaded: downloaded,
            system: nil,
            preferDownloaded: false
        )
        XCTAssertEqual(resolved.active, bundled)
        XCTAssertEqual(resolved.shadowed, downloaded, "下载的那份没生效，要能被设置页发现")
    }

    func testPreferencePromotesDownloadedCopy() {
        let bundled = runtime(.bundled, "0.2.2rc2")
        let downloaded = runtime(.downloaded, "0.2.3rc1")
        let resolved = AgentRuntimeLocator.resolve(
            bundled: bundled,
            downloaded: downloaded,
            system: nil,
            preferDownloaded: true
        )
        XCTAssertEqual(resolved.active, downloaded)
        XCTAssertEqual(resolved.shadowed, bundled)
    }

    func testPreferenceFallsBackToBundledWhenNothingDownloaded() {
        let bundled = runtime(.bundled, "0.2.2rc2")
        let resolved = AgentRuntimeLocator.resolve(
            bundled: bundled,
            downloaded: nil,
            system: nil,
            preferDownloaded: true
        )
        XCTAssertEqual(resolved.active, bundled)
        XCTAssertNil(resolved.shadowed)
    }

    func testDownloadedWinsOnLiteBuild() {
        let downloaded = runtime(.downloaded, "0.2.2rc2")
        let resolved = AgentRuntimeLocator.resolve(
            bundled: nil,
            downloaded: downloaded,
            system: nil,
            preferDownloaded: false
        )
        XCTAssertEqual(resolved.active, downloaded)
        XCTAssertNil(resolved.shadowed)
    }

    func testSystemPathIsTheLastResort() {
        let system = runtime(.systemPath, nil)
        let resolved = AgentRuntimeLocator.resolve(
            bundled: nil,
            downloaded: nil,
            system: system,
            preferDownloaded: false
        )
        XCTAssertEqual(resolved.active, system)
        XCTAssertNil(resolved.shadowed)
    }

    func testNothingInstalled() {
        let resolved = AgentRuntimeLocator.resolve(
            bundled: nil,
            downloaded: nil,
            system: nil,
            preferDownloaded: false
        )
        XCTAssertNil(resolved.active)
        XCTAssertNil(resolved.shadowed)
    }
}
