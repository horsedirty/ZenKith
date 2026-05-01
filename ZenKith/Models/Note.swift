import Foundation

/// 文件类型分类
enum NoteFileType: String, CaseIterable {
    case markdown
    case latexSource
    case bibTeX
    case styleClass
    case image
    case pdfDoc
    case logAux
    case other

    init(ext: String) {
        switch ext.lowercased() {
        case "md":                self = .markdown
        case "tex", "ltx":        self = .latexSource
        case "bib":               self = .bibTeX
        case "cls", "sty", "bst": self = .styleClass
        case "jpg", "jpeg", "png", "gif", "svg", "eps", "webp": self = .image
        case "pdf":               self = .pdfDoc
        case "aux", "log", "out", "toc", "lof", "lot", "bbl", "blg", "fls", "fdb_latexmk", "synctex", "synctex.gz", "run.xml", "nav", "snm": self = .logAux
        default:                  self = .other
        }
    }

    var isEditable: Bool {
        switch self {
        case .markdown, .latexSource, .bibTeX, .styleClass, .logAux: return true
        case .image, .pdfDoc, .other: return false
        }
    }

    var systemImage: String {
        switch self {
        case .markdown:    return "doc.text"
        case .latexSource: return "doc.richtext"
        case .bibTeX:      return "books.vertical"
        case .styleClass:  return "gearshape.2"
        case .image:       return "photo"
        case .pdfDoc:      return "doc.richtext"
        case .logAux:      return "doc.text.magnifyingglass"
        case .other:       return "doc"
        }
    }

    /// 已知的后缀列表（用于新建文件时选择）
    static let latexAllExtensions: [String] = [
        "tex", "ltx", "bib", "cls", "sty", "bst",
        "jpg", "jpeg", "png", "gif", "svg", "eps", "webp", "pdf",
        "aux", "log", "out", "toc", "lof", "lot", "bbl", "blg", "fls"
    ]

    static let supportedExtensions: Set<String> = {
        var exts = Set<String>()
        exts.insert("md")
        for e in latexAllExtensions { exts.insert(e) }
        return exts
    }()
}

/// 笔记文件模型，每个文件对应一个本地文件
struct NoteFile: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var fileURL: URL
    var modifiedDate: Date

    var fileType: NoteFileType {
        NoteFileType(ext: fileURL.pathExtension)
    }

    init(title: String, fileURL: URL, modifiedDate: Date = Date()) {
        self.id = UUID()
        self.title = title
        self.fileURL = fileURL
        self.modifiedDate = modifiedDate
    }

    /// 去掉后缀的显示标题
    var displayTitle: String {
        let ext = "." + fileURL.pathExtension.lowercased()
        if title.hasSuffix(ext) {
            return String(title.dropLast(ext.count))
        }
        // common extensions
        if title.hasSuffix(".md") { return String(title.dropLast(3)) }
        if title.hasSuffix(".tex") { return String(title.dropLast(4)) }
        return title
    }
}
