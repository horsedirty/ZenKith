import Foundation
import Translation

struct TranslationService {

    static var defaultConfiguration: TranslationSession.Configuration {
        TranslationSession.Configuration(
            source: nil,
            target: Locale.Language(identifier: "zh-Hans")
        )
    }

    /// Translate a batch of paragraphs, calling onDone for each completed paragraph
    func translateBatch(
        _ paragraphs: [TranslationParagraph],
        using session: TranslationSession,
        onParagraphDone: @escaping (TranslationParagraph, String) -> Void
    ) async throws {
        for paragraph in paragraphs {
            guard paragraph.status != .done else { continue }

            let response = try await session.translate(paragraph.originalText)
            onParagraphDone(paragraph, response.targetText)
        }
    }
}
