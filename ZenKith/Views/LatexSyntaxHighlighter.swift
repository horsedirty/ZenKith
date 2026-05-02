import AppKit

// MARK: - LaTeX Syntax Highlighter

final class LatexSyntaxHighlighter {

    // MARK: - Theme

    struct Theme {
        var command: NSColor          // \command
        var environment: NSColor      // \begin{...}, \end{...}
        var mathInline: NSColor       // $...$
        var mathDisplay: NSColor      // $$...$$, \[...\]
        var comment: NSColor          // % ...
        var braces: NSColor           // { }
        var brackets: NSColor         // [ ]
        var sectionCommand: NSColor   // \section, \chapter, etc.
        var textFormatting: NSColor   // \textbf, \textit, etc.
        var specialChar: NSColor      // \&, \%, \$, etc.
        var argumentText: NSColor     // text inside { } after commands
        var defaultText: NSColor
        var defaultFont: NSFont

        static let dark = Theme(
            command: NSColor(red: 0.40, green: 0.72, blue: 1.00, alpha: 1),       // blue
            environment: NSColor(red: 0.95, green: 0.55, blue: 0.30, alpha: 1),   // orange
            mathInline: NSColor(red: 0.60, green: 0.80, blue: 0.40, alpha: 1),    // green
            mathDisplay: NSColor(red: 0.50, green: 0.75, blue: 0.35, alpha: 1),   // darker green
            comment: NSColor(red: 0.50, green: 0.50, blue: 0.55, alpha: 1),       // gray
            braces: NSColor(red: 0.85, green: 0.70, blue: 0.30, alpha: 1),        // gold
            brackets: NSColor(red: 0.70, green: 0.60, blue: 0.85, alpha: 1),      // purple
            sectionCommand: NSColor(red: 1.00, green: 0.60, blue: 0.40, alpha: 1),// coral
            textFormatting: NSColor(red: 0.75, green: 0.55, blue: 0.90, alpha: 1),// violet
            specialChar: NSColor(red: 0.90, green: 0.45, blue: 0.45, alpha: 1),   // red
            argumentText: NSColor(red: 0.85, green: 0.75, blue: 0.55, alpha: 1),  // warm tan
            defaultText: NSColor(red: 0.92, green: 0.92, blue: 0.94, alpha: 1),
            defaultFont: .monospacedSystemFont(ofSize: 13, weight: .regular)
        )

        static let light = Theme(
            command: NSColor(red: 0.10, green: 0.35, blue: 0.70, alpha: 1),
            environment: NSColor(red: 0.75, green: 0.35, blue: 0.10, alpha: 1),
            mathInline: NSColor(red: 0.20, green: 0.55, blue: 0.15, alpha: 1),
            mathDisplay: NSColor(red: 0.15, green: 0.50, blue: 0.10, alpha: 1),
            comment: NSColor(red: 0.45, green: 0.45, blue: 0.50, alpha: 1),
            braces: NSColor(red: 0.60, green: 0.45, blue: 0.10, alpha: 1),
            brackets: NSColor(red: 0.45, green: 0.30, blue: 0.65, alpha: 1),
            sectionCommand: NSColor(red: 0.70, green: 0.25, blue: 0.10, alpha: 1),
            textFormatting: NSColor(red: 0.50, green: 0.25, blue: 0.70, alpha: 1),
            specialChar: NSColor(red: 0.75, green: 0.15, blue: 0.15, alpha: 1),
            argumentText: NSColor(red: 0.55, green: 0.40, blue: 0.15, alpha: 1),
            defaultText: NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1),
            defaultFont: .monospacedSystemFont(ofSize: 13, weight: .regular)
        )
    }

    // MARK: - Token

    private enum TokenType {
        case comment
        case mathDisplay
        case mathInline
        case environment
        case sectionCommand
        case textFormatting
        case specialChar
        case command
        case braces
        case brackets
    }

    // MARK: - Properties

    var theme: Theme {
        didSet { cachedPatterns = nil }
    }

    private var cachedPatterns: [(NSRegularExpression, TokenType)]?
    private var isHighlighting = false

    // MARK: - Known Command Sets

    private static let sectionCommands: Set<String> = [
        "part", "chapter", "section", "subsection", "subsubsection",
        "paragraph", "subparagraph", "title", "author", "date",
        "maketitle", "tableofcontents", "listoffigures", "listoftables"
    ]

    private static let formattingCommands: Set<String> = [
        "textbf", "textit", "texttt", "textsc", "textsf", "textrm", "textsl",
        "emph", "underline", "overline", "sout",
        "bfseries", "itshape", "ttfamily", "scshape",
        "tiny", "scriptsize", "footnotesize", "small", "normalsize",
        "large", "Large", "LARGE", "huge", "Huge",
        "centering", "raggedright", "raggedleft"
    ]

    private static let specialChars: Set<String> = [
        "\\&", "\\%", "\\$", "\\#", "\\_", "\\{", "\\}",
        "\\~", "\\^", "\\\\", "\\newline", "\\linebreak"
    ]

    // MARK: - Init

    init(theme: Theme? = nil) {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        self.theme = theme ?? (isDark ? .dark : .light)
    }

    // MARK: - Public API

    /// 对整个文本存储进行语法高亮
    func highlight(_ textStorage: NSTextStorage) {
        guard !isHighlighting else { return }
        isHighlighting = true
        defer { isHighlighting = false }

        let fullRange = NSRange(location: 0, length: textStorage.length)
        let text = textStorage.string

        textStorage.beginEditing()

        // 重置默认样式
        let defaultAttrs: [NSAttributedString.Key: Any] = [
            .font: theme.defaultFont,
            .foregroundColor: theme.defaultText
        ]
        textStorage.setAttributes(defaultAttrs, range: fullRange)

        // 按优先级从低到高应用高亮（后应用的覆盖先应用的）
        applyTokenHighlighting(to: textStorage, text: text)

        textStorage.endEditing()
    }

    /// 增量高亮：只处理编辑影响的行范围
    func highlightEdited(_ textStorage: NSTextStorage, editedRange: NSRange) {
        guard !isHighlighting else { return }
        isHighlighting = true
        defer { isHighlighting = false }

        let text = textStorage.string as NSString
        let totalLength = textStorage.length
        guard totalLength > 0 else { return }

        // 扩展到完整行范围，并额外包含前后各一行以处理跨行结构
        let clampedRange = NSRange(
            location: min(editedRange.location, totalLength - 1),
            length: min(editedRange.length, totalLength - editedRange.location)
        )
        var lineRange = text.lineRange(for: clampedRange)

        // 向前扩展一行
        if lineRange.location > 0 {
            let prevLineRange = text.lineRange(for: NSRange(location: lineRange.location - 1, length: 0))
            lineRange = NSUnionRange(prevLineRange, lineRange)
        }
        // 向后扩展一行
        let endLoc = NSMaxRange(lineRange)
        if endLoc < totalLength {
            let nextLineRange = text.lineRange(for: NSRange(location: endLoc, length: 0))
            lineRange = NSUnionRange(lineRange, nextLineRange)
        }

        // 安全裁剪
        lineRange = NSIntersectionRange(lineRange, NSRange(location: 0, length: totalLength))
        guard lineRange.length > 0 else { return }

        textStorage.beginEditing()

        // 重置该范围的默认样式
        let defaultAttrs: [NSAttributedString.Key: Any] = [
            .font: theme.defaultFont,
            .foregroundColor: theme.defaultText
        ]
        textStorage.setAttributes(defaultAttrs, range: lineRange)

        // 对该范围内的文本进行高亮
        let substring = text.substring(with: lineRange)
        applyTokenHighlighting(to: textStorage, text: substring, offset: lineRange.location)

        textStorage.endEditing()
    }

    // MARK: - Pattern Building

    private func patterns() -> [(NSRegularExpression, TokenType)] {
        if let cached = cachedPatterns { return cached }

        var result: [(NSRegularExpression, TokenType)] = []

        func add(_ pattern: String, _ type: TokenType, options: NSRegularExpression.Options = []) {
            if let regex = try? NSRegularExpression(pattern: pattern, options: options) {
                result.append((regex, type))
            }
        }

        // 1. 注释（最高优先级，最后绘制以覆盖其他）
        //    匹配 % 开头到行尾，但排除 \%
        add(#"(?<!\\)%.*$"#, .comment, options: .anchorsMatchLines)

        // 2. 数学模式 - display: $$...$$ 或 \[...\]
        add(#"\$\$[\s\S]*?\$\$"#, .mathDisplay)
        add(#"\\\[[\s\S]*?\\\]"#, .mathDisplay)

        // 3. 数学模式 - inline: $...$（非贪婪，不跨行）
        add(#"(?<!\\)\$(?!\$)(?:[^$\\]|\\.)*\$"#, .mathInline)
        // \(...\)
        add(#"\\\(.*?\\\)"#, .mathInline)

        // 4. 环境命令: \begin{...} 和 \end{...}
        add(#"\\(?:begin|end)\s*\{[^}]*\}"#, .environment)

        // 5. 章节命令
        let sectionPattern = Self.sectionCommands.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        add(#"\\(?:"# + sectionPattern + #")(?:\*)?(?=\s*[\[{]|\s*$)"#, .sectionCommand)

        // 6. 文本格式命令
        let fmtPattern = Self.formattingCommands.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        add(#"\\(?:"# + fmtPattern + #")(?=\s*[\[{]|\s*$|\b)"#, .textFormatting)

        // 7. 特殊转义字符: \&, \%, \$ 等
        add(#"\\[&%$#_{}~^]"#, .specialChar)
        add(#"\\(?:newline|linebreak)\b"#, .specialChar)

        // 8. 通用命令: \commandname
        add(#"\\[a-zA-Z@]+"#, .command)

        // 9. 花括号和方括号
        add(#"[{}]"#, .braces)
        add(#"[\[\]]"#, .brackets)

        cachedPatterns = result
        return result
    }

    // MARK: - Token Highlighting

    private func applyTokenHighlighting(to textStorage: NSTextStorage, text: String, offset: Int = 0) {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        // 记录注释区域，其他 token 不应覆盖注释
        var commentRanges: [NSRange] = []

        // 先收集注释范围
        if let commentRegex = try? NSRegularExpression(pattern: #"(?<!\\)%.*$"#, options: .anchorsMatchLines) {
            let matches = commentRegex.matches(in: text, range: fullRange)
            for match in matches {
                commentRanges.append(match.range)
            }
        }

        for (regex, tokenType) in patterns() {
            let matches = regex.matches(in: text, range: fullRange)
            for match in matches {
                let range = match.range
                guard range.location != NSNotFound, range.length > 0 else { continue }

                // 如果不是注释 token，检查是否与注释区域重叠
                if tokenType != .comment {
                    let overlapsComment = commentRanges.contains { NSIntersectionRange($0, range).length > 0 }
                    if overlapsComment { continue }
                }

                let color = colorForToken(tokenType)
                let adjustedRange = NSRange(location: range.location + offset, length: range.length)

                // 安全检查
                guard adjustedRange.location + adjustedRange.length <= textStorage.length else { continue }

                textStorage.addAttribute(.foregroundColor, value: color, range: adjustedRange)

                // 注释使用斜体
                if tokenType == .comment {
                    if let italicFont = NSFontManager.shared.convert(theme.defaultFont, toHaveTrait: .italicFontMask) as NSFont? {
                        textStorage.addAttribute(.font, value: italicFont, range: adjustedRange)
                    }
                }

                // 章节命令加粗
                if tokenType == .sectionCommand {
                    if let boldFont = NSFontManager.shared.convert(theme.defaultFont, toHaveTrait: .boldFontMask) as NSFont? {
                        textStorage.addAttribute(.font, value: boldFont, range: adjustedRange)
                    }
                }
            }
        }
    }

    private func colorForToken(_ type: TokenType) -> NSColor {
        switch type {
        case .comment:        return theme.comment
        case .mathDisplay:    return theme.mathDisplay
        case .mathInline:     return theme.mathInline
        case .environment:    return theme.environment
        case .sectionCommand: return theme.sectionCommand
        case .textFormatting: return theme.textFormatting
        case .specialChar:    return theme.specialChar
        case .command:        return theme.command
        case .braces:         return theme.braces
        case .brackets:       return theme.brackets
        }
    }
}

// MARK: - NSTextStorageDelegate Integration

/// 将此 delegate 设置到 NSTextStorage 上，即可自动在编辑时触发增量高亮
final class LatexHighlightingDelegate: NSObject, NSTextStorageDelegate {

    let highlighter: LatexSyntaxHighlighter

    init(highlighter: LatexSyntaxHighlighter) {
        self.highlighter = highlighter
        super.init()
    }

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        // 只在文字内容变化时触发，忽略纯属性变化
        guard editedMask.contains(.editedCharacters) else { return }

        // 在下一个 run loop 中执行高亮，避免在 textStorage 编辑回调中嵌套编辑
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.highlighter.highlightEdited(textStorage, editedRange: editedRange)
        }
    }
}
