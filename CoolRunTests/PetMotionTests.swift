import XCTest
@testable import CoolRun

/// 桌宠的动作引擎是纯函数，能直接算，不用起界面。
final class PetMotionTests: XCTestCase {
    func testTrackInterpolatesBetweenKeyframes() {
        let track = PetTrack(.dy, [
            PetKeyframe(0, 0, .linear),
            PetKeyframe(1, -20, .linear),
        ])
        XCTAssertEqual(track.value(at: 0), 0, accuracy: 0.001)
        XCTAssertEqual(track.value(at: 0.5), -10, accuracy: 0.001)
        XCTAssertEqual(track.value(at: 1), -20, accuracy: 0.001)
    }

    func testTrackClampsOutsideRange() {
        let track = PetTrack(.dx, [
            PetKeyframe(0.2, 5, .linear),
            PetKeyframe(0.8, 15, .linear),
        ])
        XCTAssertEqual(track.value(at: -3), 5, accuracy: 0.001, "进度小于 0 应该夹到首帧")
        XCTAssertEqual(track.value(at: 9), 15, accuracy: 0.001, "进度大于 1 应该夹到尾帧")
    }

    func testEasingStartsAtZeroEndsAtOne() {
        for easing in PetEasing.allCases {
            XCTAssertEqual(easing.apply(0), 0, accuracy: 0.0001, "\(easing) 起点应为 0")
            XCTAssertEqual(easing.apply(1), 1, accuracy: 0.0001, "\(easing) 终点应为 1")
            XCTAssertEqual(easing.apply(-5), 0, accuracy: 0.0001)
            XCTAssertEqual(easing.apply(5), 1, accuracy: 0.0001)
        }
    }

    func testHopLeavesAndReturnsToRest() {
        let hop = PetMotionLibrary.hopMotion(height: 18)
        let start = hop.pose(at: 0)
        let top = hop.pose(at: 0.35)
        let end = hop.pose(at: 1)

        XCTAssertEqual(start.dy, 0, accuracy: 0.001)
        XCTAssertEqual(top.dy, -18, accuracy: 0.001, "0.35 处应该跳到最高点")
        XCTAssertEqual(end.dy, 0, accuracy: 0.001, "动作结束要回到原位")
        XCTAssertEqual(end.scaleX, 1, accuracy: 0.001)
        XCTAssertEqual(end.scaleY, 1, accuracy: 0.001)
    }

    func testPoseElapsedClampsBeyondDuration() {
        let spin = PetMotionLibrary.spin
        XCTAssertEqual(spin.pose(elapsed: 0).rotation, 0, accuracy: 0.001)
        XCTAssertEqual(spin.pose(elapsed: spin.duration / 2).rotation, 180, accuracy: 1)
        XCTAssertEqual(spin.pose(elapsed: spin.duration * 5).rotation, 360, accuracy: 0.001, "超时应该停在最后一帧")
    }

    func testWaveReturnsToZero() {
        let frames = PetMotionLibrary.wave(amplitude: 6, cycles: 2.5)
        XCTAssertEqual(frames.first?.value ?? 9, 0, accuracy: 0.0001)
        XCTAssertEqual(frames.last?.value ?? 9, 0, accuracy: 0.0001, "摆动结束必须回到 0，不然会歪着不动")
        XCTAssertGreaterThan(frames.map(\.value).max() ?? 0, 5)
        XCTAssertLessThan(frames.map(\.value).min() ?? 0, -5)
    }

    func testEveryActionDurationMatchesItsMotion() {
        let actions: [PetAction] = [
            .lookLeft, .lookRight, .crouch, .hop(7), .spin, .dash(1), .wiggle,
            .stretch, .shake, .celebrate, .faint, .yawn, .nod, .peek,
        ]
        for action in actions {
            guard let motion = action.motion else {
                XCTFail("\(action) 没有对应的动作")
                continue
            }
            XCTAssertEqual(
                motion.duration, action.duration, accuracy: 0.0001,
                "\(action) 的时长和关键帧表不一致，动作会被提前掐断"
            )
        }
        XCTAssertNil(PetAction.none.motion)
    }

    func testDashGoesBothWays() {
        XCTAssertGreaterThan(PetMotionLibrary.dash(1).pose(at: 0.4).dx, 10)
        XCTAssertLessThan(PetMotionLibrary.dash(-1).pose(at: 0.4).dx, -10)
    }

    // MARK: 情绪符号

    func testEffectBurstCountAndSpread() {
        let now = Date()
        let effects = PetEffectBurst.make(.confetti, count: 5, now: now)
        XCTAssertEqual(effects.count, 5)
        XCTAssertTrue(effects.allSatisfy { $0.isAlive(at: now) }, "刚出生的符号应该是活的")
        XCTAssertGreaterThan(Set(effects.map(\.origin.x)).count, 1, "同一批要散开，不能全叠在一点")
        XCTAssertEqual(Set(effects.map(\.delay)).count, 5, "同一批要错开起飞")
    }

    func testEffectBurstIsCapped() {
        XCTAssertEqual(PetEffectBurst.make(.star, count: 99).count, 12, "一次最多吐 12 个，防止刷爆")
        XCTAssertEqual(PetEffectBurst.make(.star, count: 0).count, 1)
    }

    func testEffectExpires() {
        let born = Date()
        let effect = PetEffectBurst.make(.heart, now: born)[0]
        XCTAssertEqual(effect.progress(at: born), 0, accuracy: 0.001)
        XCTAssertFalse(effect.isAlive(at: born.addingTimeInterval(effect.life + effect.delay + 0.1)))
        XCTAssertEqual(
            effect.progress(at: born.addingTimeInterval(effect.life * 3)), 1,
            accuracy: 0.001,
            "过期后进度要夹在 1，不能继续漂"
        )
    }

    func testEveryEffectKindHasSymbolAndLife() {
        for kind in PetEffectKind.allCases {
            XCTAssertFalse(kind.symbol.isEmpty, "\(kind) 缺少 SF Symbol")
            XCTAssertGreaterThan(kind.life, 0.3)
            XCTAssertGreaterThan(kind.size, 6)
        }
    }
}
