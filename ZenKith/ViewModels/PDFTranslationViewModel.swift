import Foundation
import Combine
import SwiftUI
import Translation

@MainActor
final class PDFTranslationViewModel: ObservableObject {

    enum State: Equatable {
        case idle
        case parsing
        case translating
        case completed
        case error(String)
    }

    // MARK: - Published

    @Published var state: State = .idle
    @Published var documents: [TranslationDocument] = []
    @Published var selectedDocumentId: UUID?
    @Published var translationProgress: Double = 0
    @Published var translationConfiguration: TranslationSession.Configuration?
    @Published var showFileImporter = false

    // MARK: - Dependencies

    private let parser = PDFParserService()
    private let translationService = TranslationService()

    private static let storageURL: URL = {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = supportDir.appendingPathComponent("ZenKith")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("translationDocuments.json")
    }()

    init() {
        loadDocuments()
    }

    // MARK: - Selected Document

    var selectedDocument: TranslationDocument? {
        guard let id = selectedDocumentId else { return nil }
        return documents.first { $0.id == id }
    }

    var sortedParagraphs: [TranslationParagraph] {
        guard let doc = selectedDocument else { return [] }
        return doc.paragraphs.sorted { ($0.pageIndex, $0.orderIndex) < ($1.pageIndex, $1.orderIndex) }
    }

    // MARK: - Import PDF

    func importPDF(from url: URL) {
        state = .parsing

        do {
            let result = try parser.parse(url: url)
            let fileName = url.lastPathComponent

            var doc = TranslationDocument(fileName: fileName, totalPages: result.totalPages)
            doc.paragraphs = result.paragraphs.map { p in
                TranslationParagraph(
                    pageIndex: p.pageIndex,
                    orderIndex: p.orderIndex,
                    originalText: p.text
                )
            }

            documents.insert(doc, at: 0)
            selectedDocumentId = doc.id
            saveDocuments()
            state = .idle
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - Translation

    func startTranslation() {
        guard var doc = selectedDocument else { return }

        let allDone = doc.paragraphs.allSatisfy { $0.status == .done }
        if allDone {
            // Reset for re-translation
            for i in 0..<doc.paragraphs.count {
                doc.paragraphs[i].status = .pending
                doc.paragraphs[i].translatedText = nil
            }
            doc.isCompleted = false
            updateDocument(doc)
        }

        translationConfiguration = TranslationService.defaultConfiguration
    }

    func performTranslation(using session: TranslationSession) async {
        guard var doc = selectedDocument else {
            translationConfiguration = nil
            return
        }

        let pending = doc.paragraphs.filter { $0.status != .done }
        guard !pending.isEmpty else {
            doc.isCompleted = true
            updateDocument(doc)
            state = .completed
            translationConfiguration = nil
            return
        }

        state = .translating
        translationProgress = doc.progress

        let totalCount = doc.paragraphs.count
        var doneCount = doc.completedCount

        do {
            try await translationService.translateBatch(
                pending,
                using: session
            ) { [weak self] paragraph, translatedText in
                guard let self = self else { return }

                if var currentDoc = self.selectedDocument,
                   let idx = currentDoc.paragraphs.firstIndex(where: { $0.id == paragraph.id }) {
                    currentDoc.paragraphs[idx].translatedText = translatedText
                    currentDoc.paragraphs[idx].status = .done
                    doneCount += 1
                    self.translationProgress = Double(doneCount) / Double(totalCount)
                    self.updateDocument(currentDoc)
                }
            }

            if var currentDoc = self.selectedDocument {
                currentDoc.isCompleted = true
                self.updateDocument(currentDoc)
            }
            state = .completed
        } catch {
            saveDocuments()
            state = .error("翻译中断: \(error.localizedDescription)")
        }

        translationConfiguration = nil
    }

    func retryFailed() {
        guard var doc = selectedDocument else { return }
        for i in 0..<doc.paragraphs.count where doc.paragraphs[i].status == .failed {
            doc.paragraphs[i].status = .pending
        }
        updateDocument(doc)
        startTranslation()
    }

    // MARK: - Document Management

    func selectDocument(_ id: UUID) {
        selectedDocumentId = id
        state = .idle
    }

    func deleteDocument(_ id: UUID) {
        documents.removeAll { $0.id == id }
        if selectedDocumentId == id {
            selectedDocumentId = documents.first?.id
        }
        saveDocuments()
    }

    func clearError() {
        if case .error = state {
            state = .idle
        }
    }

    // MARK: - Private

    private func updateDocument(_ document: TranslationDocument) {
        guard let idx = documents.firstIndex(where: { $0.id == document.id }) else { return }
        documents[idx] = document
        saveDocuments()
    }

    private func saveDocuments() {
        guard let data = try? JSONEncoder().encode(documents) else { return }
        try? data.write(to: Self.storageURL, options: .atomic)
    }

    private func loadDocuments() {
        guard let data = try? Data(contentsOf: Self.storageURL),
              let loaded = try? JSONDecoder().decode([TranslationDocument].self, from: data) else { return }
        documents = loaded
        if selectedDocumentId == nil {
            selectedDocumentId = documents.first?.id
        }
    }
}
