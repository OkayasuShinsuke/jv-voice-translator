import XCTest
@testable import Evaluation

final class EvalOptionsTests: XCTestCase {
    func testDefaults() throws {
        let options = try EvalOptions.parse([])
        XCTAssertEqual(options.datasetPath, "Evaluation/datasets")
        XCTAssertEqual(options.outputPath, "eval-report.md")
        XCTAssertEqual(options.translatorName, "identity")
    }

    func testParseValues() throws {
        let options = try EvalOptions.parse(["--dataset", "data", "--out=r.md", "--translator", "identity"])
        XCTAssertEqual(options.datasetPath, "data")
        XCTAssertEqual(options.outputPath, "r.md")
        XCTAssertEqual(options.translatorName, "identity")
    }

    func testErrors() {
        XCTAssertThrowsError(try EvalOptions.parse(["--out"])) { error in
            XCTAssertEqual(error as? EvalOptions.ParseError, .missingValue("--out"))
        }
        XCTAssertThrowsError(try EvalOptions.parse(["--bogus"])) { error in
            XCTAssertEqual(error as? EvalOptions.ParseError, .unknownOption("--bogus"))
        }
        XCTAssertTrue(try EvalOptions.parse(["--help"]).showHelp)
    }
}
