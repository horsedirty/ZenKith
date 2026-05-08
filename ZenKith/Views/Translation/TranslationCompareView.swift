import SwiftUI

struct TranslationCompareView: View {
    let document: TranslationDocument
    @ObservedObject var viewModel: PDFTranslationViewModel

    @State private var selectedPage: Int? = nil

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.state == .translating {
                progressHeader
            }

            if document.totalPages > 1 {
                pageSelector(totalPages: document.totalPages)
            }

            Divider()

            TranslationCompareWebView(paragraphs: displayedParagraphs)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                translateButton
            }
        }
    }

    private var displayedParagraphs: [TranslationParagraph] {
        let sorted = document.paragraphs.sorted { ($0.pageIndex, $0.orderIndex) < ($1.pageIndex, $1.orderIndex) }
        guard let page = selectedPage else { return sorted }
        return sorted.filter { $0.pageIndex == page }
    }

    private var progressHeader: some View {
        VStack(spacing: 4) {
            ProgressView(value: viewModel.translationProgress)
                .tint(.accentColor)
            Text("翻译中 \(Int(viewModel.translationProgress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
    }

    private func pageSelector(totalPages: Int) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                pagePill("全部", page: nil)
                ForEach(0..<totalPages, id: \.self) { index in
                    pagePill("第 \(index + 1) 页", page: index)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color(nsColor: .separatorColor).opacity(0.15))
    }

    private func pagePill(_ title: String, page: Int?) -> some View {
        let isSelected = selectedPage == page
        return Button {
            selectedPage = page
        } label: {
            Text(title)
                .font(.system(size: 11))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
                .foregroundColor(isSelected ? Color.accentColor : .secondary)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.accentColor.opacity(0.4) : Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var translateButton: some View {
        if case .translating = viewModel.state {
            ProgressView().controlSize(.small)
        } else if document.isCompleted {
            Menu {
                Button("重新翻译全部") {
                    viewModel.startTranslation(for: document)
                }
            } label: {
                Label("已完成", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 90)
        } else {
            let hasFailed = document.paragraphs.contains { $0.status == .failed }
            Button {
                if hasFailed {
                    viewModel.retryFailed(for: document)
                } else {
                    viewModel.startTranslation(for: document)
                }
            } label: {
                Label(hasFailed ? "重试" : "开始翻译", systemImage: hasFailed ? "arrow.clockwise" : "translate")
            }
        }
    }
}
