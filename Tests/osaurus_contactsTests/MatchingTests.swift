import XCTest

@testable import osaurus_contacts

final class MatchingTests: XCTestCase {

  // MARK: - Digit normalization

  func testNormalizeDigitsStripsFormatting() {
    XCTAssertEqual(Matching.normalizeDigits("+1 (415) 555-1234"), "14155551234")
    XCTAssertEqual(Matching.normalizeDigits("415.555.1234"), "4155551234")
    XCTAssertEqual(Matching.normalizeDigits("no digits"), "")
  }

  // MARK: - Phone matching

  func testExactNormalizedMatch() {
    XCTAssertTrue(Matching.phoneMatches(query: "(415) 555-1234", candidate: "415.555.1234"))
  }

  func testSuffixMatchHandlesCountryCode() {
    XCTAssertTrue(Matching.phoneMatches(query: "4155551234", candidate: "+1 415 555 1234"))
    XCTAssertTrue(Matching.phoneMatches(query: "+1 415 555 1234", candidate: "4155551234"))
  }

  func testSevenDigitLocalNumberSuffixMatches() {
    XCTAssertTrue(Matching.phoneMatches(query: "5551234", candidate: "+1 (415) 555-1234"))
  }

  func testShortNumberDoesNotMatchBySubstring() {
    // Regression: raw substring containment let short numbers match any
    // contact whose number happened to contain those digits.
    XCTAssertFalse(Matching.phoneMatches(query: "911", candidate: "+1 415 591 1234"))
    XCTAssertFalse(Matching.phoneMatches(query: "555", candidate: "415 555 1234"))
    XCTAssertFalse(Matching.phoneMatches(query: "1234", candidate: "415 555 1234"))
  }

  func testShortNumberStillMatchesExactly() {
    XCTAssertTrue(Matching.phoneMatches(query: "911", candidate: "911"))
  }

  func testInfixDigitsDoNotMatch() {
    // "4155512" appears in the middle of "14155512345" but is not a suffix,
    // so it must not match even though it has 7 digits.
    XCTAssertFalse(Matching.phoneMatches(query: "4155512", candidate: "+1 415 551 2345"))
  }

  func testEmptyNeverMatches() {
    XCTAssertFalse(Matching.phoneMatches(query: "", candidate: "4155551234"))
    XCTAssertFalse(Matching.phoneMatches(query: "abc", candidate: "4155551234"))
    XCTAssertFalse(Matching.phoneMatches(query: "4155551234", candidate: ""))
  }

  // MARK: - Duplicate display names

  func testDuplicateNamesArePreservedWithDisambiguatedKeys() {
    // Regression: contacts with the same display name used to overwrite each
    // other in the dictionary result.
    let results = Matching.nameKeyedResults([
      (name: "John Smith", phones: ["111"]),
      (name: "John Smith", phones: ["222"]),
      (name: "Jane Doe", phones: ["333"]),
      (name: "John Smith", phones: ["444"]),
    ])

    XCTAssertEqual(results.count, 4)
    XCTAssertEqual(results["John Smith"], ["111"])
    XCTAssertEqual(results["John Smith (2)"], ["222"])
    XCTAssertEqual(results["John Smith (3)"], ["444"])
    XCTAssertEqual(results["Jane Doe"], ["333"])
  }

  func testDisambiguationAvoidsCollidingWithRealNames() {
    let results = Matching.nameKeyedResults([
      (name: "John Smith", phones: ["111"]),
      (name: "John Smith (2)", phones: ["222"]),
      (name: "John Smith", phones: ["333"]),
    ])

    XCTAssertEqual(results.count, 3)
    XCTAssertEqual(results["John Smith"], ["111"])
    XCTAssertEqual(results["John Smith (2)"], ["222"])
    XCTAssertEqual(results["John Smith (3)"], ["333"])
  }
}
