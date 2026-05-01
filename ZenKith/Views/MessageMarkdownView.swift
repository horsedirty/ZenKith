import SwiftUI
import WebKit

/// 轻量级 Markdown 渲染视图，用于 AI 消息展示（不含 MathJax CDN）
struct MessageMarkdownView: View {
    let markdown: String
    let baseURL: URL

    var body: some View {
        MessageMarkdownWebViewRepresentable(markdown: markdown, baseURL: baseURL)
    }
}

// MARK: - WebView Representable

private struct MessageMarkdownWebViewRepresentable: NSViewRepresentable {
    let markdown: String
    let baseURL: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 300, height: 100), configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator

        let html = buildMessageHTML(markdown)
        context.coordinator.lastMarkdown = markdown
        webView.loadHTMLString(html, baseURL: baseURL)

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastMarkdown != markdown else { return }
        context.coordinator.lastMarkdown = markdown

        let html = buildMessageHTML(markdown)
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    // MARK: - HTML

    private func buildMessageHTML(_ md: String) -> String {
        let bodyHTML = MarkdownParser.toBodyHTML(md)
        let isDark = NSApp.effectiveAppearance.name == .darkAqua
            || NSApp.effectiveAppearance.name == .vibrantDark

        let bg = isDark ? "#1c1c1e" : "#ffffff"
        let fg = isDark ? "#e5e5ea" : "#1d1d1f"
        let codeBg = isDark ? "#2c2c2e" : "#f5f5f7"
        let border = isDark ? "#38383a" : "#e5e5ea"
        let link = isDark ? "#0a84ff" : "#007aff"

        return """
        <!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>
        *{margin:0;padding:0;box-sizing:border-box}
        body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;font-size:13px;line-height:1.65;color:\(fg);padding:8px 10px;background:\(bg);word-wrap:break-word}
        h1,h2,h3,h4{margin:0.6em 0 0.3em;font-weight:600}
        h1{font-size:1.3em}h2{font-size:1.15em}h3{font-size:1.05em}
        p{margin:0.4em 0}
        a{color:\(link)}
        code{font-family:"SF Mono",Menlo,monospace;background:\(codeBg);padding:1px 4px;border-radius:3px;font-size:0.92em}
        pre{background:\(codeBg);border:1px solid \(border);border-radius:6px;padding:10px;overflow-x:auto;margin:0.5em 0}
        pre code{background:none;padding:0;font-size:0.88em;line-height:1.5}
        blockquote{border-left:3px solid \(link);margin:0.5em 0;padding:0.3em 0.8em;opacity:0.9}
        ul,ol{padding-left:1.5em;margin:0.4em 0}
        li{margin:0.2em 0}
        table{border-collapse:collapse;width:100%;margin:0.5em 0;font-size:0.9em}
        th,td{border:1px solid \(border);padding:4px 8px;text-align:left}
        th{background:\(codeBg);font-weight:600}
        hr{border:none;border-top:1px solid \(border);margin:0.8em 0}
        strong{font-weight:600}
        img{max-width:100%;border-radius:4px}
        </style></head>
        <body>\(bodyHTML)</body></html>
        """
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastMarkdown: String = ""
    }
}
