import XCTest
import SwiftTreeSitter
import TreeSitterBend2

final class TreeSitterBend2Tests: XCTestCase {
    func testCanLoadGrammar() throws {
        let parser = Parser()
        let language = Language(language: tree_sitter_bend2())
        XCTAssertNoThrow(try parser.setLanguage(language),
                         "Error loading Bend2 grammar")
    }
}
