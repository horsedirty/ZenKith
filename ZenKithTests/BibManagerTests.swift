import XCTest
@testable import ZenKith

@MainActor
final class BibManagerTests: XCTestCase {

    func testParseMultipleEntries() {
        let content = """
        @article{einstein1905,
          author = {Albert Einstein},
          title = {Zur Elektrodynamik bewegter K{\\"o}rper},
          journal = {Annalen der Physik},
          year = {1905}
        }

        @book{knuth1984,
          author = {Donald E. Knuth},
          title = {The TeXbook},
          publisher = {Addison-Wesley},
          year = {1984}
        }

        @inproceedings{hochreiter1997,
          author = {Sepp Hochreiter and J{\\"u}rgen Schmidhuber},
          title = {Long Short-Term Memory},
          booktitle = {Neural Computation},
          year = {1997}
        }
        """
        let bibManager = BibManager()
        bibManager.loadBibContent(content)
        XCTAssertEqual(bibManager.entries.count, 3)
        XCTAssertEqual(bibManager.entries[0].key, "einstein1905")
        XCTAssertEqual(bibManager.entries[0].type, "article")
        XCTAssertEqual(bibManager.entries[0].author, "Albert Einstein")
        XCTAssertEqual(bibManager.entries[0].title, "Zur Elektrodynamik bewegter K{\\\"o}rper")
        XCTAssertEqual(bibManager.entries[0].journal, "Annalen der Physik")
        XCTAssertEqual(bibManager.entries[1].key, "knuth1984")
        XCTAssertEqual(bibManager.entries[2].key, "hochreiter1997")
    }

    func testParseEntryWithNestedBraces() {
        let content = """
        @article{test2024,
          title = {A {Bold} Title with {Nested} Braces},
          author = {Smith, John},
          journal = {Test Journal},
          year = {2024}
        }
        """
        let bibManager = BibManager()
        bibManager.loadBibContent(content)
        XCTAssertEqual(bibManager.entries.count, 1)
        XCTAssertEqual(bibManager.entries[0].title, "A {Bold} Title with {Nested} Braces")
    }

    func testParseEmptyBibReturnsZero() {
        let bibManager = BibManager()
        bibManager.loadBibContent("")
        XCTAssertEqual(bibManager.entries.count, 0)
    }

    func testParseBibWithQuotedFields() {
        let content = """
        @article{test2023,
          author = "Jane Doe",
          title = "A Simple Test",
          journal = "Test",
          year = "2023"
        }
        """
        let bibManager = BibManager()
        bibManager.loadBibContent(content)
        XCTAssertEqual(bibManager.entries.count, 1)
        XCTAssertEqual(bibManager.entries[0].author, "Jane Doe")
        XCTAssertEqual(bibManager.entries[0].year, "2023")
    }

    func testCiteKeysForPrefix() {
        let content = """
        @article{smith2020, author = {A}, title = {T1}, journal = {J}, year = {2020}}
        @article{smith2021, author = {B}, title = {T2}, journal = {J}, year = {2021}}
        @article{jones2020, author = {C}, title = {T3}, journal = {J}, year = {2020}}
        """
        let bibManager = BibManager()
        bibManager.loadBibContent(content)
        let smithKeys = bibManager.citeKeys(for: "smith")
        XCTAssertEqual(smithKeys.count, 2)
        XCTAssertTrue(smithKeys.contains("smith2020"))
        XCTAssertTrue(smithKeys.contains("smith2021"))
    }
}
