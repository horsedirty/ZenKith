import Foundation
import Combine
import SwiftUI

/// 笔记文件管理核心 —— 管理 .md 文件的读写、文件夹、自动保存
@MainActor
final class NotesManager: ObservableObject {

    // MARK: - 发布属性

    /// 当前工作目录
    @Published var currentDirectory: URL

    /// 笔记列表（按修改时间倒序）
    @Published var notes: [NoteFile] = []

    /// 子文件夹列表
    @Published var folders: [URL] = []

    /// 当前选中的笔记
    @Published var selectedNote: NoteFile?

    /// 当前编辑的文本内容（双向绑定编辑器）
    @Published var editingContent: String = ""

    /// 目录历史栈（面包屑导航）
    @Published var directoryStack: [URL] = []

    /// 自动保存防抖
    private var saveCancellable: AnyCancellable?
    private let saveSubject = PassthroughSubject<String, Never>()
    private var isSaving = false

    /// 文件读取缓存（URL → 内容）
    private var contentCache: [URL: String] = [:]

    // MARK: - 初始化

    init(directory: URL) {
        self.currentDirectory = directory
        ensureDirectoryExists()
        refreshFileList()

        // 自动保存：2 秒防抖
        saveCancellable = saveSubject
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] content in
                self?.performAutoSave(content)
            }
    }

    // MARK: - 目录管理

    /// 确保工作目录存在，不存在则创建
    private func ensureDirectoryExists() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: currentDirectory.path) {
            try? fm.createDirectory(at: currentDirectory, withIntermediateDirectories: true)
        }
    }

    /// 更换工作目录
    func changeDirectory(to url: URL, recordHistory: Bool = true) {
        if recordHistory {
            directoryStack.append(currentDirectory)
        }
        currentDirectory = url
        ensureDirectoryExists()
        contentCache.removeAll()
        selectedNote = nil
        editingContent = ""
        refreshFileList()
    }

    /// 是否可返回上级目录
    var canGoBack: Bool {
        !directoryStack.isEmpty
    }

    /// 返回上级目录
    func goBack() {
        guard let previous = directoryStack.popLast() else { return }
        changeDirectory(to: previous, recordHistory: false)
    }

    // MARK: - 文件列表刷新

    /// 扫描工作目录，刷新笔记和文件夹列表
    func refreshFileList() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: currentDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            notes = []
            folders = []
            return
        }

        var noteFiles: [NoteFile] = []
        var folderURLs: [URL] = []

        for url in contents {
            guard let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey]),
                  let isDirectory = resourceValues.isDirectory else {
                continue
            }

            if isDirectory {
                folderURLs.append(url)
            } else if url.pathExtension.lowercased() == "md" {
                let modDate = resourceValues.contentModificationDate ?? Date()
                let note = NoteFile(
                    title: url.lastPathComponent,
                    fileURL: url,
                    modifiedDate: modDate
                )
                noteFiles.append(note)
            }
        }

        notes = noteFiles.sorted { $0.modifiedDate > $1.modifiedDate }
        folders = folderURLs.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: - 文件操作

    /// 新建笔记
    func createNote(named name: String = "未命名笔记") {
        let sanitized = sanitizeFileName(name)
        let finalName = sanitized.hasSuffix(".md") ? sanitized : sanitized + ".md"
        let fileURL = currentDirectory.appendingPathComponent(finalName)

        // 避免重名
        var counter = 1
        var resolvedURL = fileURL
        let fm = FileManager.default
        while fm.fileExists(atPath: resolvedURL.path) {
            let base = sanitized.replacingOccurrences(of: ".md", with: "")
            resolvedURL = currentDirectory.appendingPathComponent("\(base) \(counter).md")
            counter += 1
        }

        let initialContent = "# \(sanitized.replacingOccurrences(of: ".md", with: ""))\n\n"
        try? initialContent.write(to: resolvedURL, atomically: true, encoding: .utf8)

        refreshFileList()
        if let note = notes.first(where: { $0.fileURL == resolvedURL }) {
            selectNote(note)
        }
    }

    /// 选中笔记，加载内容
    func selectNote(_ note: NoteFile) {
        // 如有未保存内容，先保存
        if let current = selectedNote, editingContent != contentCache[current.fileURL] {
            saveContent(editingContent, for: current)
        }

        selectedNote = note
        loadContent(for: note)
    }

    /// 加载笔记内容到编辑器
    private func loadContent(for note: NoteFile) {
        if let cached = contentCache[note.fileURL] {
            editingContent = cached
            return
        }
        do {
            let content = try String(contentsOf: note.fileURL, encoding: .utf8)
            editingContent = content
            contentCache[note.fileURL] = content
        } catch {
            editingContent = ""
        }
    }

    /// 触发自动保存（更新缓存 + 写盘）
    func scheduleAutoSave() {
        guard let note = selectedNote else { return }
        contentCache[note.fileURL] = editingContent
        saveSubject.send(editingContent)
    }

    /// 立即保存
    func saveImmediately() {
        guard let note = selectedNote else { return }
        performAutoSave(editingContent)
    }

    /// 执行实际写入
    private func performAutoSave(_ content: String) {
        guard let note = selectedNote, !isSaving else { return }
        isSaving = true
        do {
            try content.write(to: note.fileURL, atomically: true, encoding: .utf8)
            contentCache[note.fileURL] = content
        } catch {
            // 静默保存失败，通常由文件权限引起
        }
        isSaving = false
    }

    private func saveContent(_ content: String, for note: NoteFile) {
        do {
            try content.write(to: note.fileURL, atomically: true, encoding: .utf8)
            contentCache[note.fileURL] = content
        } catch {
            // 静默失败
        }
    }

    /// 重命名笔记
    func renameNote(_ note: NoteFile, to newName: String) {
        let sanitized = sanitizeFileName(newName)
        let finalName = sanitized.hasSuffix(".md") ? sanitized : sanitized + ".md"
        let newURL = note.fileURL.deletingLastPathComponent().appendingPathComponent(finalName)

        guard !FileManager.default.fileExists(atPath: newURL.path) else { return }

        do {
            try FileManager.default.moveItem(at: note.fileURL, to: newURL)
            contentCache.removeValue(forKey: note.fileURL)
            refreshFileList()
            if selectedNote?.id == note.id,
               let updated = notes.first(where: { $0.fileURL == newURL }) {
                selectNote(updated)
            }
        } catch {
            // 重命名失败
        }
    }

    /// 删除笔记
    func deleteNote(_ note: NoteFile) {
        do {
            try FileManager.default.removeItem(at: note.fileURL)
            contentCache.removeValue(forKey: note.fileURL)
            if selectedNote?.id == note.id {
                selectedNote = nil
                editingContent = ""
            }
            refreshFileList()
        } catch {
            // 删除失败
        }
    }

    // MARK: - 文件夹操作

    /// 新建子文件夹
    func createFolder(named name: String = "新建文件夹") {
        let sanitized = sanitizeFileName(name)
        let folderURL = currentDirectory.appendingPathComponent(sanitized)

        var counter = 1
        var resolved = folderURL
        while FileManager.default.fileExists(atPath: resolved.path) {
            resolved = currentDirectory.appendingPathComponent("\(sanitized) \(counter)")
            counter += 1
        }

        try? FileManager.default.createDirectory(at: resolved, withIntermediateDirectories: false)
        refreshFileList()
    }

    /// 删除文件夹
    func deleteFolder(_ folderURL: URL) {
        try? FileManager.default.removeItem(at: folderURL)
        refreshFileList()
    }

    /// 进入子文件夹
    func navigateToFolder(_ folderURL: URL) {
        changeDirectory(to: folderURL)
    }

    // MARK: - 目录选择

    /// 通过 NSOpenPanel 选择工作目录
    func selectDirectoryPanel() {
        let panel = NSOpenPanel()
        panel.title = "选择笔记存放目录"
        panel.message = "选择要存放 Markdown 笔记的文件夹"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = currentDirectory

        guard panel.runModal() == .OK, let url = panel.url else { return }
        // 直接选择新目录，清除历史栈
        directoryStack.removeAll()
        changeDirectory(to: url, recordHistory: false)

        // 通过通知让 AppSettings 更新持久化
        NotificationCenter.default.post(
            name: .directoryDidChange,
            object: nil,
            userInfo: ["url": url]
        )
    }

    /// 跳转到指定目录（不记录历史）
    func jumpToDirectory(_ url: URL) {
        directoryStack.removeAll()
        changeDirectory(to: url, recordHistory: false)
    }

    // MARK: - 工具方法

    /// 安全化文件名
    private func sanitizeFileName(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "/:?*|\"<>")
        let components = name.components(separatedBy: invalidChars)
        let sanitized = components.joined(separator: "_")
        return sanitized.trimmingCharacters(in: .whitespaces).isEmpty
            ? "未命名"
            : sanitized.trimmingCharacters(in: .whitespaces)
    }
}
