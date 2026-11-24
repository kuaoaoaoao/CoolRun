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
        let relativePath: String
        let icon: String
        let risk: Risk
        let category: Category

        func name(_ lang: AppLanguage) -> String {
            CleanupAdvisor.localizedName(id, lang: lang)
        }

        func note(_ lang: AppLanguage) -> String {
            CleanupAdvisor.localizedNote(id, lang: lang)
        }
    }

    private nonisolated static let templates: [Template] = [
        Template(
            id: "caches",
            relativePath: "Library/Caches",
            icon: "shippingbox.fill",
            risk: .safe,
            category: .cache
        ),
        Template(
            id: "logs",
            relativePath: "Library/Logs",
            icon: "doc.text.fill",
            risk: .safe,
            category: .log
        ),
        Template(
            id: "derived-data",
            relativePath: "Library/Developer/Xcode/DerivedData",
            icon: "hammer.fill",
            risk: .safe,
            category: .developer
        ),
        Template(
            id: "device-support",
            relativePath: "Library/Developer/Xcode/iOS DeviceSupport",
            icon: "iphone.gen3",
            risk: .safe,
            category: .developer
        ),
        Template(
            id: "simulator-caches",
            relativePath: "Library/Developer/CoreSimulator/Caches",
            icon: "square.stack.3d.up.fill",
            risk: .safe,
            category: .developer
        ),
        Template(
            id: "npm-cache",
            relativePath: ".npm/_cacache",
            icon: "cube.box.fill",
            risk: .safe,
            category: .package
        ),
        Template(
            id: "pnpm-store",
            relativePath: "Library/pnpm/store",
            icon: "cube.box.fill",
            risk: .safe,
            category: .package
        ),
        Template(
            id: "homebrew-cache",
            relativePath: "Library/Caches/Homebrew",
            icon: "mug.fill",
            risk: .safe,
            category: .package
        ),
        Template(
            id: "trash",
            relativePath: ".Trash",
            icon: "trash.fill",
            risk: .caution,
            category: .trash
        ),
        Template(
            id: "device-backups",
            relativePath: "Library/Application Support/MobileSync/Backup",
            icon: "iphone.and.arrow.forward",
            risk: .caution,
            category: .backup
        )
    ]

    // MARK: - 条目文案

    nonisolated private static func localizedName(_ id: String, lang: AppLanguage) -> String {
        switch id {
        case "caches":
            return LocalizedString.l(lang, en: "App Caches", zh: "应用缓存", ja: "アプリのキャッシュ", ko: "앱 캐시")
        case "logs":
            return LocalizedString.l(lang, en: "Runtime Logs", zh: "运行日志", ja: "実行ログ", ko: "실행 로그")
        case "derived-data":
            return LocalizedString.l(lang, en: "Xcode Build Cache", zh: "Xcode 编译缓存", ja: "Xcode ビルドキャッシュ", ko: "Xcode 빌드 캐시")
        case "device-support":
            return LocalizedString.l(lang, en: "Device Debug Symbols", zh: "真机调试符号", ja: "実機デバッグシンボル", ko: "실기기 디버그 심볼")
        case "simulator-caches":
            return LocalizedString.l(lang, en: "Simulator Caches", zh: "模拟器缓存", ja: "シミュレータのキャッシュ", ko: "시뮬레이터 캐시")
        case "npm-cache":
            return LocalizedString.l(lang, en: "npm Cache", zh: "npm 缓存", ja: "npm キャッシュ", ko: "npm 캐시")
        case "pnpm-store":
            return LocalizedString.l(lang, en: "pnpm Global Store", zh: "pnpm 全局存储", ja: "pnpm グローバルストア", ko: "pnpm 전역 저장소")
        case "homebrew-cache":
            return LocalizedString.l(lang, en: "Homebrew Cache", zh: "Homebrew 安装包缓存", ja: "Homebrew パッケージキャッシュ", ko: "Homebrew 패키지 캐시")
        case "trash":
            return LocalizedString.l(lang, en: "Trash", zh: "废纸篓", ja: "ゴミ箱", ko: "휴지통")
        case "device-backups":
            return LocalizedString.l(lang, en: "iPhone / iPad Local Backups", zh: "iPhone / iPad 本地备份", ja: "iPhone / iPad のローカルバックアップ", ko: "iPhone / iPad 로컬 백업")
        default:
            return id
        }
    }

    nonisolated private static func localizedNote(_ id: String, lang: AppLanguage) -> String {
        switch id {
        case "caches":
            return LocalizedString.l(
                lang,
                en: "Temporary caches from each app. The first launch after deletion is a bit slower, then they rebuild themselves.",
                zh: "各 App 的临时缓存。删掉后第一次打开会稍慢，之后自己重建。",
                ja: "各アプリの一時キャッシュです。削除直後の初回起動は少し遅くなりますが、その後は自動で再作成されます。",
                ko: "각 앱의 임시 캐시입니다. 삭제 후 첫 실행은 조금 느리지만 이후 스스로 다시 만들어집니다."
            )
        case "logs":
            return LocalizedString.l(
                lang,
                en: "System and app logs. Deleting them does not affect functionality, you just lose material for troubleshooting.",
                zh: "系统和 App 的日志。删掉不影响功能，只是出问题时少了排查材料。",
                ja: "システムとアプリのログです。削除しても動作に影響はありませんが、問題発生時の調査材料が減ります。",
                ko: "시스템과 앱 로그입니다. 삭제해도 기능에는 영향이 없지만 문제 발생 시 조사 자료가 줄어듭니다."
            )
        case "derived-data":
            return LocalizedString.l(
                lang,
                en: "Build intermediates. The next build starts from scratch and takes longer, but nothing breaks.",
                zh: "编译中间产物。删掉后下次编译从头来，慢一点，但不会出错。",
                ja: "ビルドの中間生成物です。次回のビルドは最初からになり少し遅くなりますが、エラーにはなりません。",
                ko: "빌드 중간 산출물입니다. 다음 빌드는 처음부터 시작해 조금 느려지지만 오류는 나지 않습니다."
            )
        case "device-support":
            return LocalizedString.l(
                lang,
                en: "System symbols used for debugging physical devices. They re-download the first time you connect a phone on a new OS.",
                zh: "调试真机用的系统符号。删掉后第一次连新系统的手机会重新下载。",
                ja: "実機デバッグ用のシステムシンボルです。削除後、新しい OS の端末に初めて接続した際に再ダウンロードされます。",
                ko: "실기기 디버깅용 시스템 심볼입니다. 삭제 후 새 OS 기기를 처음 연결할 때 다시 내려받습니다."
            )
        case "simulator-caches":
            return LocalizedString.l(
                lang,
                en: "Simulator runtime caches, rebuilt automatically after deletion.",
                zh: "模拟器运行时缓存，删了会自动重建。",
                ja: "シミュレータの実行時キャッシュです。削除しても自動で再作成されます。",
                ko: "시뮬레이터 런타임 캐시로, 삭제해도 자동으로 다시 만들어집니다."
            )
        case "npm-cache":
            return LocalizedString.l(
                lang,
                en: "Packages downloaded by npm. Installing dependencies re-downloads them; projects already installed are unaffected.",
                zh: "npm 下载过的包。删掉后装依赖会重新下载，已装好的项目不受影响。",
                ja: "npm がダウンロードしたパッケージです。依存関係の導入時に再ダウンロードされますが、導入済みのプロジェクトには影響しません。",
                ko: "npm이 내려받은 패키지입니다. 의존성을 설치할 때 다시 내려받지만 이미 설치된 프로젝트에는 영향이 없습니다."
            )
        case "pnpm-store":
            return LocalizedString.l(
                lang,
                en: "The pnpm package store. Reinstalling dependencies re-downloads them; existing node_modules still work.",
                zh: "pnpm 的包仓库。删掉后重装依赖会重新下载，已有 node_modules 仍可用。",
                ja: "pnpm のパッケージストアです。依存関係の再導入時に再ダウンロードされますが、既存の node_modules はそのまま使えます。",
                ko: "pnpm 패키지 저장소입니다. 의존성을 다시 설치할 때 재다운로드되지만 기존 node_modules는 그대로 사용할 수 있습니다."
            )
        case "homebrew-cache":
            return LocalizedString.l(
                lang,
                en: "Downloaded installers. Reinstalling the same version re-downloads them.",
                zh: "下载过的安装包。删掉后重装同一版本会重新下载。",
                ja: "ダウンロード済みのインストーラです。同じバージョンを再インストールすると再ダウンロードされます。",
                ko: "내려받은 설치 파일입니다. 같은 버전을 다시 설치하면 재다운로드됩니다."
            )
        case "trash":
            return LocalizedString.l(
                lang,
                en: "Items you already threw away. Emptying is irreversible, so check nothing you still need is inside.",
                zh: "已经扔掉的東西。清空后无法恢复，先确认里面没有你还要的。",
                ja: "すでに捨てた項目です。空にすると元に戻せないので、必要なものが残っていないか確認してください。",
                ko: "이미 버린 항목입니다. 비우면 되돌릴 수 없으니 필요한 것이 없는지 먼저 확인하세요."
            )
        case "device-backups":
            return LocalizedString.l(
                lang,
                en: "Phone backups stored on this Mac. Deleting them removes the local copy; iCloud backups are unaffected.",
                zh: "这台电脑上的手机备份。删掉后本地就没有了，iCloud 备份不受影响。",
                ja: "この Mac 上の端末バックアップです。削除するとローカルには残りませんが、iCloud バックアップには影響しません。",
                ko: "이 Mac에 있는 기기 백업입니다. 삭제하면 로컬에는 남지 않지만 iCloud 백업에는 영향이 없습니다."
            )
        default:
            return ""
        }
    }

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
        let lang = AppSettings.shared.language
        progressText = LocalizedString.l(
            lang,
            en: "Checking what can be cleaned…",
            zh: "正在看哪些能清…",
            ja: "何を削除できるか確認中…",
            ko: "무엇을 정리할 수 있는지 확인 중…"
        )
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
                    name: template.name(lang),
                    note: template.note(lang),
                    icon: template.icon,
                    risk: template.risk,
                    category: template.category,
                    url: url,
                    bytes: bytes,
                    isDirectory: true
                )
            )
        }

        progressText = LocalizedString.l(
            lang,
            en: "Looking for large files…",
            zh: "正在找大文件…",
            ja: "大きなファイルを探しています…",
            ko: "큰 파일을 찾는 중…"
        )
        let largeFiles = await Self.largeFiles(in: home)
        collected.append(contentsOf: largeFiles)

        items = collected.sorted { lhs, rhs in
            if lhs.risk != rhs.risk { return lhs.risk < rhs.risk }
            return lhs.bytes > rhs.bytes
        }
        lastScanAt = Date()
    }

    // MARK: - 清理

    /// 每一次真正移走东西都留一条记录。
    ///
    /// 这不是为了好看：用户发现文件不见了的时候，「本鱼到底动没动过」必须有据可查。
    /// 追加写 JSONL，坏了也只坏最后一行。
    nonisolated static var auditFileURL: URL {
        GoldDataStorage.fileURL(named: "cleanup-audit.jsonl")
    }

    private nonisolated static func recordAudit(name: String, url: URL, bytes: UInt64) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let escapedName = name.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedPath = url.path.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let line = "{\"time\":\"\(stamp)\",\"name\":\"\(escapedName)\",\"path\":\"\(escapedPath)\",\"bytes\":\(bytes)}\n"
        guard let data = line.data(using: .utf8) else { return }
        let fileURL = auditFileURL
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

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
                Self.recordAudit(name: name, url: url, bytes: size)
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
        await runOffPool { measureSync(url) }
    }

    /// 在真正的后台线程上跑阻塞的文件系统遍历。
    ///
    /// 这里不能用 `Task.detached`：它仍然跑在 Swift 并发的协作线程池里，
    /// 线程数等于核数，一次遍历几十万文件的同步 `open`/`getdirentries` 会把
    /// 池里的线程占住，别的 async 任务只能排队等。用 GCD 队列才是真的离开。
    nonisolated private static func runOffPool<T: Sendable>(
        _ work: @escaping @Sendable () -> T
    ) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: work())
            }
        }
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
        await runOffPool { largeFilesSync(in: home) }
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
