import Foundation
import OsaurusPluginKit

// Maps a thrown error to a canonical failure envelope.
// Contacts permission failures are non-retryable `permission_denied`;
// permission-prompt timeouts are `timeout`; everything else is treated as a
// retryable `execution_error`.
func contactsFailure(_ error: Error) -> String {
  switch error {
  case let ContactsError.permissionDenied(message):
    return Envelope.failure(.permissionDenied, message)
  case let ContactsError.permissionTimeout(message):
    return Envelope.failure(.timeout, message)
  case let ContactsError.searchFailed(message):
    return Envelope.failure(.executionError, message)
  default:
    return Envelope.failure(.executionError, error.localizedDescription)
  }
}

struct GetAllNumbersTool {
  let name = "get_all_numbers"
  let description = "Get all contacts and their phone numbers"
  let parameters =
    "{\"type\":\"object\",\"properties\":{\"limit\":{\"type\":\"integer\",\"description\":\"Max number of contacts to return (default 1000)\"}},\"required\":[]}"

  let manager: ContactsManager

  func run(args: String) -> String {
    struct Args: Decodable {
      let limit: Int?
    }

    // An empty payload means "no arguments"; anything else must be valid JSON
    // instead of being silently treated as defaults.
    var requestedLimit: Int? = nil
    if !args.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      guard let data = args.data(using: .utf8),
        let input = try? JSONDecoder().decode(Args.self, from: data)
      else {
        return Envelope.failure(.invalidArgs, "Invalid arguments: expected a JSON object")
      }
      requestedLimit = input.limit
    }

    let limit = requestedLimit ?? 1000
    guard limit > 0 else {
      return Envelope.failure(.invalidArgs, "limit must be a positive integer, got \(limit)")
    }

    do {
      let contacts = try manager.getAllNumbers(limit: limit)
      guard let data = try? JSONEncoder().encode(contacts),
        let json = String(data: data, encoding: .utf8)
      else {
        return Envelope.failure(.executionError, "Failed to encode contacts result")
      }
      return json
    } catch {
      return contactsFailure(error)
    }
  }
}

struct FindNumberTool {
  let name = "find_number"
  let description = "Find phone numbers for a contact by name"
  let parameters =
    "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\",\"description\":\"Name to search for\"}},\"required\":[\"name\"]}"

  let manager: ContactsManager

  func run(args: String) -> String {
    struct Args: Decodable {
      let name: String
    }

    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return Envelope.failure(.invalidArgs, "Missing or invalid 'name' argument")
    }

    guard !input.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return Envelope.failure(.invalidArgs, "'name' must not be empty")
    }

    do {
      let numbers = try manager.findNumber(name: input.name)
      if numbers.isEmpty {
        return Envelope.failure(.notFound, "No phone numbers found for '\(input.name)'")
      }
      guard let data = try? JSONEncoder().encode(numbers),
        let json = String(data: data, encoding: .utf8)
      else {
        return Envelope.failure(.executionError, "Failed to encode phone numbers result")
      }
      return json
    } catch {
      return contactsFailure(error)
    }
  }
}

struct FindContactByPhoneTool {
  let name = "find_contact_by_phone"
  let description = "Find a contact name by their phone number"
  let parameters =
    "{\"type\":\"object\",\"properties\":{\"phoneNumber\":{\"type\":\"string\",\"description\":\"Phone number to search for\"}},\"required\":[\"phoneNumber\"]}"

  let manager: ContactsManager

  func run(args: String) -> String {
    struct Args: Decodable {
      let phoneNumber: String
    }

    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return Envelope.failure(.invalidArgs, "Missing or invalid 'phoneNumber' argument")
    }

    guard !Matching.normalizeDigits(input.phoneNumber).isEmpty else {
      return Envelope.failure(.invalidArgs, "'phoneNumber' must contain at least one digit")
    }

    do {
      guard let name = try manager.findContactByPhone(phone: input.phoneNumber) else {
        return Envelope.failure(.notFound, "No contact found for phone number '\(input.phoneNumber)'")
      }
      let result = ["name": name]
      guard let data = try? JSONEncoder().encode(result),
        let json = String(data: data, encoding: .utf8)
      else {
        return Envelope.failure(.executionError, "Failed to encode contact result")
      }
      return json
    } catch {
      return contactsFailure(error)
    }
  }
}

struct FindContactByNameTool {
  let name = "find_contact_by_name"
  let description = "Find full contact details (phone, email) for a contact by name"
  let parameters =
    "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\",\"description\":\"Name to search for\"}},\"required\":[\"name\"]}"

  let manager: ContactsManager

  func run(args: String) -> String {
    struct Args: Decodable {
      let name: String
    }

    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return Envelope.failure(.invalidArgs, "Missing or invalid 'name' argument")
    }

    guard !input.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return Envelope.failure(.invalidArgs, "'name' must not be empty")
    }

    do {
      let contacts = try manager.findContactByName(name: input.name)
      if contacts.isEmpty {
        return Envelope.failure(.notFound, "No contact found for '\(input.name)'")
      }
      guard let data = try? JSONEncoder().encode(contacts),
        let json = String(data: data, encoding: .utf8)
      else {
        return Envelope.failure(.executionError, "Failed to encode contacts result")
      }
      return json
    } catch {
      return contactsFailure(error)
    }
  }
}
