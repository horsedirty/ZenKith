# ZenKith 编辑器体验改进 设计文档

> 日期: 2026-05-16 | 方案: 渐进增强

## 概述

针对九个独立问题进行渐进式修复和增强，不改动架构，仅在现有 MVVM + Service 模式上做最小化修改。

---

## 1. 菜单栏双语本地化

**现状:** 所有自定义菜单硬编码中文，系统菜单默认英文，导致中英混杂。无本地化基础设施。

**方案:** 建立 Apple 推荐的 String Catalog 本地化系统。

**改动文件:**
- 新建 `ZenKith/Localizable.xcstrings` — String Catalog，包含所有菜单文本的中/英版本
- 修改 `ZenKithApp.swift:50-128` — 所有 `Button("中文")` → `Button("menu_key", bundle: .main)` 或使用 `Text("localized_key")`
- 修改 `PersistanceKeys.swift` — 新增通知名 `toggleSidebar`/`toggleAIDrawer`/`exportNote` 已存在，无需改动

**关键决策:**
- 使用 Xcode 15+ 的 String Catalog (`.xcstrings`) 而非旧式 `.strings` 文件，支持可视化编辑
- 所有自定义菜单项使用 `LocalizedStringResource` 或 `NSLocalizedString`
- 系统菜单组（File/Edit/View/Window/Help）保持跟随系统语言不变
- 自定义菜单（显示/导出）根据 `.xcstrings` 中的系统语言自动切换

**示例结构:**
```json
{
  "new_note" : { "extractionState" : "manual", "localizations" : {
    "en" : { "stringUnit" : { "value" : "New Note" } },
    "zh-Hans" : { "stringUnit" : { "value" : "新建笔记" } }
  }}
}
```

---

## 2. .bib 解析修复 + 显示增强

**现状:** `BibManager.parseBibtex()` 中的正则 `@(\\w+)\\s*\\{\\s*(\\S+)\\s*,\\s*([^@]*?)\\}\\s*$` 末尾的 `$` 锚定整个字符串结尾，导致只能解析 `.bib` 文件的最后一个条目。`NoteFileType.bibTeX` 对应文件直接进入 `nonEditablePreview`，用户根本看不到 BibManagerView。

**根因:**
1. 正则 `$` 锚定导致只匹配第一个条目（或最后一个，取决于 `.dotMatchesLineSeparators` 行为），实践中大量条目丢失
2. `NoteFileType.bibTeX` 类型文件被视为"不可编辑"，直接渲染为图标预览，不进入编辑模式，导致左侧面板的"文献"标签页无法显示内容

**方案:**
修复正则 + 将 `.bib` 文件引导到可编辑预览以便触发左侧面板加载。

**改动文件:**
- `BibManager.swift:84` — 修复 `parseBibtex`：改用逐条目扫描方式替代一次性正则
  - 在内容中查找每个 `@type{` 的起始位置
  - 从 `{` 之后用括号栈平衡算法找到匹配的 `}`（处理嵌套 braces）
  - 提取 key（`{` 后到第一个 `,` 之间）和 fields（剩余的逗号分隔 key=value 对）
  - 对每个 field 用 `extractBibValue` 解析 value（支持 `{...}` 和 `"..."` 包裹）
- `BibEntry` 结构体增加字段：`doi`, `url`, `publisher`, `volume`, `number`, `pages`
- `BibManagerView.swift` — 增强每个条目的信息展示，显示更多字段（author/year/journal/title 四行布局）
- `SidebarView.swift:188` — 对于 `.bibTeX` 类型文件，图标颜色保持橙色
- `ContentView.swift:342` — 考虑为 `.bibTeX` 类型增加特殊处理：选中 .bib 文件时，`editorLanguage` 设为 `.latex` 以触发大纲/文献面板加载

**验收标准:**
- 一个包含 10+ 条目的 `.bib` 文件能正确解析出全部条目
- BibManagerView 中每个条目显示: key（强调色）、title、author(year)、journal、type 标签
- 双击条目可将 `\cite{key}` 插入编辑器

---

## 3. 自定义查找替换栏

**现状:** 仅启用 NSTextView 原生查找栏（`usesFindBar = true`），功能有限：无"高亮所有匹配项"、无不离开查找栏的替换体验。

**方案:** 在编辑器顶部嵌入自定义查找替换栏，类似 VS Code 的查找栏。

**改动文件:**
- 新建 `ZenKith/Views/EditorFindBar.swift` — 自定义查找替换栏组件
- 修改 `EditorView.swift` — 在 `makeNSView` 中嵌入查找栏，添加快捷键 Cmd+F 触发

**EditorFindBar 设计:**
- 外观：编辑器顶部 36pt 高的水平条，半透明背景，与编辑器无缝衔接
- 查找输入框 + 匹配计数（如 "3 / 15"）+ 上一个/下一个按钮 + 区分大小写开关
- 替换输入框 + 替换按钮 + 全部替换按钮（展开式，点击切换按钮显示替换行）
- 关闭按钮（Esc 关闭）
- 高亮逻辑：使用 `NSTextView` 的 `showFindIndicator(for:)` 或遍历 `NSTextStorage` 添加临时背景色 attribute
- 区分大小写：使用 `.caseInsensitive` 选项控制 `String.range(of:)` 查找
- 上一个/下一个：维护 `currentMatchIndex`，遍历所有匹配位置，`selectAndScroll(to:)` 跳转

**交互:**
- Cmd+F 打开查找栏（若查找栏已打开则聚焦查找输入框）
- Cmd+Option+F 打开查找替换栏（展开替换行）
- Esc 关闭查找栏
- Enter 跳转到下一个匹配
- Shift+Enter 跳转到上一个匹配
- 编辑器中同时高亮所有匹配项（黄色半透明背景）

---

## 4. PDF 点击跳转（SyncTeX 反向搜索）

**现状:** 代码层面 SyncTeX 反向搜索已实现（PDFKitView 有 `NSClickGestureRecognizer` → `handlePDFClick` → `synctexQuery` → `scrollToLine`），但用户反馈点击 PDF 完全没反应。`sinctex` CLI 工具已确认安装。

**根因分析:** `PDFView` 自带复杂的点击手势处理（文本选择、注释点击、链接跳转），在 PDFView 上直接添加 `NSClickGestureRecognizer` 会被内部手势拦截。`NSClickGestureRecognizer` 与 PDFView 的手势识别存在冲突，导致 `handlePDFClick` 完全不被调用。

**方案:** 放弃 `NSClickGestureRecognizer`，改为子类化 `PDFView` + 重写 `mouseDown(with:)`。这种方式不依赖手势识别器，直接从事件处理链的最底层拦截点击，绕过 PDFView 内部手势的冲突。

**改动文件:**
- `ContentView.swift:740-783` (PDFKitView) — 将 PDFKitView 内部使用的 PDFView 替换为自定义 SyncTeXPDFView 子类
- 新增 `SyncTeXPDFView` 类（内嵌于 PDFKitView 或单独文件）

**SyncTeXPDFView 设计:**
```swift
final class SyncTeXPDFView: PDFView {
    var onPageClick: ((Int, Double, Double) -> Void)?

    override func mouseDown(with event: NSEvent) {
        // 先让父类处理选择/滚动等标准行为
        super.mouseDown(with: event)

        // 提取点击坐标进行反向搜索
        let point = convert(event.locationInWindow, from: nil)
        guard let page = page(for: point, nearest: false),
              let doc = document else { return }
        let pageIndex = doc.index(for: page)
        let pagePoint = convert(point, to: page)
        let pageHeight = page.bounds(for: displayBox).height
        onPageClick?(pageIndex + 1, pagePoint.x, pageHeight - pagePoint.y)
    }
}
```

**注意事项:**
- 调用 `super.mouseDown` 确保标准 PDFView 行为（选择、滚动、链接）不受影响
- 空页或点击在页面外时安全返回
- 同步搜索在主线程完成，对于大型文档使用 `synctex` CLI 可能有短暂延迟（通常 <100ms）

---

## 5. 文件浏览器选中反馈增强

**现状:** SwiftUI `List` 的 sidebar 样式自带选中高亮，但视觉反馈较弱。且 `NoteFile.id` 是每次 `init` 新生成的 `UUID`，`refreshFileList()` 时会刷新导致选中状态丢失。

**方案:** 图标填充 + 选中持久化。

**改动文件:**
- `SidebarView.swift:187-188` — 选中时图标使用 `.fill` 变体（如 `doc.text` → `doc.text.fill`）
- `NotesManager.swift` — 在 `refreshFileList()` 时保留原有选中状态（用文件路径而非 UUID 匹配）

**具体修改:**
- `noteRow` 中：检测 `manager.selectedNote?.id == note.id`，选中时图标改为 `"\(note.fileType.systemImage).fill"`
- `NotesManager.refreshFileList()` 中：刷新前保存 `selectedNote?.fileURL`，刷新后用路径重新定位选中的笔记

**可用的填充图标映射:**
- `.markdown` → `doc.richtext.fill`
- `.latexSource` → `doc.text.fill`
- `.bibTeX` → `book.fill`
- `.styleClass` → `paintbrush.fill`
- `.image` → `photo.fill`
- `.pdfDoc` → `doc.fill`
- `.logAux` → `terminal.fill`
- `.other` → `doc.fill`

**验收标准:**
- 单击文件/文件夹后，图标变为填充版本 + 行保持高亮
- 创建新文件或切换目录后，选中状态不丢失

---

## 6. 中文输入法光标消失

**现状:** 使用拼音输入法在 NSTextView 中输入中文时，`textDidChange` 在 IME 组字阶段触发 → 更新 SwiftUI binding → `updateNSView` 调用 → 第 113 行 `tv.textStorage?.setAttributedString(...)` 替换全文 → 销毁 IME 组字状态（marked text）。

**根因:** `updateNSView` 中的外部文本变更处理（第 110-117 行）没有检查 `hasMarkedText` 状态。

**方案:** 在 IME 组字期间跳过 SwiftUI binding → updateNSView 的文本替换。

**改动文件:**
- `EditorView.swift:110-117` (updateNSView) — 增加 `hasMarkedText` 守卫
- `EditorView.swift:292-305` (textDidChange) — 在 IME 组字期间仅记录文本变化，不更新 binding

**具体逻辑:**
```swift
// 在 textDidChange 中:
func textDidChange(_ notification: Notification) {
    guard let tv = textView else { return }
    if isProgrammaticChange { return }

    // IME 组字期间不更新 binding（避免破坏 marked text）
    if tv.hasMarkedText() {
        self._pendingText = tv.string  // 记录最终文本
        return
    }

    isInternalEdit = true
    text = tv.string
    isInternalEdit = false
    // ... 后续逻辑
}

// 在 updateNSView 中:
if tv.string != text, !context.coordinator.isInternalEdit {
    // IME 组字期间不替换文本
    if tv.hasMarkedText() { return }
    // ... 原来的替换逻辑
}
```

**验收标准:**
- 使用拼音输入法输入中文时，光标所在的组字文本不会消失
- IME 组字结束后文本正确同步到 binding

---

## 7. `\ref`/`\cite` 编译显示 `??`

**现状:** 用户输入 `\ref{label}` 或 `\cite{key}` 后编译 PDF 显示 `??`。补全弹窗正常出现。`\ref` 没有 label 补全支持。

**根因:**
1. `\ref` 显示 `??` — 通常是多轮编译不够（需 2+ 轮），当前代码做 2-3 轮，理论上够用。排查方向：第三轮检测 `needsThirdPass` 可能漏匹配某些 LaTeX 日志模式
2. `\cite` 显示 `??` — `needsBibtexPass` 扫描 `.bib` 文件仅在当前工作目录。若用户 `.bib` 文件在子目录或被 `.gitignore` 导致找不到
3. `\ref{` 没有补全 — `LatexCompletionEngine.evaluateState` 只匹配 `\cite{` 和 `\begin{`，需要增加 `\ref{` 的 label 补全

**方案:**
- 修复 `needsThirdPass` 的日志匹配，增加更多模式
- 增加 `needsBibtexPass` 的日志输出（编译日志中告知用户 BibTeX 是否被跳过）
- `LatexCompletionEngine` 增加 `\ref{` label 补全：在 `evaluateState` 中检测 `\ref{` 前缀，从当前文档提取所有 `\label{...}` 提供补全

**改动文件:**
- `LatexService.swift:210-213` — `needsThirdPass` 增强
- `LatexCompletionEngine.swift:142-179` — `evaluateState` 增加 `\ref{` 检测
- `LatexCompletionEngine.swift` — 新增 `detectRefPrefix` 方法

**needsThirdPass 增强:**
当前模式仅匹配 `"Rerun to get cross-references"`。增加：
```
"rerun LaTeX"
"Label(s) may have changed"
"There were undefined references"
"Citation(s) may have changed"
```

**\ref label 补全:**
- 新增 `refLabels: [String]` 属性
- 新增 `setRefLabels(_:)` 方法
- 新增 `FilterMode.refLabel` 枚举值
- 在 `evaluateState` 中调用 `detectRefPrefix`，检测光标前 50 字符内是否有 `\ref{` 前缀（不含 `}`)
- `ContentView` 或 `EditorView` 在文档内容变化时重新提取所有 `\label{...}` 并传递给 completionEngine

---

## 8. 花括号匹配高亮

**现状:** 无此功能。

**方案:** 在 `textViewDidChangeSelection` 中检测光标位置，若光标紧跟在 `}` 之后，向前查找匹配的 `{`，用黄色半透明背景高亮。

**改动文件:**
- `EditorView.swift:309-328` (textViewDidChangeSelection) — 增加括号匹配逻辑
- `EditorView.swift` Coordinator — 新增 `braceMatchLayer: CAShapeLayer?` 属性

**实现逻辑:**
1. 获取当前光标位置 `cursorPos = tv.selectedRange().location`
2. 检查 `cursorPos > 0 && text.character(at: cursorPos - 1) == "}"`
3. 从 `cursorPos - 2` 向左扫描，使用栈平衡算法查找匹配的 `{`：
   - 遇到 `}` 则深度 +1
   - 遇到 `{` 则深度 -1
   - 深度为 0 时找到匹配的 `{`
4. 获取匹配 `{` 的字符 rect，用 `CAShapeLayer` 绘制黄色高亮背景
5. 高亮在光标移动后自动清除

**性能考虑:**
- 仅扫描当前行 ± 少量行，最坏情况 O(n)，对于 600 行文件可忽略不计
- 使用 `textView.textStorage?.string` 直接访问字符，不需要创建新字符串

---

## 9. 编辑区输入卡顿

**现状:** 600+ 行 LaTeX 文件输入每个字符都卡顿。

**根因分析:**
1. 每次 `textDidChange` → `updateNSView` → 第 128-130 行：LaTeX 模式下无条件调用 `applyFullHighlightIfNeeded`，触发**全文**语法高亮重新计算
2. 第 319 行 ContentView 中 `LatexOutliner.parse(manager.editingContent)` 在每次 SwiftUI 渲染时重新解析整个文档
3. SyncTeX 反向搜索中的 `synctexQuery` 是同步阻塞调用（但仅在点击 PDF 时触发，不是打字卡顿的原因）
4. 补全引擎 `evaluateState` 在每次按键后触发，但在 LaTeX 模式下开销较小

**方案:** 增量渲染 + 防抖缓存。

**改动文件:**
- `EditorView.swift:127-131` (updateNSView) — 移除 LaTeX 模式下的无条件全文高亮调用，改为仅在初始化/语言切换时执行
- `EditorView.swift:301-304` (textDidChange) — 移除补全引擎的每次按键触发（已在 `textViewDidChangeSelection` 中触发）
- `ContentView.swift:319` — 为 `LatexOutliner.parse` 添加结果缓存（仅在内容变化时重新解析，使用 hash 做 cache key）

**具体修改:**

**1. 语法高亮优化:**
```swift
// 移除 updateNSView 中的:
if language == .latex {
    context.coordinator.applyFullHighlightIfNeeded(to: tv)
}
// 因为 NSTextStorageDelegate 的 didProcessEditing 已经做增量高亮
// 保留 applyFullHighlightIfNeeded 仅在首次初始化时调用
```

**2. 大纲解析缓存:**
在 ContentView 中新增：
```swift
@State private var cachedOutlineHash: Int = 0
@State private var cachedOutlineItems: [OutlineItem] = []
```
当 `manager.editingContent.hashValue != cachedOutlineHash` 时才重新解析。

**3. 补全引擎触发优化:**
`textDidChange` 中移除 `completionEngine.evaluateState` 调用，仅依赖 `textViewDidChangeSelection` 触发（光标移动时才评估补全状态），因为实际输入触发了光标移动。

**验收标准:**
- 600 行 LaTeX 文件编辑流畅，无明显卡顿
- 语法高亮在编辑后正确更新（仅局部更新，非全文重新计算）
- 大纲面板在内容变化后 0.3s 内更新

---

## 文件变更清单

| 操作 | 文件 | 关联问题 |
|------|------|---------|
| 新建 | `ZenKith/Localizable.xcstrings` | #1 菜单栏本地化 |
| 修改 | `ZenKith/ZenKithApp.swift` | #1 菜单栏本地化 |
| 修改 | `ZenKith/Views/BibManager.swift` | #2 .bib 解析 |
| 修改 | `ZenKith/Views/BibManagerView.swift` | #2 .bib 显示 |
| 新建 | `ZenKith/Views/EditorFindBar.swift` | #3 查找替换 |
| 修改 | `ZenKith/Views/EditorView.swift` | #3, #6, #8, #9 |
| 修改 | `ZenKith/ContentView.swift` | #4, #7, #9 |
| 修改 | `ZenKith/Services/LatexService.swift` | #7 |
| 修改 | `ZenKith/Views/LatexCompletionEngine.swift` | #7 |
| 修改 | `ZenKith/Views/SidebarView.swift` | #5 |
| 修改 | `ZenKith/ViewModels/NotesManager.swift` | #5 |

---

## 测试策略

| 问题 | 测试方式 |
|------|---------|
| #1 菜单栏 | 切换系统语言后验证菜单文本变化；验证字符串 Key 未遗漏 |
| #2 .bib 解析 | 手动测试：准备 10+ 条目 .bib 文件（含嵌套大括号字段），验证全部解析；验证 BibManagerView 显示全部条目 |
| #3 查找替换 | 手动测试：Cmd+F 打开查找栏，输入关键词，验证匹配计数和高亮 |
| #4 PDF 跳转 | 编译带 `\section` 的 .tex，点击 PDF 各 section 验证编辑区跳转 |
| #5 选中反馈 | 点击不同文件，观察图标变化和高亮保持 |
| #6 中文输入 | 使用拼音输入法输入多段中文，验证不消失 |
| #7 \ref/\cite | 编译带 `\ref`/`\cite` 的文档，验证 PDF 显示正确编号 |
| #8 括号匹配 | 将光标放在 `}` 后，验证对应 `{` 高亮 |
| #9 性能 | 编辑 600+ 行文件，主观判断流畅度 |

---

## 注意事项

1. **\ref/\cite 问题本质是 LaTeX 编译流程问题**，与编辑器代码逻辑无关。`LatexService.compile` 已实现 bibtex + 多轮编译，但可能 `.bib` 文件路径匹配、`needsThirdPass` 模式覆盖不足导致问题。
2. **性能问题的核心是 `updateNSView` 中无条件全文高亮**。`LatexSyntaxHighlighter` 本身已支持增量高亮（`highlightLines`），只是被无条件全文调用覆盖了。
3. **String Catalog 需要在 Xcode 中创建和维护**，通过 CLI 创建 `.xcstrings` 文件不做的事（需要用 Xcode 编辑器配置），但可以手写 JSON 格式的初始内容。
