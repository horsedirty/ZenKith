import AppKit
import Combine
import Foundation

// MARK: - Completion State

enum CompletionState: Equatable {
    case idle
    case active(prefix: String, range: NSRange)
    case navigating(prefix: String, range: NSRange, selectedIndex: Int)

    var isActive: Bool {
        if case .idle = self { return false }
        return true
    }

    var prefix: String? {
        switch self {
        case .active(let p, _), .navigating(let p, _, _): return p
        case .idle: return nil
        }
    }

    var range: NSRange? {
        switch self {
        case .active(_, let r), .navigating(_, let r, _): return r
        case .idle: return nil
        }
    }
}

enum FilterMode {
    case command
    case beginEnvironment
    case citeKey
    case refLabel
}

// MARK: - Completion Item

struct LatexCompletion: Identifiable, Equatable {
    let id = UUID()
    let command: String
    let displayName: String
    let insertionText: String
    let category: Category
    let detail: String

    enum Category: String, CaseIterable, Identifiable {
        case documentStructure = "结构"
        case section = "章节"
        case textFormatting = "格式"
        case mathSymbol = "数学"
        case mathFunction = "函数"
        case environment = "环境"
        case reference = "引用"
        case package = "宏包"
        case other = "其他"

        var id: String { rawValue }
    }

    static func == (lhs: LatexCompletion, rhs: LatexCompletion) -> Bool { lhs.id == rhs.id }
}

// MARK: - Completion Engine

@MainActor
final class LatexCompletionEngine: ObservableObject {

    @Published var state = CompletionState.idle
    @Published var suggestions: [LatexCompletion] = []

    /// Fires when state or suggestions change (after async filter completes).
    /// Coordinator uses this to show/hide the popover at the right time.
    var onStateChanged: (() -> Void)?

    var selectedItem: LatexCompletion? {
        switch state {
        case .navigating(_, _, let idx):
            guard idx >= 0, idx < suggestions.count else { return nil }
            return suggestions[idx]
        default:
            return suggestions.first
        }
    }

    private var filterTask: Task<Void, Never>?
    private let allCommands: [LatexCompletion]
    private var citeKeys: [String] = []
    private var refLabels: [String] = []

    func setCiteKeys(_ keys: [String]) {
        self.citeKeys = keys
    }

    func setRefLabels(_ labels: [String]) {
        self.refLabels = labels
    }

    init() {
        self.allCommands = Self.buildCommandList()
    }

    // MARK: - Async Filtering

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
                let lower = prefix.lowercased()
                results = Self.environmentCompletions.filter { $0.command.lowercased().hasPrefix(lower) }
            case .citeKey:
                let lower = prefix.lowercased()
                let keys = self.citeKeys
                results = keys
                    .filter { $0.lowercased().contains(lower) }
                    .prefix(30)
                    .map { key in
                        LatexCompletion(command: key, displayName: key, insertionText: key, category: .reference, detail: "引用")
                    }
            case .refLabel:
                let lower = prefix.lowercased()
                let labels = self.refLabels
                results = labels
                    .filter { $0.lowercased().contains(lower) }
                    .prefix(30)
                    .map { label in
                        LatexCompletion(command: label, displayName: label, insertionText: label, category: .reference, detail: "标签引用")
                    }
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

    // MARK: - Evaluate State from TextView

    func evaluateState(in textView: NSTextView) {
        let cursorPos = textView.selectedRange().location
        guard cursorPos > 0 else { dismissWithCallback(); return }

        let text = textView.string as NSString

        if let beginRange = detectBeginPrefix(in: text, cursorPos: cursorPos) {
            let prefix = text.substring(with: NSRange(location: beginRange.location + 7, length: cursorPos - beginRange.location - 7))
            filterAsync(prefix: prefix, range: beginRange, filterMode: .beginEnvironment)
            return
        }

        if let refRange = detectRefPrefix(in: text, cursorPos: cursorPos) {
            let prefix = text.substring(with: NSRange(location: refRange.location + 5, length: cursorPos - refRange.location - 5))
            filterAsync(prefix: prefix, range: refRange, filterMode: .refLabel)
            return
        }

        if let citeRange = detectCitePrefix(in: text, cursorPos: cursorPos) {
            let prefix = text.substring(with: NSRange(location: citeRange.location + 6, length: cursorPos - citeRange.location - 6))
            filterAsync(prefix: prefix, range: citeRange, filterMode: .citeKey)
            return
        }

        var i = cursorPos - 1
        while i >= 0 {
            let ch = Character(UnicodeScalar(text.character(at: i))!)
            if ch == "\\" {
                let prefixLength = cursorPos - i
                let rawPrefix = text.substring(with: NSRange(location: i, length: prefixLength))
                let prefix = String(rawPrefix.dropFirst())
                let range = NSRange(location: i, length: prefixLength)
                filterAsync(prefix: prefix, range: range)
                return
            }
            if ch.isLetter || ch == "_" || ch == "^" {
                i -= 1
                continue
            }
            break
        }

        dismissWithCallback()
    }

    private func detectBeginPrefix(in text: NSString, cursorPos: Int) -> NSRange? {
        let pattern = "\\begin{"
        let searchStart = max(0, cursorPos - 50)
        let searchRange = NSRange(location: searchStart, length: cursorPos - searchStart)
        let full = text.substring(with: searchRange)
        if let lastBegin = full.range(of: pattern, options: .backwards) {
            let beginIdx = searchStart + full.distance(from: full.startIndex, to: lastBegin.lowerBound)
            let substring = text.substring(with: NSRange(location: beginIdx, length: cursorPos - beginIdx))
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

    private func detectRefPrefix(in text: NSString, cursorPos: Int) -> NSRange? {
        let pattern = "\\ref{"
        let searchStart = max(0, cursorPos - 50)
        let searchRange = NSRange(location: searchStart, length: cursorPos - searchStart)
        let full = text.substring(with: searchRange)
        if let lastRef = full.range(of: pattern, options: .backwards) {
            let refIdx = searchStart + full.distance(from: full.startIndex, to: lastRef.lowerBound)
            let substring = text.substring(with: NSRange(location: refIdx, length: cursorPos - refIdx))
            if !substring.contains("}") {
                return NSRange(location: refIdx, length: cursorPos - refIdx)
            }
        }
        return nil
    }

    // MARK: - Navigation (calls onStateChanged)

    func navigateUp() {
        switch state {
        case .active(let prefix, let range):
            guard !suggestions.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.state = .navigating(prefix: prefix, range: range, selectedIndex: self.suggestions.count - 1)
                self.onStateChanged?()
            }
        case .navigating(let prefix, let range, let idx):
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let newIdx = idx > 0 ? idx - 1 : self.suggestions.count - 1
                self.state = .navigating(prefix: prefix, range: range, selectedIndex: newIdx)
                self.onStateChanged?()
            }
        case .idle: break
        }
    }

    func navigateDown() {
        switch state {
        case .active(let prefix, let range):
            guard !suggestions.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.state = .navigating(prefix: prefix, range: range, selectedIndex: 0)
                self.onStateChanged?()
            }
        case .navigating(let prefix, let range, let idx):
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let newIdx = idx < self.suggestions.count - 1 ? idx + 1 : 0
                self.state = .navigating(prefix: prefix, range: range, selectedIndex: newIdx)
                self.onStateChanged?()
            }
        case .idle: break
        }
    }

    // MARK: - Commit

    func commit(in textView: NSTextView) {
        guard let item = selectedItem else { return }
        guard let range = state.range else { return }

        let insertion = item.insertionText
        textView.replaceCharacters(in: range, with: insertion)

        let newLocation = range.location
        if let cursorRange = findCursorPosition(in: insertion, baseLocation: newLocation) {
            textView.setSelectedRange(cursorRange)
        } else {
            let endPos = newLocation + (insertion as NSString).length
            textView.setSelectedRange(NSRange(location: endPos, length: 0))
        }

        dismissWithCallback()
    }

    private func findCursorPosition(in text: String, baseLocation: Int) -> NSRange? {
        guard let r = text.range(of: "${1:") else { return nil }
        let prefixEnd = text.distance(from: text.startIndex, to: r.lowerBound)
        guard let close = text[text.index(text.startIndex, offsetBy: prefixEnd)...].range(of: "}") else { return nil }
        let end = text.distance(from: text.startIndex, to: close.lowerBound)
        let placeholderPrefix = "${1:"
        let loc = baseLocation + prefixEnd + placeholderPrefix.count
        let len = end - prefixEnd - placeholderPrefix.count
        return NSRange(location: loc, length: len)
    }

    // MARK: - Dismiss

    func dismiss() {
        filterTask?.cancel()
        filterTask = nil
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.state = .idle
            self.suggestions = []
            self.onStateChanged?()
        }
    }

    private func dismissWithCallback() {
        filterTask?.cancel()
        filterTask = nil
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.state = .idle
            self.suggestions = []
            self.onStateChanged?()
        }
    }
}

// MARK: - Command List Builder
// (existing command list, unchanged)
extension LatexCompletionEngine {

    private static func buildCommandList() -> [LatexCompletion] {
        var cmds: [LatexCompletion] = []

        func add(_ cmd: String, _ display: String, _ insertion: String, _ cat: LatexCompletion.Category, _ detail: String) {
            cmds.append(LatexCompletion(command: cmd, displayName: display, insertionText: insertion, category: cat, detail: detail))
        }

        // 结构 (5)
        add("documentclass", "\\documentclass{…}", "\\documentclass{${1:article}}", .documentStructure, "文档类")
        add("usepackage", "\\usepackage{…}", "\\usepackage{${1:}}", .documentStructure, "引入宏包")
        add("title", "\\title{…}", "\\title{${1:}}", .documentStructure, "标题")
        add("author", "\\author{…}", "\\author{${1:}}", .documentStructure, "作者")
        add("date", "\\date{…}", "\\date{${1:\\today}}", .documentStructure, "日期")

        // 章节 (7)
        add("section", "\\section{…}", "\\section{${1:}}", .section, "一级标题")
        add("subsection", "\\subsection{…}", "\\subsection{${1:}}", .section, "二级标题")
        add("subsubsection", "\\subsubsection{…}", "\\subsubsection{${1:}}", .section, "三级标题")
        add("chapter", "\\chapter{…}", "\\chapter{${1:}}", .section, "章")
        add("paragraph", "\\paragraph{…}", "\\paragraph{${1:}}", .section, "段落标题")
        add("subparagraph", "\\subparagraph{…}", "\\subparagraph{${1:}}", .section, "子段落标题")
        add("part", "\\part{…}", "\\part{${1:}}", .section, "部分")

        // 格式 (12)
        add("textbf", "\\textbf{…}", "\\textbf{${1:}}", .textFormatting, "粗体")
        add("textit", "\\textit{…}", "\\textit{${1:}}", .textFormatting, "斜体")
        add("emph", "\\emph{…}", "\\emph{${1:}}", .textFormatting, "强调")
        add("underline", "\\underline{…}", "\\underline{${1:}}", .textFormatting, "下划线")
        add("textsc", "\\textsc{…}", "\\textsc{${1:}}", .textFormatting, "小型大写")
        add("texttt", "\\texttt{…}", "\\texttt{${1:}}", .textFormatting, "等宽字体")
        add("textsf", "\\textsf{…}", "\\textsf{${1:}}", .textFormatting, "无衬线体")
        add("textrm", "\\textrm{…}", "\\textrm{${1:}}", .textFormatting, "衬线体")
        add("textnormal", "\\textnormal{…}", "\\textnormal{${1:}}", .textFormatting, "正常字体")
        add("textsuperscript", "\\textsuperscript{…}", "\\textsuperscript{${1:}}", .textFormatting, "上标")
        add("textsubscript", "\\textsubscript{…}", "\\textsubscript{${1:}}", .textFormatting, "下标")
        add("textcolor", "\\textcolor{…}", "\\textcolor{${1:}}{${2:}}", .textFormatting, "文字颜色")

        // 数学希腊字母 (52)
        add("alpha", "\\alpha", "\\alpha", .mathSymbol, "α")
        add("beta", "\\beta", "\\beta", .mathSymbol, "β")
        add("gamma", "\\gamma", "\\gamma", .mathSymbol, "γ")
        add("delta", "\\delta", "\\delta", .mathSymbol, "δ")
        add("epsilon", "\\epsilon", "\\epsilon", .mathSymbol, "ε")
        add("varepsilon", "\\varepsilon", "\\varepsilon", .mathSymbol, "ε")
        add("zeta", "\\zeta", "\\zeta", .mathSymbol, "ζ")
        add("eta", "\\eta", "\\eta", .mathSymbol, "η")
        add("theta", "\\theta", "\\theta", .mathSymbol, "θ")
        add("vartheta", "\\vartheta", "\\vartheta", .mathSymbol, "ϑ")
        add("iota", "\\iota", "\\iota", .mathSymbol, "ι")
        add("kappa", "\\kappa", "\\kappa", .mathSymbol, "κ")
        add("lambda", "\\lambda", "\\lambda", .mathSymbol, "λ")
        add("mu", "\\mu", "\\mu", .mathSymbol, "μ")
        add("nu", "\\nu", "\\nu", .mathSymbol, "ν")
        add("xi", "\\xi", "\\xi", .mathSymbol, "ξ")
        add("pi", "\\pi", "\\pi", .mathSymbol, "π")
        add("varpi", "\\varpi", "\\varpi", .mathSymbol, "ϖ")
        add("rho", "\\rho", "\\rho", .mathSymbol, "ρ")
        add("varrho", "\\varrho", "\\varrho", .mathSymbol, "ϱ")
        add("sigma", "\\sigma", "\\sigma", .mathSymbol, "σ")
        add("varsigma", "\\varsigma", "\\varsigma", .mathSymbol, "ς")
        add("tau", "\\tau", "\\tau", .mathSymbol, "τ")
        add("upsilon", "\\upsilon", "\\upsilon", .mathSymbol, "υ")
        add("phi", "\\phi", "\\phi", .mathSymbol, "φ")
        add("varphi", "\\varphi", "\\varphi", .mathSymbol, "φ")
        add("chi", "\\chi", "\\chi", .mathSymbol, "χ")
        add("psi", "\\psi", "\\psi", .mathSymbol, "ψ")
        add("omega", "\\omega", "\\omega", .mathSymbol, "ω")
        add("Gamma", "\\Gamma", "\\Gamma", .mathSymbol, "Γ")
        add("Delta", "\\Delta", "\\Delta", .mathSymbol, "Δ")
        add("Theta", "\\Theta", "\\Theta", .mathSymbol, "Θ")
        add("Lambda", "\\Lambda", "\\Lambda", .mathSymbol, "Λ")
        add("Xi", "\\Xi", "\\Xi", .mathSymbol, "Ξ")
        add("Pi", "\\Pi", "\\Pi", .mathSymbol, "Π")
        add("Sigma", "\\Sigma", "\\Sigma", .mathSymbol, "Σ")
        add("Upsilon", "\\Upsilon", "\\Upsilon", .mathSymbol, "Υ")
        add("Phi", "\\Phi", "\\Phi", .mathSymbol, "Φ")
        add("Psi", "\\Psi", "\\Psi", .mathSymbol, "Ψ")
        add("Omega", "\\Omega", "\\Omega", .mathSymbol, "Ω")
        add("nabla", "\\nabla", "\\nabla", .mathSymbol, "∇")
        add("partial", "\\partial", "\\partial", .mathSymbol, "∂")
        add("infty", "\\infty", "\\infty", .mathSymbol, "∞")
        add("emptyset", "\\emptyset", "\\emptyset", .mathSymbol, "∅")
        add("varnothing", "\\varnothing", "\\varnothing", .mathSymbol, "∅")
        add("forall", "\\forall", "\\forall", .mathSymbol, "∀")
        add("exists", "\\exists", "\\exists", .mathSymbol, "∃")
        add("neg", "\\neg", "\\neg", .mathSymbol, "¬")
        add("bot", "\\bot", "\\bot", .mathSymbol, "⊥")
        add("top", "\\top", "\\top", .mathSymbol, "⊤")
        add("angle", "\\angle", "\\angle", .mathSymbol, "∠")
        add("triangle", "\\triangle", "\\triangle", .mathSymbol, "△")

        // 数学关系符号 (20)
        add("leq", "\\leq", "\\leq", .mathSymbol, "≤")
        add("geq", "\\geq", "\\geq", .mathSymbol, "≥")
        add("neq", "\\neq", "\\neq", .mathSymbol, "≠")
        add("approx", "\\approx", "\\approx", .mathSymbol, "≈")
        add("equiv", "\\equiv", "\\equiv", .mathSymbol, "≡")
        add("sim", "\\sim", "\\sim", .mathSymbol, "∼")
        add("simeq", "\\simeq", "\\simeq", .mathSymbol, "≃")
        add("cong", "\\cong", "\\cong", .mathSymbol, "≅")
        add("propto", "\\propto", "\\propto", .mathSymbol, "∝")
        add("perp", "\\perp", "\\perp", .mathSymbol, "⊥")
        add("parallel", "\\parallel", "\\parallel", .mathSymbol, "∥")
        add("subset", "\\subset", "\\subset", .mathSymbol, "⊂")
        add("supset", "\\supset", "\\supset", .mathSymbol, "⊃")
        add("subseteq", "\\subseteq", "\\subseteq", .mathSymbol, "⊆")
        add("supseteq", "\\supseteq", "\\supseteq", .mathSymbol, "⊇")
        add("in", "\\in", "\\in", .mathSymbol, "∈")
        add("ni", "\\ni", "\\ni", .mathSymbol, "∋")
        add("notin", "\\notin", "\\notin", .mathSymbol, "∉")
        add("ll", "\\ll", "\\ll", .mathSymbol, "≪")
        add("gg", "\\gg", "\\gg", .mathSymbol, "≫")

        // 数学箭头 (18)
        add("rightarrow", "\\rightarrow", "\\rightarrow", .mathSymbol, "→")
        add("leftarrow", "\\leftarrow", "\\leftarrow", .mathSymbol, "←")
        add("leftrightarrow", "\\leftrightarrow", "\\leftrightarrow", .mathSymbol, "↔")
        add("Rightarrow", "\\Rightarrow", "\\Rightarrow", .mathSymbol, "⇒")
        add("Leftarrow", "\\Leftarrow", "\\Leftarrow", .mathSymbol, "⇐")
        add("Leftrightarrow", "\\Leftrightarrow", "\\Leftrightarrow", .mathSymbol, "⇔")
        add("longrightarrow", "\\longrightarrow", "\\longrightarrow", .mathSymbol, "⟶")
        add("longleftarrow", "\\longleftarrow", "\\longleftarrow", .mathSymbol, "⟵")
        add("mapsto", "\\mapsto", "\\mapsto", .mathSymbol, "↦")
        add("longmapsto", "\\longmapsto", "\\longmapsto", .mathSymbol, "⟼")
        add("hookrightarrow", "\\hookrightarrow", "\\hookrightarrow", .mathSymbol, "↪")
        add("hookleftarrow", "\\hookleftarrow", "\\hookleftarrow", .mathSymbol, "↩")
        add("rightharpoonup", "\\rightharpoonup", "\\rightharpoonup", .mathSymbol, "⇀")
        add("leftharpoonup", "\\leftharpoonup", "\\leftharpoonup", .mathSymbol, "↼")
        add("uparrow", "\\uparrow", "\\uparrow", .mathSymbol, "↑")
        add("downarrow", "\\downarrow", "\\downarrow", .mathSymbol, "↓")
        add("updownarrow", "\\updownarrow", "\\updownarrow", .mathSymbol, "↕")
        add("nearrow", "\\nearrow", "\\nearrow", .mathSymbol, "↗")

        // 数学运算符/函数 (18)
        add("frac", "\\frac{…}{…}", "\\frac{${1:}}{${2:}}", .mathFunction, "分数")
        add("sqrt", "\\sqrt{…}", "\\sqrt{${1:}}", .mathFunction, "平方根")
        add("sqrtn", "\\sqrt[3]{…}", "\\sqrt[${1:}]${2:{}}", .mathFunction, "n次根")
        add("sum", "\\sum_{}^{}", "\\sum_{${1:}}^{${2:}}", .mathFunction, "求和")
        add("prod", "\\prod_{}^{}", "\\prod_{${1:}}^{${2:}}", .mathFunction, "累积")
        add("int", "\\int_{}^{}", "\\int_{${1:}}^{${2:}}", .mathFunction, "积分")
        add("iint", "\\iint_{}^{}", "\\iint_{${1:}}^{${2:}}", .mathFunction, "二重积分")
        add("iiint", "\\iiint_{}^{}", "\\iiint_{${1:}}^{${2:}}", .mathFunction, "三重积分")
        add("oint", "\\oint_{}^{}", "\\oint_{${1:}}^{${2:}}", .mathFunction, "环积分")
        add("lim", "\\lim_{}", "\\lim_{${1:}}", .mathFunction, "极限")
        add("log", "\\log", "\\log", .mathFunction, "对数")
        add("ln", "\\ln", "\\ln", .mathFunction, "自然对数")
        add("sin", "\\sin", "\\sin", .mathFunction, "正弦")
        add("cos", "\\cos", "\\cos", .mathFunction, "余弦")
        add("tan", "\\tan", "\\tan", .mathFunction, "正切")
        add("exp", "\\exp", "\\exp", .mathFunction, "指数函数")
        add("max", "\\max", "\\max", .mathFunction, "最大值")
        add("min", "\\min", "\\min", .mathFunction, "最小值")

        // 环境 (25)
        add("begin", "\\begin{…}…\\end{…}", "\\begin{${1:}}", .environment, "开始环境")
        add("end", "\\end{…}", "\\end{${1:}}", .environment, "结束环境")
        add("itemize", "\\begin{itemize}…", "\\begin{itemize}\n\\item ${1:}\n\\end{itemize}", .environment, "无序列表")
        add("enumerate", "\\begin{enumerate}…", "\\begin{enumerate}\n\\item ${1:}\n\\end{enumerate}", .environment, "有序列表")
        add("description", "\\begin{description}…", "\\begin{description}\n\\item[${1:}] ${2:}\n\\end{description}", .environment, "描述列表")
        add("item", "\\item …", "\\item ${1:}", .environment, "列表项")
        add("figure", "\\begin{figure}…", "\\begin{figure}[${1:htbp}]\n\\centering\n\\includegraphics{${2:}}\n\\caption{${3:}}\n\\label{${4:}}\n\\end{figure}", .environment, "插图")
        add("table", "\\begin{table}…", "\\begin{table}[${1:htbp}]\n\\centering\n\\caption{${2:}}\n\\label{${3:}}\n\\begin{tabular}{${4:}}\n${5:}\n\\end{tabular}\n\\end{table}", .environment, "表格")
        add("tabular", "\\begin{tabular}…", "\\begin{tabular}{${1:}}\n${2:}\n\\end{tabular}", .environment, "表格主体")
        add("equation", "\\begin{equation}…", "\\begin{equation}\n${1:}\n\\end{equation}", .environment, "公式")
        add("align", "\\begin{align}…", "\\begin{align}\n${1:}\n\\end{align}", .environment, "对齐公式")
        add("alignstar", "\\begin{align*}…", "\\begin{align*}\n${1:}\n\\end{align*}", .environment, "无编号对齐")
        add("center", "\\begin{center}…", "\\begin{center}\n${1:}\n\\end{center}", .environment, "居中")
        add("flushleft", "\\begin{flushleft}…", "\\begin{flushleft}\n${1:}\n\\end{flushleft}", .environment, "左对齐")
        add("flushright", "\\begin{flushright}…", "\\begin{flushright}\n${1:}\n\\end{flushright}", .environment, "右对齐")
        add("quote", "\\begin{quote}…", "\\begin{quote}\n${1:}\n\\end{quote}", .environment, "引用")
        add("quotation", "\\begin{quotation}…", "\\begin{quotation}\n${1:}\n\\end{quotation}", .environment, "引文")
        add("abstract", "\\begin{abstract}…", "\\begin{abstract}\n${1:}\n\\end{abstract}", .environment, "摘要")
        add("verbatim", "\\begin{verbatim}…", "\\begin{verbatim}\n${1:}\n\\end{verbatim}", .environment, "原样输出")
        add("lstlisting", "\\begin{lstlisting}…", "\\begin{lstlisting}\n${1:}\n\\end{lstlisting}", .environment, "代码块")
        add("thebibliography", "\\begin{thebibliography}…", "\\begin{thebibliography}{${1:}}\n\\bibitem{${2:}} ${3:}\n\\end{thebibliography}", .environment, "参考文献")
        add("proof", "\\begin{proof}…", "\\begin{proof}\n${1:}\n\\end{proof}", .environment, "证明")
        add("theorem", "\\begin{theorem}…", "\\begin{theorem}\n${1:}\n\\end{theorem}", .environment, "定理")
        add("lemma", "\\begin{lemma}…", "\\begin{lemma}\n${1:}\n\\end{lemma}", .environment, "引理")
        add("corollary", "\\begin{corollary}…", "\\begin{corollary}\n${1:}\n\\end{corollary}", .environment, "推论")

        // 引用 (5)
        add("ref", "\\ref{…}", "\\ref{${1:}}", .reference, "引用标签")
        add("label", "\\label{…}", "\\label{${1:}}", .reference, "标签")
        add("cite", "\\cite{…}", "\\cite{${1:}}", .reference, "引用文献")
        add("pageref", "\\pageref{…}", "\\pageref{${1:}}", .reference, "页码引用")
        add("bibliography", "\\bibliography{…}", "\\bibliography{${1:}}", .reference, "文献文件")

        // 宏包/命令定义 (8)
        add("newcommand", "\\newcommand{}{}", "\\newcommand{\\${1:}}{${2:}}", .package, "定义命令")
        add("renewcommand", "\\renewcommand{}{}", "\\renewcommand{\\${1:}}{${2:}}", .package, "重定义命令")
        add("newenvironment", "\\newenvironment{}{}{}", "\\newenvironment{${1:}}{${2:}}{${3:}}", .package, "定义环境")
        add("input", "\\input{…}", "\\input{${1:}}", .package, "引入文件")
        add("include", "\\include{…}", "\\include{${1:}}", .package, "包含文件")
        add("DeclareMathOperator", "\\DeclareMathOperator", "\\DeclareMathOperator{\\${1:}}{${2:}}", .package, "声明数学算子")
        add("newcommandstar", "\\newcommand*{}{}", "\\newcommand*{\\${1:}}{${2:}}", .package, "定义短命令")
        add("providecommand", "\\providecommand{}{}", "\\providecommand{\\${1:}}{${2:}}", .package, "提供命令")

        // 其他 (15)
        add("maketitle", "\\maketitle", "\\maketitle", .other, "生成标题")
        add("tableofcontents", "\\tableofcontents", "\\tableofcontents", .other, "目录")
        add("newpage", "\\newpage", "\\newpage", .other, "新页")
        add("clearpage", "\\clearpage", "\\clearpage", .other, "清除页面")
        add("pagebreak", "\\pagebreak", "\\pagebreak", .other, "分页")
        add("linebreak", "\\linebreak", "\\linebreak", .other, "换行")
        add("hfill", "\\hfill", "\\hfill", .other, "水平填充")
        add("vfill", "\\vfill", "\\vfill", .other, "垂直填充")
        add("noindent", "\\noindent", "\\noindent", .other, "取消缩进")
        add("centering", "\\centering", "\\centering", .other, "居中")
        add("raggedright", "\\raggedright", "\\raggedright", .other, "左齐")
        add("raggedleft", "\\raggedleft", "\\raggedleft", .other, "右齐")
        add("hline", "\\hline", "\\hline", .other, "水平线")
        add("hspace", "\\hspace{…}", "\\hspace{${1:}}", .other, "水平间距")
        add("vspace", "\\vspace{…}", "\\vspace{${1:}}", .other, "垂直间距")
        add("includegraphics", "\\includegraphics{…}", "\\includegraphics{${1:}}", .other, "插入图片")
        add("caption", "\\caption{…}", "\\caption{${1:}}", .other, "图/表标题")
        add("footnote", "\\footnote{…}", "\\footnote{${1:}}", .other, "脚注")
        add("thanks", "\\thanks{…}", "\\thanks{${1:}}", .other, "致谢")
        add("url", "\\url{…}", "\\url{${1:}}", .other, "网址")
        add("href", "\\href{}{}", "\\href{${1:}}{${2:}}", .other, "超链接")
        add("today", "\\today", "\\today", .other, "今天日期")
        add("LaTeX", "\\LaTeX", "\\LaTeX", .other, "LaTeX徽标")
        add("TeX", "\\TeX", "\\TeX", .other, "TeX徽标")

        return cmds
    }

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
            ("matrix", "matrix 矩阵"),
            ("pmatrix", "pmatrix 括号矩阵"),
            ("bmatrix", "bmatrix 方括号矩阵"),
            ("cases", "cases 分段函数"),
            ("lstlisting", "lstlisting 代码块"),
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
}
