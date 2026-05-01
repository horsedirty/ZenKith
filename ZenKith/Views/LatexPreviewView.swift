import SwiftUI
import WebKit
import PDFKit

/// LaTeX 预览视图：WebView + MathJax 渲染（无本地编译器时的回退方案）
struct LatexPreviewView: NSViewRepresentable {
    var latexSource: String
    var fontSize: Double
    var baseURL: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.lastSource = ""
        context.coordinator.lastFontSize = 0
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if latexSource == context.coordinator.lastSource && fontSize == context.coordinator.lastFontSize {
            return
        }
        context.coordinator.lastSource = latexSource
        context.coordinator.lastFontSize = fontSize
        let html = LatexService.latexToHTML(latexSource, fontSize: fontSize)
        webView.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator: NSObject {
        var lastSource = ""
        var lastFontSize: Double = 0
    }
}
