import XCTest
@testable import CoolRun

/// 桌宠的抛掷物理。这一层是纯值类型，不需要窗口就能测。
final class PetPhysicsTests: XCTestCase {
    private let size = CGSize(width: 168, height: 190)
    private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let frame: TimeInterval = 1.0 / 60.0

    func testFallsUnderGravity() {
        var body = PetBody(origin: CGPoint(x: 100, y: 500))
        let result = PetPhysics.step(&body, size: size, bounds: bounds, dt: frame)

        XCTAssertLessThan(body.origin.y, 500, "重力应该把她往下拉")
        XCTAssertLessThan(body.velocity.dy, 0, "y 轴向上，下落时速度分量为负")
        XCTAssertTrue(result.isMoving)
        XCTAssertEqual(result.impact, 0, "还在空中，不该有撞击")
    }

    func testBouncesOffFloor() {
        var body = PetBody(origin: CGPoint(x: 100, y: 0), velocity: CGVector(dx: 0, dy: -600))
        let result = PetPhysics.step(&body, size: size, bounds: bounds, dt: frame)

        XCTAssertGreaterThanOrEqual(body.origin.y, bounds.minY, "不能穿到地面以下")
        XCTAssertGreaterThan(body.velocity.dy, 400, "600 的下落速度按 0.78 恢复应该弹回 480 上下")
        XCTAssertGreaterThanOrEqual(result.impact, 600)
    }

    func testFloorFrictionStopsSlide() {
        var body = PetBody(origin: CGPoint(x: 100, y: 0), velocity: CGVector(dx: 800, dy: 0))
        var moving = true
        for _ in 0..<600 where moving {
            moving = PetPhysics.step(&body, size: size, bounds: bounds, dt: frame).isMoving
        }

        XCTAssertFalse(moving, "摩擦应该让她停在原地")
        XCTAssertEqual(body.velocity.dx, 0)
        XCTAssertEqual(body.velocity.dy, 0)
    }

    func testStaysInsideBounds() {
        var body = PetBody(origin: CGPoint(x: 100, y: 100), velocity: CGVector(dx: 5000, dy: 2200))
        for _ in 0..<240 {
            PetPhysics.step(&body, size: size, bounds: bounds, dt: frame)
            XCTAssertGreaterThanOrEqual(body.origin.x, bounds.minX)
            XCTAssertLessThanOrEqual(body.origin.x + size.width, bounds.maxX)
            XCTAssertGreaterThanOrEqual(body.origin.y, bounds.minY)
            XCTAssertLessThanOrEqual(body.origin.y + size.height, bounds.maxY)
        }
    }

    func testClampPullsPointBackInside() {
        let clamped = PetPhysics.clamp(CGPoint(x: -50, y: 900), size: size, bounds: bounds)
        XCTAssertEqual(clamped.x, bounds.minX)
        XCTAssertEqual(clamped.y, bounds.maxY - size.height)
    }

    func testZeroDeltaDoesNothing() {
        var body = PetBody(origin: CGPoint(x: 300, y: 300), velocity: CGVector(dx: 100, dy: 100))
        let result = PetPhysics.step(&body, size: size, bounds: bounds, dt: 0)

        XCTAssertEqual(body.origin, CGPoint(x: 300, y: 300))
        XCTAssertTrue(result.isMoving)
        XCTAssertEqual(result.impact, 0)
    }
}
