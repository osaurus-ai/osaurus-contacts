import XCTest

@testable import osaurus_contacts

/// Regression tests for tool-level argument validation. All invalid-args paths
/// return before any Contacts framework access, so these run without TCC
/// permission.
final class ToolValidationTests: XCTestCase {

  private struct Failure: Decodable {
    let ok: Bool
    let kind: String
    let message: String
    let retryable: Bool
  }

  private func decodeFailure(_ json: String, file: StaticString = #filePath, line: UInt = #line)
    throws -> Failure
  {
    let data = try XCTUnwrap(json.data(using: .utf8), file: file, line: line)
    return try JSONDecoder().decode(Failure.self, from: data)
  }

  private var manager: ContactsManager { ContactsManager() }

  // MARK: - get_all_numbers

  func testGetAllNumbersRejectsMalformedJSON() throws {
    // Regression: malformed JSON args were silently treated as defaults.
    let failure = try decodeFailure(GetAllNumbersTool(manager: manager).run(args: "{not json"))
    XCTAssertEqual(failure.kind, "invalid_args")
    XCTAssertFalse(failure.retryable)
  }

  func testGetAllNumbersRejectsNegativeLimit() throws {
    let failure = try decodeFailure(
      GetAllNumbersTool(manager: manager).run(args: #"{"limit": -5}"#))
    XCTAssertEqual(failure.kind, "invalid_args")
    XCTAssertTrue(failure.message.contains("limit"))
  }

  // MARK: - find_number / find_contact_by_name

  func testFindNumberRejectsEmptyName() throws {
    // Regression: an empty name matched every contact via substring search.
    let failure = try decodeFailure(FindNumberTool(manager: manager).run(args: #"{"name": "  "}"#))
    XCTAssertEqual(failure.kind, "invalid_args")
  }

  func testFindContactByNameRejectsEmptyName() throws {
    let failure = try decodeFailure(
      FindContactByNameTool(manager: manager).run(args: #"{"name": ""}"#))
    XCTAssertEqual(failure.kind, "invalid_args")
  }

  func testFindNumberRejectsMissingName() throws {
    let failure = try decodeFailure(FindNumberTool(manager: manager).run(args: "{}"))
    XCTAssertEqual(failure.kind, "invalid_args")
  }

  // MARK: - find_contact_by_phone

  func testFindContactByPhoneRejectsDigitlessNumber() throws {
    let failure = try decodeFailure(
      FindContactByPhoneTool(manager: manager).run(args: #"{"phoneNumber": "call me"}"#))
    XCTAssertEqual(failure.kind, "invalid_args")
  }

  func testFindContactByPhoneRejectsMalformedJSON() throws {
    let failure = try decodeFailure(FindContactByPhoneTool(manager: manager).run(args: "null"))
    XCTAssertEqual(failure.kind, "invalid_args")
  }
}
