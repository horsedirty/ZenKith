# LaTeX 专业编辑功能 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有架构上渐进式增强六个 LaTeX 专业编辑功能：AI+LaTeX 深度集成、编译错误定位、文档大纲、代码片段快速插入、SyncTeX 反向搜索、参考文献管理。

**Architecture:** 在现有 MVVM + `@MainActor` + Service 层模式上挂载独立模块。通过 NotificationCenter 通信，最小化对现有文件的侵入。

**Tech Stack:** SwiftUI, AppKit (NSTextView, PDFView, WKWebView), NotificationCenter, XCTest (TDD)

**Testing:** 项目当前无测试目标，需先用 Xcode 添加 `ZenKithTests` target。每个 Task 包含 TDD 完整循环：RED → verify fail → GREEN → verify pass → REFACTOR → commit。

---

### Task 1: LatexError 结构化编译错误

**Files:**
- Modify: `ZenKith/Services/LatexService.swift`
- Test: `ZenKithTests/LatexServiceTests.swift`

- [ ] **Step 1: 先通过 Xcode 添加 ZenKithTests target**
  1. 打开 `ZenKith.xcodeproj`
  2. File → New → Target → macOS → Unit Testing Bundle
  3. Target name: `ZenKithTests`
  4. 选择 ZenKith 主 target 作为 Host Application
  5. 关闭 Xcode，确认 `ZenKithTests/` 目录已创建

- [ ] **Step 2: 编写失败测试**

```swift
// ZenKithTests/LatexServiceTests.swift
import XCTest
@testable import ZenKith

final class LatexServiceTests: XCTestCase {

    func testExtractErrorLinesParsesLineNumbers() {
        let log = """
        === 编译: pdflatex ===
        ! Undefined control sequence.
        l.42 \\badcommand
        This is fine
        ! LaTeX Error: File not found.
        l.108 \\include{missing}
        """
        let errors = LatexService.extractErrorLines(from: log)
        XCTAssertEqual(errors.count, 2)
        XCTAssertEqual(errors[0].line, 42)
        XCTAssertEqual(errors[0].message, "Undefined control sequence.")
        XCTAssertEqual(errors[1].line, 108)
        XCTAssertEqual(errors[1].message, "LaTeX Error: File not found.")
    }

    func testExtractErrorLinesReturnsWarningsSeparately() {
        let log = """
        LaTeX Warning: Overfull \\hbox
        l.55 \\hline
        """
        let errors = LatexService.extractErrorLines(from: log)
        XCTAssertEqual(errors.first?.type, .warning)
    }

    func testExtractErrorLinesNoErrors() {
        let errors = LatexService.extractErrorLines(from: "Output written on document.pdf")
        XCTAssertTrue(errors.isEmpty)
    }
}
```

- [ ] **Step 3: 运行测试确认失败**

```bash
xcodebuild test -project ZenKith.xcodeproj -scheme ZenKith -destination 'platform=macOS' 2>&1 | tail -20
```
预期: `Type 'LatexService' has no member 'extractErrorLines'` 或类似编译错误

- [ ] **Step 4: 在 LatexService.swift 中新增 LatexError 和 extractErrorLines**

```swift
// 在 LatexCompileResult 下方新增:

/// 编译错误类型
enum LatexErrorType: String, Equatable {
    case error
    case warning
}

/// 结构化的 LaTeX 编译错误
struct LatexError: Equatable {
    let line: Int
    let message: String
    let type: LatexErrorType
}

// 在 LatexService 中添加:

/// 从编译日志中提取结构化的错误列表（含行号）
static func extractErrorLines(from log: String) -> [LatexError] {
    let lines = log.components(separatedBy: "\n")
    var errors: [LatexError] = []

    for i in 0..<lines.count {
        let line = lines[i].trimmingCharacters(in: .whitespaces)
        var errorLine = -1
        var message = ""
        var type: LatexErrorType = .error

        if line.hasPrefix("! ") {
            message = String(line.dropFirst(2))
            errorLine = extractLineNumber(from: lines, around: i)
        } else if line.hasPrefix("LaTeX Error:") {
            message = line
            errorLine = extractLineNumber(from: lines, around: i)
        } else if line.hasPrefix("LaTeX Warning:") {
            message = line
            type = .warning
            errorLine = extractLineNumber(from: lines, around: i)
        }

        if errorLine > 0 {
            errors.append(LatexError(line: errorLine, message: message, type: type))
        }
    }
    return errors
}

private static func extractLineNumber(from lines: [String], around index: Int) -> Int {
    for j in index..<min(index + 5, lines.count) {
        let l = lines[j].trimmingCharacters(in: .whitespaces)
        if l.hasPrefix("l.") {
            let numStr = String(l.dropFirst(2))
                .components(separatedBy: CharacterSet.decimalDigits.inverted)
                .first ?? ""
            return Int(numStr) ?? -1
        }
    }
    return -1
}
```

- [ ] **Step 5: 在 LatexCompileResult 中新增 errors 属性**

```swift
struct LatexCompileResult {
    let pdfData: Data?
    let log: String
    let success: Bool
    let passCount: Int

    var errors: [LatexError] {
        LatexService.extractErrorLines(from: log)
    }
}
```

- [ ] **Step 6: 运行测试确认通过**

```bash
xcodebuild test -project ZenKith.xcodeproj -scheme ZenKith -destination 'platform=macOS' 2>&1 | tail -20
```
预期: `** TEST SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add ZenKith/Services/LatexService.swift ZenKithTests/LatexServiceTests.swift
git commit -m "feat: 添加 LatexError 结构化编译错误支持"
```

---

### Task 2: LatexOutliner 文档大纲解析器

**Files:**
- Create: `ZenKith/Views/LatexOutliner.swift`
- Test: `ZenKithTests/LatexOutlinerTests.swift`

- [ ] **Step 1: 编写失败测试**

```swift
// ZenKithTests/LatexOutlinerTests.swift
import XCTest
@testable import ZenKith

final class LatexOutlinerTests: XCTestCase {

    func testParseSectionsReturnsCorrectHierarchy() {
        let source = """
        \\documentclass{article}
        \\begin{document}
        \\section{Introduction}
        Some text here.
        \\subsection{Background}
        More text.
        \\section{Methods}
        \\subsection{Setup}
        \\subsubsection{Configuration A}
        Details.
        \\subsection{Results}
        \\end{document}
        """
        let items = LatexOutliner.parse(source)
        XCTAssertEqual(items.count, 2) // Introduction, Methods
        XCTAssertEqual(items[0].title, "Introduction")
        XCTAssertEqual(items[0].level, 1)
        XCTAssertEqual(items[1].children.count, 2) // Setup, Results
        XCTAssertEqual(items[1].children[0].children.count, 1) // Configuration A
        XCTAssertEqual(items[1].children[0].children[0].level, 3)
    }

    func testParseSectionsIncludesLineNumbers() {
        let source = """
        line1
        line2
        \\section{Test}
        """
        let items = LatexOutliner.parse(source)
        XCTAssertEqual(items.first?.lineNumber, 3)
    }

    func testParseIgnoresCommentedSections() {
        let source = "% \\section{Commented}"
        let items = LatexOutliner.parse(source)
        XCTAssertTrue(items.isEmpty)
    }

    func testParseIncludesChapter() {
        let source = "\\chapter{Overview}\n\\section{Start}"
        let items = LatexOutliner.parse(source)
        XCTAssertEqual(items[0].title, "Overview")
        XCTAssertEqual(items[0].level, 0)
    }

    func testParseEmptySource() {
        XCTAssertTrue(LatexOutliner.parse("").isEmpty)
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild test -project ZenKith.xcodeproj -scheme ZenKith -destination 'platform=macOS' 2>&1 | tail -5
```

- [ ] **Step 3: 实现 LatexOutliner**

```swift
// ZenKith/Views/LatexOutliner.swift
import Foundation

struct OutlineItem: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let lineNumber: Int
    let level: Int  // 0=chapter, 1=section, 2=subsection, 3=subsubsection
    let children: [OutlineItem]
}

enum LatexOutliner {

    private static let sectionPatterns: [(String, Int)] = [
        ("subsubsection", 3),
        ("subsection", 2),
        ("section", 1),
        ("chapter", 0),
    ]

    static func parse(_ source: String) -> [OutlineItem] {
        let lines = source.components(separatedBy: "\n")
        var flatItems: [(lineNumber: Int, level: Int, title: String)] = []

        for (idx, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("%") else { continue }

            for (command, level) in sectionPatterns {
                let prefix = "\\\(command){"
                if line.hasPrefix(prefix), let close = findMatchingBrace(in: line, from: prefix.count - 1) {
                    let title = String(line[line.index(line.startIndex, offsetBy: prefix.count)..<close])
                    flatItems.append((idx + 1, level, title))
                    break
                }
            }
        }

        return buildTree(from: flatItems)
    }

    private static func findMatchingBrace(in line: String, from startBraceIdx: Int) -> String.Index? {
        let startIdx = line.index(line.startIndex, offsetBy: startBraceIdx)
        var depth = 0
        for i in line[startIdx...].indices {
            let ch = line[i]
            if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 { return i }
            }
        }
        return nil
    }

    private static func buildTree(from flat: [(lineNumber: Int, level: Int, title: String)]) -> [OutlineItem] {
        var result: [OutlineItem] = []
        var stack: [(level: Int, children: inout [OutlineItem])] = [(-1, &result)]

        for item in flat {
            while let top = stack.last, top.level >= item.level {
                stack.removeLast()
            }
            var children: [OutlineItem] = []
            let node = OutlineItem(title: item.title, lineNumber: item.lineNumber, level: item.level, children: children)
            stack[stack.count - 1].children.append(node)
            stack.append((item.level, &stack[stack.count - 1].children[stack[stack.count - 1].children.count - 1].children))
        }
        return result
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
xcodebuild test -project ZenKith.xcodeproj -scheme ZenKith -destination 'platform=macOS' 2>&1 | tail -5
```

- [ ] **Step 5: Commit**

```bash
git add ZenKith/Views/LatexOutliner.swift ZenKithTests/LatexOutlinerTests.swift
git commit -m "feat: 添加 LatexOutliner 文档大纲解析器"
```

---

### Task 3: scrollToLine 通知 + EditorView 响应

**Files:**
- Modify: `ZenKith/Views/EditorView.swift`
- Modify: `ZenKith/Utilities/PersistenceKeys.swift`

- [ ] **Step 1: 新增通知名**

```swift
// 在 PersistenceKeys.swift 或其他 Notifications 扩展文件中新增:

extension Notification.Name {
    static let scrollToLine = Notification.Name("ZenKith.scrollToLine")
}
```

- [ ] **Step 2: 在 EditorView.Coordinator 中监听通知**

在 `EditorView.swift` 的 `Coordinator` 中新增:

```swift
// 在 init 末尾添加:
private var lineHighlightLayer: CAShapeLayer?

// 在 Coordinator init 末尾添加:
NotificationCenter.default.addObserver(
    self,
    selector: #selector(handleScrollToLine(_:)),
    name: .scrollToLine,
    object: nil
)

// 新增方法:
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

    // 高亮目标行
    highlightLine(lineNumber)
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

    if let rect = tv.firstRect(forCharacterRange: range, actualRange: nil),
       rect != .zero {
        let layer = CAShapeLayer()
        layer.fillColor = NSColor.systemYellow.withAlphaComponent(0.2).cgColor
        let lineRect = NSRect(x: 0, y: rect.origin.y, width: tv.bounds.width, height: rect.height)
        layer.path = CGPath(rect: lineRect, transform: nil)
        tv.layer?.addSublayer(layer)
        self.lineHighlightLayer = layer

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak layer] in
            layer?.removeFromSuperlayer()
        }
    }
}
```

- [ ] **Step 3: 构建验证编译通过**

```bash
xcodebuild build -project ZenKith.xcodeproj -scheme ZenKith -destination 'platform=macOS' 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add ZenKith/Views/EditorView.swift ZenKith/Utilities/PersistenceKeys.swift
git commit -m "feat: EditorView 支持 scrollToLine 通知和行高亮"
```

---

### Task 4: ContentView 编译错误跳转

**Files:**
- Modify: `ZenKith/ContentView.swift`

- [ ] **Step 1: 编译日志面板错误可点击**

修改 `compileLog` sheet 中的日志显示，将 `LatexError` 结构化为可点击项:

```swift
// 在 ContentView 中新增 computed property:
private var compileErrors: [LatexError] {
    LatexService.extractErrorLines(from: compileLog)
}

// 在 sheet(isPresented: $showCompileLog) 中替换 ScrollView 内容:
.sheet(isPresented: $showCompileLog) {
    VStack(spacing: 12) {
        Text("编译日志").font(.appHeadline)
        if compileErrors.isEmpty {
            ScrollView {
                Text(compileLog.isEmpty ? "无输出" : compileLog)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(compileErrors.indices, id: \.self) { idx in
                        let err = compileErrors[idx]
                        HStack(spacing: 4) {
                            Image(systemName: err.type == .error ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(err.type == .error ? .red : .orange)
                                .font(.system(size: 10))
                            Text("行 \(err.line):")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(err.message)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(err.type == .error ? .red : .orange)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showCompileLog = false
                            NotificationCenter.default.post(
                                name: .scrollToLine,
                                object: nil,
                                userInfo: ["line": err.line]
                            )
                        }
                        Divider()
                    }
                    // 尾部追加 "发送错误给AI" 按钮
                    Button(action: {
                        let errorText = compileErrors.map { "行\($0.line): \($0.message)" }.joined(separator: "\n")
                        aiViewModel.sendCompileErrorsToAI(errors: compileErrors, source: manager.editingContent)
                        showCompileLog = false
                    }) {
                        Label("将错误发送给 AI 诊断", systemImage: "sparkles")
                            .font(.appCaption)
                    }
                    .padding(.top, 8)
                }
                .padding()
            }
        }
        Button("关闭") { showCompileLog = false }
            .keyboardShortcut(.cancelAction)
    }
    .frame(width: 600, height: 400)
    .padding()
}
```

- [ ] **Step 2: 构建验证编译通过**

```bash
xcodebuild build -project ZenKith.xcodeproj -scheme ZenKith -destination 'platform=macOS' 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add ZenKith/ContentView.swift
git commit -m "feat: 编译日志错误可点击跳转到源码行 + 发送错误给AI"
```

---

### Task 5: OutlinePanelView 大纲面板

**Files:**
- Create: `ZenKith/Views/OutlinePanelView.swift`

- [ ] **Step 1: 实现 OutlinePanelView**

```swift
// ZenKith/Views/OutlinePanelView.swift
import SwiftUI

struct OutlinePanelView: NSViewRepresentable {
    var items: [OutlineItem]
    var onSelectLine: (Int) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let outlineView = NSOutlineView()
        outlineView.headerView = nil
        outlineView.selectionHighlightStyle = .sourceList
        outlineView.indentationPerLevel = 12
        outlineView.rowSizeStyle = .small

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        col.width = 200
        outlineView.addTableColumn(col)
        outlineView.outlineTableColumn = col

        outlineView.delegate = context.coordinator
        outlineView.dataSource = context.coordinator

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        context.coordinator.outlineView = outlineView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.items = items
        (scrollView.documentView as? NSOutlineView)?.reloadData()
        // 展开所有层级
        guard let ov = scrollView.documentView as? NSOutlineView else { return }
        for i in 0..<items.count {
            expandRecursively(ov, at: i, items: items[i].children)
        }
    }

    private func expandRecursively(_ ov: NSOutlineView, at index: Int, items: [OutlineItem]) {
        ov.expandItem(nil)
        // 使用 item 本身作为 expansion identity
        for (i, child) in items.enumerated() {
            ov.expandItem(child)
            expandRecursively(ov, at: i, items: child.children)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectLine: onSelectLine)
    }

    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var items: [OutlineItem] = []
        var onSelectLine: (Int) -> Void
        weak var outlineView: NSOutlineView?

        init(onSelectLine: @escaping (Int) -> Void) {
            self.onSelectLine = onSelectLine
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let item = item as? OutlineItem else { return items.count }
            return item.children.count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            guard let item = item as? OutlineItem else { return items[index] }
            return item.children[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let item = item as? OutlineItem else { return false }
            return !item.children.isEmpty
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let item = item as? OutlineItem else { return nil }
            let id = NSUserInterfaceItemIdentifier("OutlineCell")
            let cell = outlineView.makeView(withIdentifier: id, owner: self) as? NSTextField ?? NSTextField()
            cell.identifier = id
            cell.isBordered = false
            cell.drawsBackground = false
            cell.isEditable = false
            cell.font = .systemFont(ofSize: 12)
            cell.lineBreakMode = .byTruncatingTail
            cell.stringValue = item.title
            return cell
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard let ov = outlineView,
                  let item = ov.item(atRow: ov.selectedRow) as? OutlineItem else { return }
            onSelectLine(item.lineNumber)
        }
    }
}
```

- [ ] **Step 2: 构建验证编译通过**

```bash
xcodebuild build -project ZenKith.xcodeproj -scheme ZenKith -destination 'platform=macOS' 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add ZenKith/Views/OutlinePanelView.swift
git commit -m "feat: 添加大纲面板 OutlinePanelView"
```

---

### Task 6: ContentView 集成大纲面板

**Files:**
- Modify: `ZenKith/ContentView.swift`

- [ ] **Step 1: 在主内容区左侧集成大纲面板**

在 `mainContentArea` 或 `editorPane` 中，LaTeX 模式下显示大纲面板:

```swift
// 在 ContentView 中新增:
@State private var showOutlinePanel = false

// 在 mainContentArea 的最外层 HStack 中，editorPane 左侧新增:
private var editorPane: some View {
    HStack(spacing: 0) {
        if settings.editorLanguage == .latex && showOutlinePanel {
            latexOutlinePanel
            Divider()
        }
        // ... 原有 editorPane 内容 (VStack)
    }
}

// 新增 latexOutlinePanel:
private var latexOutlinePanel: some View {
    let outlineItems = LatexOutliner.parse(manager.editingContent)
    return OutlinePanelView(items: outlineItems) { lineNumber in
        NotificationCenter.default.post(
            name: .scrollToLine,
            object: nil,
            userInfo: ["line": lineNumber]
        )
    }
    .frame(width: min(220, 240))
}

// 工具栏新增大纲切换按钮（在 LaTeX 工具栏已有内容后添加）:
// 在 latex 模式下的 toolbar 代码区域:
Button(action: { showOutlinePanel.toggle() }) {
    Image(systemName: showOutlinePanel ? "list.bullet.indent" : "list.bullet")
        .font(.appBody)
        .foregroundColor(showOutlinePanel ? .accentColor : .secondary)
}
.buttonStyle(.borderless)
.help("切换文档大纲 (LaTeX)")
```

- [ ] **Step 2: 构建验证编译通过**

```bash
xcodebuild build -project ZenKith.xcodeproj -scheme ZenKith -destination 'platform=macOS' 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add ZenKith/ContentView.swift
git commit -m "feat: 集成文档大纲面板到主界面"
```

---

### Task 7: LatexCompletionEngine 环境补全增强

**Files:**
- Modify: `ZenKith/Views/LatexCompletionEngine.swift`

- [ ] **Step 1: 在 evaluateState 中检测 \begin{ 前缀**

```swift
// 在 evaluateState 方法中，在现有 \\ 检测逻辑前新增:

func evaluateState(in textView: NSTextView) {
    let cursorPos = textView.selectedRange().location
    guard cursorPos > 0 else { dismissWithCallback(); return }

    let text = textView.string as NSString

    // 检测 \begin{ 前缀
    if let beginRange = detectBeginPrefix(in: text, cursorPos: cursorPos) {
        let prefix = text.substring(with: NSRange(location: beginRange.location + 7, length: cursorPos - beginRange.location - 7))
        filterAsync(prefix: prefix, range: beginRange, filterMode: .beginEnvironment)
        return
    }

    // 检测 \cite{ 前缀
    if let citeRange = detectCitePrefix(in: text, cursorPos: cursorPos) {
        let prefix = text.substring(with: NSRange(location: citeRange.location + 6, length: cursorPos - citeRange.location - 6))
        filterAsync(prefix: prefix, range: citeRange, filterMode: .citeKey)
        return
    }

    // ... 原有 \\ 检测逻辑
}

private func detectBeginPrefix(in text: NSString, cursorPos: Int) -> NSRange? {
    let pattern = "\\begin{"
    let searchStart = max(0, cursorPos - 50)
    let searchRange = NSRange(location: searchStart, length: cursorPos - searchStart)
    let full = text.substring(with: searchRange)
    if let lastBegin = full.range(of: pattern, options: .backwards) {
        let beginIdx = searchStart + full.distance(from: full.startIndex, to: lastBegin.lowerBound)
        let endIdxPos = cursorPos
        let substring = text.substring(with: NSRange(location: beginIdx, length: endIdxPos - beginIdx))
        if !substring.contains("}") {
            return NSRange(location: beginIdx, length: cursorPos - beginIdx)
        }
    }
    return nil
}

private func detectCitePrefix(in text: NSString, cursorPos: Int) -> NSRange? {
    let pattern = "\\cite{"
    let searchStart = max(0, cursorPos - 50)
    let searchRange = NSRange(location: searchStart, length: cursorPos - searchStart)
    let full = text.substring(with: searchRange)
    if let lastCite = full.range(of: pattern, options: .backwards) {
        let citeIdx = searchStart + full.distance(from: full.startIndex, to: lastCite.lowerBound)
        let substring = text.substring(with: NSRange(location: citeIdx, length: cursorPos - citeIdx))
        if !substring.contains("}") {
            return NSRange(location: citeIdx, length: cursorPos - citeIdx)
        }
    }
    return nil
}
```

- [ ] **Step 2: 修改 filterAsync 支持环境模式**

```swift
// 在 LatexCompletionEngine 中新增:
enum FilterMode {
    case command    // 默认 \\ 命令补全
    case beginEnvironment
    case citeKey
}

// filterAsync 签名改为:
func filterAsync(prefix: String, range: NSRange, filterMode: FilterMode = .command) {
    filterTask?.cancel()
    let delay = prefix.isEmpty ? Duration.milliseconds(0) : Duration.milliseconds(50)

    filterTask = Task { @MainActor [weak self] in
        try? await Task.sleep(for: delay)
        guard !Task.isCancelled, let self else { return }

        let results: [LatexCompletion]
        switch filterMode {
        case .command:
            let lower = prefix.lowercased()
            results = await Task.detached(priority: .userInitiated) { [cmds = self.allCommands] in
                cmds.filter { $0.command.lowercased().hasPrefix(lower) }
            }.value
        case .beginEnvironment:
            results = Self.environmentCompletions.filter { $0.command.lowercased().hasPrefix(prefix.lowercased()) }
        case .citeKey:
            results = self.citeKeyCompletions(prefix: prefix)
        }

        guard !Task.isCancelled else { return }
        DispatchQueue.main.async {
            guard !Task.isCancelled else { return }
            self.suggestions = results
            self.state = results.isEmpty ? .idle : .active(prefix: prefix, range: range)
            self.onStateChanged?()
        }
    }
}

// 环境补全列表:
static let environmentCompletions: [LatexCompletion] = {
    let envs: [(String, String)] = [
        ("document", "document 文档体"),
        ("figure", "figure 插图"),
        ("table", "table 表格"),
        ("tabular", "tabular 表格主体"),
        ("equation", "equation 行间公式"),
        ("align", "align 对齐公式"),
        ("itemize", "itemize 无序列表"),
        ("enumerate", "enumerate 有序列表"),
        ("description", "description 描述列表"),
        ("center", "center 居中"),
        ("quote", "quote 引用"),
        ("quotation", "quotation 引文"),
        ("verbatim", "verbatim 原样输出"),
        ("abstract", "abstract 摘要"),
        ("proof", "proof 证明"),
        ("theorem", "theorem 定理"),
        ("lemma", "lemma 引理"),
        ("corollary", "corollary 推论"),
        ("definition", "definition 定义"),
        ("example", "example 示例"),
        ("remark", "remark 备注"),
        ("align*", "align* 无编号对齐"),
        ("equation*", "equation* 无编号公式"),
        ("matrix", "matrix 矩阵"),
        ("pmatrix", "pmatrix 括号矩阵"),
        ("bmatrix", "bmatrix 方括号矩阵"),
        ("cases", "cases 分段函数"),
        ("lstlisting", "lstlisting 代码块"),
        ("thebibliography", "thebibliography 参考文献"),
        ("minipage", "minipage 小页"),
    ]
    return envs.map { cmd, detail in
        LatexCompletion(
            command: cmd,
            displayName: "\\begin{\(cmd)}",
            insertionText: "\\begin{\(cmd)}\n${1:}\n\\end{\(cmd)}",
            category: .environment,
            detail: detail
        )
    }
}()
```

- [ ] **Step 3: cite key 补全（占位，后续 BibManager Task 完成）**

```swift
private func citeKeyCompletions(prefix: String) -> [LatexCompletion] {
    // 占位实现，BibManager Task 后替换
    return []
}

// 新增方法用于 BibManager 集成:
func setCiteKeys(_ keys: [String]) {
    self._citeKeys = keys
}
private var _citeKeys: [String] = []

private func citeKeyCompletions(prefix: String) -> [LatexCompletion] {
    let lower = prefix.lowercased()
    return _citeKeys
        .filter { $0.lowercased().contains(lower) }
        .map { key in
            LatexCompletion(
                command: key,
                displayName: key,
                insertionText: key,
                category: .reference,
                detail: "引用"
            )
        }
}
```

- [ ] **Step 4: commit 方法适配环境补全**

在 `commit` 方法中，检测是否以 `\begin{` 开头，替换时保持完整:

```swift
// commit 方法无需修改，因为 insertionText 已包含 \begin{env}...\end{env}
```

- [ ] **Step 5: 构建验证**

```bash
xcodebuild build -project ZenKith.xcodeproj -scheme ZenKith -destination 'platform=macOS' 2>&1 | tail -5
```

- [ ] **Step 6: Commit**

```bash
git add ZenKith/Views/LatexCompletionEngine.swift
git commit -m "feat: 补全引擎支持 \\begin{ 环境补全和 \\cite 引用键补全"
```

---

### Task 8: InsertSnippetMenu 代码片段工具栏

**Files:**
- Create: `ZenKith/Views/InsertSnippetMenu.swift`
- Modify: `ZenKith/ContentView.swift` (toolbar)

- [ ] **Step 1: 实现 InsertSnippetMenu**

```swift
// ZenKith/Views/InsertSnippetMenu.swift
import SwiftUI

struct LatexSnippet: Identifiable {
    let id = UUID()
    let name: String
    let template: String
    let category: String
}

struct InsertSnippetMenu: View {
    var onInsert: (String) -> Void

    private static let snippets: [LatexSnippet] = {
        var list: [LatexSnippet] = []

        func add(_ name: String, _ template: String, _ cat: String) {
            list.append(LatexSnippet(name: name, template: template, category: cat))
        }

        // 表格
        add("3列表格", "\\begin{tabular}{|c|c|c|}\n\\hline\n${1:Col1} & ${2:Col2} & ${3:Col3} \\\\\\hline\n${4:} & ${5:} & ${6:} \\\\\\hline\n\\end{tabular}", "表格")
        add("4列表格", "\\begin{tabular}{|c|c|c|c|}\n\\hline\n${1:} & ${2:} & ${3:} & ${4:} \\\\\\hline\n${5:} & ${6:} & ${7:} & ${8:} \\\\\\hline\n\\end{tabular}", "表格")
        add("longtable 长表格", "\\begin{longtable}{|c|c|c|}\n\\hline\n${1:Col1} & ${2:Col2} & ${3:Col3} \\\\\\hline\n\\endhead\n${4:} & ${5:} & ${6:} \\\\\\hline\n\\end{longtable}", "表格")
        add("tabularx 自适应宽", "\\begin{tabularx}{\\textwidth}{|X|X|X|}\n\\hline\n${1:} & ${2:} & ${3:} \\\\\\hline\n\\end{tabularx}", "表格")

        // 矩阵
        add("2x2 矩阵", "\\begin{pmatrix}\n${1:a} & ${2:b} \\\\\n${3:c} & ${4:d}\n\\end{pmatrix}", "矩阵")
        add("3x3 方括号矩阵", "\\begin{bmatrix}\n${1:1} & ${2:0} & ${3:0} \\\\\n${4:0} & ${5:1} & ${6:0} \\\\\n${7:0} & ${8:0} & ${9:1}\n\\end{bmatrix}", "矩阵")
        add("cases 分段", "\\begin{cases}\n${1:x}, & \\text{if } ${2:x > 0} \\\\\n${3:0}, & \\text{otherwise}\n\\end{cases}", "矩阵")

        // 图形
        add("figure 插图", "\\begin{figure}[htbp]\n\\centering\n\\includegraphics[width=${1:0.8}\\textwidth]{${2:image.pdf}}\n\\caption{${3:标题}}\n\\label{fig:${4:}}\n\\end{figure}", "图形")
        add("subfigures 子图", "\\begin{figure}[htbp]\n\\centering\n\\begin{subfigure}{${1:0.45}\\textwidth}\n\\centering\n\\includegraphics[width=\\textwidth]{${2:}}\n\\caption{${3:左图}}\n\\end{subfigure}\n\\hfill\n\\begin{subfigure}{${4:0.45}\\textwidth}\n\\centering\n\\includegraphics[width=\\textwidth]{${5:}}\n\\caption{${6:右图}}\n\\end{subfigure}\n\\caption{${7:总标题}}\n\\end{figure}", "图形")

        // 定理
        add("theorem 定理", "\\begin{theorem}\n${1:定理内容}\n\\end{theorem}", "定理")
        add("lemma 引理", "\\begin{lemma}\n${1:引理内容}\n\\end{lemma}", "定理")
        add("proof 证明", "\\begin{proof}\n${1:证明过程}\n\\end{proof}", "定理")

        // 其他
        add("itemize 列表", "\\begin{itemize}\n\\item ${1:第一项}\n\\item ${2:第二项}\n\\end{itemize}", "列表")
        add("enumerate 编号列表", "\\begin{enumerate}\n\\item ${1:第一项}\n\\item ${2:第二项}\n\\end{enumerate}", "列表")

        return list
    }()

    private let categories = ["表格", "矩阵", "图形", "列表", "定理"]

    var body: some View {
        Menu {
            ForEach(categories, id: \.self) { cat in
                let items = Self.snippets.filter { $0.category == cat }
                if !items.isEmpty {
                    Menu(cat) {
                        ForEach(items) { snippet in
                            Button(snippet.name) {
                                onInsert(snippet.template)
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "plus.rectangle")
                .font(.appBody)
                .foregroundColor(.accentColor)
        }
        .menuStyle(.borderlessButton)
        .help("插入 LaTeX 代码片段")
    }
}
```

- [ ] **Step 2: 在 ContentView toolbar 中集成**

在 `ContentView.swift` 的 `toolbarContent` 中，LaTeX 模式下、在编译按钮后添加:

```swift
// 在 latex 编译器菜单后:
InsertSnippetMenu { snippetTemplate in
    guard let note = manager.selectedNote else { return }
    manager.editingContent += "\n" + snippetTemplate + "\n"
}
```

- [ ] **Step 3: 构建验证**

```bash
xcodebuild build -project ZenKith.xcodeproj -scheme ZenKith -destination 'platform=macOS' 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add ZenKith/Views/InsertSnippetMenu.swift ZenKith/ContentView.swift
git commit -m "feat: 添加 LaTeX 代码片段插入菜单"
```

---

### Task 9: AIViewModel LaTeX 集成

**Files:**
- Modify: `ZenKith/ViewModels/AIViewModel.swift`

- [ ] **Step 1: 新增属性和方法**

```swift
// 在 AIViewModel 中新增:

@Published var includeLatexContext: Bool = false

// 当前文件语言感知
var currentNoteLanguage: EditorLanguage? = nil

// 发送编辑器选中文本给 AI
func sendSelectionToAI(_ text: String) {
    guard !isStreaming else { return }
    if selectedSessionId == nil { createNewSession() }

    let prompt = "以下是我 LaTeX 文档中选中的一段代码，请帮我分析或改进：\n\n```latex\n\(text)\n```"

    let userMessage = AIService.ChatMessage(role: .user, content: prompt)
    messages.append(userMessage)

    isStreaming = true
    streamingText = ""
    streamingReasoning = ""
    saveCurrentSession()

    aiService.streamChat(
        messages: messages,
        config: config,
        systemPrompt: "你是一个专业的 LaTeX 写作助手，帮助用户改进 LaTeX 代码、提供排版建议和知识解答。请使用中文回复。",
        onReasoningChunk: { [weak self] chunk in self?.streamingReasoning += chunk },
        onChunk: { [weak self] chunk in self?.streamingText += chunk },
        onComplete: { [weak self] content, reasoning in
            guard let self else { return }
            let msg = AIService.ChatMessage(role: .assistant, content: content, reasoningContent: reasoning.isEmpty ? nil : reasoning)
            self.messages.append(msg)
            self.streamingText = ""
            self.streamingReasoning = ""
            self.isStreaming = false
            self.saveCurrentSession()
        },
        onError: { [weak self] error in
            guard let self else { return }
            let msg = AIService.ChatMessage(role: .assistant, content: "错误：\(error.localizedDescription)")
            self.messages.append(msg)
            self.streamingText = ""
            self.streamingReasoning = ""
            self.isStreaming = false
            self.saveCurrentSession()
        }
    )
}

// 发送编译错误给 AI 诊断
func sendCompileErrorsToAI(errors: [LatexError], source: String) {
    guard !isStreaming else { return }
    if selectedSessionId == nil { createNewSession() }

    let errorLines = errors.map { "行\($0.line): \($0.message)" }.joined(separator: "\n")
    let prompt = "我的 LaTeX 文档编译失败了，以下是错误日志和源代码，请帮我诊断并给出修复建议：\n\n## 错误日志\n\(errorLines)\n\n## 源代码\n```latex\n\(source)\n```"

    let userMessage = AIService.ChatMessage(role: .user, content: prompt)
    messages.append(userMessage)

    isStreaming = true
    streamingText = ""
    streamingReasoning = ""
    saveCurrentSession()

    aiService.streamChat(
        messages: messages,
        config: config,
        systemPrompt: "你是一个专业的 LaTeX 写作助手，擅长诊断编译错误并提供修复方案。请使用中文回复。",
        onReasoningChunk: { [weak self] chunk in self?.streamingReasoning += chunk },
        onChunk: { [weak self] chunk in self?.streamingText += chunk },
        onComplete: { [weak self] content, reasoning in
            guard let self else { return }
            let msg = AIService.ChatMessage(role: .assistant, content: content, reasoningContent: reasoning.isEmpty ? nil : reasoning)
            self.messages.append(msg)
            self.streamingText = ""
            self.streamingReasoning = ""
            self.isStreaming = false
            self.saveCurrentSession()
        },
        onError: { [weak self] error in
            guard let self else { return }
            let msg = AIService.ChatMessage(role: .assistant, content: "错误：\(error.localizedDescription)")
            self.messages.append(msg)
            self.streamingText = ""
            self.streamingReasoning = ""
            self.isStreaming = false
            self.saveCurrentSession()
        }
    )
}
```

- [ ] **Step 2: 增强 sendMessage() 自动附加 LaTeX 上下文**

在 `sendMessage()` 的 `includeNoteContent` 检测后、finalInput 拼接中新增:

```swift
// 在 sendMessage() 中 includeNoteContent 检测后新增:

if includeLatexContext, let note = currentNoteProvider?() {
    let codeBlockLang = (currentNoteLanguage == .latex) ? "latex" : "markdown"
    finalInput = "以下是我当前文档「\(note.title)」的完整内容：\n\n```\(codeBlockLang)\n\(note.content)\n```\n\n我的问题是：\(finalInput)"
}
```

- [ ] **Step 3: 构建验证**

```bash
xcodebuild build -project ZenKith.xcodeproj -scheme ZenKith -destination 'platform=macOS' 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add ZenKith/ViewModels/AIViewModel.swift
git commit -m "feat: AIViewModel 支持 LaTeX 上下文、选中内容发送、编译错误诊断"
```

---

### Task 10: EditorView 右键菜单 + 快捷键

**Files:**
- Modify: `ZenKith/Views/EditorView.swift`

- [ ] **Step 1: 在 Coordinator 中实现右键菜单**

```swift
// 在 Coordinator 中新增:

func setupContextMenu() {
    guard let tv = textView else { return }
    tv.menu = buildContextMenu()
}

private func buildContextMenu() -> NSMenu {
    let menu = NSMenu()

    let sendToAIItem = NSMenuItem(
        title: "发送选中内容给 AI",
        action: #selector(sendSelectionToAI),
        keyEquivalent: "e"
    )
    sendToAIItem.keyEquivalentModifierMask = [.command, .shift]
    menu.addItem(sendToAIItem)

    menu.addItem(.separator())

    // 标准菜单项
    let copyItem = NSMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    copyItem.keyEquivalentModifierMask = .command
    menu.addItem(copyItem)

    let pasteItem = NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    pasteItem.keyEquivalentModifierMask = .command
    menu.addItem(pasteItem)

    let selectAllItem = NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    selectAllItem.keyEquivalentModifierMask = .command
    menu.addItem(selectAllItem)

    return menu
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

// 在 makeNSView 中调用 setupContextMenu:
// context.coordinator.setupContextMenu()
```

- [ ] **Step 2: ContentView 监听 sendSelectionToAI 通知**

在 `ContentView` 的 body 中添加:

```swift
.onReceive(NotificationCenter.default.publisher(for: .sendSelectionToAI)) { notification in
    if let text = notification.userInfo?["text"] as? String {
        aiViewModel.sendSelectionToAI(text)
    }
}
```

在 PersistenceKeys 中新增通知名:

```swift
static let sendSelectionToAI = Notification.Name("ZenKith.sendSelectionToAI")
```

- [ ] **Step 3: 构建验证**

```bash
xcodebuild build -project ZenKith.xcodeproj -scheme ZenKith -destination 'platform=macOS' 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add ZenKith/Views/EditorView.swift ZenKith/ContentView.swift ZenKith/Utilities/PersistenceKeys.swift
git commit -m "feat: EditorView 右键菜单发送选中内容给 AI + Cmd+Shift+E 快捷键"
```

---

### Task 11: BibManager ViewModel

**Files:**
- Create: `ZenKith/Views/BibManager.swift`

- [ ] **Step 1: 实现 BibManager**

```swift
// ZenKith/Views/BibManager.swift
import Foundation
import Combine

struct BibEntry: Identifiable, Equatable, Codable {
    let id = UUID()
    let key: String
    let type: String         // article, book, inproceedings, etc.
    let author: String
    let title: String
    let journal: String
    let year: String
    let volume: String
    let number: String
    let pages: String
    let doi: String
    let url: String
    let rawFields: [String: String]

    var citationSummary: String {
        let authorShort: String = {
            let parts = author.components(separatedBy: " and ")
            if parts.count == 1 { return parts[0].components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? author }
            if parts.count == 2 { return "\(parts[0].components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? "") & \(parts[1].components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? "")" }
            return "\(parts[0].components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? "") et al."
        }()
        return "\(authorShort) (\(year)), \(title). *\(journal)*"
    }
}

@MainActor
final class BibManager: ObservableObject {
    @Published var entries: [BibEntry] = []
    @Published var searchQuery: String = ""
    @Published var duplicateKeys: [String] = []

    var filteredEntries: [BibEntry] {
        if searchQuery.isEmpty { return entries }
        let q = searchQuery.lowercased()
        return entries.filter {
            $0.key.lowercased().contains(q) ||
            $0.title.lowercased().contains(q) ||
            $0.author.lowercased().contains(q)
        }
    }

    var allKeys: [String] { entries.map(\.key) }

    func loadBibFiles(from directory: URL? = nil) {
        var allEntries: [BibEntry] = []
        let dir = directory ?? FileManager.default.homeDirectoryForCurrentUser
        guard let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
        for case let fileURL as URL in enumerator where fileURL.pathExtension.lowercased() == "bib" {
            if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                allEntries.append(contentsOf: parseBibtex(content))
            }
        }
        entries = allEntries
        detectDuplicateKeys()
    }

    func citeKeys(for prefix: String) -> [String] {
        let lower = prefix.lowercased()
        return entries.map(\.key).filter { $0.lowercased().contains(lower) }
    }

    func findUnusedCitations(texContent: [String]) -> [BibEntry] {
        let allText = texContent.joined(separator: "\n")
        return entries.filter { entry in
            !allText.contains("\\cite{\(entry.key)")
        }
    }

    func findMissingCitations(texContent: String) -> [String] {
        var missing: [String] = []
        let pattern = try? NSRegularExpression(pattern: "\\\\cite\\{([^}]*)\\}", options: [])
        let nsText = texContent as NSString
        pattern?.enumerateMatches(in: texContent, options: [], range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
            guard let match, match.numberOfRanges > 1 else { return }
            let keysStr = nsText.substring(with: match.range(at: 1))
            let keys = keysStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            for key in keys where !entries.contains(where: { $0.key == key }) {
                if !missing.contains(key) { missing.append(key) }
            }
        }
        return missing
    }

    private func parseBibtex(_ content: String) -> [BibEntry] {
        var entries: [BibEntry] = []
        let pattern = try? NSRegularExpression(pattern: "@(\\w+)\\{([^,]+),\\s*([^@]*)", options: [.dotMatchesLineSeparators])
        pattern?.enumerateMatches(in: content, options: [], range: NSRange(location: 0, length: content.utf16.count)) { match, _, _ in
            guard let match, match.numberOfRanges == 4,
                  let typeRange = Range(match.range(at: 1), in: content),
                  let keyRange = Range(match.range(at: 2), in: content),
                  let fieldsRange = Range(match.range(at: 3), in: content) else { return }
            let type = String(content[typeRange]).trimmingCharacters(in: .whitespaces)
            let key = String(content[keyRange]).trimmingCharacters(in: .whitespaces)
            let fields = parseBibFields(String(content[fieldsRange]))
            entries.append(BibEntry(
                key: key, type: type,
                author: fields["author"] ?? "",
                title: fields["title"] ?? "",
                journal: fields["journal"] ?? fields["booktitle"] ?? "",
                year: fields["year"] ?? "",
                volume: fields["volume"] ?? "",
                number: fields["number"] ?? "",
                pages: fields["pages"] ?? "",
                doi: fields["doi"] ?? "",
                url: fields["url"] ?? "",
                rawFields: fields
            ))
        }
        return entries
    }

    private func parseBibFields(_ text: String) -> [String: String] {
        var fields: [String: String] = [:]
        var current: String = text
        while let eqIdx = current.firstIndex(of: "=") {
            let fieldName = String(current[..<eqIdx]).trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ",\n")))
            let afterEq = current[current.index(after: eqIdx)...]
            let fieldNameClean = fieldName.trimmingCharacters(in: .whitespaces)
            guard let val = extractBibValue(from: String(afterEq).trimmingCharacters(in: .whitespaces)) else { break }
            fields[fieldNameClean.lowercased()] = val.value
            let consumed = afterEq.distance(from: afterEq.startIndex, to: afterEq.startIndex) + val.startOffset
            let remaining = val.value + val.endDelimiter
            let nextStart = afterEq.index(afterEq.startIndex, offsetBy: val.value.utf16.count + val.startOffset)
            if afterEq[nextStart...].firstIndex(of: ",") != nil {
                let commaIdx = afterEq[nextStart...].firstIndex(of: ",")!
                current = String(afterEq[afterEq.index(after: commaIdx)...])
            } else {
                break
            }
        }
        return fields
    }

    private func extractBibValue(from text: String) -> (value: String, endDelimiter: String, startOffset: Int, consumedCount: Int)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("{") {
            var depth = 0
            for (i, ch) in trimmed.enumerated() {
                if ch == "{" { depth += 1 }
                else if ch == "}" { depth -= 1; if depth == 0 {
                    let startIdx = trimmed.index(trimmed.startIndex, offsetBy: 1)
                    let endIdx = trimmed.index(trimmed.startIndex, offsetBy: i)
                    return (String(trimmed[startIdx..<endIdx]), "}", 0, i + 1)
                }}
            }
            return (trimmed, "}", 0, trimmed.count)
        }
        if trimmed.hasPrefix("\"") {
            if let endQuote = trimmed[trimmed.index(after: trimmed.startIndex)...].firstIndex(of: "\"") {
                let startIdx = trimmed.index(after: trimmed.startIndex)
                return (String(trimmed[startIdx..<endQuote]), "\"", 0, trimmed.distance(from: trimmed.startIndex, to: trimmed.index(after: endQuote)))
            }
        }
        // 无引用包裹的值
        if let commaIdx = trimmed.firstIndex(of: ",") {
            return (String(trimmed[..<commaIdx]).trimmingCharacters(in: .whitespaces), ",", 0, 0)
        }
        return (trimmed.trimmingCharacters(in: .whitespaces), "", 0, 0)
    }

    private func detectDuplicateKeys() {
        let keys = entries.map(\.key)
        var seen: Set<String> = []
        var dupes: Set<String> = []
        for k in keys {
            if seen.contains(k) { dupes.insert(k) } else { seen.insert(k) }
        }
        duplicateKeys = Array(dupes)
    }
}
```

- [ ] **Step 2: 构建验证**

```bash
xcodebuild build -project ZenKith.xcodeproj -scheme ZenKith -destination 'platform=macOS' 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add ZenKith/Views/BibManager.swift
git commit -m "feat: 添加 BibManager 参考文献管理器"
```

---

### Task 12: BibManagerView 参考文献面板

**Files:**
- Create: `ZenKith/Views/BibManagerView.swift`

- [ ] **Step 1: 实现 BibManagerView**

```swift
// ZenKith/Views/BibManagerView.swift
import SwiftUI

struct BibManagerView: View {
    @ObservedObject var bibManager: BibManager
    var onSelectCiteKey: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 搜索栏
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索参考文献...", text: $bibManager.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.appCaption)
                if !bibManager.searchQuery.isEmpty {
                    Button(action: { bibManager.searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // 条目列表
            if bibManager.filteredEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "book.closed").font(.appFont(size: 28)).foregroundColor(.secondary)
                    Text("未找到参考文献").font(.appCaption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(bibManager.filteredEntries) { entry in
                    BibEntryRow(entry: entry, onDoubleClick: {
                        onSelectCiteKey(entry.key)
                    })
                }
                .listStyle(.plain)
            }

            // 底部警告
            if !bibManager.duplicateKeys.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Label("重复的引用键: \(bibManager.duplicateKeys.joined(separator: ", "))", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
                .padding(8)
            }
        }
    }
}

struct BibEntryRow: View {
    let entry: BibEntry
    var onDoubleClick: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.key)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.accentColor)
            Text(entry.title)
                .font(.system(size: 11))
                .lineLimit(2)
            HStack {
                Text(entry.author)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if !entry.year.isEmpty {
                    Text("(\(entry.year))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(entry.type)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(3)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onDoubleClick() }
    }
}
```

- [ ] **Step 2: 构建验证**

```bash
xcodebuild build -project ZenKith.xcodeproj -scheme ZenKith -destination 'platform=macOS' 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add ZenKith/Views/BibManagerView.swift
git commit -m "feat: 添加 BibManagerView 参考文献浏览面板"
```

---

### Task 13: 集成 BibManager 到 ContentView + 补全引擎

**Files:**
- Modify: `ZenKith/ContentView.swift`
- Modify: `ZenKith/Views/LatexCompletionEngine.swift`

- [ ] **Step 1: ContentView 集成 BibManager**

```swift
// 在 ContentView 中新增:
@StateObject private var bibManager = BibManager()

// 在 onAppear 中加载 bib:
.onAppear {
    // ... 原有代码
    bibManager.loadBibFiles(from: manager.selectedNote?.fileURL.deletingLastPathComponent())
}

// 大纲面板区域改为 TabView:
private var latexLeftPanel: some View {
    TabView {
        let outlineItems = LatexOutliner.parse(manager.editingContent)
        OutlinePanelView(items: outlineItems) { lineNumber in
            NotificationCenter.default.post(name: .scrollToLine, object: nil, userInfo: ["line": lineNumber])
        }
        .tabItem { Label("大纲", systemImage: "list.bullet") }

        BibManagerView(bibManager: bibManager) { citeKey in
            manager.editingContent += "\\cite{\(citeKey)}"
        }
        .tabItem { Label("参考文献", systemImage: "books.vertical") }
    }
    .frame(width: min(240, 260))
}

// 在 editorPane 中使用 latexLeftPanel:
// 替换之前的 latexOutlinePanel 为 latexLeftPanel
```

**注意:** SwiftUI macOS 上 `TabView` 的 `tabItem` 需配合 `Picker` 或其他自定义分段控件。替代方案：使用 `Picker` 切换大纲/参考文献面板。

更简单方案 — 用分段控件切换:

```swift
@State private var leftPanelTab = 0

private var latexLeftPanel: some View {
    VStack(spacing: 0) {
        Picker("", selection: $leftPanelTab) {
            Text("大纲").tag(0)
            Text("文献").tag(1)
        }
        .pickerStyle(.segmented)
        .padding(4)

        if leftPanelTab == 0 {
            let outlineItems = LatexOutliner.parse(manager.editingContent)
            OutlinePanelView(items: outlineItems) { lineNumber in
                NotificationCenter.default.post(name: .scrollToLine, object: nil, userInfo: ["line": lineNumber])
            }
        } else {
            BibManagerView(bibManager: bibManager) { citeKey in
                manager.editingContent += "\\cite{\(citeKey)}"
            }
        }
    }
}
```

- [ ] **Step 2: 连接 BibManager 到补全引擎**

在 `ContentView.swift` 中，当 bib 数据变化时更新补全引擎:

```swift
// 在 ContentView 中新增:
.onChange(of: bibManager.allKeys) {
    // 通知补全引擎更新引用键列表
    NotificationCenter.default.post(
        name: .bibKeysDidUpdate,
        object: nil,
        userInfo: ["keys": bibManager.allKeys]
    )
}
```

EditorView Coordinator 监听:

```swift
// 在 Coordinator init 中新增:
NotificationCenter.default.addObserver(
    self,
    selector: #selector(handleBibKeysUpdate(_:)),
    name: .bibKeysDidUpdate,
    object: nil
)

@objc private func handleBibKeysUpdate(_ notification: Notification) {
    if let keys = notification.userInfo?["keys"] as? [String] {
        completionEngine.setCiteKeys(keys)
    }
}
```

- [ ] **Step 3: 构建验证**

```bash
xcodebuild build -project ZenKith.xcodeproj -scheme ZenKith -destination 'platform=macOS' 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add ZenKith/ContentView.swift ZenKith/Views/EditorView.swift ZenKith/Utilities/PersistenceKeys.swift
git commit -m "feat: 集成 BibManager 到大纲面板 + cite key 补全联动"
```

---

### Task 14: SyncTeX 反向搜索

**Files:**
- Modify: `ZenKith/Services/LatexService.swift`
- Modify: `ZenKith/ContentView.swift`

- [ ] **Step 1: LatexService 新增 synctex 查询方法**

```swift
// 在 LatexService 中新增:

/// 通过 SyncTeX 查询 PDF 点击位置对应的源码行号
static func synctexQuery(pdfURL: URL, page: Int, x: Double, y: Double) -> Int? {
    let task = Process()
    task.launchPath = "/usr/bin/env"
    task.arguments = ["synctex", "edit", "-o", "\(page):\(Int(x)):\(Int(y)):\(pdfURL.path)"]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice
    do { try task.run(); task.waitUntilExit() } catch { return nil }
    guard let data = try? pipe.fileHandleForReading.readToEnd(),
          let output = String(data: data, encoding: .utf8) else { return nil }

    // SyncTeX edit 输出格式: "File: <line>:<col>:<path>"
    if let fileLine = output.components(separatedBy: "\n")
        .first(where: { $0.starts(with: "File:") }),
       let lineStr = fileLine.components(separatedBy: ":").dropFirst().first,
       let line = Int(lineStr.trimmingCharacters(in: .whitespaces)) {
        return line
    }
    return nil
}
```

- [ ] **Step 2: ContentView 中 PDFKitView 点击事件**

修改 `PDFKitView` 的 `makeNSView` 实现:

```swift
struct PDFKitView: NSViewRepresentable {
    var url: URL?
    var document: PDFDocument?
    var onPDFClick: ((Int, Double, Double) -> Void)?  // page, x, y

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        // 添加点击手势
        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePDFClick(_:)))
        pdfView.addGestureRecognizer(click)
        return pdfView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onClick: onPDFClick)
    }

    final class Coordinator: NSObject {
        var onClick: ((Int, Double, Double) -> Void)?

        init(onClick: ((Int, Double, Double) -> Void)?) {
            self.onClick = onClick
        }

        @objc func handlePDFClick(_ gesture: NSClickGestureRecognizer) {
            guard let pdfView = gesture.view as? PDFView,
                  let page = pdfView.currentPage,
                  let onClick else { return }
            let point = gesture.location(in: pdfView)
            let converted = pdfView.convert(point, to: page)
            let pageIndex = pdfView.document?.index(for: page) ?? 0
            onClick(pageIndex + 1, converted.x, page.bounds(for: pdfView.displayBox).height - converted.y)
        }
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if let doc = document {
            pdfView.document = doc
        } else if let url, let doc = PDFDocument(url: url) {
            pdfView.document = doc
        }
    }
}
```

- [ ] **Step 3: 在 ContentView 中连接 SyncTeX 回调**

```swift
// 在 latexPreviewPane 中，PDFKitView 部分:
PDFKitView(document: document, onPDFClick: { page, x, y in
    guard let note = manager.selectedNote else { return }
    let pdfURL = note.fileURL.deletingPathExtension().appendingPathExtension("pdf")
    if let line = LatexService.synctexQuery(pdfURL: pdfURL, page: page, x: x, y: y) {
        NotificationCenter.default.post(
            name: .scrollToLine,
            object: nil,
            userInfo: ["line": line]
        )
    }
})
```

- [ ] **Step 4: 构建验证**

```bash
xcodebuild build -project ZenKith.xcodeproj -scheme ZenKith -destination 'platform=macOS' 2>&1 | tail -5
```

- [ ] **Step 5: Commit**

```bash
git add ZenKith/Services/LatexService.swift ZenKith/ContentView.swift
git commit -m "feat: 实现 SyncTeX 反向搜索（PDF点击跳转源码）"
```

---

### Task 15: 最终集成验证

- [ ] **Step 1: 全量构建测试**

```bash
xcodebuild build -project ZenKith.xcodeproj -scheme ZenKith -destination 'platform=macOS' 2>&1 | tail -20
```

- [ ] **Step 2: 运行全部测试**

```bash
xcodebuild test -project ZenKith.xcodeproj -scheme ZenKith -destination 'platform=macOS' 2>&1 | tail -20
```

- [ ] **Step 3: 确认所有通知名已注册**

确保 `PersistenceKeys.swift` 中包含所有新增通知:

```swift
extension Notification.Name {
    static let scrollToLine = Notification.Name("ZenKith.scrollToLine")
    static let sendSelectionToAI = Notification.Name("ZenKith.sendSelectionToAI")
    static let sendCompileErrorsToAI = Notification.Name("ZenKith.sendCompileErrorsToAI")
    static let bibKeysDidUpdate = Notification.Name("ZenKith.bibKeysDidUpdate")
    static let outlineSelectionChanged = Notification.Name("ZenKith.outlineSelectionChanged")
}
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: 完成所有 LaTeX 专业编辑功能集成验证"
```
