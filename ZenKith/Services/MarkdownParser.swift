import Foundation
import Markdown

/// 将 Markdown 文本解析并转换为 HTML，支持数学公式保护、代码高亮、图片路径转换
final class MarkdownParser {

    // MARK: - 公共接口

    /// 将 Markdown 转换为完整 HTML 页面
    static func toHTML(_ markdown: String, baseURL: URL) -> String {
        let (processedText, mathPlaceholders) = protectMathExpressions(markdown)
        let document = Document(parsing: processedText)
        let bodyHTML = renderMarkup(document)
        let restored = restoreMathExpressions(bodyHTML, placeholders: mathPlaceholders)
        let finalHTML = fixImagePaths(in: restored, baseURL: baseURL)
        return wrapInTemplate(finalHTML)
    }

    /// 将 Markdown 转换为纯 body HTML（无模板，用于 AI 消息等轻量场景）
    static func toBodyHTML(_ markdown: String) -> String {
        let (processedText, mathPlaceholders) = protectMathExpressions(markdown)
        let document = Document(parsing: processedText)
        let bodyHTML = renderMarkup(document)
        return restoreMathExpressions(bodyHTML, placeholders: mathPlaceholders)
    }

    // MARK: - 数学公式保护

    /// 用占位符替换 $$...$$ 和 $...$，防止 Markdown 解析器误解释 _、* 等字符
    private static func protectMathExpressions(_ text: String) -> (String, [String: String]) {
        var result = text
        var map: [String: String] = [:]
        var index = 0

        // 先处理块级公式 $$...$$
        let blockPattern = "\\$\\$([\\s\\S]*?)\\$\\$"
        if let regex = try? NSRegularExpression(pattern: blockPattern, options: []) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsString.length))
            for match in matches.reversed() {
                let full = nsString.substring(with: match.range)
                let placeholder = "⧛MATH_BLOCK_\(index)⧚"
                map[placeholder] = full
                result = result.replacingOccurrences(of: full, with: placeholder)
                index += 1
            }
        }

        // 再处理行内公式 $...$ (不匹配 $$)
        let inlinePattern = "(?<!\\$)\\$(?!\\$)([^\\$]+?)\\$(?!\\$)"
        if let regex = try? NSRegularExpression(pattern: inlinePattern, options: []) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsString.length))
            for match in matches.reversed() {
                let full = nsString.substring(with: match.range)
                let placeholder = "⧛MATH_INLINE_\(index)⧚"
                map[placeholder] = full
                result = result.replacingOccurrences(of: full, with: placeholder)
                index += 1
            }
        }

        return (result, map)
    }

    private static func restoreMathExpressions(_ html: String, placeholders: [String: String]) -> String {
        var result = html
        for (placeholder, math) in placeholders {
            // HTML 实体内转义
            let escaped = math
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            result = result.replacingOccurrences(of: placeholder, with: escaped)
        }
        return result
    }

    // MARK: - Markdown AST → HTML

    private static func renderMarkup(_ markup: Markup) -> String {
        var html = ""
        for child in markup.children {
            renderNode(child, into: &html)
        }
        return html.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func renderNode(_ node: Markup, into html: inout String) {
        switch node {
        case let paragraph as Paragraph:
            html += "<p>"
            renderChildren(node, into: &html, inline: true)
            html += "</p>\n"

        case let heading as Heading:
            let level = min(heading.level, 6)
            html += "<h\(level)>"
            renderChildren(node, into: &html, inline: true)
            html += "</h\(level)>\n"

        case let codeBlock as CodeBlock:
            let lang = codeBlock.language ?? ""
            let code = codeBlock.code.escapeHTML()
            html += "<pre><code class=\"language-\(lang)\">\(code)</code></pre>\n"

        case let blockQuote as BlockQuote:
            html += "<blockquote>\n"
            renderChildren(node, into: &html)
            html += "</blockquote>\n"

        case let orderedList as OrderedList:
            let tag = orderedList.startIndex > 1 ? "ol start=\"\(orderedList.startIndex)\"" : "ol"
            html += "<\(tag)>\n"
            renderChildren(node, into: &html)
            html += "</ol>\n"

        case _ as UnorderedList:
            html += "<ul>\n"
            renderChildren(node, into: &html)
            html += "</ul>\n"

        case let listItem as ListItem:
            html += "<li>"
            for child in listItem.children {
                if child is Paragraph {
                    // ListItem 的 Paragraph 直接渲染行内内容，不加 <p> 标签
                    renderChildren(child, into: &html, inline: true)
                } else {
                    renderNode(child, into: &html)
                }
            }
            html += "</li>\n"

        case _ as ThematicBreak:
            html += "<hr>\n"

        case let htmlBlock as HTMLBlock:
            html += htmlBlock.rawHTML + "\n"

        case let table as Table:
            html += renderTable(table)

        case _ as SoftBreak:
            html += " "

        case _ as LineBreak:
            html += "<br>\n"

        // 行内元素 —— 由父级在 inline 模式下调用
        case let textNode as Text:
            html += textNode.string.escapeHTML()

        case let inlineCode as InlineCode:
            html += "<code>\(inlineCode.code.escapeHTML())</code>"

        case let emphasis as Emphasis:
            html += "<em>"
            renderChildren(node, into: &html, inline: true)
            html += "</em>"

        case let strongNode as Strong:
            html += "<strong>"
            renderChildren(node, into: &html, inline: true)
            html += "</strong>"

        case let strikethrough as Strikethrough:
            html += "<del>"
            renderChildren(node, into: &html, inline: true)
            html += "</del>"

        case let link as Link:
            let dest = link.destination?.escapeHTML() ?? "#"
            let titleAttr = link.title.map { " title=\"\($0.escapeHTML())\"" } ?? ""
            html += "<a href=\"\(dest)\"\(titleAttr)>"
            renderChildren(node, into: &html, inline: true)
            html += "</a>"

        case let image as Image:
            let src = image.source?.escapeHTML() ?? ""
            let alt = image.plainText.escapeHTML()
            let titleAttr = image.title.map { " title=\"\($0.escapeHTML())\"" } ?? ""
            html += "<img src=\"\(src)\" alt=\"\(alt)\"\(titleAttr)>"

        case let inlineHTML as InlineHTML:
            html += inlineHTML.rawHTML

        default:
            // 未知节点尝试递归渲染子节点
            renderChildren(node, into: &html)
        }
    }

    private static func renderChildren(_ node: Markup, into html: inout String, inline: Bool = false) {
        for child in node.children {
            renderNode(child, into: &html)
        }
    }

    // MARK: - 表格渲染

    private static func renderTable(_ table: Table) -> String {
        var html = "<table>\n"
        let alignments = table.columnAlignments

        html += "<thead>\n"
        html += renderTableRow(table.head, cellTag: "th", alignments: alignments)
        html += "</thead>\n"

        html += "<tbody>\n"
        for row in table.body.children {
            html += renderTableRow(row, cellTag: "td", alignments: alignments)
        }
        html += "</tbody>\n"

        html += "</table>\n"
        return html
    }

    private static func renderTableRow(_ row: Markup, cellTag: String, alignments: [Table.ColumnAlignment?]) -> String {
        var html = "<tr>\n"
        for (index, cell) in row.children.enumerated() {
            var alignAttr = ""
            if index < alignments.count, let alignment = alignments[index] {
                switch alignment {
                case .left: alignAttr = " style=\"text-align:left\""
                case .center: alignAttr = " style=\"text-align:center\""
                case .right: alignAttr = " style=\"text-align:right\""
                default: break
                }
            }
            html += "<\(cellTag)\(alignAttr)>"
            for child in cell.children {
                renderNode(child, into: &html)
            }
            html += "</\(cellTag)>\n"
        }
        html += "</tr>\n"
        return html
    }

    // MARK: - 图片路径修正

    /// 将相对路径的图片 src 转换为绝对 file:// URL
    private static func fixImagePaths(in html: String, baseURL: URL) -> String {
        let pattern = "src=\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return html
        }

        var result = html
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))

        for match in matches.reversed() {
            guard let srcRange = Range(match.range(at: 1), in: html) else { continue }
            let src = String(html[srcRange])

            // 跳过绝对 URL 和 data: URI
            if src.hasPrefix("http") || src.hasPrefix("file://") || src.hasPrefix("data:") {
                continue
            }

            let absoluteURL = baseURL.appendingPathComponent(src).absoluteString
            if let fullRange = Range(match.range(at: 0), in: html) {
                result.replaceSubrange(fullRange, with: "src=\"\(absoluteURL)\"")
            }
        }

        return result
    }

    // MARK: - HTML 模板

    /// 将 body 内容包裹在完整的 HTML 模板中，包含 MathJax 和 highlight.js
    private static func wrapInTemplate(_ body: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root {
          --bg: #ffffff;
          --text: #1d1d1f;
          --code-bg: #f5f5f7;
          --border: #e5e5ea;
          --link: #007aff;
          --blockquote: #f0f0f5;
          --table-stripe: #f9f9fb;
        }
        @media (prefers-color-scheme: dark) {
          :root {
            --bg: #1c1c1e;
            --text: #e5e5ea;
            --code-bg: #2c2c2e;
            --border: #38383a;
            --link: #0a84ff;
            --blockquote: #2c2c2e;
            --table-stripe: #2c2c2e;
          }
        }
        body {
          font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
          font-size: 16px;
          line-height: 1.8;
          color: var(--text);
          background: var(--bg);
          max-width: 860px;
          margin: 0 auto;
          padding: 20px 24px 60px;
          word-wrap: break-word;
        }
        h1, h2, h3, h4, h5, h6 {
          margin-top: 1.5em;
          margin-bottom: 0.5em;
          font-weight: 600;
          line-height: 1.3;
        }
        h1 { font-size: 2em; border-bottom: 1px solid var(--border); padding-bottom: 0.3em; }
        h2 { font-size: 1.5em; }
        h3 { font-size: 1.25em; }
        p { margin: 0.8em 0; }
        a { color: var(--link); text-decoration: none; }
        a:hover { text-decoration: underline; }
        img { max-width: 100%; height: auto; border-radius: 8px; }
        blockquote {
          border-left: 4px solid var(--link);
          margin: 1em 0;
          padding: 0.5em 1em;
          background: var(--blockquote);
          border-radius: 0 8px 8px 0;
        }
        code {
          font-family: "SF Mono", "Menlo", "Monaco", monospace;
          background: var(--code-bg);
          padding: 2px 6px;
          border-radius: 4px;
          font-size: 0.9em;
        }
        pre {
          background: var(--code-bg);
          border: 1px solid var(--border);
          border-radius: 8px;
          padding: 16px;
          overflow-x: auto;
        }
        pre code {
          background: none;
          padding: 0;
          font-size: 0.88em;
          line-height: 1.6;
        }
        table {
          border-collapse: collapse;
          width: 100%;
          margin: 1em 0;
        }
        th, td {
          border: 1px solid var(--border);
          padding: 8px 12px;
          text-align: left;
        }
        th {
          background: var(--code-bg);
          font-weight: 600;
        }
        hr {
          border: none;
          border-top: 1px solid var(--border);
          margin: 2em 0;
        }
        ul, ol { padding-left: 1.5em; }
        li { margin: 0.3em 0; }
        mark { background: #ffeb3b; color: #000; border-radius: 2px; padding: 0 1px; }
        @media (prefers-color-scheme: dark) {
          mark { background: #ffd60a; color: #000; }
        }
        </style>
        <!-- MathJax 3 数学公式渲染 -->
        <script>
        MathJax = {
          tex: {
            inlineMath: [['$', '$'], ['\\\\(', '\\\\)']],
            displayMath: [['$$', '$$'], ['\\\\[', '\\\\]']],
            processEscapes: true
          },
          options: {
            ignoreHtmlClass: 'no-mathjax'
          }
        };
        </script>
        <script id="MathJax-script" async src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-mml-chtml.js"></script>
        <!-- highlight.js 代码高亮 -->
        <link rel="stylesheet" id="hljs-theme" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github.min.css">
        <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
        <script>
        // 根据系统主题切换 highlight.js 主题
        (function() {
          const darkQuery = window.matchMedia('(prefers-color-scheme: dark)');
          function updateTheme(e) {
            const link = document.getElementById('hljs-theme');
            link.href = e.matches
              ? 'https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github-dark.min.css'
              : 'https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github.min.css';
          }
          darkQuery.addEventListener('change', updateTheme);
          updateTheme(darkQuery);
        })();
        </script>
        </head>
        <body>
        \(body)
        <script>
        // MathJax 渲染完成后触发高亮
        MathJax.startup.promise.then(function() {
          hljs.highlightAll();
        });
        MathJax.startup.defaultReady();
        </script>
        </body>
        </html>
        """
    }
}

// MARK: - String 扩展

private extension String {
    /// 对 HTML 特殊字符进行转义
    func escapeHTML() -> String {
        self.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
