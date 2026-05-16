import SwiftUI
import AppKit

struct EditorFindBar: NSViewRepresentable {
    @Binding var isVisible: Bool
    var textView: NSTextView?

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 36))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.95).cgColor

        let findField = NSSearchField(frame: NSRect(x: 8, y: 6, width: 200, height: 24))
        findField.placeholderString = "查找"
        findField.target = context.coordinator
        findField.action = #selector(Coordinator.findFieldChanged(_:))
        findField.sendsWholeSearchString = false
        findField.sendsSearchStringImmediately = false
        container.addSubview(findField)

        let countLabel = NSTextField(labelWithString: "")
        countLabel.frame = NSRect(x: 212, y: 9, width: 60, height: 16)
        countLabel.font = .systemFont(ofSize: 10)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .center
        container.addSubview(countLabel)

        let seg = NSSegmentedControl(
            labels: ["▲", "▼"],
            trackingMode: .momentary,
            target: context.coordinator,
            action: #selector(Coordinator.navigateMatch(_:))
        )
        seg.frame = NSRect(x: 276, y: 6, width: 52, height: 22)
        seg.segmentStyle = NSSegmentedControl.Style.separated
        seg.setWidth(24, forSegment: 0)
        seg.setWidth(24, forSegment: 1)
        container.addSubview(seg)

        let caseButton = NSButton(
            checkboxWithTitle: "Aa",
            target: context.coordinator,
            action: #selector(Coordinator.toggleCaseSensitive(_:))
        )
        caseButton.frame = NSRect(x: 334, y: 7, width: 42, height: 20)
        caseButton.font = .systemFont(ofSize: 10)
        container.addSubview(caseButton)

        let closeButton = NSButton(
            image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "关闭")!,
            target: context.coordinator,
            action: #selector(Coordinator.closeFindBar)
        )
        closeButton.frame = NSRect(x: 380, y: 8, width: 16, height: 16)
        closeButton.isBordered = false
        closeButton.bezelStyle = .inline
        container.addSubview(closeButton)

        let replaceField = NSTextField(frame: NSRect(x: 8, y: 38, width: 200, height: 24))
        replaceField.placeholderString = "替换为"
        replaceField.isHidden = true
        container.addSubview(replaceField)

        let replaceButton = NSButton(title: "替换", target: context.coordinator, action: #selector(Coordinator.replaceOne(_:)))
        replaceButton.frame = NSRect(x: 214, y: 38, width: 50, height: 22)
        replaceButton.isHidden = true
        replaceButton.bezelStyle = .rounded
        replaceButton.font = .systemFont(ofSize: 10)
        container.addSubview(replaceButton)

        let replaceAllButton = NSButton(title: "全部替换", target: context.coordinator, action: #selector(Coordinator.replaceAll(_:)))
        replaceAllButton.frame = NSRect(x: 268, y: 38, width: 60, height: 22)
        replaceAllButton.isHidden = true
        replaceAllButton.bezelStyle = .rounded
        replaceAllButton.font = .systemFont(ofSize: 10)
        container.addSubview(replaceAllButton)

        let toggleReplaceButton = NSButton(
            image: NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "展开替换")!,
            target: context.coordinator,
            action: #selector(Coordinator.toggleReplaceRow(_:))
        )
        toggleReplaceButton.frame = NSRect(x: 360, y: 8, width: 16, height: 16)
        toggleReplaceButton.isBordered = false
        container.addSubview(toggleReplaceButton)

        context.coordinator.findField = findField
        context.coordinator.countLabel = countLabel
        context.coordinator.segmentedControl = seg
        context.coordinator.caseButton = caseButton
        context.coordinator.replaceField = replaceField
        context.coordinator.replaceButton = replaceButton
        context.coordinator.replaceAllButton = replaceAllButton
        context.coordinator.toggleReplaceButton = toggleReplaceButton
        context.coordinator.container = container

        return container
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(textView: textView, isVisible: $isVisible)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.textView = textView
        if !isVisible {
            context.coordinator.clearHighlights()
        }
    }

    final class Coordinator: NSObject {
        weak var textView: NSTextView?
        @Binding var isVisible: Bool
        private var matches: [NSRange] = []
        private var currentMatchIndex: Int = -1
        private var caseSensitive = false
        private var showReplaceRow = false
        private var searchDebounceTimer: Timer?
        private let maxHighlights = 500

        weak var findField: NSSearchField?
        weak var countLabel: NSTextField?
        weak var segmentedControl: NSSegmentedControl?
        weak var caseButton: NSButton?
        weak var replaceField: NSTextField?
        weak var replaceButton: NSButton?
        weak var replaceAllButton: NSButton?
        weak var toggleReplaceButton: NSButton?
        weak var container: NSView?

        init(textView: NSTextView?, isVisible: Binding<Bool>) {
            self.textView = textView
            self._isVisible = isVisible
        }

        @objc func findFieldChanged(_ sender: NSSearchField) {
            searchDebounceTimer?.invalidate()
            let query = sender.stringValue
            searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
                self?.performSearch(query)
            }
        }

        @objc func navigateMatch(_ sender: NSSegmentedControl) {
            let forward = sender.selectedSegment == 1
            navigateMatch(forward: forward)
        }

        @objc func toggleCaseSensitive(_ sender: NSButton) {
            caseSensitive = (sender.state == .on)
            if let query = findField?.stringValue, !query.isEmpty {
                performSearch(query)
            }
        }

        @objc func toggleReplaceRow(_ sender: NSButton) {
            showReplaceRow.toggle()
            let height: CGFloat = showReplaceRow ? 68 : 36
            replaceField?.isHidden = !showReplaceRow
            replaceButton?.isHidden = !showReplaceRow
            replaceAllButton?.isHidden = !showReplaceRow
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                ctx.allowsImplicitAnimation = true
                container?.animator().setFrameSize(NSSize(width: container?.frame.width ?? 400, height: height))
            }
        }

        @objc func replaceOne(_ sender: NSButton) {
            guard let tv = textView,
                  let replaceText = replaceField?.stringValue,
                  currentMatchIndex >= 0, currentMatchIndex < matches.count else { return }
            tv.replaceCharacters(in: matches[currentMatchIndex], with: replaceText)
            if let query = findField?.stringValue {
                performSearch(query)
            }
        }

        @objc func replaceAll(_ sender: NSButton) {
            guard let tv = textView,
                  let replaceText = replaceField?.stringValue,
                  !matches.isEmpty else { return }
            tv.textStorage?.beginEditing()
            for range in matches.reversed() {
                tv.replaceCharacters(in: range, with: replaceText)
            }
            tv.textStorage?.endEditing()
            if let query = findField?.stringValue {
                performSearch(query)
            }
        }

        @objc func closeFindBar() {
            isVisible = false
            clearHighlights()
        }

        private func performSearch(_ query: String) {
            clearHighlights()
            matches = []
            currentMatchIndex = -1
            updateCountLabel()
            guard let tv = textView, !query.isEmpty else { return }

            let text = tv.string
            let options: NSString.CompareOptions = caseSensitive ? [] : .caseInsensitive
            var searchStart = text.startIndex
            while let range = text[searchStart...].range(of: query, options: options) {
                let nsRange = NSRange(range, in: text)
                matches.append(nsRange)
                searchStart = range.upperBound
            }

            if !matches.isEmpty {
                currentMatchIndex = 0
                selectAndScroll(to: 0)
                highlightAllMatches()
            }
            updateCountLabel()
        }

        private func navigateMatch(forward: Bool) {
            guard !matches.isEmpty, let tv = textView else { return }
            if forward {
                currentMatchIndex = (currentMatchIndex + 1) % matches.count
            } else {
                currentMatchIndex = (currentMatchIndex - 1 + matches.count) % matches.count
            }
            selectAndScroll(to: currentMatchIndex)
            updateCountLabel()
        }

        private func selectAndScroll(to index: Int) {
            guard let tv = textView, index >= 0, index < matches.count else { return }
            tv.scrollRangeToVisible(matches[index])
            tv.setSelectedRange(matches[index])
            tv.window?.makeFirstResponder(tv)
        }

        private func highlightAllMatches() {
            guard let tv = textView, let ts = tv.textStorage else { return }
            for range in matches.prefix(maxHighlights) {
                ts.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.25), range: range)
            }
        }

        func clearHighlights() {
            guard let tv = textView, let ts = tv.textStorage, !matches.isEmpty else { return }
            for range in matches {
                ts.removeAttribute(.backgroundColor, range: range)
            }
        }

        private func updateCountLabel() {
            if matches.isEmpty {
                countLabel?.stringValue = findField?.stringValue.isEmpty == false ? "0 个匹配" : ""
            } else {
                countLabel?.stringValue = "\(currentMatchIndex + 1) / \(matches.count)"
            }
        }
    }
}
