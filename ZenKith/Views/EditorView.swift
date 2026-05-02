import SwiftUI
import AppKit

struct EditorView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: Double
    var language: EditorLanguage = .markdown

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, language: language)
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
        let font = NSFont.monospacedSystemFont(ofSize: max(12, min(32, fontSize)), weight: .regular)
        textView.font = font

        let dark = NSApp.effectiveAppearance.name == .darkAqua || NSApp.effectiveAppearance.name == .vibrantDark
        textView.backgroundColor = dark
            ? NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
            : NSColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1)
        textView.textColor = dark
            ? NSColor(red: 0.90, green: 0.90, blue: 0.92, alpha: 1)
            : NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        textView.insertionPointColor = .controlAccentColor

        scrollView.documentView = textView

        let rulerView = LineNumberRulerView(scrollView: scrollView, orientation: .verticalRuler)
        rulerView.textView = textView
        rulerView.font = font
        rulerView.backgroundColor = dark
            ? NSColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1)
            : NSColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1)
        rulerView.textColor = dark
            ? NSColor(red: 0.45, green: 0.45, blue: 0.50, alpha: 1)
            : NSColor(red: 0.55, green: 0.55, blue: 0.60, alpha: 1)
        rulerView.separatorColor = .separatorColor
        scrollView.verticalRulerView = rulerView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        scrollView.contentView.postsFrameChangedNotifications = true

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.rulerView = rulerView
        context.coordinator.completionPopover = CompletionPopover(engine: context.coordinator.completionEngine)

        context.coordinator.wireCompletionEngine()

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

        let font = NSFont.monospacedSystemFont(ofSize: max(12, min(32, fontSize)), weight: .regular)
        tv.font = font

        let dark = NSApp.effectiveAppearance.name == .darkAqua || NSApp.effectiveAppearance.name == .vibrantDark
        tv.backgroundColor = dark
            ? NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
            : NSColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1)
        tv.textColor = dark
            ? NSColor(red: 0.90, green: 0.90, blue: 0.92, alpha: 1)
            : NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        tv.insertionPointColor = .controlAccentColor

        if let ruler = context.coordinator.rulerView {
            ruler.font = font
            ruler.backgroundColor = dark
                ? NSColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1)
                : NSColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1)
            ruler.textColor = dark
                ? NSColor(red: 0.45, green: 0.45, blue: 0.50, alpha: 1)
                : NSColor(red: 0.55, green: 0.55, blue: 0.60, alpha: 1)
        }

        context.coordinator.language = language
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var language: EditorLanguage

        fileprivate var isInternalEdit = false
        fileprivate var isProgrammaticChange = false
        fileprivate weak var textView: NSTextView?
        fileprivate weak var scrollView: NSScrollView?
        fileprivate weak var rulerView: LineNumberRulerView?

        let completionEngine = LatexCompletionEngine()
        fileprivate var completionPopover: CompletionPopover?

        init(text: Binding<String>, language: EditorLanguage) {
            self._text = text
            self.language = language
        }

        /// Wire engine callback so popover shows/hides at the right time (after async filter completes).
        func wireCompletionEngine() {
            completionEngine.onStateChanged = { [weak self] in
                guard let self, let tv = self.textView else { return }
                if self.completionEngine.state.isActive {
                    self.showCompletions(in: tv)
                } else {
                    self.completionPopover?.hide()
                }
            }
        }

        // MARK: - Text Change

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            if isProgrammaticChange { return }
            isInternalEdit = true
            text = tv.string
            isInternalEdit = false

            if language == .latex {
                DispatchQueue.main.async { [weak self] in
                    guard let self, let tv = self.textView else { return }
                    self.completionEngine.evaluateState(in: tv)
                }
            }
        }

        // MARK: - Selection Change

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = textView, language == .latex else { return }

            let cursorPos = tv.selectedRange().location
            if completionEngine.state.isActive {
                if let range = completionEngine.state.range {
                    if cursorPos < range.location || cursorPos > range.location + range.length {
                        DispatchQueue.main.async { [weak self] in
                            self?.completionEngine.dismiss()
                        }
                    }
                }
                return
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, let tv = self.textView else { return }
                self.completionEngine.evaluateState(in: tv)
            }
        }

        // MARK: - Keyboard Interception

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard language == .latex, completionEngine.state.isActive else { return false }

            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                DispatchQueue.main.async { [weak self] in self?.completionEngine.navigateUp() }
                return true
            case #selector(NSResponder.moveDown(_:)):
                DispatchQueue.main.async { [weak self] in self?.completionEngine.navigateDown() }
                return true
            case #selector(NSResponder.insertNewline(_:)):
                DispatchQueue.main.async { [weak self] in
                    guard let self, let tv = self.textView else { return }
                    self.completionEngine.commit(in: tv)
                }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                DispatchQueue.main.async { [weak self] in
                    self?.completionEngine.dismiss()
                }
                return true
            default:
                return false
            }
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard language == .latex, let replacement = replacementString, completionEngine.state.isActive else { return true }

            if replacement == "\t" {
                DispatchQueue.main.async { [weak self] in
                    guard let self, let tv = self.textView else { return }
                    self.completionEngine.commit(in: tv)
                }
                return false
            }
            return true
        }

        // MARK: - Completion Popover Anchor

        private func showCompletions(in textView: NSTextView) {
            guard let popover = completionPopover else { return }
            guard let range = completionEngine.state.range else { return }

            let anchorRect = cursorAnchorRect(in: textView, atCharIndex: range.location + range.length)
            popover.show(near: anchorRect, in: textView)
        }

        /// Compute the screen-space NSRect for the insertion point after `charIndex`.
        private func cursorAnchorRect(in textView: NSTextView, atCharIndex charIndex: Int) -> NSRect {
            let range = NSRange(location: charIndex, length: 0)
            
            // 使用 Cocoa 系统自带的获取字符屏幕位置的方法，这会自动处理 TextKit 2 和滚动偏移
            var rect = textView.firstRect(forCharacterRange: range, actualRange: nil)
            
            if rect.origin.x == .infinity || rect.width < 0 {
                // 兜底方案：如果上述方法失败（如空行），计算行高
                let font = textView.font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                let lineHeight = font.pointSize * 1.2
                
                // 获取当前光标所在的行大致位置
                let layout = textView.layoutManager
                let container = textView.textContainer
                if let layout = layout, let container = container {
                    let glyphIdx = layout.glyphIndexForCharacter(at: max(0, charIndex - 1))
                    let lineRect = layout.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil)
                    rect = NSRect(x: lineRect.minX, y: lineRect.minY, width: 1, height: lineRect.height)
                    // 转到屏幕坐标
                    rect = textView.convert(rect, to: nil)
                    if let window = textView.window {
                        rect = window.convertToScreen(rect)
                    }
                }
            }
            
            // CompletionPopover 期望的是窗口坐标系的 NSRect
            if let window = textView.window {
                return window.convertFromScreen(rect)
            }
            
            return rect
        }

        private func fallbackCursorRect(in textView: NSTextView, atCharIndex charIndex: Int) -> NSRect {
            let font = textView.font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            let lineHeight = font.boundingRectForFont.height
            let text = textView.string as NSString
            var lineCount = 1
            let limit = min(charIndex, text.length)
            for i in 0..<limit {
                if text.character(at: i) == Character("\n").utf16.first! { lineCount += 1 }
            }
            return NSRect(x: 0, y: CGFloat(lineCount - 1) * lineHeight, width: 0, height: lineHeight)
        }
    }
}
