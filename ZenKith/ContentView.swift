import SwiftUI
import Combine
import AppKit
import PDFKit

/// 主内容布局：左侧笔记列表（可折叠） + 中央编辑/预览区 + 右侧可呼出 AI 抽屉
struct ContentView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var manager: NotesManager
    @EnvironmentObject var aiViewModel: AIViewModel
    @Environment(\.openWindow) var openWindow

    @State private var showAIDrawer = false
    @State private var aiDrawerWidth: CGFloat = 340
    @State private var selectedText: String = ""
    @State private var dragStartWidth: CGFloat = 0
    @State private var sidebarCollapsed = false

    // LaTeX 编译状态
    @State private var isCompiling = false
    @State private var compilePass = (0, 0)
    @State private var compileLog = ""
    @State private var compilePDFData: Data?
    @State private var showCompileLog = false

    // 编译缓存：texURL → (PDF data, 源码hash)
    @State private var compileCache: [URL: (data: Data, hash: Int)] = [:]

    // PDFDocument 对象缓存，避免在流式渲染时重复创建
    @State private var cachedPDFDocument: PDFDocument?
    @State private var cachedPDFSourceURL: URL?

    // MARK: - Body

    var body: some View {
        baseView
            .onReceive(NotificationCenter.default.publisher(for: .sendCompileErrorsToAI)) { notification in
                guard let errors = notification.userInfo?["errors"] as? String,
                      let source = notification.userInfo?["source"] as? String else { return }
                aiViewModel.sendCompileErrorsToAI(errorsText: errors, source: source)
            }
            .sheet(isPresented: $showCompileLog) {
                makeCompileLogSheet(errors: LatexService.extractErrorLines(from: compileLog))
            }
    }

    @ViewBuilder
    private var baseView: some View {
        Group {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    if !sidebarCollapsed {
                        SidebarView(manager: manager, settings: settings)
                            .frame(width: min(280, geometry.size.width * 0.25))
                        sidebarToggleDivider
                    } else {
                        collapsedSidebar
                        sidebarToggleDivider
                    }

                    mainContentArea

                    if showAIDrawer {
                        Divider()
                        AIDrawer(viewModel: aiViewModel)
                            .frame(width: max(280, aiDrawerWidth))
                            .overlay(aiDrawerDragHandle)
                            .onAppear { dragStartWidth = aiDrawerWidth }
                    }
                }
            }
        }
        .toolbar { ToolbarItemGroup { toolbarContent } }
        .onAppear {
            aiViewModel.setNoteContentProvider { [manager] in
                guard let note = manager.selectedNote else { return nil }
                return (manager.editingContent, note.displayTitle)
            }
            startScrollMonitor()
        }
        .onDisappear { stopScrollMonitor() }
        .onChange(of: manager.editingContent) {
            DispatchQueue.main.async { manager.scheduleAutoSave() }
        }
        .onChange(of: manager.selectedNote) { _, newNote in
            if let note = newNote {
                let ext = note.fileURL.pathExtension.lowercased()
                if ext == "tex" || ext == "ltx" {
                    settings.editorLanguage = .latex
                    if let cached = compileCache[note.fileURL] {
                        compilePDFData = cached.data
                        if cachedPDFSourceURL != note.fileURL {
                            cachedPDFDocument = PDFDocument(data: cached.data)
                            cachedPDFSourceURL = note.fileURL
                        }
                        compileLog = ""
                    } else {
                        compilePDFData = nil
                        cachedPDFDocument = nil
                        cachedPDFSourceURL = nil
                        compileLog = ""
                    }
                } else if ext == "md" {
                    settings.editorLanguage = .markdown
                    compilePDFData = nil
                    cachedPDFDocument = nil
                    cachedPDFSourceURL = nil
                    compileLog = ""
                }
            }
        }
        .background(Button("") { showAIDrawer.toggle() }
            .keyboardShortcut("i", modifiers: [.command, .shift]).opacity(0))
        .background(Button("") { cycleViewMode() }
            .keyboardShortcut("l", modifiers: [.command, .shift]).opacity(0))
        .background(Button("") { compileLatex() }
            .keyboardShortcut("b", modifiers: [.command]).opacity(0))
        .background(Button("") { sidebarCollapsed.toggle() }
            .keyboardShortcut("s", modifiers: [.command, .shift]).opacity(0))
        .onReceive(NotificationCenter.default.publisher(for: .toggleAIDrawer)) { _ in
            showAIDrawer.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            sidebarCollapsed.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportNote)) { notification in
            if let format = notification.userInfo?["format"] as? ExportService.ExportFormat {
                exportNote(format: format)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .directoryDidChange)) { notification in
            if let url = notification.userInfo?["url"] as? URL {
                settings.defaultDirectoryURL = url
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openPDFTranslation)) { _ in
            openWindow(id: "pdfTranslation")
        }
    }

    // MARK: - 折叠侧边栏

    private var sidebarToggleDivider: some View {
        Button(action: { sidebarCollapsed.toggle() }) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
                .overlay(
                    Image(systemName: sidebarCollapsed ? "chevron.right" : "chevron.left")
                        .font(.appFont(size: 8))
                        .foregroundColor(.secondary)
                        .offset(x: sidebarCollapsed ? 10 : -10)
                )
        }
        .buttonStyle(.borderless)
        .frame(width: 20)
        .contentShape(Rectangle())
        .help(sidebarCollapsed ? "显示目录栏 (Cmd+Shift+S)" : "隐藏目录栏 (Cmd+Shift+S)")
    }

    private var collapsedSidebar: some View {
        VStack(spacing: 8) {
            Button(action: { sidebarCollapsed = false }) {
                Image(systemName: "sidebar.left").font(.appTitle3)
            }
            .buttonStyle(.borderless).help("展开侧边栏")
            Button(action: { showAIDrawer.toggle() }) {
                Image(systemName: "sparkles").font(.appTitle3)
            }
            .buttonStyle(.borderless).help("AI 助手")
            Spacer()
        }
        .padding(.vertical, 8).frame(width: 40)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - AI drawer drag handle

    private var aiDrawerDragHandle: some View {
        HStack {
            Rectangle().fill(Color.clear).frame(width: 4).contentShape(Rectangle())
                .gesture(DragGesture()
                    .onChanged { v in dragStartWidth = max(280, min(600, dragStartWidth - v.translation.width)) }
                    .onEnded { _ in aiDrawerWidth = dragStartWidth })
            Spacer()
        }
    }

    // MARK: - 主内容区

    @ViewBuilder
    private var mainContentArea: some View {
        if let note = manager.selectedNote, !note.fileType.isEditable {
            nonEditablePreview(note)
        } else {
            switch settings.viewMode {
            case .split:  splitView
            case .editor: editorOnlyView
            case .preview: previewPaneOnly
            }
        }
    }

    private var splitView: some View {
        HStack(spacing: 0) {
            editorPane
            Divider()
            previewPane
        }
    }

    private var editorOnlyView: some View { editorPane }
    private var previewPaneOnly: some View { previewPane }

    // MARK: - 非可编辑文件预览（图片、PDF）

    @ViewBuilder
    private func nonEditablePreview(_ note: NoteFile) -> some View {
        switch note.fileType {
        case .image:
            if let nsImage = NSImage(contentsOf: note.fileURL) {
                Image(nsImage: nsImage)
                    .resizable().aspectRatio(contentMode: .fit)
                    .padding()
            } else {
                VStack { Image(systemName: "photo").font(.appLargeTitle); Text("无法加载图片") }
            }
        case .pdfDoc:
            PDFKitView(url: note.fileURL)
        default:
            VStack {
                Image(systemName: note.fileType.systemImage).font(.appLargeTitle)
                Text("\(note.displayTitle)\n二进制文件，无法编辑")
                    .multilineTextAlignment(.center).foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 编辑器

    private var editorPane: some View {
        VStack(spacing: 0) {
            if let note = manager.selectedNote {
                if note.fileType.isEditable {
                    EditorView(
                        text: $manager.editingContent,
                        fontSize: settings.fontSize,
                        language: settings.editorLanguage
                    )
                    .id(note.id)
                } else {
                    Color(nsColor: .controlBackgroundColor)
                        .overlay {
                            VStack(spacing: 12) {
                                Image(systemName: note.fileType.systemImage).font(.appFont(size: 36)).foregroundColor(.secondary)
                                Text("\(note.displayTitle)").font(.appHeadline)
                                Text("此文件类型不可编辑").foregroundColor(.secondary)
                            }
                        }
                }
                noteStatusBar(note)
            } else {
                emptyStateView
            }
        }
    }

    // MARK: - 预览

    private var previewPane: some View {
        Group {
            if let note = manager.selectedNote {
                switch note.fileType {
                case .latexSource:
                    latexPreviewPane(note)
                case .image:
                    if let nsImage = NSImage(contentsOf: note.fileURL) {
                        Image(nsImage: nsImage).resizable().aspectRatio(contentMode: .fit).padding()
                    }
                case .pdfDoc:
                    PDFKitView(url: note.fileURL)
                case .logAux:
                    ScrollView { Text(manager.editingContent).font(.system(size: 11, design: .monospaced)).padding() }
                        .background(Color(nsColor: .textBackgroundColor))
                default:
                    PreviewWebView(
                        rawMarkdown: manager.editingContent,
                        baseURL: note.fileURL.deletingLastPathComponent(),
                        fontSize: settings.fontSize,
                        highlightText: selectedText
                    )
                }
            } else {
                Color(nsColor: .controlBackgroundColor)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "eye").font(.appFont(size: 32)).foregroundColor(.secondary)
                            Text("选择一篇笔记以预览").foregroundColor(.secondary)
                        }
                    }
            }
        }
    }

    // MARK: - LaTeX 预览面板（编译结果）

    private func latexPreviewPane(_ note: NoteFile) -> some View {
        VStack(spacing: 0) {
            if isCompiling {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("正在编译 (第 \(compilePass.0)/\(compilePass.1) 轮)...")
                        .font(.appCaption).foregroundColor(.secondary)
                    ProgressView(value: Double(compilePass.0), total: Double(compilePass.1))
                        .frame(width: 200)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let document = cachedPDFDocument {
                PDFKitView(document: document)
            } else if LatexService.detectInstalledCompilers().isEmpty {
                // 无本地编译器，使用 WebView + MathJax 回退渲染
                LatexPreviewView(
                    latexSource: manager.editingContent,
                    fontSize: settings.fontSize,
                    baseURL: note.fileURL.deletingLastPathComponent()
                )
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "hammer").font(.appFont(size: 32)).foregroundColor(.secondary)
                    Text("尚未编译").font(.appHeadline).foregroundColor(.secondary)
                    Text("Cmd+B 或点击工具栏编译按钮 (\(settings.latexCompiler.displayName))")
                        .font(.appCaption).foregroundColor(.secondary)
                    if !compileLog.isEmpty {
                        Divider()
                        ScrollView {
                            Text(compileLog)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(maxHeight: 200)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - LaTeX 编译

    private func compileLatex() {
        guard let note = manager.selectedNote,
              settings.editorLanguage == .latex,
              !isCompiling else { return }
        manager.saveImmediately()

        let texURL = note.fileURL
        let compiler = settings.latexCompiler
        let sourceHash = manager.editingContent.hashValue
        isCompiling = true
        compilePass = (0, 3)
        compileLog = ""

        Task {
            let result = await LatexService.compile(texURL: texURL, compiler: compiler) { pass, total in
                Task { @MainActor in
                    compilePass = (pass, total)
                }
            }
            compilePDFData = result.pdfData
            compileLog = result.log
            isCompiling = false
            compilePass = (0, 0)
            if let pdfData = result.pdfData {
                compileCache[texURL] = (data: pdfData, hash: sourceHash)
                cachedPDFDocument = PDFDocument(data: pdfData)
                cachedPDFSourceURL = texURL
            }
        }
    }

    // MARK: - 编译日志 Sheet

    @ViewBuilder
    private func makeCompileLogSheet(errors: [LatexError]) -> some View {
        VStack(spacing: 12) {
            Text("编译日志").font(.appHeadline)
            if errors.isEmpty {
                ScrollView {
                    Text(compileLog.isEmpty ? "无输出" : compileLog)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            } else {
                compileErrorList(errors: errors)
            }
            Button("关闭") { showCompileLog = false }
                .keyboardShortcut(.cancelAction)
        }
        .frame(width: 600, height: 400)
        .padding()
    }

    @ViewBuilder
    private func compileErrorList(errors: [LatexError]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(errors.enumerated()), id: \.offset) { _, err in
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
                            .lineLimit(3)
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
                Button(action: {
                    let errorText = errors.map { "行\($0.line): \($0.message)" }.joined(separator: "\n")
                    showCompileLog = false
                    let source = manager.editingContent
                    NotificationCenter.default.post(
                        name: .sendCompileErrorsToAI,
                        object: nil,
                        userInfo: ["errors": errorText, "source": source]
                    )
                }) {
                    Label("将错误发送给 AI 诊断", systemImage: "sparkles")
                        .font(.appCaption)
                }
                .padding(.top, 8)
            }
            .padding()
        }
    }

    // MARK: - 工具栏

    private var toolbarContent: some View {
        HStack(spacing: 6) {
            // 侧边栏切换
            Button(action: { sidebarCollapsed.toggle() }) {
                Image(systemName: "sidebar.left")
                    .font(.appBody)
                    .foregroundColor(sidebarCollapsed ? .secondary : .accentColor)
            }
            .buttonStyle(.borderless)
            .help(sidebarCollapsed ? "显示目录栏 (Cmd+Shift+S)" : "隐藏目录栏 (Cmd+Shift+S)")

            Text("|").foregroundColor(.secondary.opacity(0.3)).font(.appCaption)

            Picker("", selection: $settings.editorLanguage) {
                ForEach(EditorLanguage.allCases, id: \.self) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .pickerStyle(.segmented).frame(width: 180)
            .help("选择编写语言：Markdown 或 LaTeX")

            if settings.editorLanguage == .latex {
                // 编译器选择
                Menu {
                    ForEach(LatexCompiler.allCases, id: \.self) { c in
                        Button(action: { settings.latexCompiler = c }) {
                            HStack {
                                Text(c.displayName)
                                if settings.latexCompiler == c {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Text(settings.latexCompiler.displayName)
                        .font(.appCaption)
                }
                .menuStyle(.borderlessButton).frame(width: 80)
                .help("选择 LaTeX 编译器")

                // 编译按钮
                Button(action: { compileLatex() }) {
                    Image(systemName: "hammer")
                        .font(.appBody)
                        .foregroundColor(isCompiling ? .orange : .accentColor)
                }
                .buttonStyle(.borderless).help("编译 LaTeX (Cmd+B)")
                .disabled(isCompiling)

                // 显示日志
                if !compileLog.isEmpty {
                    Button(action: { showCompileLog = true }) {
                        Image(systemName: compilePDFData != nil ? "checkmark.circle" : "exclamationmark.triangle")
                            .font(.appBody)
                            .foregroundColor(compilePDFData != nil ? .green : .orange)
                    }
                    .buttonStyle(.borderless).help("查看编译日志")
                }
            }

            Text("|").foregroundColor(.secondary.opacity(0.3)).font(.appCaption)

            ForEach(ViewMode.allCases, id: \.self) { mode in
                Button(action: { settings.viewMode = mode }) {
                    Image(systemName: mode.systemImage)
                        .font(.appBody)
                        .foregroundColor(settings.viewMode == mode ? .accentColor : .secondary)
                }
                .buttonStyle(.borderless).help(mode.displayName)
            }

            Text("|").foregroundColor(.secondary.opacity(0.3)).font(.appCaption)

            Text("\(Int(settings.fontSize))")
                .font(.appCaption).foregroundColor(.secondary).frame(width: 18)
                .help("Cmd+滚轮 调节字号")

            Spacer()

            Button(action: { showAIDrawer.toggle() }) {
                Image(systemName: "sparkles")
                    .font(.appBody)
                    .foregroundColor(showAIDrawer ? .accentColor : .secondary)
            }
            .buttonStyle(.borderless).help("AI 助手 (Cmd+Shift+I)")

            Text("|").foregroundColor(.secondary.opacity(0.3)).font(.appCaption)

            Menu {
                ForEach(ExportService.ExportFormat.allCases, id: \.self) { format in
                    Button(action: { exportNote(format: format) }) {
                        Label(format.rawValue, systemImage: exportIcon(format))
                    }
                }
            } label: {
                Image(systemName: "square.and.arrow.up").font(.appBody)
            }
            .menuStyle(.borderlessButton).frame(width: 24).help("导出笔记")
        }
        .padding(.horizontal, 8).frame(height: 32)
    }

    private func exportIcon(_ f: ExportService.ExportFormat) -> String {
        switch f {
        case .pdf: "doc.richtext"
        case .docx: "doc.text"
        case .txt: "doc.plaintext"
        case .markdown: "arrow.down.doc"
        }
    }

    // MARK: - 状态栏

    private var emptyStateView: some View {
        Color(nsColor: .controlBackgroundColor)
            .overlay {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text").font(.appFont(size: 48)).foregroundColor(.secondary)
                    Text("ZenKith").font(.appTitle2).foregroundColor(.secondary)
                    Text("在左侧创建一个新笔记开始写作\nCmd+N 快速新建")
                        .multilineTextAlignment(.center).foregroundColor(.secondary)
                }
            }
    }

    private func noteStatusBar(_ note: NoteFile) -> some View {
        HStack(spacing: 12) {
            Button(action: { sidebarCollapsed.toggle() }) {
                Image(systemName: sidebarCollapsed ? "sidebar.right" : "sidebar.left")
            }
            .buttonStyle(.borderless).help(sidebarCollapsed ? "展开侧边栏" : "折叠侧边栏")

            Image(systemName: note.fileType.systemImage)
                .font(.appCaption2).foregroundColor(.secondary)

            Text(note.displayTitle).font(.appCaption).foregroundColor(.secondary).lineLimit(1)

            Spacer()

            if note.fileType.isEditable {
                Text("字数: \(manager.editingContent.count)").font(.appCaption).foregroundColor(.secondary)
            }
            Text(note.modifiedDate.formatted(date: .abbreviated, time: .shortened))
                .font(.appCaption).foregroundColor(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
    }

    // MARK: - Cmd+滚轮字号

    @State private var scrollMonitor: Any? = nil

    private func startScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard event.modifierFlags.contains(.command) else { return event }
            let d = event.scrollingDeltaY
            if abs(d) > 0.5 {
                settings.fontSize = max(12, min(32, settings.fontSize + (d > 0 ? 1 : -1)))
            }
            return nil
        }
    }

    private func stopScrollMonitor() {
        if let m = scrollMonitor { NSEvent.removeMonitor(m); scrollMonitor = nil }
    }

    // MARK: - 导出

    private func exportNote(format: ExportService.ExportFormat) {
        guard let note = manager.selectedNote else { return }
        manager.saveImmediately()
        var ctx = ExportService.ExportContext(
            markdownContent: manager.editingContent,
            fileURL: note.fileURL,
            baseURL: note.fileURL.deletingLastPathComponent()
        )
        ctx.editorLanguage = settings.editorLanguage
        Task { await ExportService.export(ctx, format: format) }
    }

    private func cycleViewMode() {
        let all = ViewMode.allCases
        guard let idx = all.firstIndex(of: settings.viewMode) else { return }
        settings.viewMode = all[(idx + 1) % all.count]
    }
}

// MARK: - PDFView 封装

struct PDFKitView: NSViewRepresentable {
    var url: URL?
    var document: PDFDocument?

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if let doc = document {
            pdfView.document = doc
        } else if let url, let doc = PDFDocument(url: url) {
            pdfView.document = doc
        }
    }
}
