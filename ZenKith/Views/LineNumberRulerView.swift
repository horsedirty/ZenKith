import AppKit

final class LineNumberRulerView: NSRulerView {

    // MARK: - Properties

    weak var textView: NSTextView? {
        didSet {
            guard textView !== oldValue else { return }
            oldValue.map { NotificationCenter.default.removeObserver(self, name: NSText.didChangeNotification, object: $0) }
            if let tv = textView {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(textDidChange),
                    name: NSText.didChangeNotification,
                    object: tv
                )
            }
            lineStartsCache = nil
            needsDisplay = true
        }
    }

    var font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular) {
        didSet {
            lineStartsCache = nil
            needsDisplay = true
        }
    }

    var backgroundColor: NSColor = NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1) {
        didSet { needsDisplay = true }
    }

    var textColor: NSColor = NSColor(red: 0.55, green: 0.55, blue: 0.60, alpha: 1) {
        didSet { needsDisplay = true }
    }

    var separatorColor: NSColor = .separatorColor {
        didSet { needsDisplay = true }
    }

    var onLineTapped: ((Int) -> Void)?

    // MARK: - Cache

    private var lineStartsCache: [Int]?
    private var lastCachedText: NSString?
    private var scrollObserver: NSObjectProtocol?

    // MARK: - Lifecycle

    override init(scrollView: NSScrollView?, orientation: NSRulerView.Orientation) {
        super.init(scrollView: scrollView, orientation: orientation)
        ruleThickness = 20
        clientView = scrollView?.documentView
        addScrollObserver()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
    }

    deinit {
        textView.map {
            NotificationCenter.default.removeObserver(self, name: NSText.didChangeNotification, object: $0)
        }
        if let observer = scrollObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        clientView = scrollView?.documentView
        addScrollObserver()
    }

    private func addScrollObserver() {
        guard let contentView = scrollView?.contentView else { return }
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: contentView,
            queue: .main
        ) { [weak self] _ in
            self?.needsDisplay = true
        }
    }

    // MARK: - Dynamic Thickness

    private func updateRuleThickness() {
        guard let tv = textView else {
            ruleThickness = 20
            return
        }
        let starts = lineStartPositions(in: tv.string)
        let totalLines = starts.count
        let digits = String(max(1, totalLines)).count
        let newThickness = font.pointSize * CGFloat(max(2, digits)) * 0.6 + 15
        if abs(ruleThickness - newThickness) > 0.5 {
            ruleThickness = newThickness
        }
    }

    // MARK: - Drawing

    override func drawHashMarksAndLabels(in rect: NSRect) {
        updateRuleThickness()

        backgroundColor.setFill()
        bounds.fill()
        drawSeparator()

        guard let tv = textView else { return }
        let visRect = tv.visibleRect

        if tv.textLayoutManager != nil {
            drawWithTextKit2(visRect: visRect, tv: tv)
        } else if let layout = tv.layoutManager, let container = tv.textContainer {
            drawWithTextKit1(visRect: visRect, layout: layout, container: container, tv: tv)
        }
    }

    // MARK: - Drawing Core Logic

    private func drawWithTextKit2(visRect: NSRect, tv: NSTextView) {
        guard let layout = tv.layoutManager, let container = tv.textContainer else { return }

        let fullText = tv.string
        let nsText = fullText as NSString
        let starts = lineStartPositions(in: fullText)

        let bufferHeight = font.pointSize * 2
        let extendedRect = visRect.insetBy(dx: 0, dy: -bufferHeight)
        let glyphRange = layout.glyphRange(forBoundingRect: extendedRect, in: container)

        layout.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, lineGlyphRange, _ in
            let charRange = layout.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
            guard charRange.location != NSNotFound else { return }

            // 检查当前片段是否为物理行的开始
            let isLineStart = charRange.location == 0 || nsText.character(at: charRange.location - 1) == 10 // \n

            if isLineStart {
                let lineNumber = self.findLineIndex(for: charRange.location, in: starts) + 1
                self.drawLineNumber(lineNumber, atY: usedRect.minY, in: tv)
            }
        }
    }

    private func drawWithTextKit1(visRect: NSRect, layout: NSLayoutManager, container: NSTextContainer, tv: NSTextView) {
        drawWithTextKit2(visRect: visRect, tv: tv)
    }

    private func findLineIndex(for charIndex: Int, in starts: [Int]) -> Int {
        var low = 0, high = starts.count
        while low < high {
            let mid = (low + high) / 2
            if starts[mid] <= charIndex { low = mid + 1 }
            else { high = mid }
        }
        return low - 1
    }

    // MARK: - Line Start Positions

    private func lineStartPositions(in text: String) -> [Int] {
        let nsText = text as NSString
        if let cache = lineStartsCache, nsText.isEqual(to: lastCachedText as String?) {
            return cache
        }

        var starts: [Int] = [0]
        let length = nsText.length
        for i in 0..<length {
            if nsText.character(at: i) == 10 { // \n
                starts.append(i + 1)
            }
        }

        lineStartsCache = starts
        lastCachedText = nsText
        return starts
    }

    // MARK: - Shared Drawing

    private func drawLineNumber(_ number: Int, atY y: CGFloat, in tv: NSTextView) {
        let numStr = "\(number)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let size = numStr.size(withAttributes: attrs)

        // y 是布局管理器坐标（文本视图坐标系）。
        // 需要将其转换到 ruler 自己的坐标系，才能在滚动后正确绘制。
        let textInset = tv.textContainerInset
        let tvPoint = NSPoint(x: 0, y: y + textInset.height)
        let rulerPoint = convert(tvPoint, from: tv)

        let x = bounds.width - size.width - 8
        numStr.draw(at: NSPoint(x: x, y: rulerPoint.y), withAttributes: attrs)
    }

    private func drawSeparator() {
        let sepRect = NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height)
        separatorColor.setFill()
        sepRect.fill()
    }

    @objc private func textDidChange() {
        lineStartsCache = nil
        lastCachedText = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard let tv = textView, let onLineTapped = onLineTapped else {
            super.mouseDown(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let tvPoint = tv.convert(point, from: self)

        guard let layout = tv.layoutManager, let container = tv.textContainer else { return }

        let charIndex = layout.characterIndex(for: tvPoint, in: container, fractionOfDistanceBetweenInsertionPoints: nil)
        let starts = lineStartPositions(in: tv.string)
        let lineNumber = findLineIndex(for: charIndex, in: starts) + 1
        onLineTapped(lineNumber)
    }
}
