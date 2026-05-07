import Foundation
import PDFKit

struct PDFParserService {

    struct ParseResult {
        let totalPages: Int
        let paragraphs: [(pageIndex: Int, orderIndex: Int, text: String)]
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
        var paragraphs: [(Int, Int, String)] = []

        for pageIndex in 0..<totalPages {
            guard let page = document.page(at: pageIndex),
                  let pageText = page.string else { continue }

            let pageParagraphs = splitIntoParagraphs(pageText)
            for (orderIndex, text) in pageParagraphs.enumerated() {
                paragraphs.append((pageIndex, orderIndex, text))
            }
        }

        if paragraphs.isEmpty {
            throw PDFParserError.noTextContent
        }

        return ParseResult(totalPages: totalPages, paragraphs: paragraphs)
    }

    private func splitIntoParagraphs(_ text: String) -> [String] {
        text.components(separatedBy: "\n\n")
            .map { paragraph in
                paragraph
                    .components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
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
