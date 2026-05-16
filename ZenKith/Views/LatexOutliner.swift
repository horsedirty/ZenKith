import Foundation

struct OutlineItem: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let lineNumber: Int
    let level: Int
    let children: [OutlineItem]
}

enum LatexOutliner {

    private static let sectionPatterns: [(String, Int)] = [
        ("subsubsection", 3),
        ("subsection", 2),
        ("section", 1),
        ("chapter", 0),
    ]

    static func parse(_ source: String) -> [OutlineItem] {
        let lines = source.components(separatedBy: "\n")
        var flatItems: [(lineNumber: Int, level: Int, title: String)] = []

        for (idx, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("%") else { continue }

            for (command, level) in sectionPatterns {
                let prefix = "\\\(command){"
                if line.hasPrefix(prefix), let close = findMatchingBrace(in: line, from: prefix.count - 1) {
                    let startIdx = line.index(line.startIndex, offsetBy: prefix.count)
                    let title = String(line[startIdx..<close])
                    flatItems.append((idx + 1, level, title))
                    break
                }
            }
        }

        return buildTree(from: flatItems)
    }

    private static func findMatchingBrace(in line: String, from startBraceIdx: Int) -> String.Index? {
        let startIdx = line.index(line.startIndex, offsetBy: startBraceIdx)
        var depth = 0
        for i in line[startIdx...].indices {
            let ch = line[i]
            if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 { return i }
            }
        }
        return nil
    }

    private static func buildTree(from flat: [(lineNumber: Int, level: Int, title: String)]) -> [OutlineItem] {
        func makeItems(_ entries: [(lineNumber: Int, level: Int, title: String)], startLevel: Int = -1) -> [OutlineItem] {
            var result: [OutlineItem] = []
            var i = 0
            while i < entries.count {
                let entry = entries[i]
                if entry.level <= startLevel { break }
                var j = i + 1
                while j < entries.count, entries[j].level > entry.level { j += 1 }
                let children = makeItems(Array(entries[(i+1)..<j]), startLevel: entry.level)
                result.append(OutlineItem(title: entry.title, lineNumber: entry.lineNumber, level: entry.level, children: children))
                i = j
            }
            return result
        }
        return makeItems(flat)
    }
}
