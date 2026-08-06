import Foundation
import OsaurusPluginKit

struct ToolDefinition {
  let id: String
  let description: String
  let parameters: String
}

enum ToolContracts {
  static let listContacts = ToolDefinition(
    id: "list_contacts",
    description: "List contacts with stable identifiers and labeled phone and email values",
    parameters: """
      {
        "type": "object",
        "properties": {
          "limit": {
            "type": "integer",
            "minimum": 1,
            "maximum": 1000,
            "description": "Maximum number of contacts to return"
          },
          "cursor": {
            "type": "string",
            "minLength": 1,
            "description": "Opaque cursor returned by a previous list_contacts call"
          }
        },
        "required": ["limit"],
        "additionalProperties": false
      }
      """
  )

  static let findContacts = ToolDefinition(
    id: "find_contacts",
    description: "Find contacts by name or phone number",
    parameters: """
      {
        "type": "object",
        "properties": {
          "query": {
            "type": "string",
            "minLength": 1,
            "description": "Name or phone number to search for"
          },
          "match_by": {
            "type": "string",
            "enum": ["name", "phone"],
            "description": "Contact field to match"
          },
          "limit": {
            "type": "integer",
            "minimum": 1,
            "maximum": 1000,
            "description": "Maximum number of matching contacts to return"
          },
          "cursor": {
            "type": "string",
            "minLength": 1,
            "description": "Opaque cursor returned by the same find_contacts query"
          }
        },
        "required": ["query", "match_by", "limit"],
        "additionalProperties": false
      }
      """
  )

  static let all = [listContacts, findContacts]
}

struct ContactsPage: Codable, Equatable {
  let contacts: [ContactRecord]
  let returned: Int
  let total: Int
  let truncated: Bool
  let nextCursor: String?

  enum CodingKeys: String, CodingKey {
    case contacts
    case returned
    case total
    case truncated
    case nextCursor = "next_cursor"
  }
}

private struct CursorPayload: Codable, Equatable {
  let version: Int
  let tool: String
  let matchBy: String?
  let query: String?
  let offset: Int

  enum CodingKeys: String, CodingKey {
    case version
    case tool
    case matchBy = "match_by"
    case query
    case offset
  }
}

private enum ContactCursor {
  static func encode(_ payload: CursorPayload) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try! encoder.encode(payload)
    return data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  static func decode(_ value: String?, expected: CursorPayload, tool: String) throws -> Int {
    guard let value else { return 0 }
    var base64 = value
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)

    guard let data = Data(base64Encoded: base64),
      let payload = try? JSONDecoder().decode(CursorPayload.self, from: data),
      payload.version == expected.version,
      payload.tool == expected.tool,
      payload.matchBy == expected.matchBy,
      payload.query == expected.query,
      payload.offset >= 0
    else {
      throw EnvelopeFailure(
        .invalidArgs,
        "cursor is invalid or belongs to a different request",
        field: "cursor",
        expected: "a cursor returned by this same tool and query",
        tool: tool
      )
    }
    return payload.offset
  }
}

func contactsFailure(_ error: Error, tool: String) -> String {
  switch error {
  case let ContactsError.permissionDenied(message):
    return Envelope.failure(.userDenied, message, tool: tool)
  case let ContactsError.permissionTimeout(message):
    return Envelope.failure(.timeout, message, tool: tool)
  case let ContactsError.searchFailed(message):
    return Envelope.failure(.executionError, message, tool: tool)
  case let failure as EnvelopeFailure:
    return Envelope.failure(
      failure.kind,
      failure.message,
      retryable: failure.retryable,
      field: failure.field,
      expected: failure.expected,
      tool: failure.tool ?? tool,
      dataJSON: failure.dataJSON
    )
  default:
    return Envelope.failure(.executionError, error.localizedDescription, tool: tool)
  }
}

private func strictArguments(_ payload: String, allowed: Set<String>, tool: String) throws
  -> [String: Any]
{
  let args = try ArgValidation.parseObject(payload)
  let unknown = Set(args.keys).subtracting(allowed).sorted()
  guard unknown.isEmpty else {
    throw EnvelopeFailure(
      .invalidArgs,
      "Unknown argument\(unknown.count == 1 ? "" : "s"): \(unknown.joined(separator: ", "))",
      expected: "only declared schema properties",
      tool: tool
    )
  }
  return args
}

private func requiredString(_ args: [String: Any], field: String, tool: String) throws -> String {
  do {
    return try ArgValidation.requireString(args, field)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  } catch let failure as EnvelopeFailure {
    throw EnvelopeFailure(
      failure.kind,
      failure.message,
      retryable: failure.retryable,
      field: field,
      expected: "a non-empty string",
      tool: tool
    )
  }
}

private func requiredLimit(_ args: [String: Any], tool: String) throws -> Int {
  guard let raw = args["limit"], !(raw is NSNull) else {
    throw EnvelopeFailure(
      .invalidArgs,
      "Missing required argument: limit",
      field: "limit",
      expected: "an integer from 1 through 1000",
      tool: tool
    )
  }
  guard let number = raw as? NSNumber,
    CFGetTypeID(number) != CFBooleanGetTypeID()
  else {
    throw EnvelopeFailure(
      .invalidArgs,
      "limit must be an integer",
      field: "limit",
      expected: "an integer from 1 through 1000",
      tool: tool
    )
  }
  let numericValue = number.doubleValue
  guard numericValue.isFinite,
    numericValue.rounded(.towardZero) == numericValue,
    numericValue >= 1,
    numericValue <= 1000
  else {
    throw EnvelopeFailure(
      .invalidArgs,
      "limit must be an integer from 1 through 1000",
      field: "limit",
      expected: "an integer from 1 through 1000",
      tool: tool
    )
  }
  return Int(numericValue)
}

private func optionalCursor(_ args: [String: Any], tool: String) throws -> String? {
  guard let raw = args["cursor"] else { return nil }
  guard let cursor = raw as? String,
    !cursor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  else {
    throw EnvelopeFailure(
      .invalidArgs,
      "cursor must be a non-empty string",
      field: "cursor",
      expected: "an opaque cursor string",
      tool: tool
    )
  }
  return cursor
}

private func successPage(
  tool: String,
  contacts: [ContactRecord],
  limit: Int,
  offset: Int,
  cursorContext: CursorPayload
) -> String {
  let start = min(offset, contacts.count)
  let end = min(start + limit, contacts.count)
  let selected = Array(contacts[start..<end])
  let truncated = end < contacts.count
  let nextCursor =
    truncated
    ? ContactCursor.encode(
      CursorPayload(
        version: cursorContext.version,
        tool: cursorContext.tool,
        matchBy: cursorContext.matchBy,
        query: cursorContext.query,
        offset: end
      ))
    : nil
  let page = ContactsPage(
    contacts: selected,
    returned: selected.count,
    total: contacts.count,
    truncated: truncated,
    nextCursor: nextCursor
  )

  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]
  guard let data = try? encoder.encode(page),
    let json = String(data: data, encoding: .utf8)
  else {
    return Envelope.failure(.executionError, "Failed to encode contacts result", tool: tool)
  }
  return Envelope.success(tool: tool, rawResult: json)
}

struct ListContactsTool {
  let definition = ToolContracts.listContacts
  let manager: any ContactsManaging

  var name: String { definition.id }
  var description: String { definition.description }
  var parameters: String { definition.parameters }

  func run(args: String) -> String {
    do {
      let input = try strictArguments(
        args, allowed: ["limit", "cursor"], tool: name)
      let limit = try requiredLimit(input, tool: name)
      let cursor = try optionalCursor(input, tool: name)
      let context = CursorPayload(
        version: 1, tool: name, matchBy: nil, query: nil, offset: 0)
      let offset = try ContactCursor.decode(cursor, expected: context, tool: name)
      return successPage(
        tool: name,
        contacts: try manager.listContacts(),
        limit: limit,
        offset: offset,
        cursorContext: context
      )
    } catch {
      return contactsFailure(error, tool: name)
    }
  }
}

struct FindContactsTool {
  let definition = ToolContracts.findContacts
  let manager: any ContactsManaging

  var name: String { definition.id }
  var description: String { definition.description }
  var parameters: String { definition.parameters }

  func run(args: String) -> String {
    do {
      let input = try strictArguments(
        args, allowed: ["query", "match_by", "limit", "cursor"], tool: name)
      let query = try requiredString(input, field: "query", tool: name)
      let matchByValue = try requiredString(input, field: "match_by", tool: name)
      do {
        _ = try ArgValidation.enumValue(
          matchByValue, field: "match_by", allowed: ["name", "phone"])
      } catch let failure as EnvelopeFailure {
        throw EnvelopeFailure(
          failure.kind,
          failure.message,
          retryable: failure.retryable,
          field: "match_by",
          expected: "name or phone",
          tool: name
        )
      }
      let matchBy = ContactMatchField(rawValue: matchByValue)!
      if matchBy == .phone && Matching.normalizeDigits(query).isEmpty {
        throw EnvelopeFailure(
          .invalidArgs,
          "query must contain at least one digit when match_by is phone",
          field: "query",
          expected: "a phone number containing digits",
          tool: name
        )
      }
      let limit = try requiredLimit(input, tool: name)
      let cursor = try optionalCursor(input, tool: name)
      let normalizedQuery =
        matchBy == .phone ? Matching.normalizeDigits(query) : Matching.normalizeName(query)
      let context = CursorPayload(
        version: 1,
        tool: name,
        matchBy: matchBy.rawValue,
        query: normalizedQuery,
        offset: 0
      )
      let offset = try ContactCursor.decode(cursor, expected: context, tool: name)
      return successPage(
        tool: name,
        contacts: try manager.findContacts(query: query, matchBy: matchBy),
        limit: limit,
        offset: offset,
        cursorContext: context
      )
    } catch {
      return contactsFailure(error, tool: name)
    }
  }
}
