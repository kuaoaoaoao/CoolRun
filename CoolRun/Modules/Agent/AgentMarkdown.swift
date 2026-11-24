import Foundation

/// 把模型输出的 Markdown 转成 SwiftUI 能直接显示的富文本。
///
/// 面板只有 400 多点宽，所以这里只做三件事：行内语法交给系统解析、
/// 标题降级成加粗行、表格压平成「键：值」。完整的 Markdown 渲染器
/// （代码块高亮、嵌套列表、表格排版）在这么窄的地方只会更难读，
/// 真正该做的是在提示词里劝模型少用表格。
enum AgentMarkdown {

    /// 单行能承载的最大列数，超过就把多余的列并到最后一列。
    private nonisolated static let maxTableColumns = 3

    nonisolated static func render(_ text: String) -> AttributedString {
        var output = AttributedString()
        let lines = text.components(separatedBy: .newlines)
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 表格块：连续的 | … | 行一起处理
            if isTableRow(trimmed) {
                var block: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard isTableRow(candidate) else { break }
                    block.append(candidate)
                    index += 1
                }
                output.append(flattenTable(block))
                continue
            }

            output.append(renderLine(trimmed))
            if index < lines.count - 1 {
                output.append(AttributedString("\n"))
            }
            index += 1
        }

        return output
    }

    // MARK: - 行

    private nonisolated static func renderLine(_ trimmed: String) -> AttributedString {
        // 标题：#、##、### 都降级成加粗行，不保留井号
        if let heading = headingText(trimmed) {
            var line = AttributedString(heading)
            line.inlinePresentationIntent = .stronglyEmphasized
            return line
        }
        return inline(trimmed)
    }

    /// 去掉行首的 1-6 个 `#` 加一个空格；不是标题返回 nil。
    private nonisolated static func headingText(_ trimmed: String) -> String? {
        var hashCount = 0
        for character in trimmed {
            if character == "#" {
                hashCount += 1
            } else {
                break
            }
        }
        guard hashCount > 0, hashCount <= 6 else { return nil }
        let rest = trimmed.dropFirst(hashCount)
        guard rest.first == " " else { return nil }
        return String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    private nonisolated static func inline(_ text: String) -> AttributedString {
        guard !text.isEmpty else { return AttributedString() }
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        if let parsed = try? AttributedString(markdown: text, options: options) {
            return parsed
        }
        return AttributedString(text)
    }

    // MARK: - 表格

    private nonisolated static func isTableRow(_ trimmed: String) -> Bool {
        trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.count > 2
    }

    private nonisolated static func cells(of row: String) -> [String] {
        row.split(separator: "|", omittingEmptySubsequences: false)
            .dropFirst()
            .dropLast()
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// `|---|---|` 这种分隔行。
    private nonisolated static func isSeparatorRow(_ cells: [String]) -> Bool {
        !cells.isEmpty && cells.allSatisfy { cell in
            !cell.isEmpty && cell.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    /// 表格压平成「第一列：其余列」的行，每行一条。
    private nonisolated static func flattenTable(_ block: [String]) -> AttributedString {
        let rows = block.map(cells(of:)).filter { !isSeparatorRow($0) }
        guard let header = rows.first else { return AttributedString() }

        var output = AttributedString()
        for (offset, row) in rows.enumerated() {
            // 表头本身不输出（下面的数据行已经带了列名），但空表头时留一行
            if offset == 0, header.allSatisfy({ $0.isEmpty }) { continue }
            if offset == 0 { continue }

            let label = row.first ?? ""
            let rest = row.dropFirst().prefix(maxTableColumns - 1).joined(separator: " · ")
            var line: AttributedString
            if rest.isEmpty {
                line = inline(label)
            } else if label.isEmpty {
                line = inline(rest)
            } else {
                var key = AttributedString(label)
                key.inlinePresentationIntent = .stronglyEmphasized
                line = key + AttributedString("：") + inline(rest)
            }
            output.append(line)
            output.append(AttributedString("\n"))
        }
        return output
    }
}
