import SwiftUI

// MARK: - 桌宠

/// 桌面上的鲸鱼娘。程序化绘制，不依赖任何图片素材，所以零体积、
/// 任意分辨率都清晰，换配色也只需要改几个常量。
struct WhalePetView: View {
    /// 正在拖拽时不做浮动动画，避免和鼠标抢位置。
    var isDragging: Bool = false

    @State private var bob = false
    @State private var tailSwing = false
    @State private var blink = false
    @State private var bubble: String?
    @State private var bubbleTask: Task<Void, Never>?

    private var coordinator: AgentCoordinator { AgentCoordinator.shared }

    var body: some View {
        ZStack(alignment: .top) {
            if let bubble {
                speechBubble(bubble)
                    .offset(y: -6)
                    .transition(.scale(scale: 0.8, anchor: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }

            whale
                .offset(y: isDragging ? 0 : (bob ? -5 : 2))
                .animation(
                    isDragging ? nil : .easeInOut(duration: 2.2).repeatForever(autoreverses: true),
                    value: bob
                )
                .padding(.top, 34)
        }
        .frame(width: 168, height: 168)
        .contentShape(Rectangle())
        .onAppear {
            bob = true
            startBlinking()
            if coordinator.isRunning {
                show("本鱼在想…", seconds: 3)
            }
        }
        .onChange(of: coordinator.isRunning) { _, running in
            show(running ? "本鱼在想…" : "想好了！", seconds: running ? 600 : 3)
        }
    }

    // MARK: 鲸鱼本体

    private var whale: some View {
        ZStack {
            // 尾巴：两片椭圆张开成鲸尾，比路径画的更稳、也更像鲸鱼
            ZStack {
                Ellipse()
                    .frame(width: 52, height: 24)
                    .rotationEffect(.degrees(-30))
                    .offset(x: 24, y: -13)
                Ellipse()
                    .frame(width: 52, height: 24)
                    .rotationEffect(.degrees(30))
                    .offset(x: 24, y: 13)
            }
            .foregroundStyle(LinearGradient(
                colors: [Color(red: 0.34, green: 0.66, blue: 1.0), Color(red: 0.14, green: 0.38, blue: 0.78)],
                startPoint: .top,
                endPoint: .bottom
            ))
            .frame(width: 84, height: 78)
            .rotationEffect(.degrees(tailSwing ? 10 : -8), anchor: .leading)
            .offset(x: 54, y: 14)
            .animation(
                isDragging ? nil : .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                value: tailSwing
            )

            // 身体
            Ellipse()
                .fill(LinearGradient(
                    colors: [
                        Color(red: 0.46, green: 0.75, blue: 1.0),
                        Color(red: 0.22, green: 0.50, blue: 0.94),
                        Color(red: 0.13, green: 0.34, blue: 0.74),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 122, height: 94)
                .overlay {
                    Ellipse()
                        .fill(LinearGradient(
                            colors: [.white.opacity(0.6), .white.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .center
                        ))
                        .frame(width: 72, height: 32)
                        .offset(x: -14, y: -26)
                }
                .overlay {
                    Ellipse()
                        .fill(.white.opacity(0.16))
                        .frame(width: 76, height: 36)
                        .offset(y: 25)
                }
                .overlay(alignment: .bottomLeading) {
                    // 胸鳍：贴身体左下边缘，别盖住脸
                    Ellipse()
                        .fill(Color(red: 0.19, green: 0.45, blue: 0.87))
                        .frame(width: 30, height: 16)
                        .rotationEffect(.degrees(-28))
                        .offset(x: -4, y: -6)
                }
                .overlay {
                    face
                }
                .shadow(color: Color(red: 0.1, green: 0.3, blue: 0.6).opacity(0.35), radius: 10, y: 6)

            if !isDragging {
                spout
                    .offset(y: -74)
                    .opacity(bob ? 0.95 : 0.3)
                    .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: bob)
            }
        }
        .frame(width: 172, height: 160)
    }

    private var spout: some View {
        ZStack {
            Circle()
                .frame(width: 5, height: 5)
                .offset(x: -7, y: 2)
            Circle()
                .frame(width: 4, height: 4)
                .offset(x: 6, y: -1)
            Circle()
                .frame(width: 3.5, height: 3.5)
                .offset(x: 0, y: -7)
        }
        .foregroundStyle(.white.opacity(0.9))
    }

    private var face: some View {
        HStack(spacing: 32) {
            eye
            eye
        }
        .offset(x: -4, y: -4)
        .overlay(alignment: .center) {
            // 嘴：一个小弧，放在两眼之间偏下
            SmileShape()
                .stroke(Color(red: 0.08, green: 0.18, blue: 0.4).opacity(0.65), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .frame(width: 16, height: 7)
                .offset(x: -4, y: 19)
        }
        .overlay(alignment: .leading) {
            // 腮红
            Ellipse()
                .fill(Color(red: 1.0, green: 0.52, blue: 0.6).opacity(0.5))
                .frame(width: 15, height: 9)
                .offset(x: -32, y: 12)
        }
    }

    private var eye: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 20, height: 20)

            if blink {
                Capsule()
                    .fill(Color(red: 0.1, green: 0.2, blue: 0.45))
                    .frame(width: 14, height: 2.5)
            } else {
                Circle()
                    .fill(Color(red: 0.08, green: 0.15, blue: 0.35))
                    .frame(width: 11, height: 11)
                    .offset(y: 1)
                Circle()
                    .fill(.white)
                    .frame(width: 4, height: 4)
                    .offset(x: -3, y: -3)
            }
        }
        .animation(.easeInOut(duration: 0.12), value: blink)
    }

    // MARK: 气泡

    private func speechBubble(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
            )
            .overlay(alignment: .bottom) {
                Triangle()
                    .fill(.white)
                    .frame(width: 10, height: 6)
                    .offset(y: 5)
            }
            .frame(maxWidth: 130)
    }

    // MARK: 行为

    func show(_ text: String, seconds: Double) {
        bubbleTask?.cancel()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
            bubble = text
        }
        bubbleTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                bubble = nil
            }
        }
    }

    private func startBlinking() {
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 3.5...6.5)))
                blink = true
                try? await Task.sleep(for: .milliseconds(120))
                blink = false
            }
        }
    }
}

// MARK: - 形状

struct WhaleTailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY

        path.move(to: CGPoint(x: rect.minX, y: midY))
        // 上叶片
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX - 4, y: midY - rect.height * 0.05)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.midX + 2, y: midY),
            control: CGPoint(x: rect.midX + 6, y: rect.height * 0.28)
        )
        // 下叶片
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.midX + 6, y: rect.height * 0.72)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: midY),
            control: CGPoint(x: rect.midX - 4, y: midY + rect.height * 0.05)
        )
        path.closeSubpath()
        return path
    }
}

struct SmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY * 1.6)
        )
        return path
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
