import SwiftUI
import AppKit

// MARK: - 行号 Ruler

private final class LineNumberRuler: NSRulerView {
    var font: NSFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    var rulerTextColor: NSColor = .secondaryLabelColor

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = scrollView?.documentView as? NSTextView,
              let layout = textView.layoutManager,
              let container = textView.textContainer else { return }

        let content = textView.string as NSString
        guard content.length > 0 else { return }

        let visibleRect = scrollView?.contentView.bounds ?? .zero
        let glyphRange = layout.glyphRange(forBoundingRect: visibleRect, in: container)
        let charRange = layout.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        var idx = charRange.location
        if idx >= content.length { return }

        var lineNo = 1
        if idx > 0 {
            let prefix = content.substring(to: min(idx, content.length))
            lineNo = prefix.components(separatedBy: "\n").count
        }

        while idx < NSMaxRange(charRange) && idx < content.length {
            let lineRange = content.lineRange(for: NSRange(location: idx, length: 0))
            let lineGlyphRange = layout.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            let lineRect = layout.boundingRect(forGlyphRange: lineGlyphRange, in: container)

            let str = "\(lineNo)"
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: rulerTextColor]
            let size = str.size(withAttributes: attrs)
            let y = lineRect.origin.y + (lineRect.height - size.height) / 2
            str.draw(at: NSPoint(x: bounds.width - size.width - 4, y: y), withAttributes: attrs)

            idx = NSMaxRange(lineRange)
            lineNo += 1
        }
    }
}


// MARK: - EditorView

struct EditorView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: Double
    var language: EditorLanguage = .markdown

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, fontSize: fontSize, language: language)
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
        textView.isFieldEditor = false

        updateFont(textView, fontSize: fontSize)
        textView.textContainerInset = NSSize(width: 8, height: 16)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.lineFragmentPadding = 8

        let ruler = LineNumberRuler(scrollView: scrollView, orientation: .verticalRuler)
        ruler.ruleThickness = 40
        ruler.clientView = textView
        scrollView.verticalRulerView = ruler
        scrollView.rulersVisible = true
        ruler.font = NSFont.monospacedSystemFont(ofSize: max(10, fontSize - 3), weight: .regular)

        scrollView.documentView = textView
        updateAppearance(textView)

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.lineNumberRuler = ruler

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if textView.string != text && !context.coordinator.isInternalEdit {
            context.coordinator.isProgrammaticChange = true
            textView.string = text
            context.coordinator.isProgrammaticChange = false
        }
        updateFont(textView, fontSize: fontSize)
        updateAppearance(textView)
        context.coordinator.fontSize = fontSize
        context.coordinator.language = language
        if let ruler = scrollView.verticalRulerView as? LineNumberRuler {
            ruler.font = NSFont.monospacedSystemFont(ofSize: max(10, fontSize - 3), weight: .regular)
            ruler.needsDisplay = true
        }
    }

    private func updateFont(_ textView: NSTextView, fontSize: Double) {
        textView.font = NSFont.monospacedSystemFont(ofSize: max(12, min(32, fontSize)), weight: .regular)
    }

    private func updateAppearance(_ textView: NSTextView) {
        let dark = NSApp.effectiveAppearance.name == .darkAqua || NSApp.effectiveAppearance.name == .vibrantDark
        textView.backgroundColor = dark ? NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1) : NSColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1)
        textView.textColor = dark ? NSColor(red: 0.90, green: 0.90, blue: 0.92, alpha: 1) : NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        textView.insertionPointColor = .controlAccentColor
        (textView.enclosingScrollView?.verticalRulerView as? LineNumberRuler)?.rulerTextColor = dark ? NSColor(white: 0.55, alpha: 1) : NSColor(white: 0.45, alpha: 1)
    }

    // MARK: - LaTeX 补全数据

    static let latexCompletions: [(String, String)] = [
        ("\\documentclass{article}","\\documentclass{article}"), ("\\usepackage{}","\\usepackage{"),
        ("\\section{}","\\section{}"), ("\\subsection{}","\\subsection{}"), ("\\subsubsection{}","\\subsubsection{}"),
        ("\\paragraph{}","\\paragraph{}"), ("\\chapter{}","\\chapter{}"),
        ("\\begin{equation}","\\begin{equation}\n    \n\\end{equation}"),
        ("\\begin{align}","\\begin{align}\n    \n\\end{align}"), ("\\begin{align*}","\\begin{align*}\n    \n\\end{align*}"),
        ("\\begin{cases}","\\begin{cases}\n    \n\\end{cases}"),
        ("\\begin{pmatrix}","\\begin{pmatrix}\n    \n\\end{pmatrix}"), ("\\begin{bmatrix}","\\begin{bmatrix}\n    \n\\end{bmatrix}"),
        ("\\begin{itemize}","\\begin{itemize}\n  \\item \n\\end{itemize}"),
        ("\\begin{enumerate}","\\begin{enumerate}\n  \\item \n\\end{enumerate}"),
        ("\\begin{description}","\\begin{description}\n  \\item[] \n\\end{description}"),
        ("\\begin{figure}[htbp]","\\begin{figure}[htbp]\n  \\centering\n  \\includegraphics{}\n  \\caption{}\n  \\label{}\n\\end{figure}"),
        ("\\begin{table}[htbp]","\\begin{table}[htbp]\n  \\centering\n  \\caption{}\n  \\begin{tabular}{}\n    \n  \\end{tabular}\n\\end{table}"),
        ("\\begin{theorem}","\\begin{theorem}\n    \n\\end{theorem}"), ("\\begin{lemma}","\\begin{lemma}\n    \n\\end{lemma}"),
        ("\\begin{proof}","\\begin{proof}\n    \n\\end{proof}"), ("\\begin{definition}","\\begin{definition}\n    \n\\end{definition}"),
        ("\\begin{corollary}","\\begin{corollary}\n    \n\\end{corollary}"),
        ("\\begin{remark}","\\begin{remark}\n    \n\\end{remark}"), ("\\begin{example}","\\begin{example}\n    \n\\end{example}"),
        ("\\begin{abstract}","\\begin{abstract}\n    \n\\end{abstract}"),
        ("\\begin{center}","\\begin{center}\n    \n\\end{center}"), ("\\begin{minipage}{}","\\begin{minipage}{}\n    \n\\end{minipage}"),
        ("\\textbf{}","\\textbf{}"), ("\\textit{}","\\textit{}"), ("\\texttt{}","\\texttt{}"), ("\\textsf{}","\\textsf{}"),
        ("\\emph{}","\\emph{}"), ("\\underline{}","\\underline{}"),
        ("\\frac{}{}","\\frac{}{}"), ("\\sqrt{}","\\sqrt{}"), ("\\sqrt[]{}","\\sqrt[]{}"),
        ("\\overline{}","\\overline{}"), ("\\hat{}","\\hat{}"), ("\\bar{}","\\bar{}"), ("\\tilde{}","\\tilde{}"), ("\\vec{}","\\vec{}"),
        ("\\sum","\\sum"), ("\\prod","\\prod"), ("\\int","\\int"), ("\\iint","\\iint"), ("\\oint","\\oint"),
        ("\\lim","\\lim"), ("\\infty","\\infty"), ("\\partial","\\partial"), ("\\nabla","\\nabla"),
        ("\\forall","\\forall"), ("\\exists","\\exists"),
        ("\\sin","\\sin"), ("\\cos","\\cos"), ("\\tan","\\tan"), ("\\log","\\log"), ("\\ln","\\ln"), ("\\exp","\\exp"),
        ("\\alpha","\\alpha "),("\\beta","\\beta "),("\\gamma","\\gamma "),("\\delta","\\delta "),("\\epsilon","\\epsilon "),
        ("\\zeta","\\zeta "),("\\eta","\\eta "),("\\theta","\\theta "),("\\iota","\\iota "),("\\kappa","\\kappa "),
        ("\\lambda","\\lambda "),("\\mu","\\mu "),("\\nu","\\nu "),("\\xi","\\xi "),("\\pi","\\pi "),
        ("\\rho","\\rho "),("\\sigma","\\sigma "),("\\tau","\\tau "),("\\upsilon","\\upsilon "),("\\phi","\\phi "),
        ("\\chi","\\chi "),("\\psi","\\psi "),("\\omega","\\omega "),
        ("\\Gamma","\\Gamma "),("\\Delta","\\Delta "),("\\Theta","\\Theta "),("\\Lambda","\\Lambda "),
        ("\\Xi","\\Xi "),("\\Pi","\\Pi "),("\\Sigma","\\Sigma "),("\\Upsilon","\\Upsilon "),
        ("\\Phi","\\Phi "),("\\Psi","\\Psi "),("\\Omega","\\Omega "),
        ("\\times","\\times "),("\\div","\\div "),("\\pm","\\pm "),("\\mp","\\mp "),("\\cdot","\\cdot "),
        ("\\equiv","\\equiv "),("\\approx","\\approx "),("\\sim","\\sim "),("\\propto","\\propto "),
        ("\\neq","\\neq "),("\\leq","\\leq "),("\\geq","\\geq "),("\\ll","\\ll "),("\\gg","\\gg "),
        ("\\subset","\\subset "),("\\supset","\\supset "),("\\subseteq","\\subseteq "),
        ("\\in","\\in "),("\\notin","\\notin "),("\\perp","\\perp "),
        ("\\rightarrow","\\rightarrow "),("\\leftarrow","\\leftarrow "),
        ("\\Rightarrow","\\Rightarrow "),("\\Leftarrow","\\Leftarrow "),("\\mapsto","\\mapsto "),
        ("\\cdots","\\cdots "),("\\ldots","\\ldots "),("\\vdots","\\vdots "),("\\ddots","\\ddots "),
        ("\\emptyset","\\emptyset "),("\\triangle","\\triangle "),("\\angle","\\angle "),
        ("\\ref{}","\\ref{}"),("\\eqref{}","\\eqref{}"),("\\cite{}","\\cite{}"),("\\label{}","\\label{}"),
        ("\\footnote{}","\\footnote{}"),("\\bibliography{}","\\bibliography{}"),("\\bibliographystyle{}","\\bibliographystyle{}"),
        ("\\includegraphics{}","\\includegraphics{}"),
        ("\\item ","\\item "),("\\caption{}","\\caption{}"),("\\centering","\\centering"),
        ("\\maketitle","\\maketitle"),("\\tableofcontents","\\tableofcontents"),("\\newpage","\\newpage"),
        ("\\hline","\\hline"),("\\today","\\today"),("\\vspace{}","\\vspace{}"),("\\hspace{}","\\hspace{}"),
    ]

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate, NSTableViewDataSource, NSTableViewDelegate {
        @Binding var text: String
        var isInternalEdit = false
        var isProgrammaticChange = false
        fileprivate weak var textView: NSTextView?
        fileprivate weak var scrollView: NSScrollView?
        fileprivate weak var lineNumberRuler: LineNumberRuler?
        fileprivate var language: EditorLanguage
        fileprivate var fontSize: Double

        // 补全
        private var panel: NSPanel?
        private var table: NSTableView?
        private var completions: [(String, String)] = []
        private var compRange = NSRange(location: 0, length: 0)
        private var compActive = false

        // 括号
        private var hlRanges: [NSRange] = []

        init(text: Binding<String>, fontSize: Double, language: EditorLanguage) {
            self._text = text
            self.fontSize = fontSize
            self.language = language
        }

        // MARK: - 文本变更

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            isInternalEdit = true

            // 合并多次变更，延迟到下一 runloop 推送，彻底避开 SwiftUI 渲染周期
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(syncToBinding), object: tv)
            perform(#selector(syncToBinding), with: tv, afterDelay: 0)

            // 补全 + 行号立即更新（只读操作，不触发状态变更）
            if language == .latex, !isProgrammaticChange {
                handleCompletion(tv)
            }
            lineNumberRuler?.needsDisplay = true
        }

        @objc private func syncToBinding(_ tv: NSTextView) {
            text = tv.string
            isInternalEdit = false
        }

        // MARK: - 选区变更 → 括号高亮

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = textView else { return }
            clearHL(tv)
            highlightBracket(tv)
        }

        // MARK: - 补全逻辑

        private func handleCompletion(_ tv: NSTextView) {
            let s = tv.string as NSString
            let sel = tv.selectedRange()
            guard sel.location > 0, sel.location <= s.length, s.length > 0 else { dismissComp(); return }

            let before = s.substring(to: sel.location)
            guard let slashIdx = before.lastIndex(of: "\\") else { dismissComp(); return }

            let after = String(before[slashIdx...])
            let cmd = String(after.dropFirst())

            if !cmd.isEmpty && !cmd.allSatisfy({ $0.isLetter || $0 == "@" }) { dismissComp(); return }

            let q = cmd.lowercased()
            let result = q.isEmpty
                ? Array(EditorView.latexCompletions.prefix(50))
                : EditorView.latexCompletions.filter { $0.0.lowercased().contains(q) }

            guard !result.isEmpty else { dismissComp(); return }

            let loc = before.distance(from: before.startIndex, to: slashIdx)
            guard loc <= sel.location, sel.location - loc > 0 else { dismissComp(); return }
            compRange = NSRange(location: loc, length: sel.location - loc)

            if result.count != completions.count || (result.first?.0 ?? "") != (completions.first?.0 ?? "") {
                completions = result
                table?.reloadData()
                if !completions.isEmpty { table?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
            }

            if !compActive { showPanel(tv) }
        }

        private func dismissComp() {
            compActive = false
            completions = []
            panel?.orderOut(nil)
        }

        private func showPanel(_ tv: NSTextView) {
            if panel == nil {
                let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                p.isFloatingPanel = true; p.backgroundColor = .controlBackgroundColor; p.hasShadow = true; p.level = .floating
                p.collectionBehavior = [.transient, .ignoresCycle]

                let t = NSTableView(frame: .zero)
                t.dataSource = self; t.delegate = self; t.headerView = nil; t.rowHeight = 22
                t.intercellSpacing = .zero; t.selectionHighlightStyle = .regular; t.backgroundColor = .clear
                t.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c")))
                t.tableColumns[0].width = 310

                let sc = NSScrollView(frame: .zero)
                sc.documentView = t; sc.hasVerticalScroller = true; sc.autohidesScrollers = true
                sc.borderType = .noBorder; sc.drawsBackground = false
                p.contentView = sc
                table = t; panel = p
            }

            if let lm = tv.layoutManager, let tc = tv.textContainer {
                let gr = lm.glyphRange(forCharacterRange: compRange, actualCharacterRange: nil)
                let r = lm.boundingRect(forGlyphRange: gr, in: tc)
                let sr = tv.window?.convertToScreen(tv.convert(r, to: nil)) ?? .zero
                panel?.setFrame(NSRect(x: sr.origin.x, y: sr.origin.y - 210, width: 320, height: 200), display: false)
            }

            panel?.orderFront(nil)
            compActive = true
            table?.reloadData()
            if !completions.isEmpty { table?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        }

        // MARK: - 补全接受

        private func accept(_ tv: NSTextView) {
            guard compActive, let t = table, t.selectedRow >= 0, t.selectedRow < completions.count else { return }
            let ins = completions[t.selectedRow].1
            dismissComp()

            let maxLoc = tv.string.count
            let safeRange = NSRange(location: min(compRange.location, maxLoc), length: min(compRange.length, maxLoc - min(compRange.location, maxLoc)))
            guard safeRange.location + safeRange.length <= tv.string.count else { return }

            isProgrammaticChange = true
            if tv.shouldChangeText(in: safeRange, replacementString: ins) {
                tv.replaceCharacters(in: safeRange, with: ins)
                tv.didChangeText()
            }
            isProgrammaticChange = false

            if let r = ins.range(of: "{}") {
                let off = ins.distance(from: ins.startIndex, to: r.lowerBound) + 1
                tv.setSelectedRange(NSRange(location: safeRange.location + off, length: 0))
            } else {
                tv.setSelectedRange(NSRange(location: safeRange.location + ins.count, length: 0))
            }
            highlightBracket(tv)
        }

        private func navCompletion(_ d: Int) {
            guard let t = table, !completions.isEmpty else { return }
            let row = max(0, min(completions.count - 1, max(0, t.selectedRow) + d))
            t.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            t.scrollRowToVisible(row)
        }

        // MARK: - TableView

        func numberOfRows(in tableView: NSTableView) -> Int { completions.count }

        func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
            (row >= 0 && row < completions.count) ? completions[row].0 : nil
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let id = NSUserInterfaceItemIdentifier("c")
            var cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView
            if cell == nil {
                cell = NSTableCellView(); cell!.identifier = id
                let tf = NSTextField(frame: NSRect(x: 6, y: 2, width: 300, height: 18))
                tf.isBezeled = false; tf.drawsBackground = false; tf.isEditable = false
                tf.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
                tf.lineBreakMode = .byTruncatingTail
                cell!.textField = tf; cell!.addSubview(tf)
            }
            if row >= 0, row < completions.count { cell?.textField?.stringValue = completions[row].0 }
            return cell
        }

        // MARK: - 键盘

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if compActive {
                if commandSelector == #selector(NSResponder.moveUp(_:)) { navCompletion(-1); return true }
                if commandSelector == #selector(NSResponder.moveDown(_:)) { navCompletion(1); return true }
                if commandSelector == #selector(NSResponder.insertNewline(_:)) { accept(textView); return true }
                if commandSelector == #selector(NSResponder.cancelOperation(_:)) { dismissComp(); return true }
                return false
            }

            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                if language == .latex {
                    let sel = textView.selectedRange()
                    if sel.location > 0 {
                        let ch = (textView.string as NSString).character(at: sel.location - 1)
                        let space = (" " as NSString).character(at: 0)
                        let newline = ("\n" as NSString).character(at: 0)
                        if ch != space && ch != newline && ch != 9 { // 9 = tab
                            handleCompletion(textView)
                            return true
                        }
                    }
                }
                textView.insertText("\t", replacementRange: textView.selectedRange())
                return true
            }

            if commandSelector == #selector(NSResponder.insertNewline(_:)) && language == .latex {
                textView.insertText("\n", replacementRange: textView.selectedRange())
                autoIndent(textView)
                lineNumberRuler?.needsDisplay = true
                return true
            }

            return false
        }

        // MARK: - 缩进

        private func autoIndent(_ tv: NSTextView) {
            let s = tv.string as NSString
            let sel = tv.selectedRange()
            guard sel.location > 0, sel.location <= s.length else { return }

            var lineStart = 0
            s.getLineStart(nil, end: nil, contentsEnd: &lineStart, for: NSRange(location: min(sel.location - 1, s.length - 1), length: 0))

            var prevStart = 0
            if lineStart > 0 {
                s.getLineStart(nil, end: nil, contentsEnd: &prevStart, for: NSRange(location: lineStart - 1, length: 0))
            }
            let prevLine = s.substring(with: NSRange(location: prevStart, length: lineStart - prevStart))

            var indent = ""
            for ch in prevLine { if ch == " " || ch == "\t" { indent.append(ch) } else { break } }

            let tr = prevLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if tr.contains("\\begin{") { indent += "    " }
            if tr.hasPrefix("\\item") {
                if tr == "\\item" { indent += "  " }
            }

            guard !indent.isEmpty else { return }
            tv.insertText(indent, replacementRange: tv.selectedRange())
        }

        // MARK: - 括号高亮

        private let pairs: [Character: Character] = ["{": "}", "}": "{", "(": ")", ")": "(", "[": "]", "]": "["]

        private func highlightBracket(_ tv: NSTextView) {
            let s = tv.string as NSString
            let sel = tv.selectedRange()
            guard sel.length == 0, s.length > 0 else { return }

            var pos = sel.location
            var ch: Character?
            if sel.location > 0, sel.location <= s.length {
                let c = Character(s.substring(with: NSRange(location: sel.location - 1, length: 1)))
                if pairs[c] != nil { ch = c; pos = sel.location - 1 }
            }
            if ch == nil, sel.location < s.length {
                let c = Character(s.substring(with: NSRange(location: sel.location, length: 1)))
                if pairs[c] != nil { ch = c; pos = sel.location }
            }
            guard let t = ch, let m = pairs[t] else { return }

            let open = (t == "{" || t == "(" || t == "[")
            guard let mPos = findMatch(s, from: pos, open: open, target: t, match: m) else { return }

            let y = NSColor.systemYellow.withAlphaComponent(0.35)
            let r1 = NSRange(location: pos, length: 1)
            let r2 = NSRange(location: mPos, length: 1)
            tv.layoutManager?.addTemporaryAttribute(.backgroundColor, value: y, forCharacterRange: r1)
            tv.layoutManager?.addTemporaryAttribute(.backgroundColor, value: y, forCharacterRange: r2)
            hlRanges = [r1, r2]
        }

        private func findMatch(_ s: NSString, from pos: Int, open: Bool, target: Character, match: Character) -> Int? {
            var d = 0
            if open {
                for i in pos..<s.length {
                    let c = Character(s.substring(with: NSRange(location: i, length: 1)))
                    if c == target { d += 1 } else if c == match { d -= 1; if d == 0 { return i } }
                }
            } else {
                for i in (0..<pos).reversed() {
                    let c = Character(s.substring(with: NSRange(location: i, length: 1)))
                    if c == target { d += 1 } else if c == match { d -= 1; if d == 0 { return i } }
                }
            }
            return nil
        }

        private func clearHL(_ tv: NSTextView) {
            for r in hlRanges { tv.layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: r) }
            hlRanges = []
        }
    }
}
