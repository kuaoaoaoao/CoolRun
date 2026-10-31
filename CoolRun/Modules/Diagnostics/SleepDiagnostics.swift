import Foundation

struct SleepLogAnalysis: Equatable, Sendable {
    let windowStart: Date?
    let windowEnd: Date?
    let sleepCount: Int
    let wakeCount: Int
    let darkWakeCount: Int
    let batteryStartPercent: Int?
    let batteryEndPercent: Int?
}

enum SleepDiagnosticParser {
    private static let assertionTypes = [
        "PreventSystemSleep",
        "PreventUserIdleSystemSleep",
        "PreventUserIdleDisplaySleep",
        "NoIdleSleepAssertion",
        "NoDisplaySleepAssertion"
    ]

    static func parseAssertions(_ text: String) -> [SleepBlocker] {
        let pattern = #"pid\s+(\d+)\(([^)]+)\):.*?\b(PreventSystemSleep|PreventUserIdleSystemSleep|PreventUserIdleDisplaySleep|NoIdleSleepAssertion|NoDisplaySleepAssertion)\b(?:.*?named:\s*\"([^\"]+)\")?"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }

        var values: [SleepBlocker] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let lineText = String(line)
            let range = NSRange(lineText.startIndex..<lineText.endIndex, in: lineText)
            guard let match = expression.firstMatch(in: lineText, range: range) else { continue }
            guard let pidRange = Range(match.range(at: 1), in: lineText),
                  let ownerRange = Range(match.range(at: 2), in: lineText),
                  let typeRange = Range(match.range(at: 3), in: lineText) else { continue }

            let assertionType = String(lineText[typeRange])
            guard assertionTypes.contains(assertionType) else { continue }
            let reason: String?
            if match.range(at: 4).location != NSNotFound,
               let reasonRange = Range(match.range(at: 4), in: lineText) {
                reason = String(lineText[reasonRange])
            } else {
                reason = nil
            }
            values.append(SleepBlocker(
                owner: String(lineText[ownerRange]),
                processID: Int(lineText[pidRange]),
                assertionType: assertionType,
                reason: reason
            ))
        }

        var seen = Set<String>()
        return values.filter { seen.insert($0.id).inserted }
    }

    static func parseLog(
        _ text: String,
        now: Date = Date(),
        lookback: TimeInterval = 24 * 60 * 60
    ) -> SleepLogAnalysis {
        let linePattern = #"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{4})\s+(Sleep|Wake|DarkWake)\s+(.+)$"#
        let batteryPattern = #"Charge:(\d+)%"#
        guard let lineExpression = try? NSRegularExpression(pattern: linePattern),
              let batteryExpression = try? NSRegularExpression(pattern: batteryPattern) else {
            return SleepLogAnalysis(
                windowStart: nil,
                windowEnd: nil,
                sleepCount: 0,
                wakeCount: 0,
                darkWakeCount: 0,
                batteryStartPercent: nil,
                batteryEndPercent: nil
            )
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"

        let cutoff = now.addingTimeInterval(-max(lookback, 60))
        var firstDate: Date?
        var lastDate: Date?
        var sleepCount = 0
        var wakeCount = 0
        var darkWakeCount = 0
        var firstBattery: Int?
        var lastBattery: Int?

        for substring in text.split(whereSeparator: \.isNewline) {
            let line = String(substring)
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = lineExpression.firstMatch(in: line, range: range),
                  let dateRange = Range(match.range(at: 1), in: line),
                  let eventRange = Range(match.range(at: 2), in: line),
                  let detailRange = Range(match.range(at: 3), in: line),
                  let date = formatter.date(from: String(line[dateRange])),
                  date >= cutoff,
                  date <= now.addingTimeInterval(5 * 60) else { continue }

            let event = String(line[eventRange])
            let detail = String(line[detailRange])
            switch event {
            case "Sleep" where detail.contains("Entering Sleep state"):
                sleepCount += 1
            case "Wake":
                wakeCount += 1
            case "DarkWake":
                darkWakeCount += 1
            default:
                break
            }

            firstDate = firstDate.map { min($0, date) } ?? date
            lastDate = lastDate.map { max($0, date) } ?? date

            if let batteryMatch = batteryExpression.firstMatch(in: line, range: range),
               let batteryRange = Range(batteryMatch.range(at: 1), in: line),
               let battery = Int(line[batteryRange]) {
                if firstBattery == nil { firstBattery = battery }
                lastBattery = battery
            }
        }

        return SleepLogAnalysis(
            windowStart: firstDate,
            windowEnd: lastDate,
            sleepCount: sleepCount,
            wakeCount: wakeCount,
            darkWakeCount: darkWakeCount,
            batteryStartPercent: firstBattery,
            batteryEndPercent: lastBattery
        )
    }
}

enum SleepDiagnosticsService {
    private static let systemOwners: Set<String> = [
        "powerd", "WindowServer", "coreaudiod", "bluetoothd", "sharingd",
        "runningboardd", "apsd", "kernel_task", "hidd"
    ]

    static func run(now: Date = Date()) async -> SleepDiagnosticSummary {
        async let assertionsResult = FixedCommandRunner.run(
            executable: "/usr/bin/pmset",
            arguments: ["-g", "assertions"],
            timeout: 4,
            outputLimit: 256_000
        )
        async let logResult = FixedCommandRunner.run(
            executable: "/usr/bin/pmset",
            arguments: ["-g", "log"],
            timeout: 8,
            outputLimit: 2_000_000,
            keepOutputTail: true
        )

        let assertionCommand = await assertionsResult
        let logCommand = await logResult
        var unavailable: [String] = []

        let blockers: [SleepBlocker]
        if assertionCommand.succeeded, !assertionCommand.standardOutput.isEmpty {
            blockers = SleepDiagnosticParser.parseAssertions(assertionCommand.standardOutput)
        } else {
            blockers = []
            unavailable.append("power_assertions")
        }

        let log: SleepLogAnalysis
        if logCommand.succeeded, !logCommand.standardOutput.isEmpty {
            log = SleepDiagnosticParser.parseLog(logCommand.standardOutput, now: now)
        } else {
            log = SleepLogAnalysis(
                windowStart: nil,
                windowEnd: nil,
                sleepCount: 0,
                wakeCount: 0,
                darkWakeCount: 0,
                batteryStartPercent: nil,
                batteryEndPercent: nil
            )
            unavailable.append("sleep_log")
        }

        let actionableBlockers = blockers.filter { !systemOwners.contains($0.owner) }
        let batteryDrop = if let start = log.batteryStartPercent, let end = log.batteryEndPercent {
            max(start - end, 0)
        } else {
            0
        }

        let severity: DiagnosticSeverity
        if unavailable.count == 2 {
            severity = .unavailable
        } else if batteryDrop >= 20 || log.darkWakeCount >= 200 {
            severity = .critical
        } else if batteryDrop >= 8 || log.darkWakeCount >= 50 || !actionableBlockers.isEmpty {
            severity = .warning
        } else if !unavailable.isEmpty || !blockers.isEmpty {
            severity = .notice
        } else {
            severity = .healthy
        }

        return SleepDiagnosticSummary(
            id: UUID(),
            timestamp: now,
            severity: severity,
            blockers: blockers,
            windowStart: log.windowStart,
            windowEnd: log.windowEnd,
            sleepCount: log.sleepCount,
            wakeCount: log.wakeCount,
            darkWakeCount: log.darkWakeCount,
            batteryStartPercent: log.batteryStartPercent,
            batteryEndPercent: log.batteryEndPercent,
            unavailableChecks: unavailable
        )
    }
}
