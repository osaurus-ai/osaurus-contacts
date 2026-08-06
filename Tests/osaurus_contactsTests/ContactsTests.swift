import OsaurusPluginKit
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

  func testManifestVersionMatchesRelease() throws {
    let data = try XCTUnwrap(contactsManifestJSON.data(using: .utf8))
    let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(root["version"] as? String, "2.0.0")
  }

  func testManifestDeclaresExactlyModernizedTools() throws {
    let data = try XCTUnwrap(contactsManifestJSON.data(using: .utf8))
    let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let capabilities = try XCTUnwrap(root["capabilities"] as? [String: Any])
    let tools = try XCTUnwrap(capabilities["tools"] as? [[String: Any]])

    XCTAssertEqual(tools.compactMap { $0["id"] as? String }, ["list_contacts", "find_contacts"])

    for (tool, definition) in zip(tools, ToolContracts.all) {
      let id = try XCTUnwrap(tool["id"] as? String)
      let description = try XCTUnwrap(tool["description"] as? String)
      XCTAssertFalse(id.isEmpty, "Tool id must be non-empty")
      XCTAssertFalse(description.isEmpty, "Tool description must be non-empty")
      XCTAssertNil(tool["name"], "Tools must use 'id', not 'name'")
      XCTAssertEqual(tool["permission_policy"] as? String, "ask")
      XCTAssertNil(tool["annotations"])
      XCTAssertNil(tool["outputSchema"])

      let manifestSchema = try XCTUnwrap(tool["parameters"] as? NSDictionary)
      let canonicalSchema = try XCTUnwrap(
        JSONSerialization.jsonObject(with: Data(definition.parameters.utf8)) as? NSDictionary)
      XCTAssertEqual(manifestSchema, canonicalSchema, "\(id) schema must use its canonical source")
      XCTAssertEqual(manifestSchema["type"] as? String, "object")
      XCTAssertEqual(manifestSchema["additionalProperties"] as? Bool, false)
    }
  }

  func testParameterNamesUseSnakeCase() throws {
    let data = try XCTUnwrap(contactsManifestJSON.data(using: .utf8))
    let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let capabilities = try XCTUnwrap(root["capabilities"] as? [String: Any])
    let tools = try XCTUnwrap(capabilities["tools"] as? [[String: Any]])

    for tool in tools {
      let parameters = try XCTUnwrap(tool["parameters"] as? [String: Any])
      let properties = try XCTUnwrap(parameters["properties"] as? [String: Any])
      for key in properties.keys {
        XCTAssertNotNil(
          key.range(of: #"^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$"#, options: .regularExpression))
      }
    }
  }

  // MARK: - Envelope

  func testFailureRoundTripsWithOkFalse() throws {
    let json = Envelope.failure(.notFound, "nothing here")

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
      (.rejected, "rejected", false),
      (.userDenied, "user_denied", false),
      (.timeout, "timeout", true),
      (.executionError, "execution_error", true),
      (.notFound, "not_found", false),
      (.unavailable, "unavailable", true),
      (.toolNotFound, "tool_not_found", false),
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

  func testExplicitRetryableOverride() throws {
    let json = Envelope.failure(.executionError, "flaky", retryable: false)
    let data = try XCTUnwrap(json.data(using: .utf8))
    let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(obj["kind"] as? String, "execution_error")
    XCTAssertEqual(obj["retryable"] as? Bool, false)
  }
}
