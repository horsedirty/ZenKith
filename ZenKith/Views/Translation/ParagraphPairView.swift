import SwiftUI

struct ParagraphPairView: View {
    let paragraph: TranslationParagraph

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(paragraph.originalText)
                .font(.body)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 0.5)
                )

            Group {
                if let translated = paragraph.translatedText {
                    Text(translated)
                        .font(.body)
                        .foregroundColor(.primary)
                } else {
                    statusView
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch paragraph.status {
        case .translating:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                Text("翻译中...").foregroundColor(.secondary)
            }
        case .failed:
            Label("翻译失败", systemImage: "exclamationmark.triangle")
                .foregroundColor(.red).font(.callout)
        default:
            Text("等待翻译").foregroundColor(.secondary).font(.callout)
        }
    }
}
