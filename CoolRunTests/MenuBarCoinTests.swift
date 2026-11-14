import XCTest
@testable import CoolRun

/// 菜单栏金币图标的几何计算。
///
/// 这些数字直接喂给 `NSImage` 绘制，算错的后果是图标画出菜单栏边界、
/// 或者闪一下变全透明——而菜单栏上出了问题，界面上没有任何报错可看。
@MainActor
final class MenuBarCoinTests: XCTestCase {

    /// 菜单栏可用高度约 24 点，图标不能画出去。
    private let maxExtent: CGFloat = 24

    func testEveryMotionStaysInsideMenuBar() {
        for motion in MenuBarCoinMotion.allCases {
            for step in 0...24 {
                let phase = CGFloat(step) / 24 * 2 * .pi
                let state = CoinIconRenderer.motionState(phase: phase, motion: motion)
                XCTAssertGreaterThan(state.width, 0, "\(motion) 宽度不该为 0 或负数（phase \(phase)）")
                XCTAssertGreaterThan(state.height, 0, "\(motion) 高度不该为 0 或负数（phase \(phase)）")
                XCTAssertLessThanOrEqual(
                    state.centerY + state.height / 2, maxExtent,
                    "\(motion) 画到菜单栏外了（phase \(phase)）"
                )
                XCTAssertGreaterThanOrEqual(
                    state.centerY - state.height / 2, 0,
                    "\(motion) 画到菜单栏上边界外了（phase \(phase)）"
                )
                XCTAssertGreaterThanOrEqual(state.centerX - state.width / 2, 0, "\(motion) 越出左边")
            }
        }
    }

    func testSparkleAndShadowStayNormalized() {
        for motion in MenuBarCoinMotion.allCases {
            for step in 0...48 {
                let phase = CGFloat(step) / 48 * 2 * .pi
                let state = CoinIconRenderer.motionState(phase: phase, motion: motion)
                XCTAssertTrue(
                    (0...1).contains(state.sparkleAmount),
                    "\(motion) 闪光是透明度，必须在 0…1：\(state.sparkleAmount)"
                )
                XCTAssertTrue(
                    (0...1).contains(state.shadowAlpha),
                    "\(motion) 阴影透明度必须在 0…1：\(state.shadowAlpha)"
                )
                XCTAssertGreaterThanOrEqual(state.shadowWidth, 0)
            }
        }
    }

    func testClassicFlipCyclesThroughBothFaces() {
        // 宽度由 |cos| 驱动：相位 0 是正面（最宽 17），π/2 是侧面（最窄 2.8）。
        // 反了的话看起来是硬币横着撕，不是翻面。
        let face = CoinIconRenderer.motionState(phase: 0, motion: .classicFlip)
        let edge = CoinIconRenderer.motionState(phase: .pi / 2, motion: .classicFlip)
        XCTAssertGreaterThan(face.width, edge.width, "正面应该比侧面宽")
        XCTAssertEqual(face.width, 17, accuracy: 0.001, "相位 0 应该是正面最宽")
        XCTAssertEqual(edge.width, 2.8, accuracy: 0.001, "相位 π/2 应该是侧面对齐")
    }

    func testCoinTossAlternatesSymbolRotation() {
        let start = CoinIconRenderer.motionState(phase: 0, motion: .coinToss)
        let half = CoinIconRenderer.motionState(phase: .pi, motion: .coinToss)
        XCTAssertNotEqual(start.symbolRotation, half.symbolRotation, "抛硬币应该让图案转起来")
    }

    func testPaletteIsOpaqueAndDistinct() {
        var symbols: [String] = []
        for appearance in MenuBarCoinAppearance.allCases {
            let palette = CoinIconRenderer.palette(appearance: appearance)
            for (label, color) in [
                ("face", palette.face), ("rim", palette.rim), ("detail", palette.detail),
            ] {
                XCTAssertEqual(color.alphaComponent, 1, "\(appearance) 的 \(label) 应该不透明")
            }
            if let symbol = palette.symbol {
                symbols.append(symbol)
                XCTAssertEqual(
                    palette.symbolColor.alphaComponent, 1,
                    "\(appearance) 有符号就该有可见的符号颜色"
                )
            } else {
                // 古钱没有符号，改用方孔——符号色留空是设计的一部分。
                XCTAssertTrue(palette.drawsSquareHole, "\(appearance) 没有符号，应该画方孔")
            }
        }
        XCTAssertEqual(
            Set(symbols).count, symbols.count,
            "不同外观应该用不同符号，否则切外观看不出变化：\(symbols)"
        )
    }
}
