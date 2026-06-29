import XCTest

@testable import osaurus_contacts

final class ContactsTests: XCTestCase {

  // MARK: - Manifest

  func testManifestIsValidJSON() throws {
    let data = try XCTUnwrap(contactsManifestJSON.data(using: .utf8))
    let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let root = try XCTUnwrap(obj)
    XCTAssertEqual(root["plugin_id"] as? String, "osaurus.contacts")
  }

  func testEveryToolHasNonEmptyIdAndDescription() throws {
    let data = try XCTUnwrap(contactsManifestJSON.data(using: .utf8))
    let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let capabilities = try XCTUnwrap(root["capabilities"] as? [String: Any])
    let tools = try XCTUnwrap(capabilities["tools"] as? [[String: Any]])

    XCTAssertFalse(tools.isEmpty, "Manifest should declare at least one tool")

    for tool in tools {
      let id = try XCTUnwrap(tool["id"] as? String)
      let description = try XCTUnwrap(tool["description"] as? String)
      XCTAssertFalse(id.isEmpty, "Tool id must be non-empty")
      XCTAssertFalse(description.isEmpty, "Tool description must be non-empty")
      // The host requires "id"; ensure no tool accidentally used "name".
      XCTAssertNil(tool["name"], "Tools must use 'id', not 'name'")
    }
  }

  // MARK: - Envelope

  func testFailureRoundTripsWithOkFalse() throws {
    let json = Envelope.failure(.notFound, "nothing here")
    XCTAssertTrue(json.hasPrefix("{\"ok\":false"), "Failure must start with {\"ok\":false")

    let data = try XCTUnwrap(json.data(using: .utf8))
    let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertEqual(obj["ok"] as? Bool, false)
    XCTAssertEqual(obj["kind"] as? String, "not_found")
    XCTAssertEqual(obj["message"] as? String, "nothing here")
    XCTAssertEqual(obj["retryable"] as? Bool, false)
  }

  func testDefaultRetryablePerKind() throws {
    let expectations: [(Envelope.Kind, String, Bool)] = [
      (.invalidArgs, "invalid_args", true),
      (.executionError, "execution_error", true),
      (.notFound, "not_found", false),
      (.unavailable, "unavailable", true),
    ]

    for (kind, rawKind, retryable) in expectations {
      let json = Envelope.failure(kind, "msg")
      let data = try XCTUnwrap(json.data(using: .utf8))
      let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
      XCTAssertEqual(obj["kind"] as? String, rawKind)
      XCTAssertEqual(obj["retryable"] as? Bool, retryable, "retryable mismatch for \(rawKind)")
    }
  }

  func testFailureEscapesSpecialCharacters() throws {
    let nasty = "line1\nline2\t\"quoted\" \\back"
    let json = Envelope.failure(.executionError, nasty)
    let data = try XCTUnwrap(json.data(using: .utf8))
    let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(obj["message"] as? String, nasty)
  }

  func testUnavailableCanOverrideRetryable() throws {
    let json = Envelope.failure(.unavailable, "denied", retryable: false)
    let data = try XCTUnwrap(json.data(using: .utf8))
    let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(obj["kind"] as? String, "unavailable")
    XCTAssertEqual(obj["retryable"] as? Bool, false)
  }
}
