import Foundation
import AppKit

// MARK: - 应用内更新检查器

/// 通过 GitHub Releases API 检查是否有新版本可用，支持自动后台检查和手动触发。
@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    private(set) var latestVersion: String?
    private(set) var releaseURL: URL?
    private(set) var releaseNotes: String?
    private(set) var isChecking = false
    private(set) var lastCheckDate: Date?
    private(set) var checkError: String?

    /// 是否有可用更新
    var hasUpdate: Bool {
        guard let latest = latestVersion else { return false }
        return Self.compareVersions(current: AppVersion.current.marketingVersion, latest: latest) == .orderedAscending
    }

    private let session: URLSession
    private let owner = "kuaoaoaoao"
    private let repo = "CoolRun"
    private var autoCheckTask: Task<Void, Never>?

    private init(session: URLSession = .shared) {
        self.session = session
    }

    /// 启动后台自动检查（每 6 小时检查一次）
    func startAutoCheck() {
        autoCheckTask?.cancel()
        autoCheckTask = Task { [weak self] in
            // 启动后延迟 30 秒再首次检查，避免影响启动性能
            try? await Task.sleep(for: .seconds(30))
            while !Task.isCancelled {
                await self?.checkForUpdates(silent: true)
                try? await Task.sleep(for: .seconds(6 * 3600))
            }
        }
    }

    func stopAutoCheck() {
        autoCheckTask?.cancel()
        autoCheckTask = nil
    }

    /// 检查更新。silent=true 时不显示"已是最新"提示。
    func checkForUpdates(silent: Bool = false) async {
        guard !isChecking else { return }
        isChecking = true
        checkError = nil

        defer { isChecking = false }

        do {
            let release = try await fetchLatestRelease()
            latestVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            releaseURL = URL(string: release.htmlURL)
            releaseNotes = release.body
            lastCheckDate = Date()

            if hasUpdate && !silent {
                showUpdateNotification()
            } else if !hasUpdate && !silent {
                showNoUpdateAlert()
            }
        } catch {
            checkError = error.localizedDescription
            if !silent {
                showCheckFailedAlert(error: error)
            }
        }
    }

    // MARK: - GitHub API

    private func fetchLatestRelease() async throws -> GitHubRelease {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/repos/\(owner)/\(repo)/releases/latest"

        guard let url = components.url else {
            throw UpdateError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            if httpResponse.statusCode == 404 {
                throw UpdateError.noReleasesFound
            }
            throw UpdateError.httpError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    // MARK: - Version Comparison

    /// 语义化版本比较：1.2.3 < 1.3.0
    static func compareVersions(current: String, latest: String) -> ComparisonResult {
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        let latestParts = latest.split(separator: ".").compactMap { Int($0) }
        let maxCount = max(currentParts.count, latestParts.count)

        for i in 0..<maxCount {
            let c = i < currentParts.count ? currentParts[i] : 0
            let l = i < latestParts.count ? latestParts[i] : 0
            if c < l { return .orderedAscending }
            if c > l { return .orderedDescending }
        }
        return .orderedSame
    }

    // MARK: - UI Notifications

    private func showUpdateNotification() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = LocalizedString.update("new_version")
        alert.informativeText = "CoolRun v\(latestVersion ?? "?") (\(LocalizedString.settings("version")) v\(AppVersion.current.marketingVersion))\n\n\(releaseNotes?.prefix(200) ?? "")"
        alert.addButton(withTitle: LocalizedString.update("go_download"))
        alert.addButton(withTitle: LocalizedString.update("remind_later"))

        if alert.runModal() == .alertFirstButtonReturn, let url = releaseURL {
            NSWorkspace.shared.open(url)
        }
    }

    private func showNoUpdateAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = LocalizedString.update("up_to_date")
        alert.informativeText = LocalizedString.update("up_to_date_msg") + " v\(AppVersion.current.marketingVersion)"
        alert.addButton(withTitle: LocalizedString.common("confirm"))
        alert.runModal()
    }

    private func showCheckFailedAlert(error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = LocalizedString.update("check_failed")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: LocalizedString.common("confirm"))
        alert.runModal()
    }
}

// MARK: - Models

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let body: String?
    let publishedAt: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body
        case publishedAt = "published_at"
    }
}

enum UpdateError: LocalizedError {
    case invalidURL
    case invalidResponse
    case noReleasesFound
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return LocalizedString.update("invalid_url")
        case .invalidResponse:
            return LocalizedString.update("invalid_response")
        case .noReleasesFound:
            return LocalizedString.update("no_releases")
        case .httpError(let code):
            return LocalizedString.update("http_error") + "（HTTP \(code)）"
        }
    }
}
