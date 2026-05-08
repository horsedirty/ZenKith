import Foundation
import Combine
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
    @Published var currentDocument: TranslationDocument?
    @Published var showFileImporter = false
    @Published var translationProgress: Double = 0
    @Published var translationConfiguration: TranslationSession.Configuration?

    // MARK: - Dependencies

    private let parser = PDFParserService()
    private let storageURL: URL
    private var settings: AppSettings?

    // MARK: - Init

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("ZenKith", isDirectory: true)
        self.storageURL = appDir.appendingPathComponent("translations", isDirectory: true)
        try? FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
        loadDocuments()
    }

    func configure(with settings: AppSettings) {
        self.settings = settings
    }

    // MARK: - Import PDF

    func importPDF(from url: URL) {
        state = .parsing

        do {
            let result = try parser.parse(url: url)
            let fileName = url.lastPathComponent

            let paragraphs = result.paragraphs.map { p in
                TranslationParagraph(
                    pageIndex: p.pageIndex,
                    orderIndex: p.orderIndex,
                    originalText: p.text,
                    formatHint: p.formatHint
                )
            }

            let document = TranslationDocument(
                fileName: fileName,
                totalPages: result.totalPages,
                paragraphs: paragraphs
            )

            documents.insert(document, at: 0)
            currentDocument = document
            saveDocument(document)
            state = .idle
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - Start Translation (entry point)

    func startTranslation(for document: TranslationDocument) {
        currentDocument = document
        guard let settings = settings else {
            state = .error("设置未准备好")
            return
        }

        switch settings.translationEngine {
        case .apple:
            translationConfiguration = TranslationSession.Configuration(
                source: nil,
                target: Locale.Language(identifier: "zh-Hans")
            )
        case .tencent:
            performTencentTranslation()
        }
    }

    // MARK: - Apple Translation (via .translationTask)

    func performAppleTranslation(using session: TranslationSession) async {
        guard var document = currentDocument else { return }

        let pendingIndices = document.paragraphs.indices.filter { document.paragraphs[$0].status != .done }

        guard !pendingIndices.isEmpty else {
            document.isCompleted = true
            updateDocument(document)
            state = .completed
            translationConfiguration = nil
            return
        }

        state = .translating
        translationProgress = document.progress

        let totalCount = document.paragraphs.count
        var doneCount = document.paragraphs.filter { $0.status == .done }.count

        let pendingParagraphs = pendingIndices.map { document.paragraphs[$0] }

        do {
            for (batchIndex, paragraph) in pendingParagraphs.enumerated() {
                let response = try await session.translate(paragraph.originalText)
                let originalIndex = pendingIndices[batchIndex]
                document.paragraphs[originalIndex].translatedText = response.targetText
                document.paragraphs[originalIndex].status = .done
                doneCount += 1
                self.translationProgress = Double(doneCount) / Double(totalCount)
                self.currentDocument = document
            }

            document.isCompleted = true
            updateDocument(document)
            state = .completed
        } catch {
            updateDocument(document)
            state = .error("Apple 翻译中断: \(error.localizedDescription)")
        }

        translationConfiguration = nil
    }

    // MARK: - Tencent Translation (direct API)

    private func performTencentTranslation() {
        guard let settings = settings else { return }

        let secretId = settings.tencentSecretId
        let secretKey = settings.tencentSecretKey

        guard !secretId.isEmpty, !secretKey.isEmpty else {
            state = .error("请先在设置中配置腾讯云 SecretId 和 SecretKey")
            return
        }

        let source = settings.tencentSourceLanguage
        let target = settings.tencentTargetLanguage

        let service = TencentTranslationService(
            secretId: secretId,
            secretKey: secretKey,
            source: source,
            target: target
        )

        Task {
            guard var document = self.currentDocument else { return }

            let pendingIndices = document.paragraphs.indices.filter { document.paragraphs[$0].status != .done }

            guard !pendingIndices.isEmpty else {
                document.isCompleted = true
                updateDocument(document)
                state = .completed
                return
            }

            state = .translating
            translationProgress = document.progress

            let totalCount = document.paragraphs.count
            var doneCount = document.paragraphs.filter { $0.status == .done }.count

            do {
                for batchIndex in pendingIndices {
                    let paragraph = document.paragraphs[batchIndex]
                    let translated = try await service.translate(paragraph.originalText)
                    document.paragraphs[batchIndex].translatedText = translated
                    document.paragraphs[batchIndex].status = .done
                    doneCount += 1
                    self.translationProgress = Double(doneCount) / Double(totalCount)
                    self.currentDocument = document
                    self.updateDocument(document)
                }

                document.isCompleted = true
                updateDocument(document)
                state = .completed
            } catch {
                updateDocument(document)
                state = .error("腾讯翻译失败: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Retry

    func retryFailed(for document: TranslationDocument) {
        guard let index = documents.firstIndex(where: { $0.id == document.id }) else { return }
        for i in documents[index].paragraphs.indices {
            if documents[index].paragraphs[i].status == .failed {
                documents[index].paragraphs[i].status = .pending
            }
        }
        currentDocument = documents[index]
        saveDocument(documents[index])
        startTranslation(for: documents[index])
    }

    // MARK: - Delete

    func deleteDocument(_ document: TranslationDocument) {
        documents.removeAll { $0.id == document.id }
        let fileURL = storageURL.appendingPathComponent("\(document.id.uuidString).json")
        try? FileManager.default.removeItem(at: fileURL)
        if currentDocument?.id == document.id {
            currentDocument = nil
        }
    }

    // MARK: - Persistence

    private func loadDocuments() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: storageURL, includingPropertiesForKeys: nil) else { return }
        let decoder = JSONDecoder()
        documents = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(TranslationDocument.self, from: data)
            }
            .sorted { $0.importDate > $1.importDate }
    }

    private func saveDocument(_ document: TranslationDocument) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(document) else { return }
        let fileURL = storageURL.appendingPathComponent("\(document.id.uuidString).json")
        try? data.write(to: fileURL)
    }

    private func updateDocument(_ document: TranslationDocument) {
        if let index = documents.firstIndex(where: { $0.id == document.id }) {
            documents[index] = document
        }
        currentDocument = document
        saveDocument(document)
    }

    func clearError() {
        if case .error = state {
            state = .idle
        }
    }
}
