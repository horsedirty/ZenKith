import Foundation

/// LaTeX 编译结果
struct LatexCompileResult {
    let pdfData: Data?
    let log: String
    let success: Bool
    let passCount: Int
}

/// LaTeX 编译与渲染服务：支持 pdflatex / xelatex / lualatex，多轮编译、BibTeX 支持
/// 所有编译操作均在后台线程执行，不阻塞 UI
final class LatexService {

    // MARK: - 编译器路径缓存

    private static var compilerPathCache: [String: String?] = [:]
    private static let cacheLock = NSLock()

    static func findCompilerPath(_ compiler: LatexCompiler) -> String? {
        let key = compiler.rawValue
        cacheLock.lock()
        if let cached = compilerPathCache[key] { cacheLock.unlock(); return cached }
        cacheLock.unlock()

        let result = _findCompilerPath(compiler)
        cacheLock.lock()
        compilerPathCache[key] = result
        cacheLock.unlock()
        return result
    }

    private static func _findCompilerPath(_ compiler: LatexCompiler) -> String? {
        let paths = [
            "/Library/TeX/texbin",
            "/usr/local/texlive/2025/bin/universal-darwin",
            "/usr/local/texlive/2024/bin/universal-darwin",
            "/usr/local/texlive/2025/bin/x86_64-darwin",
            "/usr/local/texlive/2024/bin/x86_64-darwin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]
        for base in paths {
            let full = (base as NSString).appendingPathComponent(compiler.rawValue)
            if FileManager.default.isExecutableFile(atPath: full) { return full }
        }
        let task = Process()
        task.launchPath = "/usr/bin/env"
        task.arguments = ["which", compiler.rawValue]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run(); task.waitUntilExit() } catch { return nil }
        if task.terminationStatus == 0,
           let data = try? pipe.fileHandleForReading.readToEnd(),
           let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty { return path }
        return nil
    }

    static func detectInstalledCompilers() -> [LatexCompiler] {
        LatexCompiler.allCases.filter { findCompilerPath($0) != nil }
    }

    static func clearPathCache() {
        cacheLock.lock()
        compilerPathCache.removeAll()
        cacheLock.unlock()
    }

    // MARK: - 编译（nonisolated，可安全在后台线程调用）

    /// 编译 .tex 文件到 PDF —— 全程在后台执行
    /// - Parameters:
    ///   - texURL: .tex 源文件路径
    ///   - compiler: 使用的编译器
    ///   - onPass: 每轮编译完成回调，回主线程调度由调用方负责
    static func compile(texURL: URL, compiler: LatexCompiler, onPass: @escaping (Int, Int) -> Void = { _, _ in }) async -> LatexCompileResult {
        guard let compilerPath = findCompilerPath(compiler) else {
            return LatexCompileResult(pdfData: nil, log: "未找到 LaTeX 编译器 \(compiler.rawValue)\n请安装 MacTeX 或 BasicTeX", success: false, passCount: 0)
        }

        let workDir = texURL.deletingLastPathComponent()
        let baseName = texURL.deletingPathExtension().lastPathComponent
        let pdfURL = workDir.appendingPathComponent("\(baseName).pdf")
        let args = buildArgs(compiler: compiler, texPath: texURL.path)

        var fullLog = ""

        // --- 第 1 轮 ---
        let (ok1, log1) = await runProcess(compilerPath, args: args, workDir: workDir)
        fullLog += log1
        onPass(1, 3)
        if !ok1 {
            return LatexCompileResult(pdfData: readPDF(pdfURL), log: fullLog + "\n=== 第 1 轮编译失败 ===", success: false, passCount: 1)
        }

        // --- BibTeX ---
        let auxURL = workDir.appendingPathComponent("\(baseName).aux")
        if needsBibtexPass(auxURL: auxURL, workDir: workDir) {
            let (_, bibLog) = await runBibtex(workDir: workDir, baseName: baseName)
            fullLog += bibLog
        }
        onPass(2, 3)

        // --- 第 2 轮 ---
        let (ok2, log2) = await runProcess(compilerPath, args: args, workDir: workDir)
        fullLog += log2
        onPass(3, 3)
        if !ok2 {
            return LatexCompileResult(pdfData: readPDF(pdfURL), log: fullLog + "\n=== 第 2 轮编译失败 ===", success: false, passCount: 2)
        }

        // --- 第 3 轮（如有需要） ---
        let logURL = workDir.appendingPathComponent("\(baseName).log")
        let needThird = needsThirdPass(logURL: logURL)
        if needThird {
            let (_, log3) = await runProcess(compilerPath, args: args, workDir: workDir)
            fullLog += log3
        }

        let finalLog = extractErrors(from: fullLog)
        let pdfData = readPDF(pdfURL)
        return LatexCompileResult(pdfData: pdfData, log: finalLog, success: pdfData != nil, passCount: needThird ? 3 : 2)
    }

    // MARK: - Process 封装（GCD 后台线程，不阻塞协作线程池）

    private static func runProcess(_ path: String, args: [String], workDir: URL) async -> (Bool, String) {
        await withCheckedContinuation { c in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.launchPath = path
                task.arguments = args
                task.currentDirectoryPath = workDir.path
                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = pipe
                do { try task.run() } catch {
                    c.resume(returning: (false, "启动失败: \(error.localizedDescription)"))
                    return
                }
                task.waitUntilExit()
                let output = (try? pipe.fileHandleForReading.readToEnd()).flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let header = "\n=== 编译: \(URL(fileURLWithPath: path).lastPathComponent) ===\n"
                c.resume(returning: (task.terminationStatus == 0, header + output))
            }
        }
    }

    private static func runBibtex(workDir: URL, baseName: String) async -> (Bool, String) {
        guard let bp = findInPath("bibtex") else {
            return (false, "\n=== BibTeX: 未找到 bibtex 命令 ===\n")
        }
        return await withCheckedContinuation { c in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.launchPath = bp
                task.arguments = [baseName]
                task.currentDirectoryPath = workDir.path
                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = pipe
                do { try task.run(); task.waitUntilExit() } catch {
                    c.resume(returning: (false, "\n=== BibTeX 运行失败 ===\n"))
                    return
                }
                let output = (try? pipe.fileHandleForReading.readToEnd()).flatMap { String(data: $0, encoding: .utf8) } ?? ""
                c.resume(returning: (task.terminationStatus == 0, "\n=== BibTeX ===\n" + output))
            }
        }
    }

    // MARK: - 辅助

    private static func buildArgs(compiler: LatexCompiler, texPath: String) -> [String] {
        [
            "-interaction=nonstopmode",
            "-file-line-error",
            "-synctex=1",
            "-output-directory=.",
            texPath,
        ]
    }

    private static func needsBibtexPass(auxURL: URL, workDir: URL) -> Bool {
        guard let auxContent = try? String(contentsOf: auxURL, encoding: .utf8) else { return false }
        guard auxContent.contains("\\bibdata{") || auxContent.contains("\\bibstyle{") || auxContent.contains("\\citation{") else { return false }
        return (try? FileManager.default.contentsOfDirectory(at: workDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            .contains(where: { $0.pathExtension.lowercased() == "bib" })) ?? false
    }

    private static func needsThirdPass(logURL: URL) -> Bool {
        guard let log = try? String(contentsOf: logURL, encoding: .utf8) else { return false }
        return log.contains("Rerun to get cross-references") || log.contains("rerun LaTeX") || log.contains("Label(s) may have changed")
    }

    private static func readPDF(_ url: URL) -> Data? {
        FileManager.default.fileExists(atPath: url.path) ? try? Data(contentsOf: url) : nil
    }

    private static func findInPath(_ command: String) -> String? {
        let key = "which_\(command)"
        cacheLock.lock()
        if let cached = compilerPathCache[key] { cacheLock.unlock(); return cached }
        cacheLock.unlock()
        let task = Process()
        task.launchPath = "/usr/bin/env"
        task.arguments = ["which", command]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run(); task.waitUntilExit() } catch { return nil }
        let result: String?
        if task.terminationStatus == 0,
           let data = try? pipe.fileHandleForReading.readToEnd(),
           let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty { result = path } else { result = nil }
        cacheLock.lock()
        compilerPathCache[key] = result
        cacheLock.unlock()
        return result
    }

    private static func extractErrors(from log: String) -> String {
        let lines = log.components(separatedBy: "\n")
        var result: [String] = []
        var inError = false
        for line in lines {
            if line.hasPrefix("!") || line.hasPrefix("LaTeX Error") || line.hasPrefix("LaTeX Warning") || line.contains("Error") || line.contains("Warning") {
                inError = true; result.append(line)
            } else if inError && line.hasPrefix("l.") {
                result.append(line); inError = false
            } else if line.contains("===") {
                result.append(""); result.append(line); result.append(""); inError = false
            }
        }
        return result.isEmpty ? log : result.joined(separator: "\n")
    }

    // MARK: - WebView 回退

    static func latexToHTML(_ source: String, fontSize: Double) -> String {
        let body = extractBody(source)
        let escaped = body
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\\", with: "\\\\")
        return """
        <!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>:root{--bg:#fff;--text:#1d1d1f}@media(prefers-color-scheme:dark){:root{--bg:#1c1c1e;--text:#e5e5ea}}
        body{font-family:"Times New Roman","Times","STSongti-SC","Songti SC",serif;font-size:\(fontSize)px;line-height:1.8;color:var(--text);background:var(--bg);max-width:860px;margin:0 auto;padding:20px 24px 60px}</style>
        <script>MathJax={tex:{inlineMath:[['$','$'],['\\\\(','\\\\)']],displayMath:[['$$','$$'],['\\\\[','\\\\]']],processEscapes:false,processRefs:true,packages:{'[+]':['noerrors','noundefined']}},options:{ignoreHtmlClass:'no-mathjax'},startup:{typeset:false}};</script>
        <script async src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-chtml.js"></script></head>
        <body><div id="lx">\(escaped)</div>
        <script>MathJax.startup.promise.then(function(){MathJax.typesetPromise([document.getElementById('lx')])});MathJax.startup.defaultReady();</script></body></html>
        """
    }

    private static func extractBody(_ source: String) -> String {
        var content = source
        if let begin = content.range(of: "\\begin{document}") {
            if let end = content.range(of: "\\end{document}", range: begin.upperBound..<content.endIndex) {
                content = String(content[begin.upperBound..<end.lowerBound])
            } else { content = String(content[begin.upperBound...]) }
        }
        return content.replacingOccurrences(of: "\\maketitle", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 兼容

    static func detectInstalledCompiler() -> String? { detectInstalledCompilers().first?.rawValue }

    static func compileToPDF(_ source: String) async -> Data? {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("zenkith_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let texFile = tmpDir.appendingPathComponent("document.tex")
        try? source.write(to: texFile, atomically: true, encoding: .utf8)
        let result = await compile(texURL: texFile, compiler: .pdflatex)
        try? FileManager.default.removeItem(at: tmpDir)
        return result.pdfData
    }
}
