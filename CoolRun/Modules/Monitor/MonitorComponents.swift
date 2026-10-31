import SwiftUI
import Combine
import AppKit
import Observation

// MARK: - 基础组件

struct MetricRow: View {
    let label: String
    let value: String
    @State private var isCopied = false
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                .font(.system(size: 10, weight: .medium))
            Spacer(minLength: 4)
            Text(value)
                .foregroundStyle(isCopied ? AppTheme.healthy : AppTheme.textPrimary(colorScheme).opacity(0.85))
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { copyToClipboard() }
        .help(LocalizedString.label("copy_hint", lang: settings.language))
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\(label): \(value)", forType: .string)
        withAnimation(.easeInOut(duration: 0.3)) { isCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.3)) { isCopied = false }
        }
    }
}

struct Separator: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(AppTheme.separator(colorScheme))
            .frame(height: 0.5)
            .padding(.horizontal, 12)
    }
}

// MARK: - 趋势图表

struct SparklineChart: View {
    let values: [Double]
    var color: Color = .blue
    var showGradient: Bool = true
    var valueRange: ClosedRange<Double>? = nil

    var body: some View {
        Canvas { context, size in
            guard values.count >= 2 else { return }

            let maxValue = valueRange?.upperBound ?? values.max() ?? 1.0
            let minValue = valueRange?.lowerBound ?? values.min() ?? 0.0
            let range = maxValue - minValue
            let normalizedMax = range > 0 ? range : 1.0

            let stepX = size.width / CGFloat(values.count - 1)
            let padding: CGFloat = 1
            let drawHeight = size.height - padding * 2

            var path = Path()
            for (index, value) in values.enumerated() {
                let x = CGFloat(index) * stepX
                let normalized = min(max((value - minValue) / normalizedMax, 0), 1)
                let y = size.height - padding - CGFloat(normalized) * drawHeight
                if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }

            if showGradient {
                var fillPath = path
                fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
                fillPath.addLine(to: CGPoint(x: 0, y: size.height))
                fillPath.closeSubpath()
                let gradient = Gradient(colors: [color.opacity(0.25), color.opacity(0.02)])
                context.fill(fillPath, with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height)))
            }

            context.stroke(path, with: .color(color), lineWidth: 1.2)

            if let lastValue = values.last {
                let lastX = size.width
                let normalized = min(max((lastValue - minValue) / normalizedMax, 0), 1)
                let lastY = size.height - padding - CGFloat(normalized) * drawHeight
                let pointRect = CGRect(x: lastX - 2, y: lastY - 2, width: 4, height: 4)
                context.fill(Path(ellipseIn: pointRect), with: .color(color))
            }
        }
    }
}

struct DualSparklineChart: View {
    let values1: [Double]
    let values2: [Double]
    var color1: Color = .blue
    var color2: Color = .green

    var body: some View {
        Canvas { context, size in
            let allValues = values1 + values2
            guard allValues.count >= 2 else { return }

            let maxValue = allValues.max() ?? 1.0
            let minValue = allValues.min() ?? 0.0
            let range = maxValue - minValue
            let normalizedMax = range > 0 ? range : 1.0
            let padding: CGFloat = 1
            let drawHeight = size.height - padding * 2

            if values1.count >= 2 {
                drawLine(context: context, size: size, values: values1, color: color1, minValue: minValue, normalizedMax: normalizedMax, padding: padding, drawHeight: drawHeight)
            }
            if values2.count >= 2 {
                drawLine(context: context, size: size, values: values2, color: color2, minValue: minValue, normalizedMax: normalizedMax, padding: padding, drawHeight: drawHeight)
            }
        }
    }

    private func drawLine(context: GraphicsContext, size: CGSize, values: [Double], color: Color, minValue: Double, normalizedMax: Double, padding: CGFloat, drawHeight: CGFloat) {
        let stepX = size.width / CGFloat(values.count - 1)
        var path = Path()
        for (index, value) in values.enumerated() {
            let x = CGFloat(index) * stepX
            let normalized = (value - minValue) / normalizedMax
            let y = size.height - padding - CGFloat(normalized) * drawHeight
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        context.stroke(path, with: .color(color), lineWidth: 1.2)
    }
}

// MARK: - 进度条组件

struct MiniBar: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let width = proxy.size.width
                let height = proxy.size.height
                let columns = 16
                for index in 0..<columns {
                    let phase = Double(index) / Double(columns)
                    let dynamic = 0.3 + abs(sin((phase + value) * .pi * 2.2)) * 0.7
                    let barHeight = max(1.5, height * dynamic * max(0.2, value))
                    let x = width * Double(index) / Double(columns)
                    path.addRect(CGRect(x: x, y: height - barHeight, width: max(1.5, width / Double(columns) - 1.5), height: barHeight))
                }
            }
            .fill(tint.opacity(0.7))
        }
    }
}

struct ProgressPill: View {
    let value: Double
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppTheme.progressBg(colorScheme))
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(2, proxy.size.width * min(max(value, 0), 1)))
            }
        }
    }
}

// MARK: - 监控卡片表面

struct MonitorCardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .appCardSurface(cornerRadius: 11)
    }
}

extension View {
    func monitorCardSurface() -> some View {
        modifier(MonitorCardSurface())
    }
}

// MARK: - 毛玻璃效果

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}


// MARK: - 格式化扩展

extension Double {
    var percentText: String {
        (self * 100).formatted(.number.precision(.fractionLength(1))) + "%"
    }
}

extension UInt64 {
    var memoryText: String {
        ByteCountFormatter.memoryFormatter.string(fromByteCount: Int64(self))
    }
    var storageText: String {
        ByteCountFormatter.storageFormatter.string(fromByteCount: Int64(self))
    }
}

extension ByteCountFormatter {
    static let memoryFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useMB]
        f.countStyle = .memory
        f.includesUnit = true
        f.isAdaptive = true
        return f
    }()
    static let storageFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useMB, .useKB]
        f.countStyle = .file
        f.includesUnit = true
        f.isAdaptive = true
        return f
    }()
}

