import SwiftUI
import AppKit

/// Markdown 源码编辑器：基于 NSTextView 的 AppKit 桥接，支持等宽字体、行号、暗色模式适配
struct EditorView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: Double

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = NSTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isGrammarCheckingEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.drawsBackground = true

        // 等宽字体
        updateFont(textView, fontSize: fontSize)

        // 设置文本容器
        textView.textContainerInset = NSSize(width: 12, height: 16)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )

        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        // 行号装订线
        textView.textContainer?.lineFragmentPadding = 8

        scrollView.documentView = textView

        // 暗色模式适配
        updateAppearance(textView)

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // 仅当 text 外部变更时更新（避免死循环）
        if textView.string != text && !context.coordinator.isInternalEdit {
            textView.string = text
        }

        // 更新字号
        updateFont(textView, fontSize: fontSize)

        updateAppearance(textView)
    }

    private func updateFont(_ textView: NSTextView, fontSize: Double) {
        let clamped = max(12, min(32, fontSize))
        textView.font = NSFont.monospacedSystemFont(ofSize: clamped, weight: .regular)
    }

    private func updateAppearance(_ textView: NSTextView) {
        let isDark = NSApp.effectiveAppearance.name == .darkAqua
            || NSApp.effectiveAppearance.name == .vibrantDark
        textView.backgroundColor = isDark
            ? NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0)
            : NSColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1.0)
        textView.textColor = isDark
            ? NSColor(red: 0.90, green: 0.90, blue: 0.92, alpha: 1.0)
            : NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0)
        textView.insertionPointColor = NSColor.controlAccentColor
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var isInternalEdit = false
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?

        init(text: Binding<String>) {
            self._text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            isInternalEdit = true
            text = textView.string
            isInternalEdit = false
        }
    }
}
