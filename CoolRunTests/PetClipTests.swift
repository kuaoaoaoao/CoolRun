import XCTest
@testable import CoolRun

/// 桌宠片段映射：心情 → 底片、动作 → 片段、一次性片段播完怎么收尾。
///
/// 这些是「看着对不对」背后的硬规则，改动作库或者换素材时最容易悄悄错位。
@MainActor
final class PetClipTests: XCTestCase {
    override func tearDown() {
        PetModel.shared.debugResetVideoAvailability()
        super.tearDown()
    }

    func testEveryMoodHasLoopingBaseClip() {
        let moods: [PetMood] = [
            .idle, .thinking, .working("system_snapshot"), .waiting, .success, .error, .sleeping,
        ]
        for mood in moods {
            let clip = PetModel.baseClip(for: mood)
            XCTAssertTrue(clip.loops, "\(mood) 的底片应该是循环片段，否则播完就定格了")
        }
    }

    func testPersistentStatesLoopAndOneShotsDoNot() {
        XCTAssertTrue(PetClip.idle.loops)
        XCTAssertTrue(PetClip.sleepLoop.loops)
        XCTAssertTrue(PetClip.drag.loops)
        XCTAssertTrue(PetClip.workBusy.loops)

        XCTAssertFalse(PetClip.eatRice.loops)
        XCTAssertFalse(PetClip.clickHappy.loops)
        XCTAssertFalse(PetClip.wake.loops)
        XCTAssertFalse(PetClip.whale.loops)
    }

    func testClipResourceNameMatchesRawValue() {
        for clip in PetClip.allCases {
            XCTAssertEqual(clip.resourceName, clip.rawValue)
        }
    }

    func testClickResponsesAreAllOneShot() {
        XCTAssertEqual(PetClip.clickResponses.count, 5)
        for clip in PetClip.clickResponses {
            XCTAssertFalse(clip.loops)
        }
    }

    func testActionMapsToClipOnlyWhenItHasFootage() {
        XCTAssertEqual(PetAction.hop(9).clip, .clickHappy)
        XCTAssertEqual(PetAction.stretch.clip, .stretch)
        XCTAssertEqual(PetAction.yawn.clip, .yawn)
        XCTAssertEqual(PetAction.celebrate.clip, .workCelebrate)
        XCTAssertEqual(PetAction.faint.clip, .workTired)
        XCTAssertNil(PetAction.none.clip)
    }

    func testSleepingBaseClipIsSleepLoop() {
        XCTAssertEqual(PetModel.baseClip(for: .sleeping), .sleepLoop)
        XCTAssertEqual(PetModel.baseClip(for: .idle), .idle)
    }

    func testClipDidFinishFallsBackToMoodClip() {
        let model = PetModel.shared
        model.nap()
        model.debugPlayClip(.eatRice, seconds: 5)
        XCTAssertEqual(model.clip, .eatRice)

        model.clipDidFinish()
        XCTAssertEqual(model.clip, .sleepLoop, "吃饭播完应该回到睡觉的底片")
        model.touch()
    }

    func testMarkVideoUnavailableStopsSwitchingClips() {
        let model = PetModel.shared
        model.nap()
        model.markVideoUnavailable()

        model.debugPlayClip(.eatRice, seconds: 5)
        XCTAssertNotEqual(model.clip, .eatRice, "视频不可用时不该再换片段")
    }
}
