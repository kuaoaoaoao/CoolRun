import Foundation
import AppKit

/// 磁盘清理顾问。
///
/// 只做一件事：把「磁盘快满了」变成「这几样可以删，你自己勾」。
/// 每个条目都必须回答两个问题——为什么能删、删了会怎样。
/// 删除一律走废纸篓，留后悔药。
@MainActor
@Observable
final class CleanupAdvisor {
    static let shared = CleanupAdvisor()

    enum Risk: Int, Comparable, Sendable {
        /// 删了会自动重建，放心删。
        case safe
        /// 删了不可恢复，先看一眼再决定。
        case caution
        /// 只展示不让删，比如系统目录。
        case protected

        static func < (lhs: Risk, rhs: Risk) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    enum Category: String, Sendable {
        case cache
        case log
        case developer
        case package
        case backup
        case trash
        case largeFile
    }

    struct Item: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
        let note: String
        let icon: String
        let risk: Risk
        let category: Category
        let url: URL
        let bytes: UInt64
        let isDirectory: Bool
    }

    struct Report: Equatable, Sendable {
        var trashed: [String] = []
        var freedBytes: UInt64 = 0
        var failures: [String] = []
    }

    private struct Template: Sendable {
        let id: String
        let name: String
        let relativePath: String
        let note: String
        let icon: String
        let risk: Risk
        let category: Category
    }

    private nonisolated static let templates: [Template] = [
        Template(
            id: "caches",
            name: "应用缓存",
            relativePath: "Library/Caches",
            note: "各 App 的临时缓存。删掉后第一次打开会稍慢，之后自己重建。",
            icon: "shippingbox.fill",
            risk: .safe,
            category: .cache
        ),
        Template(
            id: "logs",
            name: "运行日志",
            relativePath: "Library/Logs",
            note: "系统和 App 的日志。删掉不影响功能，只是出问题时少了排查材料。",
            icon: "doc.text.fill",
            risk: .safe,
            category: .log
        ),
        Template(
            id: "derived-data",
            name: "Xcode 编译缓存",
            relativePath: "Library/Developer/Xcode/DerivedData",
            note: "编译中间产物。删掉后下次编译从头来，慢一点，但不会出错。",
            icon: "hammer.fill",
            risk: .safe,
            category: .developer
        ),
        Template(
            id: "device-support",
            name: "真机调试符号",
            relativePath: "Library/Developer/Xcode/iOS DeviceSupport",
            note: "调试真机用的系统符号。删掉后第一次连新系统的手机会重新下载。",
            icon: "iphone.gen3",
            risk: .safe,
            category: .developer
        ),
        Template(
            id: "simulator-caches",
            name: "模拟器缓存",
            relativePath: "Library/Developer/CoreSimulator/Caches",
            note: "模拟器运行时缓存，删了会自动重建。",
            icon: "square.stack.3d.up.fill",
            risk: .safe,
            category: .developer
        ),
        Template(
            id: "npm-cache",
            name: "npm 缓存",
            relativePath: ".npm/_cacache",
            note: "npm 下载过的包。删掉后装依赖会重新下载，已装好的项目不受影响。",
            icon: "cube.box.fill",
            risk: .safe,
            category: .package
        ),
        Template(
            id: "pnpm-store",
            name: "pnpm 全局存储",
            relativePath: "Library/pnpm/store",
            note: "pnpm 的包仓库。删掉后重装依赖会重新下载，已有 node_modules 仍可用。",
            icon: "cube.box.fill",
            risk: .safe,
            category: .package
        ),
        Template(
            id: "homebrew-cache",
            name: "Homebrew 安装包缓存",
            relativePath: "Library/Caches/Homebrew",
            note: "下载过的安装包。删掉后重装同一版本会重新下载。",
            icon: "mug.fill",
            risk: .safe,
            category: .package
        ),
        Template(
            id: "trash",
            name: "废纸篓",
            relativePath: ".Trash",
            note: "已经扔掉的東西。清空后无法恢复，先确认里面没有你还要的。",
            icon: "trash.fill",
            risk: .caution,
            category: .trash
        ),
        Template(
            id: "device-backups",
            name: "iPhone / iPad 本地备份",
            relativePath: "Library/Application Support/MobileSync/Backup",
            note: "这台电脑上的手机备份。删掉后本地就没有了，iCloud 备份不受影响。",
            icon: "iphone.and.arrow.forward",
            risk: .caution,
            category: .backup
        )
    ]

    private(set) var items: [Item] = []
    private(set) var isScanning = false
    private(set) var progressText: String?
    private(set) var lastScanAt: Date?
    private(set) var lastReport: Report?
    private(set) var lastError: String?

    private nonisolated static let largeFileThreshold: UInt64 = 300 * 1024 * 1024
    private nonisolated static let largeFileLimit = 12

    var reclaimableBytes: UInt64 {
        items.filter { $0.risk != .protected }.reduce(0) { $0 &+ $1.bytes }
    }

    var safeBytes: UInt64 {
        items.filter { $0.risk == .safe }.reduce(0) { $0 &+ $1.bytes }
    }

    // MARK: - 扫描

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        lastError = nil
        progressText = "正在看哪些能清…"
        defer {
            isScanning = false
            progressText = nil
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        var collected: [Item] = []

        for template in Self.templates {
            let url = home.appendingPathComponent(template.relativePath, isDirectory: true)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let bytes = await Self.measure(url)
            guard bytes > 0 else { continue }
            collected.append(
                Item(
                    id: template.id,
                    name: template.name,
                    note: template.note,
                    icon: template.icon,
                    risk: template.risk,
                    category: template.category,
                    url: url,
                    bytes: bytes,
                    isDirectory: true
                )
            )
        }

        progressText = "正在找大文件…"
        let largeFiles = await Self.largeFiles(in: home)
        collected.append(contentsOf: largeFiles)

        items = collected.sorted { lhs, rhs in
            if lhs.risk != rhs.risk { return lhs.risk < rhs.risk }
            return lhs.bytes > rhs.bytes
        }
        lastScanAt = Date()
    }

    // MARK: - 清理

    func clean(_ selected: [Item]) async -> Report {
        var report = Report()
        for item in selected where item.risk != .protected {
            let name = item.name
            let url = item.url
            let size = item.bytes
            let result = await Task.detached(priority: .userInitiated) { () -> Result<Void, Error> in
                do {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    return .success(())
                } catch {
                    return .failure(error)
                }
            }.value

            switch result {
            case .success:
                report.trashed.append(name)
                report.freedBytes &+= size
            case .failure(let error):
                report.failures.append("\(name)：\(error.localizedDescription)")
            }
        }

        lastReport = report
        if !report.trashed.isEmpty {
            let removed = Set(report.trashed)
            items.removeAll { removed.contains($0.name) }
        }
        return report
    }

    // MARK: - 工具

    nonisolated static func measure(_ url: URL) async -> UInt64 {
        await Task.detached(priority: .utility) { measureSync(url) }.value
    }

    nonisolated private static func measureSync(_ url: URL) -> UInt64 {
        do {
            let fileManager = FileManager.default
            guard let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true }
            ) else {
                return 0
            }
            var total: UInt64 = 0
            for case let fileURL as URL in enumerator {
                guard let values = try? fileURL.resourceValues(
                    forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
                ), values.isRegularFile == true else { continue }
                total &+= UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            }
            return total
        }
    }

    nonisolated private static func largeFiles(in home: URL) async -> [Item] {
        await Task.detached(priority: .utility) { largeFilesSync(in: home) }.value
    }

    nonisolated private static func largeFilesSync(in home: URL) -> [Item] {
        do {
            let fileManager = FileManager.default
            let roots = ["Downloads", "Desktop", "Documents", "Movies"].map {
                home.appendingPathComponent($0, isDirectory: true)
            }

            var found: [(url: URL, bytes: UInt64)] = []
            for root in roots where fileManager.fileExists(atPath: root.path) {
                guard let enumerator = fileManager.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants],
                    errorHandler: { _, _ in true }
                ) else { continue }
                for case let fileURL as URL in enumerator {
                    guard let values = try? fileURL.resourceValues(
                        forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
                    ), values.isRegularFile == true else { continue }
                    let bytes = UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                    guard bytes >= largeFileThreshold else { continue }
                    found.append((fileURL, bytes))
                }
            }

            return found
                .sorted { $0.bytes > $1.bytes }
                .prefix(largeFileLimit)
                .map { entry in
                    Item(
                        id: "large-\(entry.url.path)",
                        name: entry.url.lastPathComponent,
                        note: entry.url.deletingLastPathComponent().path.replacingOccurrences(
                            of: home.path,
                            with: "~"
                        ),
                        icon: "doc.fill",
                        risk: .caution,
                        category: .largeFile,
                        url: entry.url,
                        bytes: entry.bytes,
                        isDirectory: false
                    )
                }
        }
    }

    nonisolated static func formatted(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useMB]
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
