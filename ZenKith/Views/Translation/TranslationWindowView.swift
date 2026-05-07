import SwiftUI
import Translation
import UniformTypeIdentifiers

struct TranslationWindowView: View {
    @StateObject private var viewModel = PDFTranslationViewModel()

    var body: some View {
        HSplitView {
            sidebarView
                .frame(minWidth: 200, idealWidth: 220)

            mainContentView
                .frame(minWidth: 500)
        }
        .frame(minWidth: 800, minHeight: 500)
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
            await viewModel.performTranslation(using: session)
        }
        .alert("错误", isPresented: errorAlertBinding) {
            Button("确定") { viewModel.clearError() }
        } message: {
            if case .error(let msg) = viewModel.state { Text(msg) }
        }
        .onAppear {
            if viewModel.documents.isEmpty {
                viewModel.showFileImporter = true
            }
        }
    }

    // MARK: - Error Alert Binding

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { if case .error = viewModel.state { return true }; return false },
            set: { _ in viewModel.clearError() }
        )
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("翻译文档")
                    .font(.headline).foregroundColor(.secondary)
                Spacer()
                Menu {
                    Button("导入 PDF...") {
                        viewModel.showFileImporter = true
                    }
                } label: {
                    Image(systemName: "plus").font(.title3)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
                .help("导入 PDF")
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            Divider()

            if viewModel.documents.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "doc.text").font(.appFont(size: 28)).foregroundColor(.secondary)
                    Text("暂无翻译文档").foregroundColor(.secondary).font(.callout)
                }
                Spacer()
            } else {
                List(selection: $viewModel.selectedDocumentId) {
                    ForEach(viewModel.documents) { doc in
                        documentRow(doc)
                            .tag(doc.id)
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func documentRow(_ doc: TranslationDocument) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(doc.fileName)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            HStack(spacing: 4) {
                Text("\(doc.totalPages) 页")
                    .font(.system(size: 10)).foregroundColor(.secondary)

                if doc.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10)).foregroundColor(.green)
                } else if doc.progress > 0 {
                    Text("\(Int(doc.progress * 100))%")
                        .font(.system(size: 10)).foregroundColor(.orange)
                } else {
                    Text("待翻译")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("删除", role: .destructive) {
                viewModel.deleteDocument(doc.id)
            }
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContentView: some View {
        if let doc = viewModel.selectedDocument {
            VStack(spacing: 0) {
                // Toolbar
                HStack {
                    Text(doc.fileName)
                        .font(.appHeadline)
                        .lineLimit(1)

                    Spacer()

                    translateButton
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider()

                TranslationCompareView(viewModel: viewModel)
            }
            .background(Color(nsColor: .textBackgroundColor))
        } else {
            VStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.appFont(size: 36)).foregroundColor(.secondary)
                Text("选择左侧文档或导入新 PDF").foregroundColor(.secondary)
                Button("导入 PDF") {
                    viewModel.showFileImporter = true
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    @ViewBuilder
    private var translateButton: some View {
        if case .translating = viewModel.state {
            ProgressView().controlSize(.small)
        } else if viewModel.selectedDocument?.isCompleted == true {
            Menu {
                Button("重新翻译全部") {
                    viewModel.startTranslation()
                }
            } label: {
                Label("已完成", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 90)
        } else {
            let hasFailed = viewModel.selectedDocument?.paragraphs.contains { $0.status == .failed } ?? false
            Button {
                if hasFailed {
                    viewModel.retryFailed()
                } else {
                    viewModel.startTranslation()
                }
            } label: {
                Label(hasFailed ? "重试" : "开始翻译", systemImage: hasFailed ? "arrow.clockwise" : "translate")
            }
        }
    }
}
