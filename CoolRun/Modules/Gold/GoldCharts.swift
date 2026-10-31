import SwiftUI
import AppKit

struct PriceLineChart: View {
    let records: [GoldPriceRecord]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            guard records.count >= 2 else { return }

            let prices = records.map(\.price)
            guard let minPrice = prices.min(), let maxPrice = prices.max() else { return }
            let range = max(maxPrice - minPrice, 0.01)

            // 水平网格参考线
            let gridColor = Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06)
            for fraction in [0.25, 0.5, 0.75] {
                var gridPath = Path()
                let y = size.height * CGFloat(fraction)
                gridPath.move(to: CGPoint(x: 0, y: y))
                gridPath.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(gridPath, with: .color(gridColor), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
            }

            var path = Path()
            var lastPoint = CGPoint.zero
            for (index, price) in prices.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(max(prices.count - 1, 1))
                let y = size.height - (CGFloat((price - minPrice) / range) * size.height)
                lastPoint = CGPoint(x: x, y: y)
                if index == 0 {
                    path.move(to: lastPoint)
                } else {
                    path.addLine(to: lastPoint)
                }
            }

            // 中国市场惯例：涨红跌绿，与 AppTheme.marketUp/marketDown 保持一致。
            let lineColor = NSColor(
                (prices.last ?? 0) >= (prices.first ?? 0) ? AppTheme.marketUp : AppTheme.marketDown
            )
            let tint = Color(nsColor: lineColor)

            // 渐变填充：线色向下淡出
            var fillPath = path
            fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
            fillPath.addLine(to: CGPoint(x: 0, y: size.height))
            fillPath.closeSubpath()
            context.fill(
                fillPath,
                with: .linearGradient(
                    Gradient(colors: [
                        tint.opacity(colorScheme == .dark ? 0.28 : 0.20),
                        tint.opacity(0.02)
                    ]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )

            context.stroke(path, with: .color(tint), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))

            // 最新价端点
            let dotRadius: CGFloat = 2.4
            context.fill(
                Path(ellipseIn: CGRect(
                    x: lastPoint.x - dotRadius,
                    y: lastPoint.y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                )),
                with: .color(tint)
            )
        }
    }
}

// MARK: - 持仓卡片

