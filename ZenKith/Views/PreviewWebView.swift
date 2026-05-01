import SwiftUI
import WebKit

/// 实时 Markdown 预览 WebView：加载 HTML、MathJax 渲染公式、highlight.js 代码高亮、选中文本同步高亮
struct PreviewWebView: NSViewRepresentable {
    var rawMarkdown: String
    var baseURL: URL
    var fontSize: Double
    var highlightText: String?

    /// 由 representable 内部调用 MarkdownParser 生成 HTML，确保每次渲染都是最新
    private func generateHTML() -> String {
        MarkdownParser.toHTML(rawMarkdown, baseURL: baseURL)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        // 显式设置非零初始尺寸，避免 WKWebView 因零尺寸跳过渲染
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 300), configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = true

        let html = generateHTML()
        context.coordinator.lastLoadedHash = hashContent(rawMarkdown, fontSize: fontSize)
        webView.loadHTMLString(html, baseURL: baseURL)

        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let currentHash = hashContent(rawMarkdown, fontSize: fontSize)

        // 内容变化时重新生成 HTML 并加载
        if currentHash != context.coordinator.lastLoadedHash {
            context.coordinator.lastLoadedHash = currentHash
            let html = generateHTML()
            webView.loadHTMLString(html, baseURL: baseURL)
            return
        }

        // 仅同步字号（通过 JS，避免重新加载）
        let jsFont = "document.body.style.fontSize = '\(fontSize)px';"
        webView.evaluateJavaScript(jsFont, completionHandler: nil)

        // 同步选中文本高亮
        if let highlight = highlightText, !highlight.isEmpty {
            syncHighlight(to: webView, text: highlight)
        } else {
            clearHighlight(in: webView)
        }
    }

    // MARK: - 内容哈希

    private func hashContent(_ content: String, fontSize: Double) -> Int {
        var hasher = Hasher()
        hasher.combine(content)
        hasher.combine(fontSize)
        return hasher.finalize()
    }

    // MARK: - 高亮同步

    private func syncHighlight(to webView: WKWebView, text: String) {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")

        let js = """
        (function() {
            var selection = '\(escaped)';
            if (!selection || selection.length === 0) { return; }
            var marks = document.querySelectorAll('mark[data-mf-highlight]');
            marks.forEach(function(m) { var p=m.parentNode; while(m.firstChild){p.insertBefore(m.firstChild,m);} p.removeChild(m); });
            function walk(node) {
                if (node.nodeType === 3) {
                    var t = node.textContent, i = t.indexOf(selection);
                    if (i !== -1) {
                        var r = document.createRange(); r.setStart(node, i); r.setEnd(node, i + selection.length);
                        var mk = document.createElement('mark'); mk.setAttribute('data-mf-highlight', '1');
                        r.surroundContents(mk); return true;
                    }
                } else if (node.nodeType === 1 && node.tagName !== 'SCRIPT' && node.tagName !== 'STYLE') {
                    for (var j = 0; j < node.childNodes.length; j++) { if (walk(node.childNodes[j])) return true; }
                }
                return false;
            }
            walk(document.body);
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func clearHighlight(in webView: WKWebView) {
        let js = """
        (function() {
            var marks = document.querySelectorAll('mark[data-mf-highlight]');
            marks.forEach(function(m) { var p=m.parentNode; while(m.firstChild){p.insertBefore(m.firstChild,m);} p.removeChild(m); });
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var lastLoadedHash: Int = 0

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        }
    }
}
