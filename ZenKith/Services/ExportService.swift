import Foundation
import AppKit
import WebKit
import UniformTypeIdentifiers

/// 导出服务：支持 PDF / Word(.docx) / TXT / Markdown(.md) 四种格式
@MainActor
final class ExportService {

    struct ExportContext {
        let markdownContent: String
        let fileURL: URL
        let baseURL: URL
        var editorLanguage: EditorLanguage = .markdown
    }

    enum ExportFormat: String, CaseIterable {
        case pdf = "PDF"
        case docx = "Word (.docx)"
        case txt = "纯文本 (.txt)"
        case markdown = "Markdown (.md)"

        var fileExtension: String {
            switch self {
            case .pdf: return "pdf"
            case .docx: return "docx"
            case .txt: return "txt"
            case .markdown: return "md"
            }
        }

        var contentType: UTType {
            switch self {
            case .pdf: return .pdf
            case .docx: return UTType("org.openxmlformats.wordprocessingml.document") ?? .data
            case .txt: return .plainText
            case .markdown: return .plainText
            }
        }
    }

    static func export(_ context: ExportContext, format: ExportFormat) async {
        let savePanel = NSSavePanel()
        savePanel.title = "导出为 \(format.rawValue)"
        savePanel.nameFieldStringValue = context.fileURL
            .deletingPathExtension().lastPathComponent
            .appending(".\(format.fileExtension)")
        savePanel.allowedContentTypes = [format.contentType]
        savePanel.canCreateDirectories = true

        let response = savePanel.runModal()
        guard response == .OK, let destinationURL = savePanel.url else { return }

        do {
            switch format {
            case .pdf:
                if context.editorLanguage == .latex {
                    try await exportLatexPDF(context, to: destinationURL)
                } else {
                    try await exportPDF(context, to: destinationURL)
                }
            case .docx: try await exportDocx(context, to: destinationURL)
            case .txt: try exportTXT(context, to: destinationURL)
            case .markdown: try exportMarkdown(context, to: destinationURL)
            }
        } catch {}
    }

    // MARK: - LaTeX PDF 导出（调用本地编译器或 WebView 回退）

    private static func exportLatexPDF(_ context: ExportContext, to url: URL) async throws {
        // 优先使用本地 LaTeX 编译器
        if let pdfData = await LatexService.compileToPDF(context.markdownContent) {
            try pdfData.write(to: url)
            return
        }
        // 回退：使用 WebView + MathJax 渲染为 PDF
        let html = LatexService.latexToHTML(context.markdownContent, fontSize: 16)
        let embeddedHTML = embedImagesAsBase64(in: html, baseURL: context.baseURL)

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 595, height: 842))

        let data: Data = try await withCheckedThrowingContinuation { continuation in
            let delegate = PDFExportDelegate(webView: webView, html: embeddedHTML, baseURL: context.baseURL) { result in
                continuation.resume(with: result)
            }
            objc_setAssociatedObject(webView, "delegateRef", delegate, .OBJC_ASSOCIATION_RETAIN)
        }

        try data.write(to: url)
    }

    // MARK: - PDF 导出

    private static func exportPDF(_ context: ExportContext, to url: URL) async throws {
        let html = MarkdownParser.toHTML(context.markdownContent, baseURL: context.baseURL)
        // 将 file:// 图片转换为 base64 内联，避免沙盒扩展错误
        let embeddedHTML = embedImagesAsBase64(in: html, baseURL: context.baseURL)

        // 创建离屏 WebView，宽度设为 A4 (595pt)，不设 rect 以自动分页
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 595, height: 842))

        let data: Data = try await withCheckedThrowingContinuation { continuation in
            let delegate = PDFExportDelegate(webView: webView, html: embeddedHTML, baseURL: context.baseURL) { result in
                continuation.resume(with: result)
            }
            objc_setAssociatedObject(webView, "delegateRef", delegate, .OBJC_ASSOCIATION_RETAIN)
        }

        try data.write(to: url)
    }

    /// 将 HTML 中 file:// 图片转换为 base64 data URI，避免 WKWebView 沙盒权限问题
    private static func embedImagesAsBase64(in html: String, baseURL: URL) -> String {
        let pattern = "src=\"(file://[^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return html
        }

        var result = html
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))

        for match in matches.reversed() {
            guard let srcRange = Range(match.range(at: 1), in: html) else { continue }
            let fileURLStr = String(html[srcRange])
            guard let fileURL = URL(string: fileURLStr),
                  let imageData = try? Data(contentsOf: fileURL) else { continue }

            let ext = fileURL.pathExtension.lowercased()
            let mime: String = {
                switch ext {
                case "png": return "image/png"
                case "jpg", "jpeg": return "image/jpeg"
                case "gif": return "image/gif"
                case "svg": return "image/svg+xml"
                case "webp": return "image/webp"
                default: return "image/png"
                }
            }()
            let base64 = imageData.base64EncodedString()
            let dataURI = "src=\"data:\(mime);base64,\(base64)\""

            if let fullRange = Range(match.range(at: 0), in: html) {
                result.replaceSubrange(fullRange, with: dataURI)
            }
        }

        return result
    }

    // MARK: - Word (.docx) 导出

    private static func exportDocx(_ context: ExportContext, to url: URL) async throws {
        guard let data = context.markdownContent.data(using: .utf8) else {
            throw ExportError.invalidData
        }

        let attributed: NSAttributedString
        do {
            attributed = try NSAttributedString(
                markdown: data,
                options: AttributedString.MarkdownParsingOptions(
                    allowsExtendedAttributes: true,
                    interpretedSyntax: .full,
                    failurePolicy: .returnPartiallyParsedIfPossible
                ),
                baseURL: context.baseURL
            )
        } catch {
            do {
                let opts: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                    .documentType: NSAttributedString.DocumentType(rawValue: "net.daringfireball.markdown")
                ]
                attributed = try NSAttributedString(data: data, options: opts, documentAttributes: nil)
            } catch {
                attributed = NSAttributedString(string: context.markdownContent)
            }
        }

        let docxData = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]
        )
        try docxData.write(to: url)
    }

    private static func exportTXT(_ context: ExportContext, to url: URL) throws {
        try context.markdownContent.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func exportMarkdown(_ context: ExportContext, to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.copyItem(at: context.fileURL, to: url)
    }
}

// MARK: - PDF 导出代理

private final class PDFExportDelegate: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let completion: (Result<Data, Error>) -> Void
    private var didFinish = false

    init(webView: WKWebView, html: String, baseURL: URL, completion: @escaping (Result<Data, Error>) -> Void) {
        self.webView = webView
        self.completion = completion
        super.init()
        webView.navigationDelegate = self
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !didFinish else { return }
        didFinish = true

        // 检查 MathJax 是否已就绪，若已就绪直接生成 PDF，否则延迟等待
        webView.evaluateJavaScript("typeof MathJax !== 'undefined' && MathJax.startup && MathJax.startup.promise") { result, _ in
            let hasMathJax = (result as? Bool) == true || (result as? NSObject) != nil
            let delay: TimeInterval = hasMathJax ? 2.5 : 0.5

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                // 不设置 rect，自动捕获完整可滚动内容并分页
                let config = WKPDFConfiguration()
                webView.createPDF(configuration: config) { result in
                    switch result {
                    case .success(let data): self.completion(.success(data))
                    case .failure(let err): self.completion(.failure(err))
                    }
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !didFinish else { return }
        didFinish = true
        completion(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard !didFinish else { return }
        didFinish = true
        completion(.failure(error))
    }
}

enum ExportError: LocalizedError {
    case invalidData
    var errorDescription: String? {
        switch self {
        case .invalidData: return "无法生成导出数据"
        }
    }
}
