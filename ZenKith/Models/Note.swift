import Foundation

/// 笔记文件模型，每个笔记对应一个本地 .md 文件
struct NoteFile: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var fileURL: URL
    var modifiedDate: Date

    init(title: String, fileURL: URL, modifiedDate: Date = Date()) {
        self.id = UUID()
        self.title = title
        self.fileURL = fileURL
        self.modifiedDate = modifiedDate
    }

    /// 去掉 .md 后缀的显示标题
    var displayTitle: String {
        if title.hasSuffix(".md") {
            return String(title.dropLast(3))
        }
        return title
    }
}
