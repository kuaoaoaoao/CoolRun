import Foundation
import Darwin

#if os(macOS)

/// 通过 libproc 采样各进程的 CPU / 内存占用。
/// CPU 使用率按两次采样之间的 CPU 时间差计算，1.0 表示占满一个核心（与活动监视器口径一致）。
final class ProcessSampler {
    /// 上次采样时各进程累计 CPU 时间（纳秒）
    private var previousCPUTimes: [pid_t: UInt64] = [:]
    private var previousSampleTime: Date?

    /// 每类排序各保留的进程数量，两类取并集供界面切换排序使用
    private let topCount = 20

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    func sample(mergeByName: Bool) -> ProcessListMetrics {
        let now = Date()
        defer { previousSampleTime = now }

        let pids = listAllPIDs()
        guard !pids.isEmpty else { return ProcessListMetrics() }

        let elapsed = previousSampleTime.map { now.timeIntervalSince($0) } ?? 0
        var entries: [ProcessMetrics] = []
        var currentCPUTimes: [pid_t: UInt64] = [:]
        currentCPUTimes.reserveCapacity(pids.count)

        for pid in pids where pid > 0 {
            guard let usage = readUsage(of: pid) else { continue }

            currentCPUTimes[pid] = usage.cpuTimeNanos

            var cpuUsage = 0.0
            if elapsed > 0, let previous = previousCPUTimes[pid], usage.cpuTimeNanos >= previous {
                cpuUsage = Double(usage.cpuTimeNanos - previous) / (elapsed * 1_000_000_000)
            }

            guard let name = processName(of: pid) else { continue }

            entries.append(ProcessMetrics(
                pid: pid,
                name: name,
                cpuUsage: cpuUsage,
                memoryBytes: usage.memoryBytes,
                instanceCount: 1,
                pids: [pid]
            ))
        }

        previousCPUTimes = currentCPUTimes

        let totalCount = entries.count
        if mergeByName {
            entries = mergeEntriesByName(entries)
        }

        // 只保留 CPU 与内存两个维度的头部进程，避免快照过大
        let byCPU = entries.sorted { $0.cpuUsage > $1.cpuUsage }.prefix(topCount)
        let byMemory = entries.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(topCount)
        var merged: [pid_t: ProcessMetrics] = [:]
        for entry in byCPU { merged[entry.pid] = entry }
        for entry in byMemory { merged[entry.pid] = entry }

        // 路径只为最终展示的头部进程读取，避免每秒对全部进程调用 proc_pidpath。
        for pid in Array(merged.keys) {
            merged[pid]?.executablePath = executablePath(of: pid)
        }

        return ProcessListMetrics(
            processes: merged.values.sorted { $0.cpuUsage > $1.cpuUsage },
            totalCount: totalCount
        )
    }

    /// 同名进程聚合为一条：CPU / 内存求和，代表 pid 取 CPU 占用最高的实例
    private func mergeEntriesByName(_ entries: [ProcessMetrics]) -> [ProcessMetrics] {
        var grouped: [String: ProcessMetrics] = [:]
        grouped.reserveCapacity(entries.count)

        for entry in entries {
            guard let existing = grouped[entry.name] else {
                grouped[entry.name] = entry
                continue
            }

            let representative = entry.cpuUsage > existing.cpuUsage ? entry : existing
            grouped[entry.name] = ProcessMetrics(
                pid: representative.pid,
                name: entry.name,
                cpuUsage: existing.cpuUsage + entry.cpuUsage,
                memoryBytes: existing.memoryBytes &+ entry.memoryBytes,
                instanceCount: existing.instanceCount + 1,
                pids: existing.pids + entry.pids
            )
        }

        return Array(grouped.values)
    }

    private func listAllPIDs() -> [pid_t] {
        let expectedBytes = proc_listallpids(nil, 0)
        guard expectedBytes > 0 else { return [] }

        // 预留余量，避免采样间隙新进程导致截断
        var pids = [pid_t](repeating: 0, count: Int(expectedBytes) / MemoryLayout<pid_t>.stride + 32)
        let writtenBytes = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        guard writtenBytes > 0 else { return [] }

        return Array(pids.prefix(Int(writtenBytes) / MemoryLayout<pid_t>.stride))
    }

    private func readUsage(of pid: pid_t) -> (cpuTimeNanos: UInt64, memoryBytes: UInt64)? {
        var info = rusage_info_current()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: (rusage_info_t?).self, capacity: 1) { reboundPointer in
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, reboundPointer)
            }
        }
        guard result == 0 else { return nil }

        // ri_user_time / ri_system_time 为 mach 时间单位，需换算成纳秒
        let machTime = info.ri_user_time &+ info.ri_system_time
        let nanos = machTime &* UInt64(Self.timebase.numer) / UInt64(Self.timebase.denom)

        return (cpuTimeNanos: nanos, memoryBytes: info.ri_phys_footprint)
    }

    private func processName(of pid: pid_t) -> String? {
        // proc_name 最多返回 32 字符，被截断时改用可执行文件路径取全名
        var nameBuffer = [CChar](repeating: 0, count: 64)
        let length = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
        let shortName = length > 0 ? String(cString: nameBuffer) : ""

        if shortName.utf8.count >= 31 || shortName.isEmpty {
            if let path = executablePath(of: pid) {
                let fullName = URL(fileURLWithPath: path).lastPathComponent
                if !fullName.isEmpty { return fullName }
            }
        }

        return shortName.isEmpty ? nil : shortName
    }

    private func executablePath(of pid: pid_t) -> String? {
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)) > 0 else {
            return nil
        }

        let path = String(cString: pathBuffer)
        return path.isEmpty ? nil : path
    }
}

#endif
