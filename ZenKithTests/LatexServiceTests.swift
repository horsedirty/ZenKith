import XCTest
@testable import ZenKith

final class LatexServiceTests: XCTestCase {

    func testExtractErrorLinesParsesLineNumbers() {
        let log = """
        === 编译: pdflatex ===
        ! Undefined control sequence.
        l.42 \\badcommand
        This is fine
        ! LaTeX Error: File not found.
        l.108 \\include{missing}
        """
        let errors = LatexService.extractErrorLines(from: log)
        XCTAssertEqual(errors.count, 2)
        XCTAssertEqual(errors[0].line, 42)
        XCTAssertEqual(errors[0].message, "Undefined control sequence.")
        XCTAssertEqual(errors[1].line, 108)
        XCTAssertEqual(errors[1].message, "LaTeX Error: File not found.")
    }

    func testExtractErrorLinesReturnsWarningsSeparately() {
        let log = """
        LaTeX Warning: Overfull \\hbox
        l.55 \\hline
        """
        let errors = LatexService.extractErrorLines(from: log)
        XCTAssertEqual(errors.first?.type, .warning)
    }

    func testExtractErrorLinesNoErrors() {
        let errors = LatexService.extractErrorLines(from: "Output written on document.pdf")
        XCTAssertTrue(errors.isEmpty)
    }

    func testExtractErrorLinesHandlesFileLineErrorFormat() {
        let log = """
        ./document.tex:42: Undefined control sequence.
        ./document.tex:108: LaTeX Error: File not found.
        ./document.tex:55: LaTeX Warning: Overfull \\hbox
        """
        let errors = LatexService.extractErrorLines(from: log)
        XCTAssertEqual(errors.count, 3)
        XCTAssertEqual(errors[0].line, 42)
        XCTAssertEqual(errors[0].type, .error)
        XCTAssertEqual(errors[1].line, 108)
        XCTAssertEqual(errors[2].line, 55)
        XCTAssertEqual(errors[2].type, .warning)
    }

    func testExtractErrorLinesHandlesInlineWarningLineNumber() {
        let log = "LaTeX Warning: Overfull \\hbox at lines 99--100"
        let errors = LatexService.extractErrorLines(from: log)
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors[0].line, 99)
        XCTAssertEqual(errors[0].type, .warning)
    }

    func testExtractErrorLinesHandlesMixedFormats() {
        let log = """
        ./document.tex:15: Missing $ inserted.
        ! Undefined control sequence.
        l.42 \\badcommand
        LaTeX Warning: Reference `fig:missing' on page 3 undefined
        """
        let errors = LatexService.extractErrorLines(from: log)
        XCTAssertEqual(errors.count, 3)
        XCTAssertEqual(errors[0].line, 15)
        XCTAssertEqual(errors[1].line, 42)
        XCTAssertEqual(errors[2].type, .warning)
    }
}
