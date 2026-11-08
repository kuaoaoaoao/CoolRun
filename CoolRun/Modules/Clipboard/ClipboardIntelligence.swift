import Foundation

/// 剪贴内容的本地分类。
///
/// 纯启发式、零成本、离线可用——它不做语义理解，只回答"这条大概是链接/命令/代码/
/// 还是长文"。这样用户至少能一键把 200 条历史收窄到自己关心的那一类，
/// 而且不联网、不花钱、不会把内容发给任何模型。
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
    nonisolated static func kind(of text: String) -> ClipKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .text }

        if isLink(trimmed) { return .link }
        if isCommand(trimmed) { return .command }
        if isCode(trimmed) { return .code }
        if isNumberLike(trimmed) { return .number }
        if trimmed.count > 240 || trimmed.components(separatedBy: "\n").count > 8 { return .long }
        return .text
    }

    nonisolated static func counts(for entries: [ClipboardHistoryEntry]) -> [ClipKind: Int] {
        var result: [ClipKind: Int] = [:]
        for entry in entries {
            result[kind(of: entry.text), default: 0] += 1
        }
        return result
    }

    // MARK: - 判定细节

    private nonisolated static let schemeMarkers = ["://"]

    private nonisolated static func isLink(_ text: String) -> Bool {
        let firstLine = text.components(separatedBy: .newlines).first ?? text
        guard !firstLine.contains(" ") || firstLine.contains("://") else { return false }
        let token = firstLine.trimmingCharacters(in: .whitespaces)
        guard !token.contains(" ") else { return false }
        guard schemeMarkers.contains(where: token.contains) || token.lowercased().hasPrefix("www.") else {
            return false
        }
        // 至少要有一个像主机的部分，避免把 "a://" 这种残片当链接。
        if let range = token.range(of: "://") {
            let host = token[range.upperBound...].prefix(while: { $0 != "/" && $0 != "?" })
            return host.contains(".") || host.lowercased() == "localhost"
        }
        return token.lowercased().hasPrefix("www.")
    }

    private nonisolated static let commandPrefixes: [String] = [
        "$ ", "sudo ", "git ", "cd ", "ls ", "rm ", "cp ", "mv ", "mkdir ", "curl ", "wget ",
        "npm ", "pnpm ", "yarn ", "npx ", "node ", "python ", "pip ", "brew ", "docker ",
        "kubectl ", "ssh ", "scp ", "xcodebuild ", "swift ", "grep ", "cat ", "chmod ",
        "defaults write ", "launchctl ", "ffmpeg ", "ollama ",
    ]

    private nonisolated static func isCommand(_ text: String) -> Bool {
        let firstLine = (text.components(separatedBy: .newlines).first ?? text)
            .trimmingCharacters(in: .whitespaces)
        let lowered = firstLine.lowercased()
        guard !lowered.isEmpty else { return false }
        if commandPrefixes.contains(where: { lowered.hasPrefix($0) }) { return true }
        // `$` 开头的多行也算：那是终端里复制出来的命令块。
        return lowered.hasPrefix("$")
    }

    private nonisolated static let codeMarkers: [String] = [
        "func ", "import ", "def ", "class ", "struct ", "enum ", "public ", "private ",
        "const ", "let ", "var ", "return ", "=>", "->", "</", "};", ");", "{\n", ":=",
        "#include", "SELECT ", "select ",
    ]

    private nonisolated static func isCode(_ text: String) -> Bool {
        let hasNewline = text.contains("\n")
        let hasBraceLine = text.contains("{") && text.contains("}")
        let markers = codeMarkers.filter { text.contains($0) }.count
        if markers >= 2 { return true }
        if markers == 1 && (hasBraceLine || hasNewline) { return true }
        // 缩进 + 分号，多半是从编辑器里复制出来的片段。
        if hasNewline && hasBraceLine { return true }
        return false
    }

    private nonisolated static func isNumberLike(_ text: String) -> Bool {
        let allowed = Set("0123456789.,+-%$¥€£:／/ ")
        guard text.count <= 40 else { return false }
        guard text.contains(where: \.isNumber) else { return false }
        return text.allSatisfy { allowed.contains($0) }
    }
}
