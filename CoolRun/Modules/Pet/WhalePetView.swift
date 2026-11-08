import SwiftUI

// MARK: - 桌宠

/// 桌面上的鲸鱼娘。
///
/// 用的是角色立绘（`Assets.xcassets/PetWhale`），动效全部由 SwiftUI 合成：
/// 呼吸、摇摆、影子、气泡。这样换图就能换角色，不需要重画代码。
struct WhalePetView: View {
    /// 正在拖拽时不做浮动动画，避免和鼠标抢位置。
    var isDragging: Bool = false

    @State private var bob = false
    @State private var sway = false
    @State private var hover = false
    @State private var bubble: String?
    @State private var bubbleTask: Task<Void, Never>?

    private var coordinator: AgentCoordinator { AgentCoordinator.shared }

    var body: some View {
        ZStack(alignment: .top) {
            // 地面影子：跟着呼吸一起缩，才有「贴在地上」的感觉
            Ellipse()
                .fill(.black.opacity(0.22))
                .frame(width: 104, height: 14)
                .blur(radius: 5)
                .scaleEffect(x: bob ? 0.88 : 1.0, y: 1.0)
                .offset(y: 166)
                .animation(
                    isDragging ? nil : .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                    value: bob
                )

            character

            if let bubble {
                speechBubble(bubble)
                    .offset(y: -2)
                    .transition(.scale(scale: 0.8, anchor: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .frame(width: 168, height: 190)
        .contentShape(Rectangle())
        .onAppear {
            bob = true
            sway = true
        }
        .onChange(of: coordinator.isRunning) { _, running in
            show(running ? "本鱼在想…" : "想好啦！", seconds: running ? 600 : 2.6)
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.18)) { hover = hovering }
        }
    }

    // MARK: 角色

    private var character: some View {
        Image("PetWhale")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(height: 152)
            // 呼吸：横向几乎不动、纵向轻微拉伸，比整体缩放自然
            .scaleEffect(
                x: hover ? 1.04 : 1.0,
                y: bob ? 1.012 : 0.994,
                anchor: .bottom
            )
            // 轻微摇摆，锚点在脚底，看起来像重心在晃
            .rotationEffect(.degrees(sway ? 1.5 : -1.5), anchor: .bottom)
            .offset(y: (bob ? -1.5 : 1.5) + 4)
            .shadow(color: Color(red: 0.1, green: 0.25, blue: 0.5).opacity(0.28), radius: 8, y: 4)
            .animation(
                isDragging ? nil : .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                value: bob
            )
            .animation(
                isDragging ? nil : .easeInOut(duration: 3.1).repeatForever(autoreverses: true),
                value: sway
            )
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
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.white.opacity(0.5), lineWidth: 0.6)
                    )
            )
            .foregroundStyle(.primary)
            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }

    private func show(_ text: String, seconds: Double) {
        bubbleTask?.cancel()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) {
            bubble = text
        }
        bubbleTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) { bubble = nil }
            }
        }
    }
}
