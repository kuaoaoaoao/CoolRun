import SwiftUI

/// AI 助手模块的入口。旧的「一问一答」聊天界面已经退役，
/// 这里只保留 Agent 对话（能读数据、调工具、多轮执行）。
struct AIAssistantView: View {
    var body: some View {
        AgentChatView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .appCardSurface(cornerRadius: 12)
    }
}
