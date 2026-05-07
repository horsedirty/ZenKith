import SwiftUI
import Translation

struct TranslationCompareView: View {
    @ObservedObject var viewModel: PDFTranslationViewModel

    @State private var selectedPage: Int? = nil

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.state == .translating {
                progressHeader
            }

            if let doc = viewModel.selectedDocument, doc.totalPages > 1 {
                pageSelector(totalPages: doc.totalPages)
            }

            columnHeaders

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(displayedParagraphs) { paragraph in
                        ParagraphPairView(paragraph: paragraph)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Computed

    private var displayedParagraphs: [TranslationParagraph] {
        let sorted = viewModel.sortedParagraphs
        guard let page = selectedPage else { return sorted }
        return sorted.filter { $0.pageIndex == page }
    }

    // MARK: - Subviews

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
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
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

    private var columnHeaders: some View {
        HStack(spacing: 12) {
            Text("原文")
                .font(.caption).fontWeight(.semibold)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("译文")
                .font(.caption).fontWeight(.semibold)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
}
