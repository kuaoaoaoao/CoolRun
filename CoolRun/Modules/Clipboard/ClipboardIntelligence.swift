import Foundation

/// 剪贴内容的本地分类。
///
/// 纯启发式、零成本、离线可用——它不做语义理解，只回答"这条大概是链接/命令/代码/
/// 还是长文"。这样用户至少能一键把 200 条历史收窄到自己关心的那一类，
/// 而且不联网、不花钱、不会把内容发给任何模型。
///
/// 性能注意：这个函数的调用方是 SwiftUI 的 body。早先版本对每条文本跑十几次
/// `String.contains`（Foundation 的 `range(of:)` 会走 Unicode 折叠，很慢），
/// 而 body 每次失效都会重算一遍，直接把 CPU 打到 62%。现在改成：小写只转一次、
/// 用 ASCII 字节扫描代替 Foundation 搜索、并且调用方必须缓存结果。
enum ClipKind: String, CaseIterable, Sendable, Identifiable {
    case link
    case command
    case code
    case number
    case long
    case text

    nonisolated var id: String { rawValue }

    nonisolated var symbol: String {
        switch self {
        case .link: return "link"
        case .command: return "terminal"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .number: return "number"
        case .long: return "text.alignleft"
        case .text: return "textformat"
        }
    }

    nonisolated func title(_ language: AppLanguage) -> String {
        switch self {
        case .link:
            return LocalizedString.l(language, en: "Links", zh: "链接", ja: "リンク", ko: "링크")
        case .command:
            return LocalizedString.l(language, en: "Commands", zh: "命令", ja: "コマンド", ko: "명령")
        case .code:
            return LocalizedString.l(language, en: "Code", zh: "代码", ja: "コード", ko: "코드")
        case .number:
            return LocalizedString.l(language, en: "Numbers", zh: "数字", ja: "数値", ko: "숫자")
        case .long:
            return LocalizedString.l(language, en: "Long text", zh: "长文", ja: "長文", ko: "장문")
        case .text:
            return LocalizedString.l(language, en: "Text", zh: "普通文字", ja: "テキスト", ko: "텍스트")
        }
    }
}

enum ClipClassifier {
    /// 判定顺序有意义：先认最容易认错的（链接里含 `://` 会被误判成代码，
    /// 代码里含数字也不能当数字看），所以链接 → 命令 → 代码 → 数字 → 长文 → 普通。
    /// 分类只看开头这么多字节。
    ///
    /// 剪贴板里经常躺着几 MB 的文本（一整份日志、一整段代码）。按字符遍历全文
    /// 会让主线程卡上好几秒——`sample` 的调用点就在这里。类型判断靠首行和前
    /// 几十个字符，看全文既慢又没必要。
    nonisolated static let sampleByteLimit = 2048

    nonisolated static func sample(of text: String) -> String {
        let utf8 = text.utf8
        guard utf8.count > sampleByteLimit else { return text }
        return String(decoding: utf8.prefix(sampleByteLimit), as: UTF8.self)
    }

    nonisolated static func kind(of text: String) -> ClipKind {
        let byteCount = text.utf8.count
        guard byteCount > 0 else { return .text }

        let sample = sample(of: text)
        let trimmed = sample.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .text }

        // 小写只转一次，后面所有匹配都用它。样本已经被截断，这里不会再有全文开销。
        let lowered = trimmed.lowercased()

        if isLink(trimmed, lowered: lowered) { return .link }
        if isCommand(lowered: lowered) { return .command }
        if isCode(trimmed, lowered: lowered, byteCount: byteCount) { return .code }
        if isNumberLike(trimmed, byteCount: byteCount) { return .number }
        if byteCount > 480 || newlineCount(in: sample) > 8 { return .long }
        return .text
    }

    private nonisolated static func newlineCount(in text: String) -> Int {
        var count = 0
        for byte in text.utf8 where byte == 0x0A {
            count += 1
            if count > 8 { return count }
        }
        return count
    }

    /// 一次扫完，返回 id → 分类。调用方应缓存它，不要在 body 里直接调用。
    nonisolated static func classify(_ entries: [ClipboardHistoryEntry]) -> [UUID: ClipKind] {
        var result: [UUID: ClipKind] = [:]
        result.reserveCapacity(entries.count)
        for entry in entries {
            result[entry.id] = kind(of: entry.text)
        }
        return result
    }

    nonisolated static func counts(from kinds: [UUID: ClipKind]) -> [ClipKind: Int] {
        var result: [ClipKind: Int] = [:]
        for kind in kinds.values {
            result[kind, default: 0] += 1
        }
        return result
    }

    nonisolated static func counts(for entries: [ClipboardHistoryEntry]) -> [ClipKind: Int] {
        counts(from: classify(entries))
    }

    // MARK: - 判定细节

    private nonisolated static func isLink(_ text: String, lowered: String) -> Bool {
        // 首行里带空格的基本是句子而不是网址；`://` 例外（前面可能有说明文字）。
        let firstLine = firstLine(of: text).trimmingCharacters(in: .whitespaces)
        let loweredLine = firstLine.lowercased()
        guard !firstLine.contains(" ") || loweredLine.contains("://") else { return false }

        let token: String
        if let space = firstLine.firstIndex(of: " ") {
            token = String(firstLine[..<space])
        } else {
            token = firstLine
        }
        let loweredToken = token.lowercased()

        guard loweredToken.contains("://") || loweredToken.hasPrefix("www.") else { return false }
        if let range = loweredToken.range(of: "://") {
            let host = loweredToken[range.upperBound...].prefix(while: { $0 != "/" && $0 != "?" })
            return host.contains(".") || host == "localhost"
        }
        return loweredToken.hasPrefix("www.")
    }

    private nonisolated static let commandPrefixes: [String] = [
        "$ ", "sudo ", "git ", "cd ", "ls ", "rm ", "cp ", "mv ", "mkdir ", "curl ", "wget ",
        "npm ", "pnpm ", "yarn ", "npx ", "node ", "python ", "pip ", "brew ", "docker ",
        "kubectl ", "ssh ", "scp ", "xcodebuild ", "swift ", "grep ", "cat ", "chmod ",
        "defaults write ", "launchctl ", "ffmpeg ", "ollama ",
    ]

    private nonisolated static func isCommand(lowered: String) -> Bool {
        let firstLine = firstLine(of: lowered)
        guard !firstLine.isEmpty else { return false }
        if firstLine.hasPrefix("$") { return true }
        return commandPrefixes.contains { firstLine.hasPrefix($0) }
    }

    /// 只留最distinctive的几个：多了没意义，只是白花时间。
    private nonisolated static let codeMarkers: [String] = [
        "func ", "import ", "def ", "class ", "struct ", "enum ", "public ", "private ",
        "const ", "return ", "=>", "->", "</", "};", ");", "#include", "select ",
    ]

    private nonisolated static func isCode(_ text: String, lowered: String, byteCount: Int) -> Bool {
        // 短文本几乎不可能是代码，先挡掉——这是最常见的一类，省下的时间最多。
        guard byteCount >= 24 else { return false }

        var markerHits = 0
        for marker in codeMarkers where lowered.contains(marker) {
            markerHits += 1
            if markerHits >= 2 { return true }
        }

        let hasBraceLine = lowered.contains("{") && lowered.contains("}")
        if markerHits == 1 && (hasBraceLine || lowered.contains("\n")) { return true }
        return hasBraceLine && lowered.contains("\n")
    }

    private nonisolated static let numberAllowed: Set<Character> = [
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
        ".", ",", "+", "-", "%", "$", "¥", "€", "£", ":", "／", "/", " ",
    ]

    private nonisolated static func isNumberLike(_ text: String, byteCount: Int) -> Bool {
        guard byteCount <= 40 else { return false }
        guard text.contains(where: \.isNumber) else { return false }
        return text.allSatisfy { numberAllowed.contains($0) }
    }

    /// 按字节找换行。`String.firstIndex(where:)` 是逐 Character 走索引，
    /// 长文本上比按字节扫慢两个数量级。
    private nonisolated static func firstLine(of text: String) -> String {
        let utf8 = text.utf8
        if let newline = utf8.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            return String(decoding: utf8[..<newline], as: UTF8.self)
        }
        return text
    }
}
