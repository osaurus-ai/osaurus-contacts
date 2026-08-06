import XCTest

@testable import osaurus_contacts

final class ToolValidationTests: XCTestCase {
  private struct Failure: Decodable {
    let ok: Bool
    let kind: String
    let message: String
    let retryable: Bool
    let field: String?
    let tool: String?
  }

  private struct Success: Decodable {
    let ok: Bool
    let tool: String
    let result: ContactsPage
  }

  private final class StubContactsManager: ContactsManaging {
    let contacts: [ContactRecord]

    init(_ contacts: [ContactRecord] = []) {
      self.contacts = contacts
    }

    func listContacts() throws -> [ContactRecord] {
      contacts
    }

    func findContacts(query: String, matchBy: ContactMatchField) throws -> [ContactRecord] {
      switch matchBy {
      case .name:
        return contacts.filter { Matching.nameMatches(query: query, candidate: $0.name) }
      case .phone:
        return contacts.filter {
          $0.phoneNumbers.contains {
            Matching.phoneMatches(query: query, candidate: $0.value)
          }
        }
      }
    }
  }

  private func contact(_ id: String, _ name: String, phone: String = "") -> ContactRecord {
    ContactRecord(
      identifier: id,
      name: name,
      phoneNumbers: phone.isEmpty ? [] : [LabeledValue(label: "mobile", value: phone)],
      emails: [LabeledValue(label: "work", value: "\(id)@example.com")]
    )
  }

  private func decodeFailure(_ json: String) throws -> Failure {
    let data = try XCTUnwrap(json.data(using: .utf8))
    return try JSONDecoder().decode(Failure.self, from: data)
  }

  private func decodeSuccess(_ json: String) throws -> Success {
    let data = try XCTUnwrap(json.data(using: .utf8))
    return try JSONDecoder().decode(Success.self, from: data)
  }

  func testListContactsRejectsMalformedJSON() throws {
    let failure = try decodeFailure(
      ListContactsTool(manager: StubContactsManager()).run(args: "{not json"))
    XCTAssertEqual(failure.kind, "invalid_args")
    XCTAssertTrue(failure.retryable)
    XCTAssertEqual(failure.tool, "list_contacts")
  }

  func testListContactsRequiresBoundedIntegerLimit() throws {
    let tool = ListContactsTool(manager: StubContactsManager())
    for args in ["{}", #"{"limit":0}"#, #"{"limit":1001}"#, #"{"limit":2.5}"#] {
      let failure = try decodeFailure(tool.run(args: args))
      XCTAssertEqual(failure.kind, "invalid_args", args)
      XCTAssertEqual(failure.field, "limit", args)
    }
  }

  func testListContactsRejectsUnknownAndNullArguments() throws {
    let tool = ListContactsTool(manager: StubContactsManager())
    let unknown = try decodeFailure(tool.run(args: #"{"limit":5,"extra":true}"#))
    XCTAssertEqual(unknown.kind, "invalid_args")
    XCTAssertTrue(unknown.message.contains("extra"))

    let nullCursor = try decodeFailure(tool.run(args: #"{"limit":5,"cursor":null}"#))
    XCTAssertEqual(nullCursor.field, "cursor")
  }

  func testFindContactsValidatesRequiredFieldsAndEnum() throws {
    let tool = FindContactsTool(manager: StubContactsManager())
    for args in [
      #"{"match_by":"name","limit":10}"#,
      #"{"query":"Jane","limit":10}"#,
      #"{"query":"Jane","match_by":"email","limit":10}"#,
    ] {
      let failure = try decodeFailure(tool.run(args: args))
      XCTAssertEqual(failure.kind, "invalid_args", args)
    }
  }

  func testFindContactsRejectsDigitlessPhoneQuery() throws {
    let failure = try decodeFailure(
      FindContactsTool(manager: StubContactsManager()).run(
        args: #"{"query":"call me","match_by":"phone","limit":10}"#))
    XCTAssertEqual(failure.kind, "invalid_args")
    XCTAssertEqual(failure.field, "query")
  }

  func testListContactsReturnsCanonicalModelAndPaginates() throws {
    let manager = StubContactsManager([
      contact("id-1", "Alex Smith", phone: "111"),
      contact("id-2", "Alex Smith", phone: "222"),
      contact("id-3", "Taylor Jones", phone: "333"),
    ])
    let tool = ListContactsTool(manager: manager)

    let first = try decodeSuccess(tool.run(args: #"{"limit":2}"#))
    XCTAssertTrue(first.ok)
    XCTAssertEqual(first.tool, "list_contacts")
    XCTAssertEqual(first.result.returned, 2)
    XCTAssertEqual(first.result.total, 3)
    XCTAssertTrue(first.result.truncated)
    XCTAssertEqual(first.result.contacts.map(\.identifier), ["id-1", "id-2"])
    XCTAssertEqual(first.result.contacts.map(\.name), ["Alex Smith", "Alex Smith"])
    let cursor = try XCTUnwrap(first.result.nextCursor)

    let second = try decodeSuccess(
      tool.run(args: #"{"limit":2,"cursor":"\#(cursor)"}"#))
    XCTAssertEqual(second.result.contacts.map(\.identifier), ["id-3"])
    XCTAssertEqual(second.result.returned, 1)
    XCTAssertEqual(second.result.total, 3)
    XCTAssertFalse(second.result.truncated)
    XCTAssertNil(second.result.nextCursor)
  }

  func testEmptyFindContactsIsSuccessful() throws {
    let success = try decodeSuccess(
      FindContactsTool(manager: StubContactsManager()).run(
        args: #"{"query":"Nobody","match_by":"name","limit":10}"#))
    XCTAssertTrue(success.ok)
    XCTAssertEqual(success.result.contacts, [])
    XCTAssertEqual(success.result.returned, 0)
    XCTAssertEqual(success.result.total, 0)
    XCTAssertFalse(success.result.truncated)
  }

  func testFindCursorCannotBeReusedForDifferentQuery() throws {
    let tool = FindContactsTool(manager: StubContactsManager([
      contact("id-1", "Alex One"),
      contact("id-2", "Alex Two"),
    ]))
    let firstJSON = tool.run(args: #"{"query":"Alex","match_by":"name","limit":1}"#)
    XCTAssertTrue(firstJSON.contains(#""ok":true"#), firstJSON)
    let first = try decodeSuccess(firstJSON)
    let cursor = try XCTUnwrap(first.result.nextCursor)
    let failure = try decodeFailure(
      tool.run(args: #"{"query":"Taylor","match_by":"name","limit":1,"cursor":"\#(cursor)"}"#))
    XCTAssertEqual(failure.kind, "invalid_args")
    XCTAssertEqual(failure.field, "cursor")
  }
}
