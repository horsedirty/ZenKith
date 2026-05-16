import XCTest
@testable import ZenKith

final class LatexOutlinerTests: XCTestCase {

    func testParseSectionsReturnsCorrectHierarchy() {
        let source = """
        \\documentclass{article}
        \\begin{document}
        \\section{Introduction}
        Some text here.
        \\subsection{Background}
        More text.
        \\section{Methods}
        \\subsection{Setup}
        \\subsubsection{Configuration A}
        Details.
        \\subsection{Results}
        \\end{document}
        """
        let items = LatexOutliner.parse(source)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].title, "Introduction")
        XCTAssertEqual(items[0].level, 1)
        XCTAssertEqual(items[1].children.count, 2)
        XCTAssertEqual(items[1].children[0].children.count, 1)
        XCTAssertEqual(items[1].children[0].children[0].level, 3)
    }

    func testParseSectionsIncludesLineNumbers() {
        let source = """
        line1
        line2
        \\section{Test}
        """
        let items = LatexOutliner.parse(source)
        XCTAssertEqual(items.first?.lineNumber, 3)
    }

    func testParseIgnoresCommentedSections() {
        let source = "% \\section{Commented}"
        let items = LatexOutliner.parse(source)
        XCTAssertTrue(items.isEmpty)
    }

    func testParseIncludesChapter() {
        let source = "\\chapter{Overview}\n\\section{Start}"
        let items = LatexOutliner.parse(source)
        XCTAssertEqual(items[0].title, "Overview")
        XCTAssertEqual(items[0].level, 0)
    }

    func testParseEmptySource() {
        XCTAssertTrue(LatexOutliner.parse("").isEmpty)
    }
}
