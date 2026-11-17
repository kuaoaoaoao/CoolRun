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

        nonisolated func instruction(_ language: AppLanguage) -> String {
            switch self {
            case .summarize:
                return LocalizedString.l(
                    language,
                    en: "Condense this into at most 5 bullet points, one per line, each starting with \"- \". Keep the key numbers, dates, names and amounts. Do not make things up, do not add advice, do not write an intro.",
                    zh: "把这段内容压缩成不超过 5 条要点，每条一行，用「- 」开头。保留关键数字、时间、人名、金额。不要编造，不要加建议，不要写开场白。",
                    ja: "この内容を最大5つの要点に圧縮し、1行に1つ「- 」で始めてください。重要な数字・日時・人名・金額は残すこと。創作や助言、前置きは不要です。",
                    ko: "이 내용을 5개 이하의 요점으로 압축하고 한 줄에 하나씩 \"- \"로 시작하세요. 핵심 숫자, 날짜, 이름, 금액은 유지하세요. 지어내지 말고 조언이나 서두도 쓰지 마세요."
                )
            case .clean:
                return LocalizedString.l(
                    language,
                    en: """
                    Clean this text up so it can be used directly: remove extra blank lines, line numbers, headers/footers, \
                    repost notices and ads; rejoin sentences broken by hard line wraps. Do not change the meaning, \
                    the order or shorten the content. Output only the cleaned body.
                    """,
                    zh: """
                    把这段文本清理成可以直接使用的干净文本：去掉多余空行、行号、页眉页脚、转载声明、广告、\
                    被硬换行切断的句子要接回去；不改变原意、不改变顺序、不缩写内容。只输出清理后的正文。
                    """,
                    ja: """
                    このテキストをそのまま使える形に整えてください：余分な空行、行番号、ヘッダー・フッター、\
                    転載表示、広告を削除し、改行で途切れた文はつなげること。意味・順序は変えず、内容も省略しないこと。\
                    整えた本文だけを出力してください。
                    """,
                    ko: """
                    이 텍스트를 바로 쓸 수 있게 정리하세요: 불필요한 빈 줄, 줄 번호, 머리말/꼬리말, \
                    재배포 문구, 광고를 제거하고, 강제 줄바꿈으로 끊긴 문장은 이어 붙이세요. 의미와 순서를 바꾸지 말고 \
                    내용을 줄이지 마세요. 정리된 본문만 출력하세요.
                    """
                )
            case .todos:
                return LocalizedString.l(
                    language,
                    en: "Extract the things a person needs to do from this content, one per line, each starting with \"- \". Each item must keep the time, target and quantity constraints from the original. If there is nothing actionable, output only \"No to-dos found\". Do not add tasks that are not in the original.",
                    zh: "从这段内容里提取需要人去做的事，一条一行，用「- 」开头。每条要带上原文里的时间、对象、数量等约束。没有可执行事项就只输出「没有找到待办」。不要补充原文没有的任务。",
                    ja: "この内容から人がやるべきことを抽出し、1行に1つ「- 」で始めてください。各項目には原文の日時・対象・数量などの条件を含めること。実行できることがなければ「ToDo は見つかりません」とだけ出力してください。原文にないタスクを補わないこと。",
                    ko: "이 내용에서 사람이 해야 할 일을 추출해 한 줄에 하나씩 \"- \"로 시작하세요. 각 항목에는 원문의 시간, 대상, 수량 등의 조건을 담으세요. 실행할 일이 없으면 \"할 일을 찾지 못했습니다\"만 출력하세요. 원문에 없는 작업을 추가하지 마세요."
                )
            case .translate:
                return LocalizedString.l(
                    language,
                    en: "If this content is in Chinese, translate it into English; otherwise translate it into Simplified Chinese. Output only the translation, with no explanation and no original text.",
                    zh: "如果这段内容是中文就翻译成英文，否则翻译成简体中文。只输出译文，不要解释、不要保留原文。",
                    ja: "この内容が中国語なら英語に、それ以外なら簡体字中国語に翻訳してください。訳文だけを出力し、説明も原文も含めないこと。",
                    ko: "이 내용이 중국어면 영어로, 그렇지 않으면 간체 중국어로 번역하세요. 번역문만 출력하고 설명이나 원문은 넣지 마세요."
                )
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
        let language = AppSettings.shared.language
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = LocalizedString.l(
                language,
                en: "This entry is empty, nothing to tidy up.",
                zh: "这条内容是空的，没什么可整理的。",
                ja: "この項目は空なので、整理するものがありません。",
                ko: "이 항목은 비어 있어서 정리할 것이 없습니다."
            )
            return
        }

        let config: AgentRunConfig
        do {
            config = try AgentSettings.shared.makeConfig()
        } catch {
            errorMessage = LocalizedString.l(
                language,
                en: "Configure a model in Agent settings first, then come back.",
                zh: "先在 Agent 设置里配好模型，再来整理。",
                ja: "先に Agent 設定でモデルを設定してからもう一度お試しください。",
                ko: "먼저 Agent 설정에서 모델을 구성한 뒤 다시 시도하세요."
            )
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

        let system = LocalizedString.l(
            language,
            en: "You are a careful text editor. Do exactly the requested operation and output only the result.",
            zh: "你是一个谨慎的文字编辑。严格按要求处理，只输出结果本身。",
            ja: "慎重なテキスト編集者です。指示された処理だけを行い、結果のみを出力します。",
            ko: "신중한 텍스트 편집자입니다. 요청된 작업만 수행하고 결과만 출력합니다."
        )

        let stream: AsyncThrowingStream<WireEvent, Error>
        let instruction = action.instruction(language)
        let userPrompt = LocalizedString.l(
            language,
            en: "Task: \(instruction)\n\nContent:\n\(truncated)",
            zh: "任务：\(instruction)\n\n内容：\n\(truncated)",
            ja: "タスク：\(instruction)\n\n内容：\n\(truncated)",
            ko: "작업: \(instruction)\n\n내용:\n\(truncated)"
        )
        do {
            let wire = AgentWireFactory.make(config.protocolKind)
            stream = try await wire.stream(
                messages: [
                    AgentMessage(role: .system, content: system),
                    AgentMessage(role: .user, content: userPrompt),
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
            errorMessage = LocalizedString.l(
                language,
                en: "The model returned nothing. Try rephrasing and run it again.",
                zh: "模型没返回内容，换个说法再试一次。",
                ja: "モデルから内容が返りませんでした。言い方を変えてもう一度お試しください。",
                ko: "모델이 내용을 반환하지 않았습니다. 표현을 바꿔 다시 시도하세요."
            )
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
        let language = AppSettings.shared.language
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty, !entries.isEmpty else { return [] }

        let config: AgentRunConfig
        do {
            config = try AgentSettings.shared.makeConfig()
        } catch {
            searchError = LocalizedString.l(
                language,
                en: "Configure a model in Agent settings first.",
                zh: "先在 Agent 设置里配好模型。",
                ja: "先に Agent 設定でモデルを設定してください。",
                ko: "먼저 Agent 설정에서 모델을 구성하세요."
            )
            return []
        }

        let candidates = Array(entries.prefix(Self.searchCandidateLimit))
        let numbered = candidates.enumerated().map { index, entry in
            "\(index + 1). \(Self.snippet(entry.text))"
        }.joined(separator: "\n")

        let system = LocalizedString.l(
            language,
            en: """
            You are searching clipboard history. The user says what they are looking for and gives numbered candidate snippets.
            Output only a JSON array of the numbers that are truly relevant, for example [3,7]; output [] if none are relevant.
            Do not output any explanation or code fences. Prefer fewer hits: skip ones that merely mention the same word for a different purpose.
            """,
            zh: """
            你要在剪贴板历史里找东西。用户会给出想找什么，以及带编号的候选片段。
            只输出一个 JSON 数组，里面是真正相关的编号，例如 [3,7]；都不相关就输出 []。
            不要输出任何解释文字或代码块标记。宁缺勿滥：只是"提到"同一个词但用途不同的，不要选。
            """,
            ja: """
            クリップボード履歴から探します。ユーザーは探したいものと、番号付きの候補断片を提示します。
            本当に関連する番号だけを JSON 配列で出力してください（例: [3,7]）。該当なしなら [] を出力します。
            説明文やコードブロック記号は出力しないこと。同じ語が出てくるだけの無関係なものは選ばないこと。
            """,
            ko: """
            클립보드 기록에서 찾습니다. 사용자가 찾는 내용과 번호가 붙은 후보 조각을 제공합니다.
            실제로 관련 있는 번호만 JSON 배열로 출력하세요(예: [3,7]). 해당 없으면 []를 출력하세요.
            설명문이나 코드 블록 표시는 출력하지 마세요. 같은 단어가 나올 뿐 용도가 다른 항목은 고르지 마세요.
            """
        )
        let user = LocalizedString.l(
            language,
            en: "Looking for: \(trimmedQuery)\n\nCandidates:\n\(numbered)",
            zh: "要找的是：\(trimmedQuery)\n\n候选片段：\n\(numbered)",
            ja: "探しているもの：\(trimmedQuery)\n\n候補：\n\(numbered)",
            ko: "찾는 내용: \(trimmedQuery)\n\n후보:\n\(numbered)"
        )

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
        let groupName = LocalizedString.l(
            AppSettings.shared.language,
            en: "Clipboard tidied",
            zh: "剪贴板整理",
            ja: "クリップボード整理",
            ko: "클립보드 정리"
        )
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
