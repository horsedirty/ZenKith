import AppKit

// MARK: - LaTeX Syntax Highlighter

final class LatexSyntaxHighlighter {

    // MARK: - Theme

    struct Theme {
        var command: NSColor
        var environment: NSColor
        var mathInline: NSColor
        var mathDisplay: NSColor
        var comment: NSColor
        var braces: NSColor
        var brackets: NSColor
        var sectionCommand: NSColor
        var textFormatting: NSColor
        var specialChar: NSColor
        var argumentText: NSColor
        var defaultText: NSColor
        var defaultFont: NSFont

        static let dark = Theme(
            command: NSColor(red: 0.40, green: 0.72, blue: 1.00, alpha: 1),
            environment: NSColor(red: 0.95, green: 0.55, blue: 0.30, alpha: 1),
            mathInline: NSColor(red: 0.60, green: 0.80, blue: 0.40, alpha: 1),
            mathDisplay: NSColor(red: 0.50, green: 0.75, blue: 0.35, alpha: 1),
            comment: NSColor(red: 0.50, green: 0.50, blue: 0.55, alpha: 1),
            braces: NSColor(red: 0.85, green: 0.70, blue: 0.30, alpha: 1),
            brackets: NSColor(red: 0.70, green: 0.60, blue: 0.85, alpha: 1),
            sectionCommand: NSColor(red: 1.00, green: 0.60, blue: 0.40, alpha: 1),
            textFormatting: NSColor(red: 0.75, green: 0.55, blue: 0.90, alpha: 1),
            specialChar: NSColor(red: 0.90, green: 0.45, blue: 0.45, alpha: 1),
            argumentText: NSColor(red: 0.85, green: 0.75, blue: 0.55, alpha: 1),
            defaultText: NSColor(red: 0.92, green: 0.92, blue: 0.94, alpha: 1),
            defaultFont: .monospacedSystemFont(ofSize: 14, weight: .regular)
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
            defaultFont: .monospacedSystemFont(ofSize: 14, weight: .regular)
        )
    }

    // MARK: - Token

    private enum TokenType: Int, Comparable {
        // Higher raw value = higher priority (applied last, wins visually)
        case brackets = 0
        case braces
        case command
        case specialChar
        case textFormatting
        case sectionCommand
        case environment
        case mathInline
        case mathDisplay
        case comment

        static func < (lhs: TokenType, rhs: TokenType) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    // MARK: - Properties

    var theme: Theme {
        didSet { cachedPatterns = nil }
    }

    /// Flag used by the delegate to prevent re-entrant highlighting.
    fileprivate var isApplyingHighlight = false

    private var cachedPatterns: [(NSRegularExpression, TokenType)]?

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

    // MARK: - Init

    init(theme: Theme? = nil) {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        self.theme = theme ?? (isDark ? .dark : .light)
    }

    // MARK: - Public API

    /// Full highlight of the entire text storage. Call on initial load or theme/language change.
    func highlight(_ textStorage: NSTextStorage) {
        let totalLength = textStorage.length
        guard totalLength > 0 else { return }

        isApplyingHighlight = true
        defer { isApplyingHighlight = false }

        let fullRange = NSRange(location: 0, length: totalLength)
        let text = textStorage.string

        textStorage.beginEditing()
        textStorage.setAttributes(defaultAttributes, range: fullRange)
        applyTokenHighlighting(to: textStorage, text: text, offset: 0)
        textStorage.endEditing()
    }

    /// Incremental highlight covering the edited region expanded to full lines.
    /// The caller must ensure `editedRange` is still valid for the current text.
    func highlightLines(containing editedRange: NSRange, in textStorage: NSTextStorage) {
        let totalLength = textStorage.length
        guard totalLength > 0 else { return }

        // Clamp the incoming range to current text length
        let safeLocation = min(editedRange.location, totalLength)
        let safeLength = min(editedRange.length, totalLength - safeLocation)
        let safeRange = NSRange(location: safeLocation, length: safeLength)

        let nsText = textStorage.string as NSString

        // Expand to full lines, plus one line before and after for cross-line constructs
        var lineRange = nsText.lineRange(for: safeRange)

        if lineRange.location > 0 {
            let prevLine = nsText.lineRange(for: NSRange(location: lineRange.location - 1, length: 0))
            lineRange = NSUnionRange(prevLine, lineRange)
        }
        let endLoc = NSMaxRange(lineRange)
        if endLoc < totalLength {
            let nextLine = nsText.lineRange(for: NSRange(location: endLoc, length: 0))
            lineRange = NSUnionRange(lineRange, nextLine)
        }

        lineRange = NSIntersectionRange(lineRange, NSRange(location: 0, length: totalLength))
        guard lineRange.length > 0 else { return }

        isApplyingHighlight = true
        defer { isApplyingHighlight = false }

        let substring = nsText.substring(with: lineRange)

        textStorage.beginEditing()
        textStorage.setAttributes(defaultAttributes, range: lineRange)
        applyTokenHighlighting(to: textStorage, text: substring, offset: lineRange.location)
        textStorage.endEditing()
    }

    // MARK: - Default Attributes

    private var defaultAttributes: [NSAttributedString.Key: Any] {
        [
            .font: theme.defaultFont,
            .foregroundColor: theme.defaultText
        ]
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

        // Order: low priority first. Higher-priority tokens are applied later and overwrite.

        // Braces and brackets
        add(#"[{}]"#, .braces)
        add(#"[\[\]]"#, .brackets)

        // Generic commands: \commandname
        add(#"\\[a-zA-Z@]+"#, .command)

        // Special escape characters: \&, \%, \$ etc.
        add(#"\\[&%$#_{}~^]"#, .specialChar)
        add(#"\\(?:newline|linebreak)\b"#, .specialChar)

        // Text formatting commands
        let fmtPattern = Self.formattingCommands.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        add(#"\\(?:"# + fmtPattern + #")(?=\s*[\[{]|\s*$|\b)"#, .textFormatting)

        // Section commands
        let sectionPattern = Self.sectionCommands.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        add(#"\\(?:"# + sectionPattern + #")(?:\*)?(?=\s*[\[{]|\s*$)"#, .sectionCommand)

        // Environment commands: \begin{...} and \end{...}
        add(#"\\(?:begin|end)\s*\{[^}]*\}"#, .environment)

        // Math inline: $...$ and \(...\)
        add(#"(?<!\\)\$(?!\$)(?:[^$\\]|\\.)*\$"#, .mathInline)
        add(#"\\\(.*?\\\)"#, .mathInline)

        // Math display: $$...$$ and \[...\]
        add(#"\$\$[\s\S]*?\$\$"#, .mathDisplay)
        add(#"\\\[[\s\S]*?\\\]"#, .mathDisplay)

        // Comments (highest priority — applied last, overwrites everything)
        add(#"(?<!\\)%.*$"#, .comment, options: .anchorsMatchLines)

        cachedPatterns = result
        return result
    }

    // MARK: - Token Highlighting

    private func applyTokenHighlighting(to textStorage: NSTextStorage, text: String, offset: Int) {
        let nsText = text as NSString
        let searchRange = NSRange(location: 0, length: nsText.length)
        let storageLength = textStorage.length

        for (regex, tokenType) in patterns() {
            let matches = regex.matches(in: text, range: searchRange)
            for match in matches {
                let range = match.range
                guard range.location != NSNotFound, range.length > 0 else { continue }

                let adjusted = NSRange(location: range.location + offset, length: range.length)
                guard adjusted.location >= 0,
                      adjusted.location + adjusted.length <= storageLength else { continue }

                textStorage.addAttribute(.foregroundColor, value: colorForToken(tokenType), range: adjusted)

                // Comments in italic
                if tokenType == .comment {
                    if let italic = NSFontManager.shared.convert(theme.defaultFont, toHaveTrait: .italicFontMask) as NSFont? {
                        textStorage.addAttribute(.font, value: italic, range: adjusted)
                    }
                }

                // Section commands in bold
                if tokenType == .sectionCommand {
                    if let bold = NSFontManager.shared.convert(theme.defaultFont, toHaveTrait: .boldFontMask) as NSFont? {
                        textStorage.addAttribute(.font, value: bold, range: adjusted)
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

// MARK: - NSTextStorageDelegate for Incremental Highlighting

/// Attach this as the NSTextStorage delegate to get automatic incremental highlighting on edits.
/// Key design: highlighting runs synchronously inside `didProcessEditing` while the
/// `isApplyingHighlight` flag prevents infinite recursion from attribute-only changes.
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
        // Only act on character edits, not our own attribute changes
        guard editedMask.contains(.editedCharacters) else { return }

        // Prevent re-entrance from our own attribute modifications
        guard !highlighter.isApplyingHighlight else { return }

        // Run synchronously — editedRange is guaranteed valid right now.
        // Async dispatch was the root cause of stale-range crashes.
        highlighter.highlightLines(containing: editedRange, in: textStorage)
    }
}
