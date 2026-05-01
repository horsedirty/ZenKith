import SwiftUI
import Combine
import AppKit

/// 主内容布局：左侧笔记列表（可折叠） + 中央编辑/预览区 + 右侧可呼出 AI 抽屉
struct ContentView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var manager: NotesManager
    @EnvironmentObject var aiViewModel: AIViewModel

    @State private var showAIDrawer = false
    @State private var aiDrawerWidth: CGFloat = 340
    @State private var selectedText: String = ""
    @State private var dragStartWidth: CGFloat = 0
    @State private var sidebarCollapsed = false

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // 左侧侧边栏（可折叠）
                if !sidebarCollapsed {
                    SidebarView(manager: manager, settings: settings)
                        .frame(width: min(280, geometry.size.width * 0.25))
                    Divider()
                } else {
                    collapsedSidebar
                    Divider()
                }

                // 中央主内容区
                mainContentArea

                // 右侧 AI 抽屉
                if showAIDrawer {
                    Divider()
                    AIDrawer(viewModel: aiViewModel)
                        .frame(width: max(280, aiDrawerWidth))
                        .overlay(aiDrawerDragHandle)
                        .onAppear { dragStartWidth = aiDrawerWidth }
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
        // 快捷键
        .background(Button("") { showAIDrawer.toggle() }
            .keyboardShortcut("i", modifiers: [.command, .shift]).opacity(0))
        .background(Button("") { cycleViewMode() }
            .keyboardShortcut("l", modifiers: [.command, .shift]).opacity(0))
        // 通知
        .onReceive(NotificationCenter.default.publisher(for: .toggleAIDrawer)) { _ in
            showAIDrawer.toggle()
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
    }

    // MARK: - 折叠侧边栏

    private var collapsedSidebar: some View {
        VStack(spacing: 8) {
            Button(action: { sidebarCollapsed = false }) {
                Image(systemName: "sidebar.left").font(.title3)
            }
            .buttonStyle(.borderless).help("展开侧边栏")

            Button(action: { showAIDrawer.toggle() }) {
                Image(systemName: "sparkles").font(.title3)
            }
            .buttonStyle(.borderless).help("AI 助手")

            Spacer()
        }
        .padding(.vertical, 8)
        .frame(width: 40)
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
        switch settings.viewMode {
        case .split:  splitView
        case .editor: editorOnlyView
        case .preview: previewPaneOnly
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

    // MARK: - 编辑器

    private var editorPane: some View {
        VStack(spacing: 0) {
            if let note = manager.selectedNote {
                EditorView(text: $manager.editingContent, fontSize: settings.fontSize).id(note.id)
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
                PreviewWebView(
                    rawMarkdown: manager.editingContent,
                    baseURL: note.fileURL.deletingLastPathComponent(),
                    fontSize: settings.fontSize,
                    highlightText: selectedText
                )
            } else {
                Color(nsColor: .controlBackgroundColor)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "eye").font(.system(size: 32)).foregroundColor(.secondary)
                            Text("选择一篇笔记以预览").foregroundColor(.secondary)
                        }
                    }
            }
        }
    }

    private var emptyStateView: some View {
        Color(nsColor: .controlBackgroundColor)
            .overlay {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text").font(.system(size: 48)).foregroundColor(.secondary)
                    Text("MarkFlow Note").font(.title2).foregroundColor(.secondary)
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

            Text(note.displayTitle).font(.caption).foregroundColor(.secondary).lineLimit(1)
            Spacer()
            Text("字数: \(manager.editingContent.count)").font(.caption).foregroundColor(.secondary)
            Text(note.modifiedDate.formatted(date: .abbreviated, time: .shortened))
                .font(.caption).foregroundColor(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
    }

    // MARK: - 工具栏（紧凑版 + AI 按钮）

    private var toolbarContent: some View {
        HStack(spacing: 6) {
            // 视图模式：3 个图标按钮
            ForEach(ViewMode.allCases, id: \.self) { mode in
                Button(action: { settings.viewMode = mode }) {
                    Image(systemName: mode.systemImage)
                        .font(.body)
                        .foregroundColor(settings.viewMode == mode ? .accentColor : .secondary)
                }
                .buttonStyle(.borderless)
                .help(mode.displayName)
            }

            Text("|").foregroundColor(.secondary.opacity(0.3)).font(.caption)

            // 字号
            Text("\(Int(settings.fontSize))")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 18)
                .help("Cmd+滚轮 调节字号")

            Spacer()

            // AI 按钮
            Button(action: { showAIDrawer.toggle() }) {
                Image(systemName: "sparkles")
                    .font(.body)
                    .foregroundColor(showAIDrawer ? .accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .help("AI 助手 (Cmd+Shift+I)")

            Text("|").foregroundColor(.secondary.opacity(0.3)).font(.caption)

            // 导出
            Menu {
                ForEach(ExportService.ExportFormat.allCases, id: \.self) { format in
                    Button(action: { exportNote(format: format) }) {
                        Label(format.rawValue, systemImage: exportIcon(format))
                    }
                }
            } label: {
                Image(systemName: "square.and.arrow.up").font(.body)
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
        let ctx = ExportService.ExportContext(
            markdownContent: manager.editingContent,
            fileURL: note.fileURL,
            baseURL: note.fileURL.deletingLastPathComponent()
        )
        Task { await ExportService.export(ctx, format: format) }
    }

    private func cycleViewMode() {
        let all = ViewMode.allCases
        guard let idx = all.firstIndex(of: settings.viewMode) else { return }
        settings.viewMode = all[(idx + 1) % all.count]
    }
}
