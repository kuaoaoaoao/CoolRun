import XCTest
@testable import CoolRun

/// 桌宠的表现状态。用单例本身测，因为窗口、气泡都挂在它上面。
final class PetModelTests: XCTestCase {
    func testFriendlyToolNameIsHumanReadable() {
        XCTAssertEqual(PetModel.friendlyTool("gold_price", lang: .chinese), "查金价")
        XCTAssertEqual(PetModel.friendlyTool("notes_create", lang: .chinese), "记笔记")
        XCTAssertEqual(PetModel.friendlyTool("plugin_com_coolrun_demo_now", lang: .chinese), "用插件")
        // 不认识的工具原样透出，别把信息吞掉
        XCTAssertEqual(PetModel.friendlyTool("some_new_tool", lang: .chinese), "some_new_tool")
    }

    func testFriendlyToolNameFollowsLanguage() {
        XCTAssertEqual(PetModel.friendlyTool("gold_price", lang: .english), "Gold price")
        XCTAssertEqual(PetModel.friendlyTool("some_new_tool", lang: .japanese), "some_new_tool")
    }

    func testBubbleTextPerMood() {
        XCTAssertNil(PetModel.bubbleText(for: .idle, lang: .chinese))
        XCTAssertEqual(PetModel.bubbleText(for: .sleeping, lang: .chinese), "z Z")
        XCTAssertEqual(PetModel.bubbleText(for: .working("查金价"), lang: .chinese), "在用「查金价」")
        XCTAssertEqual(PetModel.bubbleText(for: .waiting, lang: .chinese), "等你点一下下～")
    }

    func testWaitingWigglesFasterThanIdle() {
        XCTAssertLessThan(PetMood.waiting.swayPeriod, PetMood.idle.swayPeriod)
        XCTAssertLessThan(PetMood.thinking.breathPeriod, PetMood.sleeping.breathPeriod)
        XCTAssertGreaterThan(PetMood.waiting.swayDegrees, PetMood.error.swayDegrees)
    }

    func testPokeShowsBubbleAndHops() {
        let model = PetModel.shared
        model.poke()

        XCTAssertNotNil(model.bubble, "戳一下应该有反应")
        XCTAssertEqual(model.action, .hop(7))
        XCTAssertFalse(model.isSleeping)
    }

    func testNapFallsAsleepAndPokeWakesHer() {
        let model = PetModel.shared
        model.nap()

        XCTAssertTrue(model.isSleeping)
        XCTAssertEqual(model.mood, .sleeping)
        XCTAssertEqual(model.bubble, "z Z")

        model.poke()
        XCTAssertFalse(model.isSleeping)
    }

    func testActionOnlyLivesForItsDuration() {
        let action = PetAction.lookLeft
        XCTAssertEqual(action.progress(at: 0), 0)
        XCTAssertEqual(action.progress(at: action.duration / 2), 0.5, accuracy: 0.001)
        XCTAssertEqual(action.progress(at: action.duration), 1)
        XCTAssertEqual(action.progress(at: 99), 1, "超出时长应该夹住，不能一直歪着")
    }
}
