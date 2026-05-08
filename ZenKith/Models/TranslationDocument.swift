import Foundation

struct TranslationDocument: Identifiable, Codable {
    var id: UUID = UUID()
    var fileName: String
    var importDate: Date = Date()
    var totalPages: Int
    var isCompleted: Bool = false
    var paragraphs: [TranslationParagraph] = []

    var progress: Double {
        guard !paragraphs.isEmpty else { return 0 }
        let doneCount = paragraphs.filter { $0.status == .done }.count
        return Double(doneCount) / Double(paragraphs.count)
    }
}

struct TranslationParagraph: Identifiable, Codable {
    var id: UUID = UUID()
    var pageIndex: Int
    var orderIndex: Int
    var originalText: String
    var translatedText: String?
    var status: TranslationStatus = .pending
    var formatHint: ParagraphFormatHint = .paragraph

    var originalMarkdown: String {
        switch formatHint {
        case .heading:
            return "# \(originalText)"
        case .subheading:
            return "## \(originalText)"
        case .listItem:
            if originalText.range(of: #"^[\-\*\+•◦▪▸►]"#, options: .regularExpression) != nil {
                return originalText
            }
            return "- \(originalText)"
        case .codeBlock:
            return "```\n\(originalText)\n```"
        case .paragraph, .emptyLine:
            return originalText
        }
    }
}

enum TranslationStatus: String, Codable {
    case pending
    case translating
    case done
    case failed
}
