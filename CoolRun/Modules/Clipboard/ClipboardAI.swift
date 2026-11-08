import Foundation
import Observation

/// 剪贴板的 AI 能力：把一条剪贴内容整理成能直接用的东西，以及"按意思找"。
///
/// 这里故意不走 Agent 的 tool 循环——整理一段文本不需要模型去翻系统数据，
/// 单轮请求更快、更便宜，也不会因为模型突发奇想调工具而超时。
@MainActor
@Observable
final class ClipboardAI {
    static let shared = ClipboardAI()

    enum Action: String, CaseIterable, Identifiable {
        case summarize
        case clean
        case todos
        case translate

        nonisolated var id: String { rawValue }

        nonisolated var symbol: String {
            switch self {
            case .summarize: return "text.append"
            case .clean: return "wand.and.stars"
            case .todos: return "checklist"
            case .translate: return "character.book.closed"
            }
        }

        nonisolated func title(_ language: AppLanguage) -> String {
            switch self {
            case .summarize:
                return LocalizedString.l(language, en: "Summarize", zh: "精简成要点", ja: "要点にまとめる", ko: "요점 정리")
            case .clean:
                return LocalizedString.l(language, en: "Clean up", zh: "清理格式", ja: "体裁を整える", ko: "서식 정리")
            case .todos:
                return LocalizedString.l(language, en: "Extract to-dos", zh: "提取待办", ja: "ToDo を抽出", ko: "할 일 추출")
            case .translate:
                return LocalizedString.l(language, en: "Translate", zh: "翻译", ja: "翻訳", ko: "번역")
            }
        }

        nonisolated var instruction: String {
            switch self {
            case .summarize:
                return "把这段内容压缩成不超过 5 条要点，每条一行，用「- 」开头。保留关键数字、时间、人名、金额。不要编造，不要加建议，不要写开场白。"
            case .clean:
                return """
                把这段文本清理成可以直接使用的干净文本：去掉多余空行、行号、页眉页脚、转载声明、广告、\
                被硬换行切断的句子要接回去；不改变原意、不改变顺序、不缩写内容。只输出清理后的正文。
                """
            case .todos:
                return "从这段内容里提取需要人去做的事，一条一行，用「- 」开头。每条要带上原文里的时间、对象、数量等约束。没有可执行事项就只输出「没有找到待办」。不要补充原文没有的任务。"
            case .translate:
                return "如果这段内容是中文就翻译成英文，否则翻译成简体中文。只输出译文，不要解释、不要保留原文。"
            }
        }
    }

    /// 单次整理的输入上限。剪贴板里偶尔会有整篇文档，全塞进 prompt 又慢又贵，
    /// 超出的部分明确截断并在结果里说明，避免用户以为模型读完了。
    nonisolated static let inputLimit = 6000
    /// 语义搜索一次最多看多少条候选。再多 prompt 会失控，且命中率并不会更好。
    nonisolated static let searchCandidateLimit = 40
    nonisolated static let searchSnippetLimit = 160

    private(set) var isWorking = false
    private(set) var output = ""
    private(set) var errorMessage: String?
    private(set) var lastAction: Action?
    private(set) var wasTruncated = false

    private(set) var isSearching = false
    private(set) var searchError: String?

    private init() {}

    // MARK: - 整理

    func transform(_ rawText: String, action: Action) async {
        guard !isWorking else { return }
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "这条内容是空的，没什么可整理的。"
            return
        }

        let config: AgentRunConfig
        do {
            config = try AgentSettings.shared.makeConfig()
        } catch {
            errorMessage = "先在 Agent 设置里配好模型，再来整理。"
            return
        }

        isWorking = true
        errorMessage = nil
        output = ""
        wasTruncated = false
        lastAction = action
        defer { isWorking = false }

        let truncated = String(trimmed.prefix(Self.inputLimit))
        wasTruncated = truncated.count < trimmed.count

        let language = AppSettings.shared.language
        let system = LocalizedString.l(
            language,
            en: "You are a careful text editor. Do exactly the requested operation and output only the result.",
            zh: "你是一个谨慎的文字编辑。严格按要求处理，只输出结果本身。",
            ja: "慎重なテキスト編集者です。指示された処理だけを行い、結果のみを出力します。",
            ko: "신중한 텍스트 편집자입니다. 요청된 작업만 수행하고 결과만 출력합니다."
        )

        let stream: AsyncThrowingStream<WireEvent, Error>
        do {
            let wire = AgentWireFactory.make(config.protocolKind)
            stream = try await wire.stream(
                messages: [
                    AgentMessage(role: .system, content: system),
                    AgentMessage(role: .user, content: "任务：\(action.instruction)\n\n内容：\n\(truncated)"),
                ],
                tools: [],
                config: config
            )
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        var text = ""
        do {
            for try await event in stream {
                if case let .text(chunk) = event { text += chunk }
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else {
            errorMessage = "模型没返回内容，换个说法再试一次。"
            return
        }
        output = result
    }

    func clearSearchState() {
        searchError = nil
    }

    func clearOutput() {
        output = ""
        errorMessage = nil
        lastAction = nil
        wasTruncated = false
    }

    // MARK: - 按意思找

    /// 关键词搜不到时，把候选片段交给模型挑编号。
    /// 返回命中的条目 id（按原顺序），失败返回空数组。
    func findByMeaning(_ query: String, in entries: [ClipboardHistoryEntry]) async -> [UUID] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty, !entries.isEmpty else { return [] }

        let config: AgentRunConfig
        do {
            config = try AgentSettings.shared.makeConfig()
        } catch {
            searchError = "先在 Agent 设置里配好模型。"
            return []
        }

        let candidates = Array(entries.prefix(Self.searchCandidateLimit))
        let numbered = candidates.enumerated().map { index, entry in
            "\(index + 1). \(Self.snippet(entry.text))"
        }.joined(separator: "\n")

        let system = """
        你要在剪贴板历史里找东西。用户会给出想找什么，以及带编号的候选片段。
        只输出一个 JSON 数组，里面是真正相关的编号，例如 [3,7]；都不相关就输出 []。
        不要输出任何解释文字或代码块标记。宁缺勿滥：只是"提到"同一个词但用途不同的，不要选。
        """
        let user = "要找的是：\(trimmedQuery)\n\n候选片段：\n\(numbered)"

        isSearching = true
        searchError = nil
        defer { isSearching = false }

        do {
            let wire = AgentWireFactory.make(config.protocolKind)
            let stream = try await wire.stream(
                messages: [
                    AgentMessage(role: .system, content: system),
                    AgentMessage(role: .user, content: user),
                ],
                tools: [],
                config: config
            )
            var text = ""
            for try await event in stream {
                if case let .text(chunk) = event { text += chunk }
            }
            let indices = Self.parseIndices(text, upperBound: candidates.count)
            return indices.map { candidates[$0].id }
        } catch {
            searchError = error.localizedDescription
            return []
        }
    }

    // MARK: - 存成笔记

    @discardableResult
    func saveAsNote(_ text: String, title: String = "") -> Bool {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return false }
        let store = NotesStore.shared
        let groupName = "剪贴板整理"
        let groupID = store.groups.first(where: { $0.name == groupName })?.id
            ?? store.addGroup(name: groupName)?.id
        return store.saveNote(title: title, body: body, groupID: groupID) != nil
    }

    // MARK: - 工具

    nonisolated static func snippet(_ text: String, limit: Int = searchSnippetLimit) -> String {
        let collapsed = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(collapsed.prefix(limit))
    }

    /// 从模型回复里抠出数组编号。模型经常多包一层 ```json，或者写成 0 基，
    /// 所以只认 1...upperBound 范围内的数字，越界的丢掉。
    nonisolated static func parseIndices(_ raw: String, upperBound: Int) -> [Int] {
        guard upperBound > 0 else { return [] }
        var seen = Set<Int>()
        var result: [Int] = []
        var current = ""
        for character in raw {
            if character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                appendIndex(&result, &seen, current, upperBound: upperBound)
                current = ""
            }
        }
        if !current.isEmpty {
            appendIndex(&result, &seen, current, upperBound: upperBound)
        }
        return result
    }

    private nonisolated static func appendIndex(
        _ result: inout [Int],
        _ seen: inout Set<Int>,
        _ digits: String,
        upperBound: Int
    ) {
        guard let value = Int(digits), value >= 1, value <= upperBound else { return }
        let index = value - 1
        guard seen.insert(index).inserted else { return }
        result.append(index)
    }
}
