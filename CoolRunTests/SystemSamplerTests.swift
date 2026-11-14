import XCTest
@testable import CoolRun

/// 系统采样是所有「电脑状态」类功能的底座（Today 概要、系统监控面板、
/// Agent 的 system_* 工具），但一直没测试 —— 它读的是 Mach/IOKit，
/// 最容易在系统升级后静默返回 0。
final class SystemSamplerTests: XCTestCase {

    /// 断言只挑「无论什么机器都必须成立」的量：核心数、内存总量、比例区间。
    /// 具体数值（CPU 百分比、温度）不稳定，不写死。
    func testLightSampleReturnsPlausibleValues() {
        let sampler = SystemSampler()
        let snapshot = sampler.sample(
            includeProcesses: false,
            includeStorage: false,
            includeSensors: false
        )

        XCTAssertGreaterThan(snapshot.cpu.coreCount, 0, "核数为 0 说明 host_processor_info 没读到")
        XCTAssertTrue((0...1).contains(snapshot.cpu.usage), "CPU 占用应在 0…1：\(snapshot.cpu.usage)")
        XCTAssertGreaterThan(snapshot.memory.total, 0)
        XCTAssertGreaterThan(snapshot.memory.used, 0)
        XCTAssertLessThanOrEqual(snapshot.memory.used, snapshot.memory.total, "已用内存不该超过总量")
        XCTAssertTrue((0...1).contains(snapshot.memory.usage))
        XCTAssertFalse(snapshot.uptime.formatted.isEmpty, "开机时长应该有可读文本")
        XCTAssertGreaterThan(snapshot.uptime.uptime, 0, "开机时长应大于 0")
    }

    func testSkippingExpensiveSectionsLeavesThemEmpty() {
        // 面板不可见时要用轻量档，省掉磁盘与 SMC 查询。
        let sampler = SystemSampler()
        let snapshot = sampler.sample(
            includeProcesses: false,
            includeStorage: false,
            includeSensors: false
        )
        XCTAssertEqual(snapshot.storage.total, 0, "关掉存储后不该有磁盘数据")
        XCTAssertTrue(snapshot.processes.processes.isEmpty, "关掉进程后不该有进程列表")
        XCTAssertEqual(snapshot.processes.totalCount, 0)
    }

    func testProcessListIsPopulatedWhenAsked() {
        let sampler = SystemSampler()
        let snapshot = sampler.sample(
            includeProcesses: true,
            mergeProcesses: true,
            includeStorage: false,
            includeSensors: false
        )
        XCTAssertGreaterThan(snapshot.processes.totalCount, 0, "进程列表不应该空")
        XCTAssertFalse(snapshot.processes.processes.isEmpty)
        let first = snapshot.processes.processes[0]
        XCTAssertFalse(first.name.isEmpty, "进程没有名字")
        XCTAssertGreaterThanOrEqual(first.cpuUsage, 0)
    }

    func testSecondSampleProducesBoundedCPUUsage() {
        // CPU 占用是两次采样的差值算的；第一次没有基线，第二次才准。
        let sampler = SystemSampler()
        _ = sampler.sample(includeProcesses: false, includeStorage: false, includeSensors: false)
        Thread.sleep(forTimeInterval: 0.35)
        let second = sampler.sample(includeProcesses: false, includeStorage: false, includeSensors: false)
        XCTAssertTrue((0...1).contains(second.cpu.usage), "二次采样的 CPU 占用应在 0…1：\(second.cpu.usage)")
    }

    func testStorageIsSaneWhenEnabled() {
        let sampler = SystemSampler()
        let snapshot = sampler.sample(
            includeProcesses: false,
            includeStorage: true,
            includeSensors: false
        )
        XCTAssertGreaterThan(snapshot.storage.total, 0, "总容量应大于 0")
        XCTAssertLessThanOrEqual(snapshot.storage.used, snapshot.storage.total)
        XCTAssertTrue((0...1).contains(snapshot.storage.usage))
    }
}
