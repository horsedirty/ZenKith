import SwiftUI
import Textual

/// AI 消息气泡的 Markdown/LaTeX 渲染视图
/// 使用 Textual 的 StructuredText 原生渲染，支持数学公式，无 WebView 滚动问题
struct MessageMarkdownView: View {
    let markdown: String
    let baseURL: URL
    let isStreaming: Bool

    var body: some View {
        StructuredText(markdown: markdown)
            .textual.textSelection(.enabled)
            .textual.structuredTextStyle(.default)
            .font(.callout)
    }
}
