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

/// 拖拽的位移算术：窗口位移必须严格等于鼠标位移。
///
/// 老实现用的是 SwiftUI 的 `translation`，那是视图坐标系里的量——视图被
/// `scaleEffect` 缩过就跟着缩，窗口一动坐标系又跟着跑，于是「飘」。
@MainActor
final class PetDragMathTests: XCTestCase {
    func testDraggedOriginFollowsMouseExactly() {
        let anchor = NSPoint(x: 500, y: 300)
        let start = NSPoint(x: 640, y: 400)
        let moved = PetController.draggedOrigin(
            anchor: anchor, start: start, current: NSPoint(x: 780, y: 340)
        )
        XCTAssertEqual(moved.x, 640, accuracy: 0.001)
        XCTAssertEqual(moved.y, 240, accuracy: 0.001)
    }

    func testDraggedOriginIsIdempotentWhenMouseDoesNotMove() {
        let anchor = NSPoint(x: -120.5, y: 42)
        let start = NSPoint(x: 10, y: 10)
        let moved = PetController.draggedOrigin(anchor: anchor, start: start, current: start)
        XCTAssertEqual(moved, anchor)
    }

    func testDraggedOriginDoesNotAccumulateAcrossSteps() {
        let anchor = NSPoint(x: 0, y: 0)
        let start = NSPoint(x: 100, y: 100)
        // 分很多小步走完 240 点，终点必须还是 240 点（不能像积分那样越走越远）。
        var current = start
        var last = anchor
        for _ in 0..<40 {
            current.x += 6
            last = PetController.draggedOrigin(anchor: anchor, start: start, current: current)
        }
        XCTAssertEqual(last.x, 240, accuracy: 0.001)
        XCTAssertEqual(last.y, 0, accuracy: 0.001)
    }
}

/// 新增的那批片段：吃的、时节、自己玩。
@MainActor
final class PetClipCatalogTests: XCTestCase {
    func testEveryClipHasACaseForItsFile() {
        // 枚举和 scripts/pet-clips.sh 的表是两处手写的，最容易只改一边。
        let expected = Set(PetClip.allCases.map(\.resourceName))
        XCTAssertEqual(expected.count, PetClip.allCases.count, "片段名不能重复")
        XCTAssertGreaterThanOrEqual(expected.count, 50)
    }

    func testEatAndPlayClipsAreAllOneShot() {
        for clip in PetClip.eatClips + PetClip.playClips {
            XCTAssertFalse(clip.loops, "\(clip) 是一次性动作，不该循环")
        }
    }

    func testSeasonalPicksSomethingForEveryMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        for month in 1...12 {
            let date = calendar.date(from: DateComponents(year: 2026, month: month, day: 15))!
            XCTAssertNotNil(PetClip.seasonal(for: date), "\(month) 月没有应景片段")
        }
    }

    func testSeasonalHighlights() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        func clip(_ month: Int, _ day: Int) -> PetClip? {
            PetClip.seasonal(for: calendar.date(from: DateComponents(year: 2026, month: month, day: day))!)
        }
        XCTAssertEqual(clip(10, 1), .mooncake)
        XCTAssertEqual(clip(12, 20), .christmasTree)
        XCTAssertEqual(clip(10, 28), .pumpkin)
        XCTAssertEqual(clip(6, 10), .eatZongzi)
    }
}
