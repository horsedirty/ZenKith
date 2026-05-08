import SwiftUI
import WebKit

struct TranslationCompareWebView: NSViewRepresentable {
    let paragraphs: [TranslationParagraph]

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = true

        let html = buildHTML()
        webView.loadHTMLString(html, baseURL: nil)

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let newHTML = buildHTML()
        let currentHash = paragraphs.map { $0.translatedText ?? $0.status.rawValue }.joined().hashValue
        if currentHash != context.coordinator.lastHash {
            context.coordinator.lastHash = currentHash
            webView.loadHTMLString(newHTML, baseURL: nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject {
        var lastHash: Int = 0
    }

    // MARK: - HTML Generation

    private func buildHTML() -> String {
        var rows = ""
        for paragraph in paragraphs {
            let originalCell = formatCell(paragraph.originalText, hint: paragraph.formatHint)
            let translatedCell: String
            if let translated = paragraph.translatedText {
                translatedCell = formatCell(translated, hint: paragraph.formatHint)
            } else {
                translatedCell = statusCell(paragraph.status)
            }
            rows += """
            <tr>
                <td class="col-original">\(originalCell)</td>
                <td class="col-translated">\(translatedCell)</td>
            </tr>
            """
        }

        return """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root {
            --bg: #ffffff;
            --text: #1d1d1f;
            --border: #e5e5ea;
            --original-bg: #f5f5f7;
            --translated-bg: #ffffff;
            --muted: #86868b;
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --bg: #1c1c1e;
                --text: #e5e5ea;
                --border: #38383a;
                --original-bg: #2c2c2e;
                --translated-bg: #1c1c1e;
                --muted: #98989d;
            }
        }
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: "Times New Roman", "Times", "STSongti-SC", "Songti SC", serif;
            font-size: 14px; line-height: 1.8; color: var(--text);
            background: var(--bg); padding: 12px 16px;
        }
        table { width: 100%; border-collapse: collapse; }
        tr { border-bottom: 1px solid var(--border); }
        tr:last-child { border-bottom: none; }
        td { padding: 10px 12px; vertical-align: top; width: 50%; }
        .col-original { background: var(--original-bg); }
        .col-translated { background: var(--translated-bg); border-left: 1px solid var(--border); }
        .col-header { font-size: 11px; font-weight: 600; color: var(--muted);
            text-transform: uppercase; letter-spacing: 0.5px; }
        h1 { font-size: 1.4em; font-weight: 700; margin-bottom: 0.2em; }
        h2 { font-size: 1.15em; font-weight: 600; margin-bottom: 0.15em; }
        h3 { font-size: 1.05em; font-weight: 600; margin-bottom: 0.1em; }
        li { margin-left: 1.2em; padding-left: 0.3em; }
        code { font-family: "SF Mono", "Menlo", monospace; font-size: 0.88em;
            background: rgba(0,0,0,0.05); padding: 1px 5px; border-radius: 3px; }
        @media (prefers-color-scheme: dark) {
            code { background: rgba(255,255,255,0.08); }
        }
        pre { background: rgba(0,0,0,0.03); padding: 10px 12px; border-radius: 6px;
            overflow-x: auto; font-size: 0.85em; line-height: 1.5; margin: 4px 0; }
        @media (prefers-color-scheme: dark) {
            pre { background: rgba(255,255,255,0.04); }
        }
        pre code { background: none; padding: 0; }
        .status-pending { color: var(--muted); font-style: italic; }
        .status-failed { color: #ff3b30; }
        .status-translating { color: #007aff; }
        .empty-row td { padding: 6px 12px; background: transparent; }
        </style>
        </head>
        <body>
        <table>
            <tr>
                <td class="col-header">原文</td>
                <td class="col-header" style="border-left:1px solid var(--border)">译文</td>
            </tr>
            \(rows)
        </table>
        </body>
        </html>
        """
    }

    private func formatCell(_ text: String, hint: ParagraphFormatHint) -> String {
        let escaped = text.escapeHTML

        switch hint {
        case .heading:
            return "<h1>\(escaped)</h1>"
        case .subheading:
            return "<h2>\(escaped)</h2>"
        case .listItem:
            return "<li>\(escaped)</li>"
        case .codeBlock:
            return "<pre><code>\(escaped)</code></pre>"
        case .paragraph:
            return "<p>\(escaped)</p>"
        case .emptyLine:
            return "<p>&nbsp;</p>"
        }
    }

    private func statusCell(_ status: TranslationStatus) -> String {
        switch status {
        case .pending:
            return "<span class=\"status-pending\">等待翻译</span>"
        case .translating:
            return "<span class=\"status-translating\">翻译中...</span>"
        case .failed:
            return "<span class=\"status-failed\">翻译失败</span>"
        case .done:
            return ""
        }
    }
}

private extension String {
    var escapeHTML: String {
        self.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
