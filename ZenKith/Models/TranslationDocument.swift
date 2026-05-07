import Foundation

enum TranslationStatus: String, Codable {
    case pending
    case translating
    case done
    case failed
}

struct TranslationParagraph: Identifiable, Codable {
    var id: UUID = UUID()
    var pageIndex: Int
    var orderIndex: Int
    var originalText: String
    var translatedText: String?
    var status: TranslationStatus = .pending
}

struct TranslationDocument: Identifiable, Codable {
    var id: UUID = UUID()
    var fileName: String
    var importDate: Date = Date()
    var totalPages: Int
    var isCompleted: Bool = false
    var paragraphs: [TranslationParagraph] = []

    var completedCount: Int {
        paragraphs.filter { $0.status == .done }.count
    }

    var progress: Double {
        guard !paragraphs.isEmpty else { return 0 }
        return Double(completedCount) / Double(paragraphs.count)
    }
}
