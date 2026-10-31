import Foundation
import Darwin

#if os(macOS)
import IOKit
import IOKit.ps
#elseif canImport(UIKit)
import UIKit
#endif

final class SystemSampler {
    private var previousCPUTicks: [UInt32]?
    private var previousNetworkBytes: (download: UInt64, upload: UInt64)?
    private var previousSampleTime: Date?
    private let smcReader = SMCReader()
    #if os(macOS)
    private let processSampler = ProcessSampler()
    #endif

    func sample(includeProcesses: Bool = true, mergeProcesses: Bool = true) -> SystemSnapshot {
        let now = Date()
        let network = sampleNetwork()
        let uptime = sampleUptime()
        let temperature = sampleTemperature()

        defer { previousSampleTime = now }

        return SystemSnapshot(
            cpu: sampleCPU(),
            memory: sampleMemory(),
            storage: sampleStorage(),
            battery: sampleBattery(),
            network: network,
            uptime: uptime,
            temperature: temperature,
            processes: sampleProcesses(enabled: includeProcesses, mergeByName: mergeProcesses),
            updatedAt: now
        )
    }

    private func sampleProcesses(enabled: Bool, mergeByName: Bool) -> ProcessListMetrics {
        #if os(macOS)
        guard enabled else { return ProcessListMetrics() }
        return processSampler.sample(mergeByName: mergeByName)
        #else
        return ProcessListMetrics()
        #endif
    }

    private func sampleCPU() -> CPUMetrics {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &load) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return CPUMetrics(coreCount: ProcessInfo.processInfo.activeProcessorCount)
        }

        let ticks = [
            UInt32(load.cpu_ticks.0),
            UInt32(load.cpu_ticks.1),
            UInt32(load.cpu_ticks.2),
            UInt32(load.cpu_ticks.3)
        ]

        defer { previousCPUTicks = ticks }

        guard let previousCPUTicks else {
            return CPUMetrics(usage: 0, coreCount: ProcessInfo.processInfo.activeProcessorCount)
        }

        let deltas = zip(ticks, previousCPUTicks).map { current, previous in
            Double(current >= previous ? current - previous : 0)
        }
        let idle = deltas[Int(CPU_STATE_IDLE)]
        let total = deltas.reduce(0, +)
        let usage = total > 0 ? (total - idle) / total : 0

        return CPUMetrics(
            usage: min(max(usage, 0), 1),
            coreCount: ProcessInfo.processInfo.activeProcessorCount
        )
    }

    private func sampleMemory() -> MemoryMetrics {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return MemoryMetrics(total: ProcessInfo.processInfo.physicalMemory)
        }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        let pageBytes = UInt64(pageSize)
        let usedPages = UInt64(stats.active_count)
            + UInt64(stats.wire_count)
            + UInt64(stats.compressor_page_count)

        return MemoryMetrics(
            used: usedPages * pageBytes,
            total: ProcessInfo.processInfo.physicalMemory
        )
    }

    private func sampleStorage() -> StorageMetrics {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser

        guard
            let values = try? url.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey
            ])
        else {
            return StorageMetrics()
        }

        let total = UInt64(max(values.volumeTotalCapacity ?? 0, 0))
        let available = UInt64(max(values.volumeAvailableCapacityForImportantUsage ?? 0, 0))

        return StorageMetrics(
            used: total > available ? total - available : 0,
            total: total
        )
    }

    private func sampleBattery() -> BatteryMetrics {
        var metrics = BatteryMetrics(
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        )

        #if os(macOS)
        guard
            let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
            let source = sources.first,
            let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue()
                as? [String: Any]
        else {
            metrics.state = .noBattery
            return metrics
        }

        let current = description[kIOPSCurrentCapacityKey] as? Double
        let max = description[kIOPSMaxCapacityKey] as? Double
        if let current, let max, max > 0 {
            metrics.level = current / max
        }

        let state = description[kIOPSPowerSourceStateKey] as? String
        let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
        if isCharging {
            metrics.state = .charging
        } else if let level = metrics.level, level >= 0.995 {
            metrics.state = .full
        } else if state == kIOPSACPowerValue {
            metrics.state = .full
        } else {
            metrics.state = .unplugged
        }

        metrics.health = sampleBatteryHealth()
        #elseif canImport(UIKit)
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        if level >= 0 {
            metrics.level = Double(level)
        }

        switch UIDevice.current.batteryState {
        case .unplugged:
            metrics.state = .unplugged
        case .charging:
            metrics.state = .charging
        case .full:
            metrics.state = .full
        case .unknown:
            metrics.state = .unknown
        @unknown default:
            metrics.state = .unknown
        }
        #else
        metrics.state = .unknown
        #endif

        return metrics
    }

    #if os(macOS)
    // 从 IORegistry 的 AppleSmartBattery 读取健康度、循环、温度与实时功率（只读，无需权限）
    private func sampleBatteryHealth() -> BatteryHealthMetrics? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        var propsRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = propsRef?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        var health = BatteryHealthMetrics()
        health.cycleCount = props["CycleCount"] as? Int
        health.designCapacity = props["DesignCapacity"] as? Int
        // Apple Silicon 上 MaxCapacity 恒为 100(%)，真实 mAh 在 AppleRawMaxCapacity/NominalChargeCapacity
        health.maxCapacity = (props["AppleRawMaxCapacity"] as? Int) ?? (props["NominalChargeCapacity"] as? Int)

        if let rawTemperature = props["Temperature"] as? Int {
            var celsius = Double(rawTemperature) / 100
            if celsius > 200 { celsius -= 273.15 } // 个别机型上报百分开尔文
            health.temperatureCelsius = celsius
        }

        let voltage = (props["Voltage"] as? Int).map { Double($0) / 1000 } // mV -> V
        health.voltage = voltage
        if let voltage, let amperage = props["Amperage"] as? Int {
            // Amperage 为有符号 mA，正充电负放电
            health.wattage = voltage * Double(amperage) / 1000
        }

        if let timeRemaining = props["TimeRemaining"] as? Int, timeRemaining > 0, timeRemaining < 0xFFFF {
            health.timeRemainingMinutes = timeRemaining
        }
        return health
    }
    #endif

    private func sampleNetwork() -> NetworkMetrics {
        let status = currentNetworkStatus()
        let (downloadSpeed, uploadSpeed) = calculateNetworkSpeed()

        return NetworkMetrics(
            activeInterfaceCount: status.activeInterfaceCount,
            primaryAddress: status.primaryAddress,
            downloadSpeed: downloadSpeed,
            uploadSpeed: uploadSpeed
        )
    }

    private func calculateNetworkSpeed() -> (download: UInt64, upload: UInt64) {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let interfaces else {
            return (0, 0)
        }
        defer { freeifaddrs(interfaces) }

        var totalDownload: UInt64 = 0
        var totalUpload: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = interfaces

        while let interface = cursor {
            defer { cursor = interface.pointee.ifa_next }

            let flags = Int32(interface.pointee.ifa_flags)
            guard flags & IFF_UP == IFF_UP, flags & IFF_LOOPBACK == 0 else {
                continue
            }

            let name = String(cString: interface.pointee.ifa_name)
            // Skip virtual interfaces
            guard !name.hasPrefix("lo") && !name.hasPrefix("utun") && !name.hasPrefix("awdl") else {
                continue
            }

            if let address = interface.pointee.ifa_addr,
               address.pointee.sa_family == UInt8(AF_LINK),
               let data = interface.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                totalDownload += UInt64(data.pointee.ifi_ibytes)
                totalUpload += UInt64(data.pointee.ifi_obytes)
            }
        }

        let now = Date()

        if let previous = previousNetworkBytes, let previousTime = previousSampleTime {
            let elapsed = now.timeIntervalSince(previousTime)
            guard elapsed > 0 else {
                return (0, 0)
            }

            let downloadDiff = totalDownload >= previous.download ? totalDownload - previous.download : 0
            let uploadDiff = totalUpload >= previous.upload ? totalUpload - previous.upload : 0

            previousNetworkBytes = (totalDownload, totalUpload)

            return (
                download: UInt64(Double(downloadDiff) / elapsed),
                upload: UInt64(Double(uploadDiff) / elapsed)
            )
        }

        previousNetworkBytes = (totalDownload, totalUpload)
        return (0, 0)
    }

    private func sampleUptime() -> UptimeMetrics {
        UptimeMetrics(uptime: ProcessInfo.processInfo.systemUptime)
    }

    private func sampleTemperature() -> TemperatureMetrics {
        guard smcReader.available else {
            return TemperatureMetrics()
        }

        let cpuTemp = smcReader.readCPUTemperature()
        let gpuTemp = smcReader.readGPUTemperature()
        let allSensors = smcReader.readTemperatures()

        // 转换为 SensorReading 数组
        let sensors = allSensors.map { reading in
            SensorReading(name: reading.name, temperature: reading.temperature)
        }

        return TemperatureMetrics(
            cpuTemperature: cpuTemp,
            gpuTemperature: gpuTemp,
            sensors: sensors
        )
    }

    private func currentNetworkStatus() -> NetworkStatus {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let interfaces else {
            return NetworkStatus()
        }
        defer { freeifaddrs(interfaces) }

        var status = NetworkStatus()
        var cursor: UnsafeMutablePointer<ifaddrs>? = interfaces
        var activeNames = Set<String>()

        while let interface = cursor {
            defer { cursor = interface.pointee.ifa_next }

            let flags = Int32(interface.pointee.ifa_flags)
            guard flags & IFF_UP == IFF_UP, flags & IFF_LOOPBACK == 0 else {
                continue
            }

            let name = String(cString: interface.pointee.ifa_name)
            activeNames.insert(name)

            if status.primaryAddress == nil,
               let address = interface.pointee.ifa_addr,
               address.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = getnameinfo(
                    address,
                    socklen_t(address.pointee.sa_len),
                    &host,
                    socklen_t(host.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
                if result == 0 {
                    status.primaryAddress = String(cString: host)
                }
            }
        }

        status.activeInterfaceCount = activeNames.count
        return status
    }
}

private struct NetworkStatus {
    var activeInterfaceCount: Int = 0
    var primaryAddress: String?
}
