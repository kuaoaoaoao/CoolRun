import XCTest
@testable import CoolRun

@MainActor
final class LocalConvenienceTests: XCTestCase {
    func testTodayItemsSortBySeverityThenDueDate() {
        let later = Date(timeIntervalSince1970: 2_000)
        let sooner = Date(timeIntervalSince1970: 1_000)
        let items = [
            TodaySummaryItem(id: "normal", kind: .gold, severity: .normal, icon: "", title: "", detail: "", destination: .gold, dueDate: nil),
            TodaySummaryItem(id: "later", kind: .countdown, severity: .warning, icon: "", title: "", detail: "", destination: .calendar, dueDate: later),
            TodaySummaryItem(id: "critical", kind: .system, severity: .critical, icon: "", title: "", detail: "", destination: .monitor, dueDate: nil),
            TodaySummaryItem(id: "sooner", kind: .birthday, severity: .warning, icon: "", title: "", detail: "", destination: .calendar, dueDate: sooner)
        ]

        XCTAssertEqual(TodaySummaryBuilder.sorted(items).map(\.id), ["critical", "sooner", "later", "normal"])
    }

    func testQuietHoursDefersAcrossMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 7, day: 31, hour: 23, minute: 15))!

        let adjusted = LocalReminderCenter.adjustedDeliveryDate(
            date,
            quietHoursEnabled: true,
            quietStartHour: 22,
            quietEndHour: 8,
            calendar: calendar
        )

        XCTAssertEqual(calendar.component(.day, from: adjusted), 1)
        XCTAssertEqual(calendar.component(.hour, from: adjusted), 8)
    }

    func testMenuBarPairUsesBothValues() {
        let text = MenuBarCompositionFormatter.render(
            style: .pair,
            primary: .cpu,
            secondary: .memory,
            rotationUsesSecondary: false,
            value: { mode, compact in "\(mode.rawValue)-\(compact)" }
        )

        XCTAssertEqual(text, "cpu-true · memory-true")
    }

    func testMenuBarRotationUsesSecondaryModeForRenderingAndLayout() {
        let activeMode = MenuBarCompositionFormatter.activeMode(
            style: .rotation,
            primary: .cpu,
            secondary: .network,
            rotationUsesSecondary: true
        )
        let text = MenuBarCompositionFormatter.render(
            style: .rotation,
            primary: .cpu,
            secondary: .network,
            rotationUsesSecondary: true,
            value: { mode, compact in "\(mode.rawValue)-\(compact)" }
        )

        XCTAssertEqual(activeMode, .network)
        XCTAssertEqual(text, "network-false")
    }

    func testSystemHistoryRetentionBounds() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let recentSample = SystemHistorySample(timestamp: now.addingTimeInterval(-60), cpuUsage: 0.2, memoryUsage: 0.3, storageUsage: 0.4, downloadSpeed: 1, uploadSpeed: 2, cpuTemperature: nil, gpuTemperature: nil)
        let oldSample = SystemHistorySample(timestamp: now.addingTimeInterval(-8 * 24 * 60 * 60), cpuUsage: 0.9, memoryUsage: 0.9, storageUsage: 0.9, downloadSpeed: 1, uploadSpeed: 2, cpuTemperature: nil, gpuTemperature: nil)
        let recentAnomaly = SystemAnomalyEvent(id: UUID(), timestamp: now.addingTimeInterval(-60), kind: .cpu, severity: .critical, value: 0.95, topProcessName: "Test")
        let oldAnomaly = SystemAnomalyEvent(id: UUID(), timestamp: now.addingTimeInterval(-31 * 24 * 60 * 60), kind: .memory, severity: .critical, value: 0.95, topProcessName: nil)

        let retained = SystemHistoryStore.retained(
            samples: [oldSample, recentSample],
            anomalies: [oldAnomaly, recentAnomaly],
            now: now
        )

        XCTAssertEqual(retained.samples, [recentSample])
        XCTAssertEqual(retained.anomalies, [recentAnomaly])
    }
}
