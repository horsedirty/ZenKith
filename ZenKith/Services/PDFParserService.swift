import Foundation
import PDFKit

enum ParagraphFormatHint: String, Codable {
    case heading
    case subheading
    case listItem
    case codeBlock
    case paragraph
    case emptyLine
}

struct PDFParserService {

    struct ParseResult {
        let totalPages: Int
        let paragraphs: [PDFParagraph]
    }

    func parse(url: URL) throws -> ParseResult {
        guard url.startAccessingSecurityScopedResource() else {
            throw PDFParserError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let document = PDFDocument(url: url) else {
            throw PDFParserError.failedToLoad
        }

        let totalPages = document.pageCount
        var paragraphs: [PDFParagraph] = []

        for pageIndex in 0..<totalPages {
            guard let page = document.page(at: pageIndex),
                  let pageText = page.string else { continue }

            let pageParagraphs = splitIntoParagraphs(pageText)
            for (orderIndex, paragraph) in pageParagraphs.enumerated() {
                paragraphs.append(
                    PDFParagraph(
                        pageIndex: pageIndex,
                        orderIndex: orderIndex,
                        text: paragraph.text,
                        formatHint: paragraph.hint
                    )
                )
            }
        }

        if paragraphs.isEmpty {
            throw PDFParserError.noTextContent
        }

        return ParseResult(totalPages: totalPages, paragraphs: paragraphs)
    }

    /// Split page text into paragraphs with format detection
    private func splitIntoParagraphs(_ text: String) -> [(text: String, hint: ParagraphFormatHint)] {
        let lines = text.components(separatedBy: "\n")
        var result: [(String, ParagraphFormatHint)] = []
        var currentBlock: [String] = []
        var currentHint: ParagraphFormatHint = .paragraph

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Empty line = paragraph boundary
            if trimmed.isEmpty {
                if !currentBlock.isEmpty {
                    result.append((joinBlock(currentBlock, hint: currentHint), currentHint))
                    currentBlock = []
                    currentHint = .paragraph
                }
                result.append(("", .emptyLine))
                continue
            }

            // Detect format hint for this line
            let lineHint = detectFormatHint(trimmed)

            // If format hints differ (paragraph vs special), flush current block
            if currentHint != lineHint && currentHint != .paragraph && lineHint != .paragraph {
                if !currentBlock.isEmpty {
                    result.append((joinBlock(currentBlock, hint: currentHint), currentHint))
                    currentBlock = []
                }
                currentHint = lineHint
            } else if currentHint == .paragraph && lineHint != .paragraph {
                // Transition from paragraph to special
                if !currentBlock.isEmpty {
                    result.append((joinBlock(currentBlock, hint: .paragraph), .paragraph))
                    currentBlock = []
                }
                currentHint = lineHint
            }

            currentBlock.append(trimmed)
        }

        // Flush remaining
        if !currentBlock.isEmpty {
            result.append((joinBlock(currentBlock, hint: currentHint), currentHint))
        }

        // Filter out truly empty (only empty line markers between paragraphs)
        return result.filter { !$0.0.isEmpty || $0.1 != .emptyLine }
    }

    private func detectFormatHint(_ line: String) -> ParagraphFormatHint {
        // Check for list markers
        let listPatterns = [
            #"^[\-\*\+•◦▪▸►]\s"#,
            #"^\d+[\.\)]\s"#,
            #"^[a-zA-Z][\.\)]\s"#,
            #"^[\(（]\d+[\)）]\s"#,
            #"^[\(（][a-zA-Z][\)）]\s"#
        ]

        for pattern in listPatterns {
            if line.range(of: pattern, options: .regularExpression) != nil {
                return .listItem
            }
        }

        // Check for code block (indented or starts with code markers)
        if line.hasPrefix("    ") || line.hasPrefix("\t") || line.hasPrefix("```") {
            return .codeBlock
        }

        // Check for headings (short, ends without period/comma, may be all caps)
        let isShort = line.count <= 80
        let isAllCaps = line == line.uppercased() && line.count > 3
        let noSentenceEnd = !line.hasSuffix(".") && !line.hasSuffix("。") && !line.hasSuffix(",") && !line.hasSuffix("，")

        if isShort && noSentenceEnd {
            if isAllCaps && line.count <= 50 {
                return .heading
            }
            if line.count <= 60 {
                return .subheading
            }
        }

        return .paragraph
    }

    /// Join lines of a block preserving their structure
    private func joinBlock(_ lines: [String], hint: ParagraphFormatHint) -> String {
        switch hint {
        case .heading, .subheading:
            return lines.joined(separator: " ")
        case .listItem:
            return lines.joined(separator: " ")
        case .codeBlock:
            return lines.joined(separator: "\n")
        case .paragraph:
            return lines.joined(separator: " ")
        case .emptyLine:
            return ""
        }
    }
}

// MARK: - PDFParagraph (moved from TranslationDocument)

struct PDFParagraph {
    let pageIndex: Int
    let orderIndex: Int
    let text: String
    let formatHint: ParagraphFormatHint
}

enum PDFParserError: LocalizedError {
    case accessDenied
    case failedToLoad
    case noTextContent

    var errorDescription: String? {
        switch self {
        case .accessDenied: return "无法访问所选文件"
        case .failedToLoad: return "无法加载 PDF 文件"
        case .noTextContent: return "PDF 中未检测到文本内容"
        }
    }
}
