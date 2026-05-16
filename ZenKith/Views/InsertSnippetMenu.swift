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
        add("3列表格", "\\begin{tabular}{|c|c|c|}\n\\hline\n${1:Col1} & ${2:Col2} & ${3:Col3} \\\\\\hline\n${4:} & ${5:} & ${6:} \\\\\\hline\n\\end{tabular}", "表格")
        add("4列表格", "\\begin{tabular}{|c|c|c|c|}\n\\hline\n${1:} & ${2:} & ${3:} & ${4:} \\\\\\hline\n${5:} & ${6:} & ${7:} & ${8:} \\\\\\hline\n\\end{tabular}", "表格")
        add("2x2 矩阵", "\\begin{pmatrix}\n${1:a} & ${2:b} \\\\\n${3:c} & ${4:d}\n\\end{pmatrix}", "矩阵")
        add("3x3 方括号矩阵", "\\begin{bmatrix}\n${1:1} & ${2:0} & ${3:0} \\\\\n${4:0} & ${5:1} & ${6:0} \\\\\n${7:0} & ${8:0} & ${9:1}\n\\end{bmatrix}", "矩阵")
        add("cases 分段", "\\begin{cases}\n${1:x}, & \\text{if } ${2:x > 0} \\\\\n${3:0}, & \\text{otherwise}\n\\end{cases}", "矩阵")
        add("figure 插图", "\\begin{figure}[htbp]\n\\centering\n\\includegraphics[width=${1:0.8}\\textwidth]{${2:image.pdf}}\n\\caption{${3:标题}}\n\\label{fig:${4:}}\n\\end{figure}", "图形")
        add("theorem 定理", "\\begin{theorem}\n${1:定理内容}\n\\end{theorem}", "定理")
        add("proof 证明", "\\begin{proof}\n${1:证明过程}\n\\end{proof}", "定理")
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
