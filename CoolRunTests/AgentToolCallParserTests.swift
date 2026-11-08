import XCTest
@testable import CoolRun

/// 覆盖「模型不走 tool_calls 字段、把调用写进正文」的兜底解析。
final class AgentToolCallParserTests: XCTestCase {

    private let known: Set<String> = ["gold_technical", "gold_strategy", "system_snapshot"]

    func testParsesTaggedCall() {
        let calls = AgentToolCallParser.parse(
            "<tool_call>{\"name\":\"gold_technical\",\"arguments\":{}}</tool_call>",
            known: known
        )
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.name, "gold_technical")
        XCTAssertEqual(calls.first?.argumentsText, "{}")
    }

    func testParsesFencedCodeBlock() {
        let text = """
        我查一下。
        ```json
        {"name":"gold_strategy","arguments":{}}
        ```
        """
        let calls = AgentToolCallParser.parse(text, known: known)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.name, "gold_strategy")
    }

    func testParsesMultipleCalls() {
        let text = """
        <tool_call>{"name":"gold_technical","arguments":{"days":60}}</tool_call>
        <tool_call>{"name":"gold_strategy","arguments":{}}</tool_call>
        """
        let calls = AgentToolCallParser.parse(text, known: known)
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls.map(\.name), ["gold_technical", "gold_strategy"])
        XCTAssertEqual(calls.first?.argumentsText, "{\"days\":60}")
    }

    func testIgnoresUnknownTool() {
        let calls = AgentToolCallParser.parse("{\"name\":\"rm_rf\",\"arguments\":{}}", known: known)
        XCTAssertTrue(calls.isEmpty)
    }

    func testIgnoresPlainProse() {
        let calls = AgentToolCallParser.parse("现在金价 871.44，建议观望。", known: known)
        XCTAssertTrue(calls.isEmpty)
    }

    func testBracesInsideStringDoNotBreakPairing() {
        let calls = AgentToolCallParser.parse(
            "{\"name\":\"system_snapshot\",\"arguments\":{\"note\":\"a{b}c\"}}",
            known: known
        )
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.name, "system_snapshot")
    }

    func testEmptyArgumentsDefaultToObject() {
        let calls = AgentToolCallParser.parse("{\"name\":\"gold_strategy\"}", known: known)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.argumentsText, "{}")
    }
}
