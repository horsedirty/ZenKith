import SwiftUI
import Translation
import UniformTypeIdentifiers

struct TranslationWindowView: View {
    @EnvironmentObject var settings: AppSettings
    @StateObject private var viewModel = PDFTranslationViewModel()

    var body: some View {
        NavigationSplitView {
            sidebarView
                .navigationSplitViewColumnWidth(min: 200, ideal: 250)
                .toolbar {
                    ToolbarItem {
                        Button {
                            viewModel.showFileImporter = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .help("导入 PDF")
                    }
                }
        } detail: {
            if let document = viewModel.currentDocument {
                TranslationCompareView(document: document, viewModel: viewModel)
            } else {
                ContentUnavailableView {
                    Label("选择或导入 PDF", systemImage: "doc.text")
                } description: {
                    Text("从左侧选择已有文档，或点击 + 导入新的 PDF 文件")
                }
            }
        }
        .navigationTitle("PDF 翻译")
        .fileImporter(
            isPresented: $viewModel.showFileImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { viewModel.importPDF(from: url) }
            case .failure(let error):
                viewModel.state = .error(error.localizedDescription)
            }
        }
        .translationTask(viewModel.translationConfiguration) { session in
            await viewModel.performAppleTranslation(using: session)
        }
        .alert("错误", isPresented: errorBinding) {
            Button("确定") { viewModel.clearError() }
        } message: {
            if case .error(let msg) = viewModel.state { Text(msg) }
        }
        .onAppear {
            viewModel.configure(with: settings)
            if viewModel.documents.isEmpty {
                viewModel.showFileImporter = true
            }
        }
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        List(selection: Binding(
            get: { viewModel.currentDocument?.id },
            set: { id in
                viewModel.currentDocument = viewModel.documents.first { $0.id == id }
            }
        )) {
            ForEach(viewModel.documents) { document in
                sidebarRow(document)
                    .tag(document.id)
                    .contextMenu {
                        Button("删除", role: .destructive) {
                            viewModel.deleteDocument(document)
                        }
                    }
            }
        }
        .listStyle(.sidebar)
    }

    private func sidebarRow(_ doc: TranslationDocument) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(doc.fileName)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            HStack(spacing: 4) {
                Text("\(doc.totalPages) 页 · \(doc.paragraphs.count) 段")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                if doc.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                } else if doc.progress > 0 {
                    Text("\(Int(doc.progress * 100))%")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                } else {
                    Text("待翻译")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Error Binding

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { if case .error = viewModel.state { return true }; return false },
            set: { _ in viewModel.clearError() }
        )
    }
}
