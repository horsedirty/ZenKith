import SwiftUI

/// 左侧笔记列表侧边栏：显示笔记列表、文件夹、新建/重命名/删除操作
struct SidebarView: View {
    @ObservedObject var manager: NotesManager
    @ObservedObject var settings: AppSettings
    @State private var showNewNoteSheet = false
    @State private var showNewFolderSheet = false
    @State private var newNoteName = ""
    @State private var newFolderName = ""
    @State private var noteToRename: NoteFile?
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 0) {
            // 头部操作栏
            headerView

            // 面包屑导航
            breadcrumbView

            Divider()

            // 列表
            List(selection: Binding<UUID?>(
                get: { manager.selectedNote?.id },
                set: { newID in
                    if let id = newID, let note = manager.notes.first(where: { $0.id == id }) {
                        manager.selectNote(note)
                    }
                }
            )) {
                // 文件夹区
                if !manager.folders.isEmpty {
                    Section("文件夹") {
                        ForEach(manager.folders, id: \.self) { folderURL in
                            Label(folderURL.lastPathComponent, systemImage: "folder")
                                .contextMenu {
                                    Button("打开") {
                                        manager.navigateToFolder(folderURL)
                                    }
                                    Divider()
                                    Button("删除", role: .destructive) {
                                        manager.deleteFolder(folderURL)
                                    }
                                }
                                .onTapGesture(count: 2) {
                                    manager.navigateToFolder(folderURL)
                                }
                        }
                    }
                }

                // 笔记列表
                Section("笔记") {
                    ForEach(manager.notes) { note in
                        noteRow(note)
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .sheet(isPresented: $showNewNoteSheet) {
            nameInputSheet(
                title: "新建笔记", text: $newNoteName, confirmLabel: "创建",
                onCancel: { showNewNoteSheet = false },
                onConfirm: {
                    let name = newNoteName.isEmpty ? "未命名笔记" : newNoteName
                    manager.createNote(named: name, language: settings.editorLanguage)
                    newNoteName = ""
                    showNewNoteSheet = false
                }
            )
        }
        .sheet(isPresented: $showNewFolderSheet) {
            nameInputSheet(
                title: "新建文件夹", text: $newFolderName, confirmLabel: "创建",
                onCancel: { showNewFolderSheet = false },
                onConfirm: {
                    let name = newFolderName.isEmpty ? "新建文件夹" : newFolderName
                    manager.createFolder(named: name)
                    newFolderName = ""
                    showNewFolderSheet = false
                }
            )
        }
        .alert("重命名", isPresented: Binding<Bool>(
            get: { noteToRename != nil },
            set: { if !$0 { noteToRename = nil } }
        )) {
            TextField("新名称", text: $renameText)
            Button("确定") {
                if let note = noteToRename {
                    manager.renameNote(note, to: renameText)
                }
                noteToRename = nil
                renameText = ""
            }
            Button("取消", role: .cancel) {
                noteToRename = nil
                renameText = ""
            }
        } message: {
            Text("输入笔记的新名称（不含后缀）")
        }
    }

    // MARK: - 头部视图

    private var headerView: some View {
        HStack(spacing: 6) {
            Text(
                manager.currentDirectory == settings.effectiveDirectory
                    ? "MarkFlow"
                    : manager.currentDirectory.lastPathComponent
            )
            .font(.appHeadline)
            .lineLimit(1)

            Spacer()

            Menu {
                Button(action: { showNewNoteSheet = true }) {
                    Label("新建笔记", systemImage: "plus.square")
                }
                Button(action: { showNewFolderSheet = true }) {
                    Label("新建文件夹", systemImage: "folder.badge.plus")
                }
                Divider()
                Button(action: { manager.selectDirectoryPanel() }) {
                    Label("切换目录...", systemImage: "folder")
                }
                Button(action: { manager.jumpToDirectory(settings.effectiveDirectory) }) {
                    Label("回到默认目录", systemImage: "house")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.appTitle3)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - 面包屑导航

    @ViewBuilder
    private var breadcrumbView: some View {
        if manager.canGoBack && manager.currentDirectory != settings.effectiveDirectory {
            HStack(spacing: 2) {
                Button(action: { manager.goBack() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.appCaption2)
                        Text("返回上级")
                            .font(.appCaption)
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 8)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(4)
                }
                .buttonStyle(.borderless)

                Text(manager.currentDirectory.lastPathComponent)
                    .font(.appCaption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    // MARK: - 笔记行

    private func noteRow(_ note: NoteFile) -> some View {
        let isSelected = manager.selectedNote?.id == note.id
        return Label {
            Text(note.displayTitle)
                .lineLimit(1)
                .fontWeight(isSelected ? .semibold : .regular)
        } icon: {
            Image(systemName: isSelected ? fillIcon(for: note.fileType) : note.fileType.systemImage)
                .foregroundColor(isSelected ? .accentColor : iconColor(for: note.fileType))
        }
        .contextMenu {
            Button("重命名") {
                noteToRename = note
                renameText = note.displayTitle
            }
            Divider()
            Button("删除", role: .destructive) {
                manager.deleteNote(note)
            }
        }
        .tag(note.id)
    }

    private func fillIcon(for type: NoteFileType) -> String {
        switch type {
        case .markdown:    return "doc.text.fill"
        case .latexSource: return "doc.richtext.fill"
        case .bibTeX:      return "books.vertical.fill"
        case .styleClass:  return "gearshape.fill"
        case .image:       return "photo.fill"
        case .pdfDoc:      return "doc.fill"
        case .logAux:      return "doc.text.fill"
        case .other:       return "doc.fill"
        }
    }

    private func iconColor(for type: NoteFileType) -> Color {
        switch type {
        case .markdown:    return .accentColor
        case .latexSource: return .blue
        case .bibTeX:      return .orange
        case .styleClass:  return .purple
        case .image:       return .green
        case .pdfDoc:      return .red
        case .logAux:      return .gray
        case .other:       return .secondary
        }
    }

    // MARK: - 输入弹窗

    private func nameInputSheet(
        title: String,
        text: Binding<String>,
        confirmLabel: String,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.appHeadline)

            TextField("名称", text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)

            HStack(spacing: 12) {
                Button("取消") {
                    text.wrappedValue = ""
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button(confirmLabel) {
                    onConfirm()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 320, height: 150)
    }
}
