import SwiftUI
import AppKit

struct EditorView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: Double
    var language: EditorLanguage = .markdown

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView(frame: .zero)
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
        textView.isFieldEditor = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width, .height]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 8, height: 16)
        textView.textContainer?.lineFragmentPadding = 8
        textView.font = NSFont.monospacedSystemFont(ofSize: max(12, min(32, fontSize)), weight: .regular)

        let dark = NSApp.effectiveAppearance.name == .darkAqua || NSApp.effectiveAppearance.name == .vibrantDark
        textView.backgroundColor = dark
            ? NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
            : NSColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1)
        textView.textColor = dark
            ? NSColor(red: 0.90, green: 0.90, blue: 0.92, alpha: 1)
            : NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        textView.insertionPointColor = .controlAccentColor

        scrollView.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView else { return }

        if tv.string != text, !context.coordinator.isInternalEdit {
            context.coordinator.isProgrammaticChange = true
            tv.textStorage?.setAttributedString(NSAttributedString(string: text))
            tv.undoManager?.removeAllActions()
            context.coordinator.isProgrammaticChange = false
        }

        tv.font = NSFont.monospacedSystemFont(ofSize: max(12, min(32, fontSize)), weight: .regular)

        let dark = NSApp.effectiveAppearance.name == .darkAqua || NSApp.effectiveAppearance.name == .vibrantDark
        tv.backgroundColor = dark
            ? NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
            : NSColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1)
        tv.textColor = dark
            ? NSColor(red: 0.90, green: 0.90, blue: 0.92, alpha: 1)
            : NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        tv.insertionPointColor = .controlAccentColor
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        fileprivate var isInternalEdit = false
        fileprivate var isProgrammaticChange = false
        fileprivate weak var textView: NSTextView?
        fileprivate weak var scrollView: NSScrollView?

        init(text: Binding<String>) {
            self._text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            if isProgrammaticChange { return }
            isInternalEdit = true
            text = tv.string
            isInternalEdit = false
        }
    }
}
