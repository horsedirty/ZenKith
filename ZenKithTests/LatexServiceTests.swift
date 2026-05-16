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
}
