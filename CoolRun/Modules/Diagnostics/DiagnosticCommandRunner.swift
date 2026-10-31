import Foundation
import Darwin

struct FixedCommandResult: Equatable, Sendable {
    let standardOutput: String
    let standardError: String
    let exitCode: Int32
    let timedOut: Bool

    var succeeded: Bool { !timedOut && exitCode == 0 }
}

enum FixedCommandRunner {
    static func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        outputLimit: Int = 512_000,
        keepOutputTail: Bool = false
    ) async -> FixedCommandResult {
        await Task.detached(priority: .utility) {
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                try process.run()
            } catch {
                return FixedCommandResult(
                    standardOutput: "",
                    standardError: error.localizedDescription,
                    exitCode: -1,
                    timedOut: false
                )
            }

            let outputTask = Task.detached(priority: .utility) {
                outputPipe.fileHandleForReading.readDataToEndOfFile()
            }
            let errorTask = Task.detached(priority: .utility) {
                errorPipe.fileHandleForReading.readDataToEndOfFile()
            }

            let deadline = Date().addingTimeInterval(max(timeout, 0.25))
            var didTimeOut = false
            while process.isRunning {
                if Task.isCancelled || Date() >= deadline {
                    didTimeOut = true
                    process.terminate()
                    break
                }
                try? await Task.sleep(for: .milliseconds(50))
            }

            if process.isRunning {
                try? await Task.sleep(for: .milliseconds(200))
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            process.waitUntilExit()

            let stdout = await outputTask.value
            let stderr = await errorTask.value
            return FixedCommandResult(
                standardOutput: limitedString(
                    stdout,
                    limit: outputLimit,
                    keepTail: keepOutputTail
                ),
                standardError: limitedString(stderr, limit: min(outputLimit, 64_000), keepTail: true),
                exitCode: process.terminationStatus,
                timedOut: didTimeOut
            )
        }.value
    }

    private nonisolated static func limitedString(_ data: Data, limit: Int, keepTail: Bool) -> String {
        let boundedLimit = max(limit, 1_024)
        let selected: Data
        if data.count <= boundedLimit {
            selected = data
        } else if keepTail {
            selected = data.suffix(boundedLimit)
        } else {
            selected = data.prefix(boundedLimit)
        }
        return String(decoding: selected, as: UTF8.self)
    }
}
