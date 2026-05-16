import SwiftUI
import AppKit

struct EditorView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: Double
    var language: EditorLanguage = .markdown
    
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, language: language)
    }
    
    func makeNSView(context: Context) -> NSView {
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
        context.coordinator.setupContextMenu()
        
        // 连接语法高亮
        context.coordinator.setupHighlighting(for: textView)

        let outerContainer = NSView(frame: .zero)
        outerContainer.addSubview(scrollView)
        scrollView.frame = outerContainer.bounds
        scrollView.autoresizingMask = [.width, .height]
        context.coordinator.setupFindBar(in: outerContainer)
        context.coordinator.setupFindBarShortcut()
        return outerContainer
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let scrollView = nsView.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView,
              let tv = scrollView.documentView as? NSTextView else { return }

        let dark = NSApp.effectiveAppearance.name == .darkAqua || NSApp.effectiveAppearance.name == .vibrantDark
        let fontSizeChanged = abs(context.coordinator.lastFontSize - fontSize) > 0.1
        let darkChanged = context.coordinator.lastDark != dark

        if fontSizeChanged || darkChanged {
            let font = NSFont.monospacedSystemFont(ofSize: max(12, min(32, fontSize)), weight: .regular)
            tv.font = font
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

            context.coordinator.lastFontSize = fontSize
            context.coordinator.lastDark = dark
        }
        
        // 外部文本变更
        var textDidChange = false
        if tv.string != text, !context.coordinator.isInternalEdit {
            if tv.hasMarkedText() {
                // IME composition in progress — do NOT overwrite text storage.
                // The coordinator's textDidChange will flush pendingText once composition commits.
                return
            } else if let pending = context.coordinator.pendingText, pending != text {
                context.coordinator.isProgrammaticChange = true
                text = pending
                context.coordinator.pendingText = nil
                context.coordinator.isProgrammaticChange = false
            } else {
                context.coordinator.isProgrammaticChange = true
                tv.textStorage?.setAttributedString(NSAttributedString(string: text))
                tv.undoManager?.removeAllActions()
                context.coordinator.isProgrammaticChange = false
            }
            textDidChange = true
        }
        
        // 语言切换或外观变化时更新高亮器（在视觉属性之后执行）
        context.coordinator.updateHighlighterIfNeeded(language: language, dark: dark, tv: tv, fontSize: fontSize)
        
        // 外部文本变更后补充全量高亮（updateHighlighterIfNeeded 可能因无主题/语言变化而跳过）
        if textDidChange {
            context.coordinator.applyFullHighlightIfNeeded(to: tv)
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
        fileprivate var lineHighlightLayer: CAShapeLayer?
        fileprivate var pendingText: String?
        fileprivate var lastFontSize: Double = 0
        fileprivate var lastDark: Bool = false
        fileprivate weak var findBarContainer: NSView?
        fileprivate var findBarHost: NSView?
        fileprivate var showFindBar = false
        
        let completionEngine = LatexCompletionEngine()

        func setupContextMenu() {
            guard let tv = textView else { return }
            let menu = NSMenu()

            let sendItem = NSMenuItem(
                title: "发送选中内容给 AI",
                action: #selector(sendSelectionToAI),
                keyEquivalent: "e"
            )
            sendItem.keyEquivalentModifierMask = [.command, .shift]
            menu.addItem(sendItem)
            menu.addItem(.separator())

            let copyItem = NSMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
            copyItem.keyEquivalentModifierMask = .command
            menu.addItem(copyItem)

            let pasteItem = NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
            pasteItem.keyEquivalentModifierMask = .command
            menu.addItem(pasteItem)

            tv.menu = menu
        }

        @objc private func sendSelectionToAI() {
            guard let tv = textView else { return }
            let selectedText: String
            if tv.selectedRange().length > 0 {
                selectedText = (tv.string as NSString).substring(with: tv.selectedRange())
            } else {
                selectedText = tv.string
            }
            NotificationCenter.default.post(
                name: .sendSelectionToAI,
                object: nil,
                userInfo: ["text": selectedText]
            )
        }
        
        fileprivate var completionPopover: CompletionPopover?
        
        // 语法高亮
        private let syntaxHighlighter = LatexSyntaxHighlighter()
        private var highlightingDelegate: LatexHighlightingDelegate?
        private var lastHighlightedDark: Bool?
        
        init(text: Binding<String>, language: EditorLanguage) {
            self._text = text
            self.language = language
            super.init()

            NotificationCenter.default.addObserver(
                forName: .scrollToLine,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleScrollToLine(notification)
            }

            NotificationCenter.default.addObserver(
                forName: .bibKeysDidUpdate,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                if let keys = notification.userInfo?["keys"] as? [String] {
                    Task { @MainActor [weak self] in
                        self?.completionEngine.setCiteKeys(keys)
                    }
                }
            }

            NotificationCenter.default.addObserver(
                forName: .refLabelsDidUpdate,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                if let labels = notification.userInfo?["labels"] as? [String] {
                    Task { @MainActor [weak self] in
                        self?.completionEngine.setRefLabels(labels)
                    }
                }
            }
        }
        
        // MARK: - Syntax Highlighting Setup
        
        func setupHighlighting(for textView: NSTextView) {
            let delegate = LatexHighlightingDelegate(highlighter: syntaxHighlighter)
            self.highlightingDelegate = delegate
            
            if language == .latex {
                textView.textStorage?.delegate = delegate
                if let ts = textView.textStorage {
                    syntaxHighlighter.highlight(ts)
                }
            }
        }
        
        func applyFullHighlightIfNeeded(to textView: NSTextView) {
            guard language == .latex, let ts = textView.textStorage else { return }
            syntaxHighlighter.highlight(ts)
        }
        
        func updateHighlighterIfNeeded(language: EditorLanguage, dark: Bool, tv: NSTextView, fontSize: Double) {
            let themeChanged = (lastHighlightedDark != dark)
            let languageChanged = (self.language != language)
            
            if languageChanged || themeChanged {
                lastHighlightedDark = dark
                
                syntaxHighlighter.theme = dark ? .dark : .light
                syntaxHighlighter.theme.defaultFont = .monospacedSystemFont(
                    ofSize: max(12, min(32, fontSize)), weight: .regular
                )
                
                if language == .latex {
                    if tv.textStorage?.delegate !== highlightingDelegate {
                        tv.textStorage?.delegate = highlightingDelegate
                    }
                    if let ts = tv.textStorage {
                        syntaxHighlighter.highlight(ts)
                    }
                } else {
                    if tv.textStorage?.delegate === highlightingDelegate {
                        tv.textStorage?.delegate = nil
                    }
                    if let ts = tv.textStorage {
                        let fullRange = NSRange(location: 0, length: ts.length)
                        let defaultAttrs: [NSAttributedString.Key: Any] = [
                            .font: NSFont.monospacedSystemFont(ofSize: max(12, min(32, fontSize)), weight: .regular),
                            .foregroundColor: dark
                            ? NSColor(red: 0.90, green: 0.90, blue: 0.92, alpha: 1)
                            : NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
                        ]
                        ts.beginEditing()
                        ts.setAttributes(defaultAttrs, range: fullRange)
                        ts.endEditing()
                    }
                }
            }
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

            if tv.hasMarkedText() {
                pendingText = tv.string
                return
            }

            isInternalEdit = true
            text = tv.string
            pendingText = nil
            isInternalEdit = false
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
            
            var rect = textView.firstRect(forCharacterRange: range, actualRange: nil)
            
            if rect.origin.x == .infinity || rect.width < 0 {
                let font = textView.font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                
                let layout = textView.layoutManager
                let container = textView.textContainer
                if let layout = layout, let container = container {
                    let glyphIdx = layout.glyphIndexForCharacter(at: max(0, charIndex - 1))
                    let lineRect = layout.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil)
                    rect = NSRect(x: lineRect.minX, y: lineRect.minY, width: 1, height: lineRect.height)
                    rect = textView.convert(rect, to: nil)
                    if let window = textView.window {
                        rect = window.convertToScreen(rect)
                    }
                }
            }
            
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

        // MARK: - Scroll to Line

        @objc private func handleScrollToLine(_ notification: Notification) {
            guard let lineNumber = notification.userInfo?["line"] as? Int,
                  let tv = textView else { return }

            let text = tv.string as NSString
            let lines = text.components(separatedBy: "\n")
            var charCount = 0
            for i in 0..<min(lineNumber - 1, lines.count) {
                charCount += lines[i].count + 1
            }
            let loc = min(charCount, text.length)
            let range = NSRange(location: loc, length: 0)
            tv.scrollRangeToVisible(range)
            tv.setSelectedRange(range)
            tv.window?.makeFirstResponder(tv)

            highlightLine(lineNumber)
        }

        // MARK: - Find Bar

        func setupFindBar(in container: NSView) {
            self.findBarContainer = container
        }

        func setupFindBarShortcut() {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let tv = self.textView,
                      tv.window?.firstResponder == tv else { return event }
                let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if event.charactersIgnoringModifiers == "f" && mods == .command {
                    self.toggleFindBar()
                    return nil
                }
                if event.keyCode == 53 {
                    self.hideFindBar()
                }
                return event
            }
        }

        func toggleFindBar() {
            guard let container = findBarContainer else { return }
            if showFindBar {
                hideFindBar()
                return
            }
            showFindBar = true
            let bar = EditorFindBar(
                isVisible: Binding(
                    get: { self.showFindBar },
                    set: { self.showFindBar = $0 }
                ),
                textView: textView
            )
            let host = NSHostingView(rootView: bar)
            host.autoresizingMask = [NSView.AutoresizingMask.width]
            let barHeight: CGFloat = 36
            host.frame = NSRect(x: 0, y: container.bounds.height - barHeight, width: container.bounds.width, height: barHeight)
            container.addSubview(host)
            findBarHost = host
        }

        func hideFindBar() {
            showFindBar = false
            findBarHost?.removeFromSuperview()
            findBarHost = nil
        }

        private func highlightLine(_ lineNumber: Int) {
            guard let tv = textView else { return }
            lineHighlightLayer?.removeFromSuperlayer()

            let text = tv.string as NSString
            let lines = text.components(separatedBy: "\n")
            var charCount = 0
            for i in 0..<min(lineNumber - 1, lines.count) {
                charCount += lines[i].count + 1
            }
            let loc = min(charCount, text.length)
            let range = NSRange(location: loc, length: 0)

            let rect = tv.firstRect(forCharacterRange: range, actualRange: nil)
            guard rect != .zero else { return }

            let layer = CAShapeLayer()
            layer.fillColor = NSColor.systemYellow.withAlphaComponent(0.2).cgColor
            let lineRect = NSRect(x: 0, y: rect.origin.y, width: tv.bounds.width, height: rect.height)
            layer.path = CGPath(rect: lineRect, transform: nil)
            tv.enclosingScrollView?.documentView?.layer?.addSublayer(layer)
            self.lineHighlightLayer = layer

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak layer] in
                layer?.removeFromSuperlayer()
            }
        }
    }
}
