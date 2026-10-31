//
//  SMCReader.swift
//  CoolRun
//
//  只读访问 macOS SMC 温度传感器。
//

import Foundation

#if os(macOS)
import IOKit

// MARK: - SMC 内核 ABI

private typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPowerLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memoryPLimit: UInt32 = 0
}

private struct SMCKeyInfo {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
    // Swift 会复用嵌套结构的尾部填充；显式保留 3 字节以匹配 C ABI。
    var padding: (UInt8, UInt8, UInt8) = (0, 0, 0)
}

/// 字段顺序必须与 AppleSMC 用户客户端的 80 字节结构一致。
private struct SMCKeyData {
    var key: UInt32 = 0
    var version = SMCVersion()
    var powerLimitData = SMCPowerLimitData()
    var keyInfo = SMCKeyInfo()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var command: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
}

private enum SMCCommand {
    static let readBytes: UInt8 = 5
    static let readKeyInfo: UInt8 = 9
    static let kernelIndex: UInt32 = 2
}

// MARK: - SMC 连接

private final class SMCConnection {
    private var connection: io_connect_t = 0

    init?() {
        guard MemoryLayout<SMCKeyData>.stride == 80 else {
            assertionFailure(
                "Unexpected SMCKeyData ABI layout: \(MemoryLayout<SMCKeyData>.stride) bytes"
            )
            return nil
        }

        let serviceNames = ["AppleSMC", "AppleSMCKeysEndpoint"]
        var service: io_service_t = 0

        for serviceName in serviceNames where service == 0 {
            service = IOServiceGetMatchingService(
                kIOMainPortDefault,
                IOServiceMatching(serviceName)
            )
        }

        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else {
            return nil
        }
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    func read(key: String) -> Double? {
        guard key.utf8.count == 4 else { return nil }

        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = fourCharacterCode(key)
        input.command = SMCCommand.readKeyInfo

        guard call(input: &input, output: &output) else { return nil }
        let keyInfo = output.keyInfo
        guard keyInfo.dataSize > 0, keyInfo.dataSize <= 32 else { return nil }

        input.keyInfo = keyInfo
        input.command = SMCCommand.readBytes
        output = SMCKeyData()

        guard call(input: &input, output: &output) else { return nil }
        return parseValue(
            type: keyInfo.dataType,
            bytes: byteArray(from: output.bytes),
            size: Int(keyInfo.dataSize)
        )
    }

    private func call(input: inout SMCKeyData, output: inout SMCKeyData) -> Bool {
        var outputSize = MemoryLayout<SMCKeyData>.stride
        let result = IOConnectCallStructMethod(
            connection,
            SMCCommand.kernelIndex,
            &input,
            MemoryLayout<SMCKeyData>.stride,
            &output,
            &outputSize
        )
        return result == kIOReturnSuccess
    }

    private func parseValue(type: UInt32, bytes: [UInt8], size: Int) -> Double? {
        guard bytes.count >= size else { return nil }

        switch type {
        case fourCharacterCode("sp78"):
            guard size >= 2 else { return nil }
            let raw = Int16(bitPattern: (UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
            return plausibleTemperature(Double(raw) / 256)

        case fourCharacterCode("flt "):
            guard size >= 4 else { return nil }
            var value: Float = 0
            withUnsafeMutableBytes(of: &value) { destination in
                destination[0] = bytes[0]
                destination[1] = bytes[1]
                destination[2] = bytes[2]
                destination[3] = bytes[3]
            }
            return plausibleTemperature(Double(value))

        case fourCharacterCode("fpe2"):
            guard size >= 2 else { return nil }
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return plausibleTemperature(Double(raw) / 4)

        case fourCharacterCode("fp88"):
            guard size >= 2 else { return nil }
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return plausibleTemperature(Double(raw) / 256)

        default:
            return nil
        }
    }

    private func plausibleTemperature(_ value: Double) -> Double? {
        guard value.isFinite, value > -40, value < 150 else { return nil }
        return value
    }

    private func byteArray(from bytes: SMCBytes) -> [UInt8] {
        withUnsafeBytes(of: bytes) { Array($0) }
    }

    private func fourCharacterCode(_ string: String) -> UInt32 {
        string.utf8.reduce(UInt32(0)) { code, character in
            (code << 8) | UInt32(character)
        }
    }
}

// MARK: - 公开 API

struct TemperatureReading: Equatable, Identifiable {
    let id = UUID()
    let name: String
    let temperature: Double

    var formatted: String {
        String(format: "%.1f°C", temperature)
    }
}

final class SMCReader {
    private struct SensorDefinition {
        let key: String
        let name: String
        let category: Category

        enum Category {
            case cpu
            case gpu
            case system
        }
    }

    private static let sensorDefinitions: [SensorDefinition] = [
        // Apple Silicon 代表性传感器
        SensorDefinition(key: "TCMz", name: "CPU Die Hotspot", category: .cpu),
        SensorDefinition(key: "TCMb", name: "CPU Core Max", category: .cpu),
        SensorDefinition(key: "TRDX", name: "GPU Die Hotspot", category: .gpu),
        SensorDefinition(key: "TPMP", name: "SoC Package", category: .system),
        SensorDefinition(key: "TVm0", name: "Unified Memory", category: .system),
        SensorDefinition(key: "TMVR", name: "Memory VRM", category: .system),
        SensorDefinition(key: "T5SP", name: "SSD Controller", category: .system),
        SensorDefinition(key: "TB0T", name: "Battery", category: .system),
        SensorDefinition(key: "TAOL", name: "Ambient", category: .system),
        SensorDefinition(key: "TW0P", name: "Wi-Fi", category: .system),

        // Intel Mac 与部分机型的兼容键
        SensorDefinition(key: "TC0P", name: "CPU Proximity", category: .cpu),
        SensorDefinition(key: "TC0D", name: "CPU Die", category: .cpu),
        SensorDefinition(key: "TC0E", name: "CPU Core", category: .cpu),
        SensorDefinition(key: "TG0P", name: "GPU Proximity", category: .gpu),
        SensorDefinition(key: "TG0D", name: "GPU Die", category: .gpu),
        SensorDefinition(key: "TM0P", name: "Memory Proximity", category: .system),
        SensorDefinition(key: "Ts0P", name: "SSD Proximity", category: .system)
    ]

    private let connection: SMCConnection?

    init() {
        connection = SMCConnection()
    }

    var available: Bool {
        connection != nil
    }

    func readTemperatures() -> [TemperatureReading] {
        guard let connection else { return [] }

        return Self.sensorDefinitions.compactMap { sensor in
            guard let temperature = connection.read(key: sensor.key) else { return nil }
            return TemperatureReading(name: sensor.name, temperature: temperature)
        }
    }

    /// 优先显示热点；热点不可用时退回其它 CPU 传感器的最高值。
    func readCPUTemperature() -> Double? {
        readTemperature(category: .cpu, preferredKeys: ["TCMz", "TCMb", "TC0D", "TC0P"])
    }

    /// 优先显示 GPU 热点；旧机型退回 GPU 核心或近端传感器。
    func readGPUTemperature() -> Double? {
        readTemperature(category: .gpu, preferredKeys: ["TRDX", "TG0D", "TG0P"])
    }

    private func readTemperature(
        category: SensorDefinition.Category,
        preferredKeys: [String]
    ) -> Double? {
        guard let connection else { return nil }

        for key in preferredKeys {
            if let temperature = connection.read(key: key) {
                return temperature
            }
        }

        return Self.sensorDefinitions
            .filter { $0.category == category }
            .compactMap { connection.read(key: $0.key) }
            .max()
    }
}

#else

final class SMCReader {
    var available: Bool { false }
    func readTemperatures() -> [TemperatureReading] { [] }
    func readCPUTemperature() -> Double? { nil }
    func readGPUTemperature() -> Double? { nil }
}

struct TemperatureReading: Equatable, Identifiable {
    let id = UUID()
    let name: String
    let temperature: Double
    var formatted: String { "" }
}

#endif
