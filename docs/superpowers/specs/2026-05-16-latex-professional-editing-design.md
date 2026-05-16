# ZenKith 专业级 LaTeX 编辑功能设计

> 日期: 2026-05-16 | 方案: 渐进增强 (方案A)

## 概述

在现有架构上以最小侵入方式扩展六个 LaTeX 专业编辑功能：AI+LaTeX 深度集成、编译错误定位、文档大纲、代码片段快速插入、SyncTeX 反向搜索、参考文献管理。

## 架构原则

- 每个功能作为独立模块挂载到现有 MVVM 架构
- 遵循 `@MainActor` + `ObservableObject` + Service 层模式
- 遵循 TDD：每个模块先写测试、再写实现

## 功能详情

### 1. AI+LaTeX 深度集成

**改动文件:**
- `AIViewModel.swift` — 新增属性和方法
- `EditorView.swift` — 右键菜单、快捷键触发

**AIViewModel 新增:**
- `includeLatexContext: Bool` — 开关是否自动附加 .tex 源码
- `sendMessage()` 增强 — 检测当前文件为 .tex 时自动包装源码为 LaTeX 代码块
- `sendSelectionToAI(_ text: String)` — 将编辑器选中文本发到 AI
- `sendCompileErrorsToAI(_ errors: [String])` — 将编译错误+源码发到 AI
- `currentNoteLanguage: EditorLanguage?` — 感知当前文件语言

**EditorView 新增:**
- 右键菜单「发送选中内容给AI」
- 快捷键 Cmd+Shift+E 发送选中内容给 AI

**ContentView 新增:**
- 编译日志面板增加「发送错误给AI」按钮

### 2. 编译错误定位

**改动文件:**
- `LatexService.swift` — 新增 `LatexError` 结构体，`extractErrors()` 返回结构化数据
- `ContentView.swift` — 错误日志项可点击
- `EditorView.swift` — 接收 `scrollToLine` 通知跳转

**LatexError 结构体:**
```swift
struct LatexError: Equatable {
    let line: Int
    let message: String
    let type: ErrorType  // .error / .warning
}
```

**交互流程:**
1. 编译完成后 `LatexCompileResult.errors` 返回 `[LatexError]`
2. ContentView 编译日志面板中错误项显示为可点击按钮
3. 点击发送 `Notification.Name.scrollToLine` 通知，携带行号
4. EditorView 接收通知 → 滚动到目标行 → 高亮行背景

### 3. 文档大纲

**新增文件:**
- `Views/LatexOutliner.swift` — 纯函数解析器，提取章节结构
- `Views/OutlinePanelView.swift` — 左侧树形面板 NSViewRepresentable

**LatexOutliner 解析规则:**
- 匹配 `\section{...}`, `\subsection{...}`, `\subsubsection{...}`, `\chapter{...}`
- 返回层级树: `[OutlineItem]`，每个 item 含 `title`, `lineNumber`, `level`, `children`
- 忽略注释行中的章节命令

**OutlinePanelView:**
- 左侧固定面板，LaTeX 模式下显示，Markdown 模式下隐藏
- `NSOutlineView` 树形展示，点击跳转到对应行
- 高亮当前所在章节（基于光标位置）
- 面板宽度可拖拽调整

### 4. 代码片段快速插入

**改动文件:**
- `Views/LatexCompletionEngine.swift` — 增加环境补全
- `Views/EditorView.swift` — 工具栏插入按钮 + InsertSnippetMenu

**环境补全增强:**
- 输入 `\begin{` 时触发环境列表补全（table, figure, equation, itemize, enumerate, align, matrix 等25+环境）
- 选中后自动插入 `\begin{env}\n\n\end{env}` 并定位光标到中间

**InsertSnippetMenu (工具栏):**
- 工具栏「插入」按钮（LaTeX 模式下显示）
- 下拉菜单按类别组织：
  - 表格: tabular, tabularx, longtable
  - 矩阵: matrix, pmatrix, bmatrix, vmatrix
  - 图形: figure + includegraphics, subfigure, wrapfigure
  - 列表: itemize, enumerate, description
  - 定理: theorem, lemma, proof, definition
  - 数学: equation, align, gather, cases
- 选中后插入完整模板

### 5. SyncTeX 反向搜索

**改动文件:**
- `LatexService.swift` — 编译时强制启用 `--synctex=1`
- `Views/PreviewWebView.swift` 或 PDFKitView — PDF 点击事件
- `EditorView.swift` — 接收跳转通知

**实现方案:**
- 编译时始终传递 `--synctex=1` 参数
- PDFView 设置 `PDFView` delegate，捕获 `PDFViewAnnotationHit` 或使用 `NSClickGestureRecognizer`
- 读取 `.synctex.gz` 文件，调用 `synctex` CLI 工具解析点击位置对应的源码行
- 发送 `scrollToLine` 通知

**注意:** 反向搜索在 MathJax 降级模式下不可用，仅在原生 PDF 编译时可用。

### 6. 参考文献管理

**新增文件:**
- `Views/BibManager.swift` — BibViewModel，管理 .bib 数据
- `Views/BibManagerView.swift` — 表格视图 + 搜索筛选

**BibManager (ViewModel):**
- 读取目录下所有 `.bib` 文件，解析条目（支持 BibTeX 标准字段）
- `BibEntry` 结构体: key, type, author, title, year, journal, 等
- `searchEntries(query:)` — 模糊搜索条目
- `findUnusedCitations(allTexContent: [String])` — 检测未使用的引用
- `findMissingCitations(citedKeys: Set<String>)` — 检测 .tex 引用了但 .bib 中不存在的 key
- `duplicateKeys()` — 检测重复的 citation key

**BibManagerView:**
- `NSTableView` 或 SwiftUI `Table` 列: 关键词、作者、标题、年份、类型
- 搜索栏实时筛选
- 双击条目将 `\cite{key}` 插入编辑器
- 底部显示警告区（未使用引用、缺失引用计数）

**补全引擎集成:**
- 输入 `\cite{` 时列出 .bib 中所有 citation keys
- 按最近使用或字母排序

## 组件关系图

```
ContentView
  ├── OutlinePanelView (左, LaTeX模式) ← LaTeXOutliner
  ├── EditorView (中)
  │    ├── LatexCompletionEngine (增强)
  │    ├── LatexSyntaxHighlighter
  │    ├── scrollToLine 接收者
  │    └── AI ViewModel 交互 (右键/快捷键)
  ├── AIDrawer (右) ← AIViewModel (增强)
  ├── PDFPreview (右) ← SyncTeX 回调 → scrollToLine
  └── BibManagerView (底部标签页，与大纲面板共用左侧区域) ← BibManager
```

## 通知通信

| 通知名 | 发送者 | 接收者 | 携带数据 |
|--------|--------|--------|----------|
| `.scrollToLine` | ContentView(错误面板), OutlinePanelView, PDFKitView | EditorView | `Int` (行号) |
| `.sendSelectionToAI` | EditorView | AIViewModel | `String` (选中文本) |
| `.sendCompileErrorsToAI` | ContentView | AIViewModel | `[LatexError]` |
| `.bibDataDidChange` | BibManager | ContentView, LatexCompletionEngine | — |

## 测试策略

遵循 TDD 铁律：先写失败测试，再写最小实现。

| 模块 | 测试类型 | 测试内容 |
|------|---------|---------|
| LatexOutliner | 单元测试 | 章节解析、层级正确、注释忽略 |
| LatexError 解析 | 单元测试 | 行号提取、错误类型分类 |
| BibManager | 单元测试 | .bib 解析、搜索、引用检测 |
| LatexCompletionEngine(扩展) | 现有测试增强 | 环境补全、cite key 补全 |
| AIViewModel(扩展) | 集成测试 | LaTeX 上下文附加、选中内容发送 |

## 文件变更清单

| 操作 | 文件 |
|------|------|
| 修改 | `ViewModels/AIViewModel.swift` |
| 修改 | `Views/EditorView.swift` |
| 修改 | `Views/LatexCompletionEngine.swift` |
| 修改 | `Services/LatexService.swift` |
| 修改 | `ContentView.swift` |
| 新增 | `Views/LatexOutliner.swift` |
| 新增 | `Views/OutlinePanelView.swift` |
| 新增 | `Views/InsertSnippetMenu.swift` |
| 新增 | `Views/BibManager.swift` |
| 新增 | `Views/BibManagerView.swift` |
